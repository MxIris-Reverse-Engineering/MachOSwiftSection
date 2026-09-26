# 0030 - 独立文件上的 accessor thunk 解析：堵住回退误判，补上跨镜像 bind 与带符号的 accessor

- **状态**: Implemented
- **创建日期**: 2026-09-13
- **最后更新**: 2026-09-14
- **所属愿景**: 无
- **关联提案**: [0028](0028-offline-opaque-accessor-thunk-resolution.md)、[0029](0029-thunk-type-construction-evaluation.md)（本提案是它们在「不在 dyld cache 里的独立 Mach-O」上的补全）
- **实现分支 / PR**: `feature/standalone-file-thunk-resolution`
- **配套文档**: [任务报告](../Internal/TaskReports/2026-09-13-standalone-file-thunk-resolution.md)、[AccessorThunkResolutionExplained.md](../Internal/AccessorThunkResolutionExplained.md)「独立文件和 cache 差在哪」一节、[MachODependencies 模块文档](../Internal/Modules/MachODependencies.md)第 1 节、术语表「system root」

## 摘要

0028 / 0029 的验证全部在 macOS 26 的 dyld shared cache 上做。2026-09-13 拿 iOS 18.5 与 iOS 26.5 模拟器运行时里的 SwiftUI、SwiftUICore（独立 Mach-O，chained fixups，跨镜像调用全部经 stub 走 GOT bind）重跑同一份 `next`，发现两类问题。

先划清范围：从 iOS 27 beta 3（24A5380i）起模拟器运行时也只带 `RuntimeRoot/System/Library/Caches/com.apple.dyld/dyld_sim_shared_cache_arm64`（含 `.01` 子缓存），不再有独立的系统框架；用 `next` 加 `--dyld-shared-cache` 直接读 24A434 与 24A5380i 的模拟器 cache，SwiftUI 0 条未读、5 条分支注释与 macOS cache 读法一致，SwiftUICore 0 条未读。所以下面的问题只出现在独立 Mach-O 上：第三方 app 及其内嵌框架（RuntimeViewer 的日常输入，它们的 kind-9 thunk 同样经 bind 调 libswiftCore / SwiftUI 的 accessor）、iOS 26 及更早的模拟器运行时、Xcode 自带的框架、现场编译的 fixture。系统框架本身已经不需要这条路。

第一类是**读错**：`AccessorThunkAnalyzer` 在求值器对某一支给不出结果时，会回退到「这一支只有一个 `bl` 就拿它当答案」。它切分支时只切到两支的汇合点，汇合之后共享的尾巴（`mov x2, x0` 然后 `b` 尾调用到 `ModifiedContent` 的 accessor）既不在统计范围内，尾调用也是 `b` 而不是 `bl`。cache 上求值器总能成功，回退从不触发；独立文件上求值器一失败，回退就把中间值当成答案。iOS 26.5 的 `OnModifierKeysChangedModifier.Body` 印成 `_TaskModifier2`（cache 上是 `ModifiedContent<_ViewModifier_Content<OnModifierKeysChangedModifier>, _TaskModifier2>`），`FeedbackGenerator<A>.Body` 两支印成 `_TaskValueModifier2A`（正确答案是三层 `ModifiedContent<…, _TaskValueModifier2<SensoryFeedback>>`，那个 `A` 是回退对泛型 accessor 用 `demangleContext` 拿到 unbound 树再做参数替换弄出来的）。这正是 0028 反复强调要避免的「真实、全限定、错误的类型」。

第二类是**读不出**，求值器在独立文件上失败的原因有三个，cache 里同一处都是 rebase 到别的镜像所以不受影响：

- **G1 跨镜像 descriptor accessor 经 bind 到达**。thunk `bl` 进 `__stubs`，stub 的 GOT 槽是 bind 名（`SwiftUICore/_$s7SwiftUI15ModifiedContentVMa`、`SwiftUICore/_$s7SwiftUI24_TagTraitWritingModifierVMa`、`libswiftSynchronization/_$s15Synchronization5MutexVMa`、`libswiftCore/_$sSqMa`）。`MachOThunkEnvironment.resolveCallee` 只把 bind 名当运行时入口查，查不到就 `.unknown`。
- **G2 带本地符号的 bound-generic accessor**。`bl` 到本镜像的 `t _$s15Synchronization5MutexVyShySSGGMa`，既不是 descriptor accessor 也不是运行时入口。
- **G3 编译器合并的 accessor `…MaTm`**。`bl _$sypSgMaTm(x0 = request, x1 = 缓存槽, x2 = 实参 metadata, x3 = 真正的 accessor 函数指针)`，函数体是 `blr x3`，符号名（`Optional<Any>`）和真实类型无关。

实测（`accessor function at N` 的条数）：

| 二进制 | 落地前 | `next` | 本提案目标 |
|---|---|---|---|
| iOS 18.5 SwiftUI | 1（G2） | 1 | 0 |
| iOS 26.5 SwiftUI | 2 字段 + 4 个 witness 印成裸 opaque 引用 | 5，另有 2 条分支注释是错的 | 0，注释与 cache 一致 |
| iOS 26.5 SwiftUICore | 4 | 4（G1 ×1、G2 ×1、G3 ×2） | 2（G3 留待后续） |
| macOS 26.6.2 cache SwiftUICore | — | 3（G2 ×1、G3 ×2） | G2 那条取决于 cache 镜像是否保留本地符号，不承诺 |
| iOS 27.0 模拟器 cache（24A434）SwiftUI / SwiftUICore | — | 0 / 0，5 条注释正确 | 不在本提案范围，只作对照 |

目标：先堵回退（宁可留占位也不给错答案），再补 G1 与 G2；G3 需要跨函数的内联求值，本提案只记录形状，留给下一个提案。

## 方案

### 1. 回退只在「整条路径只有这一次调用」时才用

位置：`Sources/SwiftThunkAnalysis/Analysis/AccessorThunkAnalyzer.swift` 的候选循环（现在的 `branchArm(after:assumingConditionTrue:in:)` 切片）与 `Sources/SwiftThunkAnalysis/Analysis/ThunkTypeEvaluator.swift` 的 `Outcome`。

- `ThunkTypeEvaluator.run` 在 `Outcome` 里多带一份 `callSites: [UInt64]`：每一次 `.call` 的目标，以及每一次离开函数的 `.branch`（尾调用，不管环境认不认识）都记一笔。
- 回退条件改为：`result == nil`、`callSites.count == 1`、且函数是以 `ret` 离开的。满足才产出 `.metadataAccessor(address: callSites[0])`；否则报 `.branchIsNotASingleLookup(condition:callCount: callSites.count)`。`branchArm` 切片删掉。
- `AccessorThunkReader.typeNode(for: .metadataAccessor)` 对**泛型** descriptor 一律返回 `nil` 并记 `.selectionNotRecognized`：没有实参时给它命名只会得到 `_TaskValueModifier2A` 这种东西。求值器认识的 accessor 本来就不会走到这里（环境和 reader 用的是同一份 `MetadataAccessorIndex`），走到这里的只剩「索引里有但算不出实参槽」的泛型，所以这条规则不会少掉任何正确答案。
- 现有 `readsBothBranchesOfASplitThunk` 的形状（每支一个 `bl`，汇合处直接 `ret`）继续成立；新增一条测试：汇合后的尾巴是 `mov x2, x0; mov x0, #0; b <环境不认识的目标>`，这一支必须**没有**候选，`callCount` 为 2。这条测试在修之前会失败。

### 2. G1：bind 名 → 依赖镜像 → 该镜像的 accessor 索引

位置：`Sources/SwiftThunkAnalysis/Resolution/MachOThunkEnvironment.swift` 的 `resolveCallee(at:)`（`resolveBind` 命中但不是运行时入口的那条 `return .unknown`）和 `foreignCallee(at:targetAddress:)`；在 `CacheImageResolver` 旁边加一个 `DependencyImageResolver`。

- `DependencyImageResolver` 用 `MachODependencies.DependencyClosure(root:searchPaths:traversal: .direct)` 拿到根镜像的直接依赖（SwiftUI → SwiftUICore、libswiftSynchronization、libswiftCore 都在 `LC_LOAD_DYLIB` 里），对每个依赖镜像用 `exportTrie?.search(by: bindName)` 找到导出偏移，再查 `MetadataAccessorIndex.index(for: dependencyImage)` 得到 descriptor，走现成的 `metadataAccessor(at:descriptorOffset:in:)`。`accessorOriginsByAddress` 已经按镜像记录来源，`ThunkTypeNodeBuilder.boundTypeNode` 会在正确的镜像里 demangle，不用改。
- 名字到镜像的映射按根镜像缓存一次（和 `MetadataAccessorIndex.index(for:)` 一样用 `SharedCache`），因为 `MachOThunkEnvironment` 现在是每读一个 thunk 就新建一个，不能每次都重新打开依赖文件。
- 搜索路径从哪来。依赖镜像在三种地方：宿主的 dyld cache（macOS 第三方 app，现成的 `.systemDyldSharedCache` 已覆盖）、某个 cache 文件（iOS 27+ 模拟器的 `dyld_sim_shared_cache_arm64`、归档的设备 cache，现成的 `.dyldSharedCache(path:)` 已覆盖）、一棵磁盘目录树（iOS 26 及更早的模拟器 `RuntimeRoot`）。只有第三种没有对应的搜索路径，`MachODependencies` 新增 `DependencySearchPath.systemRoot(path:)`：`locate(loadName:)` 时拼 `path + loadName`，存在且是 Mach-O 就用（只处理绝对 install name，`@rpath/…` 落空）。
- 推断规则（`DependencySearchPath.inferred(forRootFileAt:)`）：沿根文件磁盘路径（`MachOFile.url`）向上找 `RuntimeRoot` 形状的祖先目录，它下面有 `System/Library/Caches/com.apple.dyld/dyld_sim_shared_cache_*` 就给 `.dyldSharedCache(path:)`；没有、但根文件路径以它自己的 install name（`imagePath`）结尾，就给 `.systemRoot(前缀)`。老运行时里的系统框架零参数命中；模拟器里的第三方 app 装在设备数据目录下、不在 `RuntimeRoot` 里，推断不到，要靠下一条的开关或宿主传路径（RuntimeViewer 知道设备对应的运行时）。
- 默认搜索路径 = `推断结果 + [.systemDyldSharedCache]`。`DisassemblingAccessorThunkResolver` 增加 `init(searchPaths:)`，`AccessorThunkReader.read` 增加同名参数；宿主想覆盖就通过 `AccessorThunkResolution.$taskResolver` 装一个带路径的 resolver，这是现成的注入点。`swift-section dump` / `interface` 加 `--dependency-search-path <路径>`（可重复；文件按 Mach-O、`dyld_*shared_cache_*` 按 cache、目录按 system root），只喂给 thunk 解析。
- 找不到镜像或导出名时仍是 `.unknown`，多记一条 `ThunkAnalysisLimitation.calleeInUnlocatedImage(bindName:)`，输出保持占位。

### 3. G2：调用目标有符号、且符号是 `type metadata accessor for T`，直接取 T

位置：`resolveCallee(at:)` 里 accessor 索引未命中之后、解码 stub 之前；`ThunkCallee` 新增 `.concreteTypeAccessor(symbolName:)`，`ThunkTypeExpression` 新增 `.namedType(symbolName:)`，`ThunkTypeNodeBuilder.typeNode(for:)` 新增对应分支。

- 查法和 `MetadataNaming.typeNodeFromMetadataSymbol` 一样：`machO.symbols(offset:)` → `SymbolicDemangler.demangleSymbol(for:in:)`，取 `Node.Kind.typeMetadataAccessFunction` 的 `type` 子节点。只接受不含 `dependentGenericParamType` 的类型（惰性特化出来的 accessor 本来就全是具体类型）。表达式里存符号名而不是 `Node`，保持 `Hashable` / `Sendable`，命名时再 demangle。
- 求值器：`apply(callee: .concreteTypeAccessor)` 的结果是 `.type(.namedType(symbolName))`，x0 到 x17 照旧作废。
- bind 到别的镜像的 `…VMa`（unbound）不走这条路：符号名分不清目标是不是泛型，实参要从 descriptor 读，仍走第 2 节。
- 剥掉本地符号的镜像（App Store 二进制）命中不了，这时和 G3 一样留给内联求值。

### 4. G3 只记录形状，不做

`…MaTm` 是编译器把多份相同的 accessor 体合并成一份、把差异（缓存槽、实参、真正的 accessor）提成参数的产物。要解它需要：把环境不认识的本镜像内函数按当前寄存器状态内联求值（深度限制）；解码 `blr xN`（现在 `br` / `braa` 归 `indirectBranch`，`blr` 落到 `unmodelled`）；让从 GOT 槽读出来的 bind 名能作为「函数引用」放在寄存器里。同一套机制也能覆盖剥符号后的 G2。放到下一个提案——已由 [merged-accessor-inline-evaluation](0031-merged-accessor-inline-evaluation.md) 完成。

### 测试

- `AccessorThunkAnalyzerTests`：第 1 节的新形状（修前红）；`ThunkTypeEvaluatorTests`：`callSites` 的记录规则。
- 新增 `Tests/SwiftThunkAnalysisTests/StandaloneFileThunkResolutionTests.swift`，fixture 现场编译（先例：`LegacyDyldInfoBindTests`、`VTableSlotAttributionTests`；按 AGENTS.md 的要求带一个 class）。源码就是今天验证用的 probe：`public struct ProbeGenericHolder<Element: Hashable>: ~Copyable { public let members: Mutex<Set<Element>> }`，当前工具链把它的 kind-9 thunk 编成 `cbz _swift_runtimeSupportsNoncopyableTypes; ldp x1, x2, [x0]; bl stub(_$sShMa); mov x1, x0; bl stub(_$s15Synchronization5MutexVMa)`，两次调用都是 G1；搜索路径用 `.systemDyldSharedCache`（宿主 cache 里有 libswiftCore 与 libswiftSynchronization），期望 `Synchronization.Mutex<Swift.Set<A>>`。同一 fixture 里的非泛型字段（`Mutex<Set<String>>`）今天的工具链走 `__swift_instantiateConcreteTypeFromMangledNameV2`，已经能解，顺带钉住不退化。
- G2 用今天的工具链造不出来（它把具体类型编成 mangled name 实例化），改用两条：一条 tabled 环境的单元测试；一条模拟器门控的集成测试，`MachOFileName.iOS_26_5_Simulator_SwiftUI`（先例：`ExternalSymbolTests` 用 18.5，`ABIEvolutionTests` 用 26.5），断言 `BGTaskSchedulerWrapper.observedTasks` 读成 `Synchronization.Mutex<Swift.Set<Swift.String>>`，运行时不存在就跳过。
- 同一条模拟器门控测试再断言分支注释与 cache 一致：`OnModifierKeysChangedModifier.Body` 两支分别是 `ModifiedContent<_ViewModifier_Content<OnModifierKeysChangedModifier>, _TaskModifier2>` / `…_TaskModifier>`，`FeedbackGenerator<A>.Body` 含 `_TaskValueModifier2<SwiftUI.SensoryFeedback>`，以及 `.tag(_:includeOptional:)` 那三个 witness 不再是占位。这一条依赖 system root 推断（RuntimeRoot）。
- 模拟器 cache 也钉一条：`DyldSharedCachePath` 加 iOS 27.0 模拟器 cache 的路径常量，断言从它读出的 SwiftUI 没有 `accessor function at`。它守的是 cache 读取对模拟器格式（magic `dyld_v1   arm64`、`.01` 子缓存）的支持，与本提案的修改无关，但今天顺手验证过，不钉下来下次又要重跑。运行时不存在就跳过。
- iOS 26.5 运行时装了就有、没装就跳过；新机器上不会再有独立框架的运行时，所以能在每台机器上跑的回归是现场编译的 probe，模拟器门控那条只是额外证据。
- 回归：`swift test --skip '^IntegrationTests\.'` 全绿；fixture 快照基线不变（probe 是独立 fixture，不进 `SymbolTestsCore`）；模拟器 SwiftUI / SwiftUICore 与 macOS cache 的四份输出重跑，unread 数达到上表目标，其余行逐字节一致。

### 文档

AGENTS.md 的 `SwiftThunkAnalysis` 条目补独立文件的三种形状与 G3 的已知限制；`MachODependencies` 模块文档补 `.systemRoot` 与推断规则；[AccessorThunkResolutionExplained.md](../Internal/AccessorThunkResolutionExplained.md) 加一节「独立文件和 cache 差在哪」；ProjectEvolutionLog、任务报告、`swift-section` 的 README（新开关）同批。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-09-13 | Created as Draft | 用户要求：测试 iOS 18.5 模拟器的 SwiftUI / SwiftUICore（独立二进制，有 bind 和 rebase），随后「继续调查怎么解决」 |
| 2026-09-13 | 回退是收紧不是删掉 | `readsBothBranchesOfASplitThunk` 钉住的形状（每支一个 `bl`、汇合处 `ret`）在真实 thunk 里存在且读法正确；错的是切片没看汇合后的尾巴。删掉回退会让那个形状退化成占位 |
| 2026-09-13 | G3 留给下一个提案 | 需要跨函数内联求值与 `blr`，是求值器的结构性扩展；本提案先把「读错」和两个便宜的缺口解决，避免一次改太多 |
| 2026-09-13 | system root 推断只喂给 thunk 解析，静态布局的依赖闭包暂不改（待用户决定） | `StaticLayoutDependencyResolution.default` 现在对模拟器二进制会到宿主 macOS cache 里找同名镜像，理论上可能拿到错误布局，但改它会动 dump / interface 的字段偏移注释，需要单独做渲染 A/B |
| 2026-09-13 | CLI 加 `--dependency-search-path` | 模拟器里的第三方 app 不在 `RuntimeRoot` 下，推断不到运行时的 cache，必须有地方把 `dyld_sim_shared_cache_arm64` 或归档的设备 cache 喂进来；加法式改动不影响既有输出 |
| 2026-09-13 | 范围收窄到独立 Mach-O：第三方 app 及内嵌框架、iOS 26 及更早的模拟器运行时、fixture；推断规则优先找 `RuntimeRoot` 下的模拟器 cache | 用户指出 iOS 27 beta 3 起模拟器也进 cache（`dyld_sim_shared_cache_arm64`）。用 `next` 读 24A434 / 24A5380i 的模拟器 cache 全部正确（SwiftUI 0 未读、5 条注释与 macOS cache 一致，SwiftUICore 0 未读），系统框架不再需要这条路 |
| 2026-09-13 | Accepted → In Progress | 用户批准（「可以」），含两个默认：system root 推断只喂给 thunk 解析、CLI 加 `--dependency-search-path` |
| 2026-09-13 | 导出表偏移改为「`__TEXT` 地址 + 偏移」（`ThunkAddressSpace.address(forExportedSymbolOffset:)`），并回头修掉 `CacheImageResolver.exportedName` 里同样的换算 | 实现时发现 `ExportedSymbol.offset` 是相对 mach header 的偏移，cache 镜像上 MachOKit 原样给出，不是文件偏移：按文件偏移换算把 libswiftCore 的 `_$sShMa` 算进了 `__LINKEDIT`，离真地址 1.8 GB。0028 起 cache 上的读取没被它坑到，只是因为见证表调用的结果本来就被跳过、能力标志的指针即便没认出名字也当非零 |
| 2026-09-13 | `TypeMetadataRecord.contextDescriptor(in:)` 对槽位是 bind 的间接记录返回 `nil` | iOS 26.5 模拟器的 `libswiftSynchronization` 在 `__swift5_types` 里登记了一条指向 `libswiftCore/_$sSqMn`（`Swift.Optional`）的间接记录，离线读到偏移 0 的垃圾 descriptor 就抛 `invalidContextDescriptor`，整个镜像的类型列表全丢（`dump` 一个类型都不印，`Mutex` 的 accessor 也进不了索引）。与 ObjC kind 返回 `nil` 同一条约定 |
| 2026-09-13 | by-name 的 opaque 引用（`opaqueReturnTypeOf`）在 dump 路径不展开，本提案不处理 | `FeedbackGenerator<A>.Body` 经 `<<opaque return type of View.onChange…>>` 到达它的 thunk，`SymbolicDemangler` 对匿名上下文的 opaque descriptor 生成的是按名引用的节点，dump 路径的 `OpaqueTypeRewriter` 只认符号引用形式；iOS 26.5 模拟器 SwiftUI 的 dump 里有 213 行这种引用，macOS cache 上 0 行，是早于本提案的限制。interface 路径经符号索引能解，之前印出的 `_TaskValueModifier2A` 正是 interface 输出。模拟器门控测试因此只断言 dump 里不再出现 `_TaskValueModifier2A` |
| 2026-09-13 | `readsBothBranchesOfASplitThunk` 的合成序列把汇合点改到 `ret` | 原序列里满足支的 `b` 跳到「不满足支的第二个 `bl`」上，只是地址算得随意；新规则看整条路径，这个随意就变成了四次调用。改成跳到 `ret`，测试意图（每支一次查找）不变 |
| 2026-09-13 | 带符号的 accessor 路线拒绝合并函数（`mergedFunction` 节点） | 首次实现只查「是不是 `type metadata accessor for <bound generic>`」，SwiftUICore 两个 G3 字段的 `…MaTm` 符号（`merged type metadata accessor for Any?` / `Array<LayoutDirection>`）就被当成答案印了出来，正是 0028 反复要避免的「真实、错误的类型」。`MachOThunkEnvironment.isConcreteTypeAccessorSymbol` 现在三条拒绝：未绑定、合并、含泛型参数；`ConcreteTypeAccessorSymbolTests` 钉住 |
| 2026-09-14 | In Progress → Implemented | 四个分支按顺序合进 `next`（合并提交 `66ef730a`），落地时取编号 0030；用户指示「把相关分支全部合并进 next 推送，然后把分支删掉」 |
