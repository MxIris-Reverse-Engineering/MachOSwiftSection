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
