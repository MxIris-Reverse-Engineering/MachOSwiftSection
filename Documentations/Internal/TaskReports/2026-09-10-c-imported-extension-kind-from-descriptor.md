# 2026-09-10 C 导入类型的合成 extension 按描述符定 kind（0023 后续修正）

对应提案：[0023-type-import-info-identity](../../Evolutions/0023-type-import-info-identity.md)（后续修正，不另立提案）

## 问题

用户在 RuntimeViewer 里对比读 TypeImportInfo（提案 0023）前后的 SwiftUICore 侧边栏，认为「加了 ImportInfo 之后很多类型丢了」。截图里能看到的差异集中在 `__C` 前缀的 extension / conformance 条目。

## 调研

**先证明有没有丢。** 分别在改动前（`7071ac46`，读 ImportInfo 之前的最后一个提交）和当前 `next` 上构建 `swift-section` CLI 与 RuntimeViewer 自己的 `runtime-viewer-cli`，对系统 dyld cache 里的 SwiftUICore 各跑一次：

| 指标 | 改动前 | 改动后 |
|------|--------|--------|
| `dump` 行数 | 99075 | 99075 |
| `interface` 行数 | 94216 | 94804 |
| `interface` 里不同的 extension 目标数 | 3570 | 3562 |
| RuntimeViewer 顶层对象（`runtime-viewer-cli types`） | 3202 | 3138 |
| 其中 Swift Struct / Class / Enum / Protocol | 1781 / 256 / 154 / 400 | 完全相同 |
| 其中 Swift Enum Conformance | 88 | 24 |
| 其中 Swift Class Extension / Struct Extension | 29 / 97 | 28 / 98 |

- 类型与协议一个不少。少的 64 个「Swift Enum Conformance」顶层条目（`SwiftUI.WindowEnvironmentKeys.IsMain`、`SwiftUI.BindingOperations.Equals`、`SwiftUI.Edge.Set` 一类）全是嵌套在 enum 命名空间下的 struct/class：旧版 conformance 那侧用树遍历推 kind、先碰到外层 enum，与类型描述符的 struct 对不上，RuntimeViewer 于是把它当成「本镜像里没有的类型」提成顶层条目，而类型自己的 interface 里反而没有这块。改后键不比 kind，conformance 并回类型本身，并带上之前丢失的 `typealias` 见证（`IsMain` 的 `typealias Value = Swift.Bool`、`Equals` 的 `Base` / `Projected`）。
- `__C` 条目全是改名：`__C.Subgraph` → `__C.AGSubgraphRef`、`__C.AnyAttribute` → `__C.AGAttribute`、`__C.Importance` → `__C.AXCustomContentImportance`、`__C.Key` / `Mode` / `Name` / `Unit` / `URLResourceKey` / `InlinePresentationIntent` 加回 `NS` 前缀、CF 类加 `Ref` 后缀、八个 `__C.*Options` → `__C.RBSymbolAnimation*Flags`。其中 8 个改名后与已存在的条目合一，所以 `__C` 目标数 117 → 109。
- 对比方法（可复用）：把 RuntimeViewer 的三个包 rsync 到一个父目录、在父目录放兄弟包符号链接并让 `MachOSwiftSection` 指向旧提交的 `git archive`，`USING_LOCAL_DEPENDENCIES=1` 构建 `runtime-viewer-cli`，用 `--host-directory` 隔离新旧两个 host，`load` → `types --json` → `host stop`，比对 `(kind, displayName)` 集合。

**真正的退化只有一处。** `__C.AGSubgraphRef` 是 CF 类，改名前（`__C.Subgraph`）列在「Swift Class Extension」，改名后列进了「Swift Struct Extension」；同一类型的 conformance（走描述符 kind）仍在「Swift Class Conformance」。根因：`SwiftDeclarationIndexer.indexTypes` 给「嵌套在 `extension <C 类型>` 里的类型」造合成 extension 时，kind 由 `extensionTypeNode.typeKind` 推导，而 0023 让 `Node.typeKind` 对 typeAlias 树一律返回 `.struct`（当时只为让名字能建出来并入键）。typeAlias 树分不出 CF 类（一个对象引用）和 typedef struct，但被扩展上下文的描述符分得出。

## 方案

只改这一条路径：demangle 出的被扩展类型是 `typeAlias` 树时，解析被扩展上下文 mangled name 开头的符号引用拿到描述符，用描述符的 kind；描述符拿不到（间接引用落在 bind 符号上）或树不是 typeAlias 时保持原样。解析逻辑放在 `SwiftInspection`（`SymbolicDemangler.extendedTypeContextDescriptor(forExtendedContext:in:)`），复用 demangler 自己的控制字节解码 `SymbolicReference.symbolicReference(for:)` 与既有的 `RelativeDirectPointer` / `RelativeIndirectSymbolOrElementPointer` 解析；`SwiftIndexing` 只多一个私有 helper 决定 kind。嵌套在同类 extension 里的 protocol 走同一条 helper。

## 实际执行

- `SymbolicDemangler` 新增 `extendedTypeContextDescriptor(forExtendedContext:in:)`：取 mangled name 的第一个 lookup 元素，只认 `.context` 类符号引用（直接或间接），解析成 `ContextDescriptorWrapper` 后投影为 `typeContextDescriptorWrapper`；其它形态一律返回 nil。
- `SwiftDeclarationIndexer` 新增私有 helper `extendedTypeKind(of:extendedContext:)`：`.type` 节点的首孩子是 `.typeAlias` 且描述符可解析时用 `TypeContextDescriptorWrapper.kind`，否则 `Node.typeKind`。两处调用点（类型嵌套、协议嵌套）都改走它。
- 回归测试 `CImportedExtensionKindTests`（`Tests/SwiftIndexingTests/`）：bridging header 里一个 `CF_BRIDGED_TYPE(id)` 的 CF 类 `ProbeObjectRef` 和一个匿名 tag 的 typedef struct `ProbeRecord`，Swift 侧各在其 extension 里嵌一个 struct；断言 `typeExtensionDefinitions` 里 `__C.ProbeObjectRef` 的键是 `.type(.class)`、`__C.ProbeRecord` 是 `.type(.struct)`，并断言该 extension 恰好带那个嵌套类型。

## 验证

- **红/绿**：`CImportedExtensionKindTests` 修前 `extensionOfCFClassIsFiledAsClass` 红（`__C.ProbeObjectRef` 的键是 `.type(.struct)`）、`extensionOfCTypedefStructIsFiledAsStruct` 绿；修后两条都绿（退出码取自 `swift test` 本身）。
- **相关套件**：`SwiftIndexingTests` / `SwiftInterfaceTests`（含 `SymbolTestsCoreInterfaceSnapshotTests`）/ `SwiftDumpTests` / `SwiftPrintingTests` / `SwiftDiffingTests` 及 `CImportedTypeConformanceInterfaceTests`、`CImportedTypeIdentityTests`、`ExtensionContainerUnificationTests`，393 条 / 63 个 suite 全过，快照无变化——`kind` 不参与键，也不打印，所以 dump / interface 输出不动。
- **全量** `swift test --skip IntegrationTests`：见文末「验证记录」。
- **RuntimeViewer 实测**：把 `runtime-viewer-cli` 分别指向修前的 `next` 与修复分支各构建一份，对 SwiftUICore 导出侧边栏对象清单比对：3138 个顶层对象两侧只差一条——`__C.AGSubgraphRef` 从「Swift Struct Extension」回到「Swift Class Extension」（Class Extension 28 → 29、Struct Extension 98 → 97），其余条目逐条相同。

## 与提案的偏离

无；这是 0023 的后续修正，提案决策日志已加一行。

## 验证记录

- 全量 `swift test --skip IntegrationTests`（退出码取自 `swift test` 本身）：1828 条 / 332 个 suite，只有 `FunctionTypeMetadataTests`（提案 0026 的 in-process 套件）的 `extendedFlags` / `thrownErrorType` / `thrownErrorTypeOffset` 三条报 `resolved → nil`；同一套件单独重跑 16 条全过。该套件不经过本批任何改动（本批只动 `SwiftInspection` 与 `SwiftIndexing`，它只测 `MachOSwiftSection` 的 in-process 读取），判定为并行全量时的顺序相关抖动，与 `SharedCacheTests` 那对已知假失败同类。
