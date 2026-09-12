# 2026-09-12 accessor thunk 的类型构造求值

对应提案：[0029](../../Evolutions/0029-thunk-type-construction-evaluation.md)
（0028 的延续；0028 的两批见 [2026-09-11-offline-accessor-thunk-resolution.md](2026-09-11-offline-accessor-thunk-resolution.md)
与 [2026-09-11-accessor-thunk-resolution-follow-up.md](2026-09-11-accessor-thunk-resolution-follow-up.md)）。

## 问题

0028 收尾后，用户问「剩下那 5 条离线未读引用是什么意思」，接着说最初的目标就是消除全部未解析的不透明类型。
SwiftUI（macOS 26 共享缓存）全量 dump 里未解析的 kind-9 引用一共 6 处：5 处关联类型 witness 指向同一个 thunk
（`DefinesSearchCompletionModifier.Body`），1 处 field record（`Drag.LazyItem<A>.state`）。

## 调研

- **thunk 在做什么**：写了一次性探针，把 thunk 每次 `bl` 经 stub 找到 GOT 槽位、rebase 目标，再用进程内 `dladdr`
  查名。结果：满足支调 `$s7SwiftUI24_TagTraitWritingModifierVMa`，再尾调用 `$s7SwiftUI15ModifiedContentVMa`；不满足支
  多几步，用到 `TagValueTraitKey`、`_TraitWritingModifier`、`Optional` 的 accessor 和 `swift_getWitnessTable`。全部
  是类型层面的入口。参数缓冲区第 3 个词被当见证表实参传，与 opaque descriptor 的泛型上下文（两层共 3 个参数）吻合。
- **Swift 源码确认**（`/Volumes/SwiftProjects/swift-project`）：`getTypeRefByFunction` 生成的 thunk 只收一个参数
  （generic requirements buffer）；runtime 遇到根节点是 `AccessorFunctionReference` 就 `accessorFn(origArgumentVector)`；
  `enumerateGenericSignatureRequirements` 的顺序是 shape class → 类型参数 → 见证表。
- **field record 那个 thunk**：查缓存槽 → 未命中就调 `Drag.LazyItem.State` 的 accessor 再调 `Synchronization.Mutex` 的
  accessor。`Mutex` 是 `~Copyable`，所以走 kind-9。
- **fixture 的两种形态**：`_swift_runtimeSupportsNoncopyableTypes` 检查 + `csel` 两个 metadata；
  `__swift_instantiateConcreteTypeFromMangledNameV2(cache, mangledNameReference)`，帮手是编译器塞进镜像的本地函数。
- **顺带发现解码器的两个问题**：`retab` 没当返回，读过函数末尾进了下一个函数；前向 `b` 到紧跟其后的函数被当成
  函数内跳转，把那个函数也吞了进来。

## 最终方案

见提案「方案」与「落地」两节。要点：符号求值器（寄存器 / 栈槽放类型表达式）、照走控制流、判定不了的条件按两种
策略各跑一遍、被调方经 stub / bind / rebase / 原始符号表 / 跨镜像定位命名、表达式按被调 descriptor 的父链逐层包
`boundGeneric*`、seam 加 `AccessorThunkOwnerLayout`、field record 两处接线。

## 实际执行与偏差

- 第一版是「分支切片求值」（沿用 0028 的切分），撞上三件事后重写成照走控制流：fixture 的缓存探测形态需要从
  `cbz` 目标处继续、运行时能力标志的 `csel` 要能判定、未知被调方的尾调用不能把 `x0` 当返回值（第一版把
  `b __swift_instantiateConcreteTypeFromMangledNameV2` 前 `x0` 里的缓存变量地址报成了 metadata）。
- 0028 的 `csel` 读法被证明不完整：`ResolvedMenuStyle.Body` 在 `csel` 之后还有一次尾调用，正确答案是
  `ModifiedContent<…, Static>`。相应的合成测试改成真实形态，并加了「尾调用不认识时不报选中值」。
- `cbz` 形态的 `FeedbackGenerator.Body` 不满足支此前报的 `_TaskValueModifier` 是中间结果（尾调用 `b` 没被数进
  调用次数），现在是完整的 `ModifiedContent<_ViewModifier_Content<FeedbackGenerator<A>>, _TaskValueModifier<SensoryFeedback>>`。
- 测试并行下 `AccessorThunkResolution.resolver` 这个进程全局先被别的套件清空（oracle 测试假红），改用互斥键后又反过来
  污染了并行跑的 fixture 快照套件（占位被渲染成真类型）。最终改为 task-local：渲染层读 `effectiveResolver`，测试用
  `$taskResolver.withValue(...)` 把 resolver 限定在自己的任务里，进程全局只留给 CLI 的 `main()`。
- oracle 比较发现两侧对私有类型上下文的拼法不同（描述符带判别符，runtime 只看到匿名上下文），归一后逐字相等。

## 验证

- 专项（trait 开）：`ThunkTypeEvaluatorTests` 7、`AccessorThunkAnalyzerTests` 12（含改写与新增）、
  `AccessorThunkReaderTests` 2、`ConstructedThunkOracleTests` 1（5 条 witness 逐字相等）、
  `FieldRecordThunkResolutionTests` 2、`OpaqueTypeRenderingIntegrationTests` 4（新增「每条引用都解出」，17 → 0），
  以及上一批的 rewriter / 进程内套件，共 43 个全绿。
- CLI A/B（SwiftUI 全量 dump，与上一批的输出比）：未解析 kind-9 引用 6 → 0；其余差异全部是 `cbz` 形态的
  witness 多出泛型实参（`_TaskValueModifier2<SensoryFeedback>` 这类）与不满足支的完整读法。
- 回归（trait 开，`SwiftInterfaceTests` + `SwiftDumpTests` + `SwiftDiffingTests` + `SwiftIndexingTests` + `SwiftPrintingTests` +
  `SwiftDeclarationRenderingTests` + `SwiftThunkAnalysisTests` + `SwiftSectionCommandTests` + `MachOSwiftSectionTests`）：
  1350 个测试 / 260 个套件全绿。首轮里 `FunctionTypeMetadataTests` 三条 `resolved → nil` 是已知的全量并行抖动
  （单独跑必过），重跑全绿；另有两条 fixture 快照假红，根因是并行套件把 resolver 注册成了进程全局，改 task-local
  后消失。
- 回归（trait 关，另开 scratch 全量重编）：1259 个测试 / 244 个套件全绿。
- fixture 快照基线零改动：不注册 resolver 的路径与之前逐字节一致。

## 同日后续：撤销 trait，`SwiftDeclarationRendering` 直接依赖 `SwiftThunkAnalysis`

用户看到 `Package.swift` 里的 `.define("THUNK_ANALYSIS", .when(traits:))` 后先裁定：这一行可以删，SwiftPM 本来
就会为每个启用的 trait 定义同名编译条件；`SwiftThunkAnalysis` 本身是个 library，不该拿 trait 在源码里分叉。我据此把
trait 改成只挂在 `swift-section` 依赖边上的链接门。用户随即追问「`SwiftInterface` 和 `SwiftDump` 不用接吗」，并进一步
裁定「直接集成过来，不做 trait 判断，也不要 trait」。

- **改动**：`Package.swift` 删掉 trait 声明、`.define`、条件依赖边和辅助函数；Capstone 的 `ARM64` trait 无条件转发。
  依赖方向摆正：`SwiftDeclarationRendering` 依赖 `SwiftThunkAnalysis`（后者不再依赖前者），`AccessorThunkOwnerLayout`
  下移到 `SwiftThunkAnalysis`，`DisassemblingAccessorThunkResolver` 上移到渲染层，`Node+OpaqueType.swift` 的两处
  rewriter 直接取 `AccessorThunkResolution.effectiveResolver`（默认即反汇编读取器）；删掉进程全局的 `resolver` 与
  `installDisassemblingResolver()`，CLI 入口恢复默认 `main()`；`SwiftDeclaration` / `SwiftDump` 各加一条依赖边。
  21 个源码 / 测试文件剥掉 `#if THUNK_ANALYSIS`。测试侧新增一个什么都读不到的 `UnreadableAccessorThunkResolver`，
  用 task-local 作用域化来钉占位渲染；dump / interface 两份快照基线里 fixture 的四行 kind-9 占位变成声明的类型，重录。
- **为什么不是在 `SwiftInterface` / `SwiftDump` 入口注册**：工作的起点有三处（索引器 `prepare()`、六个 `Dumpable.dump`、
  四个打印入口，RuntimeViewer 绕过 `printRoot`），注册要在第一次读 seam 之前发生；既然不要开关，直接依赖比在十一个
  入口做惰性注册干净得多，seam 只剩测试注入的用途。
- **核实过的事实**：用一个 `/tmp` 小包实测 SwiftPM 会为启用的 trait 自动定义同名编译条件、条件依赖随 trait 链接；
  `.when(traits:)` 返回 `TargetDependencyCondition?`；`SwiftThunkAnalysis` 的依赖集不含渲染层以上任何模块，翻转不成环。
- **代价**：Capstone 的 ARM64 后端成为渲染层以上所有模块的常规依赖（含 CI 的 `swift test`）；默认输出变化——kind-9
  引用一律解析。
- **验证途中发现的既有问题（未动，另议）**：AGENTS.md 约定的 `--skip IntegrationTests` 是正则子串匹配，会把名字里含
  这个子串的两个正常套件一并跳过——`SwiftThunkAnalysisTests.OpaqueTypeRenderingIntegrationTests`（4 个）与
  `SwiftPrintingTests.NodePrinterIntegrationTests`（5 个）。本节的回归全部改用锚定到 target 的
  `--skip '^IntegrationTests\.'`，两者照跑。修法二选一：把 AGENTS.md 里的 skip 写法锚定，或给这两个套件改名。
- **验证**：
  - 构建：`swift build` 全部 target 通过；产物 `nm` 查到 `SwiftThunkAnalysis` 符号 1506 个，`swift-section` 不再有任何
    注册代码。
  - 快照：删掉 dump / interface 两份基线后以 `record: .missing` 重录，diff 恰好是 fixture 的四行 kind-9 占位变成
    `NoncopyableResourceTest` / `NoncopyableGenericBoxTest<Swift.Int>`（与 `FieldRecordThunkResolutionTests` 钉的类型一致）；
    复跑两套快照套件 65 个测试全绿。
  - 回归（`SwiftInterfaceTests` + `SwiftDumpTests` + `SwiftDiffingTests` + `SwiftIndexingTests` + `SwiftPrintingTests` +
    `SwiftDeclarationRenderingTests` + `SwiftThunkAnalysisTests` + `SwiftSectionCommandTests` + `MachOSwiftSectionTests`，
    按 target 名锚定过滤、`--skip '^IntegrationTests\.'`）：`swift package clean` 后干净构建连跑两遍，均 1350 个测试 /
    260 个套件全绿、退出码 0。之前在增量构建上跑过一次，测试进程在 `MachOSwiftSectionTests.ProtocolRecordTests` 的
    in-process 读取里 SIGSEGV（memcpy 到垃圾地址；该套件不依赖 `SwiftThunkAnalysis`，上一轮同样的回归它是绿的）——与
    AGENTS.md 记载的「增量构建链了过期下游对象」现象吻合，这次的触发是跨模块搬类型加翻转依赖边；清空产物后不再复现。
  - CLI 端到端（SwiftUI，当前系统共享缓存）：未读引用 0 处；与本批第一步（trait 开）的产物输出逐字节相同（diff 0 行）。

## 同日后续：另一支进输出

用户指出「`swift interface` 好像没有打印 2 条分支」。核实：候选在 0028 收尾时只进了模型
（`AssociatedTypeWitnessProjection.conditionalCandidates`），`interface` 的 `renderMergedAssociatedTypeRecords` 与
`dump` 的 `AssociatedTypeDumper.records` 都在打印时用不收集候选的入口现场解析，另一支从未有过输出面。

- **决定**（一轮提问）：排版取「标题一行 + 每支一行带条件、标签对齐、当前支也列在内」；默认打印，不加 flag。
- **改动**：`SwiftDeclarationRendering` 新增 `ConditionalWitnessComment`（纯文本行渲染）与
  `PlatformAvailabilityCondition.platformName / versionText / phrase`（平台号经 `MachOKit.Platform` 翻名，
  Swift IRGen 的 `getBaseMachOPlatformID` 传的就是 Mach-O `PLATFORM_*`）；两条打印路径改用
  `resolveOpaqueTypeCollectingConditionalCandidates(witnessMangledName:conformingTypeName:in:)`，有两支及以上时在
  `typealias` 上方逐行 `Comment`。两个入口内部是同一个 rewriter、都不真的抛错，换入口不改变出错时的输出。
- **测试**：`ConditionalWitnessCommentTests`（纯单元：行文本、对齐、`always` 标签、平台翻名、patch 版本）；
  `OpaqueTypeRenderingIntegrationTests.everyBranchPrintsAboveTheWitness`（SwiftUI：每条有两支的 conformance dump 出来
  都有标题行、`or later:` 行、`before` 行，两支文本不同，`typealias` 等于 `or later` 那支）。
- **验证**：专项 + 两套快照 75 个测试全绿；回归（同上 9 个测试 target，anchored skip）1356 个测试 / 261 个套件全绿、
  退出码 0；fixture 快照基线零改动。SwiftUI（当前系统共享缓存）`interface` 与 `dump` 各出现 17 个分支注释块，与之前输出
  的 diff 都恰好 51 行（17 × 3 行注释），其余逐字节不变。

## 同日后续：专题导读

用户反馈整套功能「大部分看不懂，太复杂了，涉及到汇编」，补写了面向不懂汇编读者的导读 [AccessorThunkResolutionExplained.md](../AccessorThunkResolutionExplained.md)：三段真实 thunk 逐行翻成人话、离线四步、进程内路径、输出与模型、代码地图、验证、降级、术语对照。已登记进文档索引、提案 0028 的配套文档、AGENTS.md 与术语表的延伸阅读。
