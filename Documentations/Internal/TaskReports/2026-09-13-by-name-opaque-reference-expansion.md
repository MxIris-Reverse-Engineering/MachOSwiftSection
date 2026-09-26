# 2026-09-13 按名字引用的 opaque 类型也展开

对应提案：[by-name-opaque-reference-expansion](../../Evolutions/0033-by-name-opaque-reference-expansion.md)（前六批见 [2026-09-11 首批](2026-09-11-offline-accessor-thunk-resolution.md)、[2026-09-11 收尾](2026-09-11-accessor-thunk-resolution-follow-up.md)、[2026-09-12 求值器](2026-09-12-thunk-type-construction-evaluation.md)、[2026-09-13 独立文件](2026-09-13-standalone-file-thunk-resolution.md)、[2026-09-13 合并 accessor](2026-09-13-merged-accessor-inline-evaluation.md)、[2026-09-13 stub island](2026-09-13-cache-stub-islands.md)）。

## 问题

用户问「目前的不透明符号引用都全部消除了吗」。15 份样本输出里 `accessor function at` 与 `opaque type symbolic reference` 都是 0，但 iOS 模拟器独立构建的 SwiftUI dump 还剩 `<<opaque return type of …>>`：iOS 26.5 215 行（207 行 witness、8 行方法签名）、iOS 18.5 155 行、iOS 27 beta 3 模拟器 cache 6 行（全是方法签名）；interface、macOS cache、iOS 设备 cache、SwiftUICore 为 0。用户说「一起弄了」。

## 调研

- 第一版提案猜是「带本地符号的 anonymous context」：demangler 通过符号把描述符写成名字。现场编译三种同模块变体（单文件、`-no-whole-module-optimization` 双文件、`fileprivate helper`），编译器都直接把 underlying type 代进去，造不出这个形状。
- 查 iOS 26.5 SwiftUI 二进制：`staticIf…QOMQ` 描述符符号只在 SwiftUICore 里导出，SwiftUI 对它有 5 条 bind。真相是**跨镜像引用**：mangled name 里对描述符的引用是 GOT bind，`SymbolicDemangler` 对 bind 只能 demangle 符号名，得到 `opaqueReturnTypeOf(函数节点)`。cache 里同一处是 rebase 到地址，读取器顺着地址跨镜像读，所以 cache 上没有。
- 双模块 probe（`ProbeCore` 声明 `helper() -> some Equatable`，`ProbeClient` 的 `body` 调它）一编就复现：dump 印 `<<opaque return type of (extension in ProbeCore):ProbeCore.HasBody.helper() -> some>>.0`，**interface 印 `typealias B = ProbeClient.Outer`**——`printOpaqueType` 只印节点的第三个孩子（实参表），把 conformer 当成了 witness。iOS 26.5 SwiftUI 的 interface 里 `SidebarListBody.CollectionViewBody.Body` 同样印成了实参表拼接出来的 `ModifiedContent<CollectionViewListRoot<A, B>_SemanticFeature<Semantics_v7>ModifiedContent<…>, …>`。之前说「interface 0 行」只是它不打这个标记。

## 最终方案

见提案「方案」节。要点：`OpaqueTypeRewriter` 把「节点第一个孩子 → `OpaqueType`」抽成 `opaqueType(referencedBy:)`（指针照旧；名字先查本镜像符号索引）；本镜像没有就 `foreignOpaqueType(referencedBy:)`：把 `global(opaqueTypeDescriptor(节点))` 重新 mangle 成 `$s…QOMQ`，用 `DependencyImageResolver` 按任务里生效的 `DisassemblingAccessorThunkResolver.searchPaths`（或默认推断）定位导出它的镜像，在那个镜像里读描述符；展开体抽成 `expansion(of:forNode:)`，跨镜像时用 `OpaqueTypeRewriter<MachOFile>(machO: 依赖镜像)` 调它，深度、分支选择、候选账本传下去。

## 实际执行

按方案落地。中途一次编辑用了不唯一的锚点（文件里有三个 rewriter 的 `visit`），把另外两个 rewriter 切掉了，`git checkout` 还原后按唯一锚点重做。方法签名里那 8 行不动。

## 验证

- **定向**：`swift test --filter '^(SwiftInterfaceTests\.CrossImageOpaqueReferenceTests|SwiftThunkAnalysisTests\.SimulatorStandaloneSwiftUIThunkTests|SwiftDeclarationRenderingTests\.|SwiftDumpTests\.|SwiftInterfaceTests\.)'` 300 条 / 49 个套件全绿（退出码 0），含两套快照套件——fixture 快照基线不变。新增：`CrossImageOpaqueReferenceTests` 三条（给搜索路径时 dump 读成 `Swift.Int` / `ProbeCore.Pair<Swift.Int, Swift.String>`、interface 印同样两行且不再印 `typealias B = ProbeClient.…`、不给搜索路径时保持按名引用）、`SimulatorStandaloneSwiftUIThunkTests.aWitnessNamingAnotherImagesOpaqueTypeExpands`（`CollectionViewBody.Body` 读成 `ModifiedContent<StaticIf<_SemanticFeature<Semantics_v7>, …>, …>`，全部 witness 无 `opaqueReturnTypeOf`）。
- **全量**：`swift test --skip '^IntegrationTests\.'` 1935 条 / 356 个套件，唯三红的是 `FunctionTypeMetadataTests` 里并行全量时抖动的三条老 flaky（`extendedFlags` / `thrownErrorType` / `thrownErrorTypeOffset`，单独复跑 15 条全绿）。本批的套件与快照套件全绿。
- **CLI 输出**（release 构建，与 stub island 那批的输出 diff）：

| 输出 | 落地前 | 现在 |
|---|---|---|
| iOS 26.5 模拟器 SwiftUI dump | 215 行按名引用（207 witness + 8 方法签名） | 6 行，全是 `ButtonStyleContent` 方法签名里的 `ViewBasedUIButton<opaque(resolvedBody)>`（成员符号原样打印，不经 rewriter）；witness 全部展开，209 行变化，`accessor function at` 仍为 0 |
| iOS 26.5 模拟器 SwiftUI interface | 0 行标记，但 witness 印的是错误类型 | 191 行变化，其中 189 行 `typealias`：`CollectionViewBody.Body` 从实参表拼出来的 `ModifiedContent<CollectionViewListRoot<A, B>_SemanticFeature<…>…>` 变成 `ModifiedContent<StaticIf<_SemanticFeature<Semantics_v7>, ModifiedContent<CollectionViewListRoot<A, B>, …>, …>, …>` |
| iOS 18.5 模拟器 SwiftUI dump | 155 行 | 6 行（同上，方法签名），149 行变化 |
| 其余（iOS 26.5 SwiftUICore、macOS 26.6.2 cache 两份、probe、iOS 26.3.1 设备 cache 两份、macOS 14.7–26.6 普查 11 份） | — | 逐字节一致 |

## 偏差

- 提案第一版的机制（本镜像符号索引）保留为第一步，真正起作用的是第二步跨镜像定位；决策日志有记录。
- interface 打印器对定位不到的按名引用仍会印错误类型，本批只记录（决策日志），留给打印器整理。
- 用户要求建一份进度文档，随本批新增 [OpaqueTypeResolutionProgress.md](../OpaqueTypeResolutionProgress.md)（活文档，每批落地时更新）。
