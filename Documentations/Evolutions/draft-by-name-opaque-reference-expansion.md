# Draft - 按名字引用的 opaque 类型也展开

- **状态**: In Progress
- **创建日期**: 2026-09-13
- **最后更新**: 2026-09-13
- **所属愿景**: 无
- **关联提案**: [standalone-file-thunk-resolution](draft-standalone-file-thunk-resolution.md)（那批的任务报告第一次记录这个限制）、[0028](0028-offline-opaque-accessor-thunk-resolution.md)（`OpaqueTypeRewriter` 的来历）
- **实现分支 / PR**: `feature/dump-by-name-opaque-expansion`，从 `feature/cache-stub-islands` 切出
- **配套文档**: [任务报告](../Internal/TaskReports/2026-09-13-by-name-opaque-reference-expansion.md)、[AccessorThunkResolutionExplained.md](../Internal/AccessorThunkResolutionExplained.md)「按名字引用的 opaque 类型」一节

## 摘要

thunk 那几批做完后，编译器写成指针的 opaque 引用（kind-9 accessor 引用、裸的描述符引用）在 15 份样本输出里全部为 0，但 iOS 模拟器独立构建的 SwiftUI dump 里还剩一类：`<<opaque return type of (extension in SwiftUI):SwiftUI.View.staticIf<…>>>`。iOS 26.5 模拟器 SwiftUI dump 215 行（207 行在 conformance 的 `typealias` witness 上，8 行在方法签名里），iOS 18.5 155 行，iOS 27 beta 3 模拟器 cache 6 行；macOS 各版 cache、iOS 设备 cache、SwiftUICore 都是 0。

来历核实下来是**跨镜像引用**：`View.staticIf` 的 opaque 描述符不在 SwiftUI 里而在 SwiftUICore（两者模块名都是 `SwiftUI`），SwiftUI 的 witness 通过 GOT bind 引用它——一个符号名。`SymbolicDemangler` 对 bind 到的符号只能 demangle 名字，得到 `opaqueReturnTypeOf(函数节点)`，描述符指针在这一步就没有。cache 里同一处是 rebase 到具体地址，rewriter 顺着地址跨镜像读，所以 macOS cache 上没有这一类。现场编译验证：同一模块内的引用（无论 WMO 与否、`fileprivate` 与否）编译器都直接把 underlying type 代入，造不出这个形状；两个模块（`ProbeCore` 声明 `helper() -> some Equatable`，`ProbeClient` 的 `body` 调它）一编就出现，dump 印 `<<opaque return type of (extension in ProbeCore):ProbeCore.HasBody.helper() -> some>>.0`。

后果比「留个占位」更糟：dump 路径印 demangler 的默认写法 `<<opaque return type of …>>`，还算诚实；**interface 路径的 `printOpaqueType` 只印节点的第三个孩子（泛型实参表），实参之间连分隔符都没有**，`SidebarListBody.CollectionViewBody.Body` 印成了 `ModifiedContent<CollectionViewListRoot<A, B>_SemanticFeature<Semantics_v7>ModifiedContent<…>, AccessibilityAttachmentModifier>`——一个真实、错误、看不出来的类型。这批之前之所以说「interface 是 0 行」，是因为它根本不打这个标记。

目标：dump 与 interface 共用的 `OpaqueTypeRewriter` 也认按名字的引用——先查本镜像符号索引，查不到就把描述符符号名重新 mangle 出来（`…QOMQ`），用独立文件那批的 `DependencyImageResolver` 按搜索路径定位导出它的镜像，在**那个镜像里**读描述符、demangle underlying type、解 thunk、展开嵌套，再把本节点的泛型实参代进去；iOS 26.5 / 18.5 模拟器 SwiftUI dump 的 witness 行从 207 / ~150 降到 0，interface 里对应的 witness 从错误类型变成完整类型，其余输出逐字节不变。

## 方案

位置：`Sources/SwiftDeclarationRendering/Extensions/Node+OpaqueType.swift` 的 `OpaqueTypeRewriter.visit`。

- 把「`opaqueType` 节点的第一个孩子 → `OpaqueType`」抽成 `opaqueType(referencedBy:)`，两种拼写：`opaqueTypeDescriptorSymbolicReference` 照旧（含 `MachOImage` 的绝对指针分支）；`opaqueReturnTypeOf` 先问本镜像的 `SymbolIndexStore.shared.opaqueTypeDescriptorSymbol(for:in:)`（符号索引早就按声明节点给每个 `…MQ` 描述符符号建了结构键，interface 打印 `some` 返回类型时用的就是它）。
- 本镜像没有就走 `foreignOpaqueType(referencedBy:)`：把 `global(opaqueTypeDescriptor(节点))` 重新 mangle 成 `$s…QOMQ`，搜索路径取任务里生效的 `DisassemblingAccessorThunkResolver.searchPaths`（CLI 的 `--dependency-search-path`、宿主注入的路径）或 `MachOThunkEnvironment.defaultSearchPaths`，`DependencyImageResolver.location(ofExportedSymbol:searchPaths:)` 定位镜像与导出偏移，`ThunkAddressSpace.address(forExportedSymbolOffset:)` 换成地址再换成该镜像的偏移，`OpaqueType(descriptor:in: 那个镜像)`。
- 展开体抽成 `expansion(of:forNode:)`（ordinal、underlying type 在本 rewriter 的镜像里 demangle、thunk 解析、实参替换、嵌套展开）；跨镜像的情况用 `OpaqueTypeRewriter<MachOFile>(machO: 依赖镜像, …)` 调它，深度、分支选择、候选账本原样传下去。实参是本节点的树，两边通用。
- 定位不到（没给搜索路径、依赖不在）就原样返回，行为不变。
- 方法签名里那 8 行不动：它们是成员符号的原样打印（参数类型里提到了另一个函数的 opaque 返回类型），不经 rewriter；interface 对同一批方法印的是 protocol 声明。
- 模块依赖：`SwiftDeclarationRendering` 已经依赖 `MachOFoundation`（含 `MachOSymbols`），只加一行 import。

### 测试

- 现场编译的双模块 fixture（`CrossImageOpaqueReferenceTests`，放在 `SwiftInterfaceTests` 里因为要同时验 interface）：`ProbeCore` 声明 `HasBody` 与 `public func helper() -> some Equatable`，`ProbeClient` 的 `Outer.body` / `Composite.body` 调它。给 `.machOFile(path: libProbeCore)` 搜索路径时 dump 路径读成 `Swift.Int` / `ProbeCore.Pair<Swift.Int, Swift.String>`，interface 印同样两行且不再印 `typealias B = ProbeClient.…`；不给搜索路径时保持按名引用。落地前的 CLI 对它 dump 印 `<<opaque return type of …>>`、interface 印 `ProbeClient.Outer`。
- 模拟器门控（`SimulatorStandaloneSwiftUIThunkTests` 补一条）：iOS 26.5 SwiftUI 的 `SidebarListBody.CollectionViewBody.Body` witness 读成 `ModifiedContent<StaticIf<…>, AccessibilityAttachmentModifier>`，且全部 witness 里不再有 `opaqueReturnTypeOf` 节点。
- 回归：定向套件、全量；fixture 快照基线不变（`SymbolTestsCore` 的快照里没有这种引用）；release CLI 重跑七份标准输出与跨版本普查，只有 iOS 26.5 / 18.5 模拟器 SwiftUI 的 dump 与 interface 变化。

### 文档

AGENTS.md 的 `SwiftThunkAnalysis` 条目里那句「by-name 的 opaque 引用不展开」改成已解，说明 interface 曾经的错误打印；[AccessorThunkResolutionExplained.md](../Internal/AccessorThunkResolutionExplained.md) 已知降级表更新；ProjectEvolutionLog 新一节；任务报告；索引。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-09-13 | Created as Draft，直接 In Progress | 用户问「不透明符号引用都全部消除了吗」，答复里指出只剩这一类，用户说「一起弄了」 |
| 2026-09-13 | 在 rewriter 里按名字查符号索引，不改 `SymbolicDemangler` 的输出 | demangler 产出的 `opaqueReturnTypeOf` 是 interface 打印 `some` 和符号索引建键都依赖的形状，改它波及面大；rewriter 多认一种拼写只加不减 |
| 2026-09-13 | 方法签名里的 8 行不处理 | 那是成员符号的原样打印，不是类型节点的展开问题；interface 对同一批方法印的是 protocol 声明，本来就不含它 |
| 2026-09-13 | 机制改成跨镜像定位，不只查本镜像符号索引 | 提案第一版以为是「带符号的 anonymous context」导致的；现场编译三种同模块变体（单文件、`-no-whole-module-optimization` 双文件、`fileprivate`）编译器都把 underlying type 代入，造不出；查 iOS 26.5 SwiftUI：`staticIf…QOMQ` 只在 SwiftUICore 里导出，SwiftUI 对它是 5 条 bind。本镜像索引的那一步保留，成本为零 |
| 2026-09-13 | 搜索路径复用 `DisassemblingAccessorThunkResolver.searchPaths` | 这类引用和 kind-9 thunk 的跨镜像调用是同一件事的两面（都是独立文件里对别的镜像的 bind），CLI 的 `--dependency-search-path` 与宿主注入自然覆盖两者，不另开开关 |
| 2026-09-13 | interface 对未展开的按名引用印出错误类型，本批记录、随本批消失 | `printOpaqueType` 只印节点的第三个孩子，`typealias B = ProbeClient.Outer` 就是把 conformer 当成了 witness。根治在打印器（印不出就印 `<<opaque return type of …>>`），但能定位的引用现在都展开了，剩下的只有依赖不在时的情况，留给打印器的下一次整理 |

