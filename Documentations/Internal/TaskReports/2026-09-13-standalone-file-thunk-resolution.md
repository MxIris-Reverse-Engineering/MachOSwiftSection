# 2026-09-13 独立文件上的 accessor thunk 解析

对应提案：[standalone-file-thunk-resolution](../../Evolutions/0030-standalone-file-thunk-resolution.md)（0028 / 0029 在不在 dyld cache 里的 Mach-O 上的补全；前三批见 [2026-09-11 首批](2026-09-11-offline-accessor-thunk-resolution.md)、[2026-09-11 收尾](2026-09-11-accessor-thunk-resolution-follow-up.md)、[2026-09-12 求值器](2026-09-12-thunk-type-construction-evaluation.md)）。

## 问题

用户要求测 iOS 18.5 模拟器的 SwiftUI / SwiftUICore：dyld cache 里的镜像没有外部依赖，独立二进制才有 bind 和 rebase，这部分从来没测过。用 `next`（`3621060c`）的 release `swift-section` 跑 iOS 18.5 与 iOS 26.5 两个运行时的 SwiftUI、SwiftUICore 各一份 `dump` 和 `interface`，再用功能落地前的提交（`246526ef^`）编一份基线做对照。

## 调研

- **iOS 18.5 基本测不到**：两个二进制反射记录里能看见的 kind-9 引用只有 `BGTaskSchedulerWrapper.observedTasks` 一条，基线与 `next` 四份输出逐字节一致。`__swift5_typeref` 里扫出的 1500 多个 kind-9 大多是代码侧 `__swift_instantiateConcreteTypeFromMangledName` 用的名字，不是反射记录，不能当分母。
- **iOS 26.5 才有料**：SwiftUI 基线 2 个字段未读加 4 个 witness 印成裸 opaque 引用，`next` 上 5 条 `accessor function at` 加 2 条分支注释；SwiftUICore 两边都是 4 条。同一份 `next` 在 macOS 26.6.2 系统 cache 上 SwiftUI 0 条未读、17 条注释。
- **两条注释是错的**。`OnModifierKeysChangedModifier.Body` 印成 `_TaskModifier2`，cache 上是 `ModifiedContent<_ViewModifier_Content<OnModifierKeysChangedModifier>, _TaskModifier2>`；`FeedbackGenerator<A>.Body`（interface 输出）印成 `_TaskValueModifier2A`。反汇编 `0x3bdb08` / `0x3bd14c`：两支各 `bl` 一个本地 accessor，然后汇合、`mov x2, x0`、`b` 尾调用到 `ModifiedContent` 的 accessor 的 stub。分析器的单查找回退把分支切到汇合点为止，尾巴没算，尾调用又是 `b` 不是 `bl`，于是每支「恰好一次调用」，取了中间值。cache 上求值器总能成功，回退从不触发，所以三批验证都没暴露。
- **三种读不出的形状**，全部经反汇编和 `dyld_info -fixups` 确认：G1 跨镜像 descriptor accessor 只有 bind 名（`SwiftUICore/_$s7SwiftUI15ModifiedContentVMa`、`libswiftSynchronization/_$s15Synchronization5MutexVMa`、`libswiftCore/_$sSqMa`）；G2 本镜像带本地符号的专用 accessor（`t _$s15Synchronization5MutexVyShySSGGMa`）；G3 编译器合并的 `…MaTm` accessor（真 accessor 从 `x3` 传入，函数体 `blr x3`）。这些字段 thunk 都先 `cbz _swift_runtimeSupportsNoncopyableTypes`，不支持时返回 `_$sytN + 8`。
- **范围更正**：用户指出 iOS 27 beta 3 起模拟器运行时只带 `dyld_sim_shared_cache_arm64`。核实 24A5355p / 24A5370g 还是独立框架，24A5380i 起是 cache。用 `next` 加 `--dyld-shared-cache` 读 24A434 与 24A5380i 的 SwiftUI：0 条未读、5 条注释与 macOS cache 一致；SwiftUICore 0 条未读。所以这批只关乎第三方 app 及内嵌框架、老运行时、fixture。
- **现场编译的 probe**：`ProbeGenericHolder<Element: Hashable>: ~Copyable { let members: Mutex<Set<Element>> }` 用当前工具链编出来正好是 G1（`bl stub(_$sShMa)` 再 `bl stub(MutexVMa)`）；具体类型的 `Mutex<Set<String>>` 字段编成 `__swift_instantiateConcreteTypeFromMangledNameV2`，早已能解。G2 只有 Apple 的 SwiftUI 构建里有。

## 最终方案

见提案「方案」节。要点：求值器记录整条路径的调用点（`bl` 与离开函数的 `b`）和是否以 `ret` 离开，回退只在分支后恰好一次调用且返回时才用，泛型 descriptor 的 accessor 不许无实参命名；bind 名经 `MachODependencies` 定位的依赖镜像的导出表到该镜像的 accessor 索引（`DependencyImageResolver`，按根镜像共享）；`MachODependencies` 新增 `.systemRoot` 搜索路径、`inferred(forRoot:)` 推断、`init(classifyingPath:)` 归类；`DisassemblingAccessorThunkResolver(searchPaths:)` 与 CLI 的 `--dependency-search-path`（dump / interface / snapshot）；带符号的专用 accessor 直接取符号里的类型（`ThunkCallee.concreteTypeAccessor`、`ThunkTypeExpression.namedByAccessorSymbol`）。G3 留给下一个提案。

## 实际执行

按方案落地，另有三处是实现中才发现的：

1. **导出表偏移的语义**。`ExportedSymbol.offset` 是相对 mach header 的偏移，cache 镜像上 MachOKit 原样给出。把它当文件偏移换算，libswiftCore 的 `_$sShMa` 会落进 `__LINKEDIT`（0x1FFD3E9A4，离真地址 0x1940FD0A4 1.8 GB），accessor 索引查不到。改成 `__TEXT` 段地址加偏移（`ThunkAddressSpace.address(forExportedSymbolOffset:)`），对 dylib、可执行文件、cache 镜像都对；`CacheImageResolver.exportedName` 自 0028 起就是错的换算，一并改掉——cache 上的读取没被坑到，只是因为见证表调用的结果本来被名字跳过、能力标志的指针没认出名字也当非零。
2. **`__swift5_types` 里指向别的镜像的间接记录**。iOS 26.5 模拟器的 `libswiftSynchronization` 登记了一条 bind 到 `libswiftCore/_$sSqMn` 的记录，离线读到偏移 0 的垃圾 descriptor 就抛 `invalidContextDescriptor`，整个镜像的类型列表全丢，`dump` 一个类型都不印。`TypeMetadataRecord.contextDescriptor(in:)` 现在对槽位是 bind 的间接记录返回 `nil`，和 ObjC kind 同一约定。
3. **by-name 的 opaque 引用**。`FeedbackGenerator<A>.Body` 的 witness 里 `onChange` 的 opaque 类型是 `opaqueReturnTypeOf`（`SymbolicDemangler` 对匿名上下文 descriptor 的输出），dump 路径的 `OpaqueTypeRewriter` 只认符号引用形式，不展开；iOS 26.5 SwiftUI 的 dump 里 213 行这种，macOS cache 0 行。早于本批，没动；测试只断言不再出现 `_TaskValueModifier2A`。

4. **合并函数的符号不能当答案**。带符号的 accessor 路线第一版只看「是不是 `type metadata accessor for <bound generic>`」，SwiftUICore 两个 G3 字段的 `…MaTm` 符号（`merged type metadata accessor for Any?`，另一个构建里是 `Array<LayoutDirection>`）通过了检查，`PlatformAccessibilitySettingsDefinition.cache` 被印成 `Swift.Array<SwiftUI.LayoutDirection>`——CLI 对比时抓到的。合并函数的符号名是合并前某一份的名字，真正的 accessor 从 `x3` 传进来；`isConcreteTypeAccessorSymbol` 现在遇到 `mergedFunction` 节点直接拒绝，`ConcreteTypeAccessorSymbolTests` 钉三条拒绝，模拟器门控测试断言这两个字段保持占位。

另外把 `readsBothBranchesOfASplitThunk` 合成序列的汇合点改到 `ret`（原来跳到另一支的第二个 `bl`，只是地址算得随意）。

## 验证

- **定向**：`swift test --filter '^(SwiftThunkAnalysisTests|MachODependenciesTests|SwiftSectionCommandTests)\.'` 101 条全绿（退出码 0）。新增：`AccessorThunkAnalyzerTests.refusesAnArmWhoseSharedTailCallsSomethingElse`（修前红）、`ThunkTypeEvaluatorTests` 的调用点记录与带符号 accessor、`ConcreteTypeAccessorSymbolTests`（未绑定 / 合并 / 非 accessor 三条拒绝）、`StandaloneFileThunkResolutionTests`（probe 经宿主 cache 解出 `Synchronization.Mutex<Swift.Set<A>>`；无搜索路径时留占位并记 `calleeInUnlocatedImage($sShMa)`；从文件位置推断出 system root）、`SystemRootSearchPathTests`（定位、失败上报、两种推断、主 cache 文件名判定、按形状归类）、模拟器门控的 `SimulatorStandaloneSwiftUIThunkTests`（`observedTasks` → `Mutex<Set<String>>`、`Drag.LazyItem<A>.state` → `Mutex<Drag.LazyItem<A>.State>`、`OnModifierKeysChangedModifier.Body` 两支与 cache 一致、无未读、libswiftSynchronization 能列出类型、SwiftUICore 两个合并 accessor 字段保持占位）与 `SimulatorCacheSwiftUIThunkTests`（iOS 27.0 模拟器 cache 无未读）。
- **全量**：`swift test --skip '^IntegrationTests\.'`。第一遍 1902 条，唯二红的是 `SharedCacheTests` 里两条按墙钟断言并行度的老 flaky（单独复跑通过）；最后一次改动（合并函数拒绝、CLI 路径校验）后整跑第二遍，1907 条 / 351 个套件全绿，退出码 0。
- **CLI 输出对比**（release 构建，与落地前 `next` 的同一份输出 diff）：

| 二进制 | 落地前未读 | 现在未读 | 变化 |
|---|---|---|---|
| iOS 26.5 模拟器 SwiftUI（dump / interface） | 5，2 条注释错 | 0，5 条注释 | `observedTasks`、`LazyItem<A>.state` 解出；`OnModifierKeysChangedModifier.Body` 两支带上外层 `ModifiedContent`；`.tag` 的三个 witness 从占位变成两支完整类型；`_TaskValueModifier2A` 消失 |
| iOS 26.5 模拟器 SwiftUICore | 4 | 2 | `StatefulMaterialProviderBox.cache`（G1）、`MaterialBackdropProxy.Storage.data`（G2）解出；两个 `…MaTm` 字段保持占位 |
| iOS 18.5 模拟器 SwiftUI | 1 | 0 | `observedTasks`（G2） |
| macOS 26.6.2 系统 cache SwiftUI | 0 | 0 | 逐字节一致（17 条注释不变） |
| macOS 26.6.2 系统 cache SwiftUICore | 3 | 2 | `MaterialBackdropProxy.Storage.data` 经本地符号解出；两个 `…MaTm` 字段保持占位 |
| 现场编译的 probe | 1 | 0 | `members: Mutex<Set<A>>` 经宿主 cache 解出 |

- `--dependency-search-path /nonexistent-root` 以退出码 64 报 `does not exist`，不再静默。
- fixture 快照基线不变（全量里的 `SwiftDumpTests` / `SwiftInterfaceTests` 快照套件通过）。

## 偏差

- 提案写的是「回退条件 `callSites.count == 1`」，实际按「分支之后」过滤调用点（可用性检查本身也是一次 `bl`）。
- 提案没预见导出表偏移与 `__swift5_types` 间接记录这两个坑；都是让 G1 真正走通的前提。
- `--dependency-search-path` 也接到了 `snapshot`（索引时同样解 witness）。
- 提案里的 `ThunkTypeExpression.namedType(symbolName:)` 落地时叫 `namedByAccessorSymbol(symbolName:)`，被调方叫 `ThunkCallee.concreteTypeAccessor(symbolName:)`，只接受类型树里含 `boundGeneric…` 节点的符号——descriptor 自己的 unbound accessor 归索引管，名字里没绑实参的一律不认。
