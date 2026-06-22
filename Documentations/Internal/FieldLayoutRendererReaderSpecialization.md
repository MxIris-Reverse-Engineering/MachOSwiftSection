# FieldLayoutRenderer 按 reader 特化（MachOImage 运行期 / MachOFile 静态）

## 背景与动机

`SwiftDeclarationRendering.FieldLayoutRenderer<MachO>` 是「元数据派生字段注释」的唯一真源
（`// Field offset:`、`// Type Layout:`、expanded 嵌套偏移树、`// Enum Layout`、spare-bit），
被 `SwiftDump` 的 dumpers 与 `SwiftPrinting` 的 printer 共用。

改造前它是**单一泛型实现**，几乎所有注释都依赖**运行期**机制
（`StructMetadata.createInProcess`、value-witness table、`RuntimeFunctions.getTypeByMangledNameInContext`、
metadata accessor），并 gating 在 `machO.asMachOImage` 上。后果：对 **MachOFile**（离线
`swift-section dump` / `interface`），离线进程内无法物化 metadata，因此 field offset / end offset /
Type Layout / expanded 树 / Enum Layout **全部为空**。

`SwiftLayout`（静态布局引擎）正是为离线设计：`StaticLayoutCalculator<MachOFile>` 不加载进程、
不调 accessor，即可算出 struct/class 字段 offset、每字段类型的 `TypeLayoutInfo`、resilient class 字段起点、
以及跨模块字段（经依赖闭包）。本次改造把 `FieldLayoutRenderer` 拆成两套按 reader 特化的实现，
并把 SwiftLayout 接到 MachOFile 路径上，使离线输出**与 MachOImage 全量对齐**。

## 设计

### 1. 泛型 facade + 两套特化实现（分派）

`FieldLayoutRenderer<MachO>` 仍是调用方看到的泛型类型，但退化为**瘦分派 facade**：保留存储属性、
`init`、`enumValue`，以及 6 个调用方入口（`fieldOffsets`、`storedFieldComments`、`enumLayout`、
`enumPrefixComments`、`enumCaseComments`）。每个入口按具体 reader 分派：

```swift
if let imageRenderer = self as? FieldLayoutRenderer<MachOImage> { imageRenderer.<image impl> }
else if let fileRenderer = self as? FieldLayoutRenderer<MachOFile> { fileRenderer.<file impl> }
```

之所以能 `self as?` 到具体泛型实例化：只有 `MachOFile` / `MachOImage` 两种类型 conform
`MachOSwiftSectionRepresentableWithCache`，两分支即穷尽；值类型对具体泛型实例化的条件下转在运行期可用。
调用方全是泛型（`SwiftDeclarationPrinter<MachO>` / 各 dumper），无法直接调用 `where MachO == X`
约束扩展里的方法，故必须经 facade 分派 —— 这也保持了 6 个入口的签名不变、调用点零改动。

- `FieldLayoutRenderer+MachOImage.swift`（`extension … where MachO == MachOImage`）：原运行期实现整体移入，
  仅把 4 个入口改名为 image 专用名（`runtimeFieldOffsets`、`imageStoredFieldComments`、`imageEnumLayout`、
  `imageEnumPrefixComments`、`imageEnumCaseComments`）。**行为零改动**（含 PAC-fault-avoiding 的泛型实参静态替换）。
- `FieldLayoutRenderer+MachOFile.swift`（`extension … where MachO == MachOFile`）：新的 SwiftLayout 静态实现。

### 2. 注入 seam：`StaticFieldLayoutProvider`（建一次，注一次）

构造 `StaticLayoutCalculator`（尤其是依赖闭包）有成本，不能每类型重建。引入**非泛型**协议
`StaticFieldLayoutProvider`（放进非泛型的 `DeclarationRenderConfiguration` 里随配置流动），由会话根
**建一次**后注入：

- `MachOFileStaticFieldLayoutProvider` 包 `StaticLayoutCalculator<MachOFile>`，所有访问经一把锁串行化
  （resolver 的记忆化无内部同步，单锁即保证跨并发渲染安全），`@unchecked Sendable`。
- `StaticLayoutDependencyResolution`：`.singleImage` / `.dependencyClosure(searchPaths:)`，默认
  `.dependencyClosure([.systemDyldSharedCache])`（用户确认的默认）。
- 注入点：`SwiftDeclarationPrinter` 首次渲染时懒建一次（仅当 reader 是 MachOFile 且开了任一 layout flag）
  并注入每类型构造的 `DeclarationRenderConfiguration`；`swift-section dump` 在建好 `dumpConfiguration`
  后、循环前建一次。

`FieldLayoutRenderer.init` 在 reader 为 MachOFile、开了 layout flag、且 provider 存在时，**每类型预算一次**
`staticAggregateFieldLayout: AggregateFieldLayout?`（reader 无关数据，存于 facade）。MachOFile 路径的
`fieldOffsets` / end offset / Type Layout 都从它取；缺 provider 时为 nil → 输出为空 = 改造前行为（无回归）。

### 3. SwiftLayout 新增 public 便捷 API（`StaticLayoutCalculator`）

- `typeLayout(forMangledTypeName:)`、`typeLayout(forDescriptor:)`：枚举 payload / 枚举自身整型大小。
- `nestedFieldOffsetTree(forMangledTypeName:baseOffset:depthLimit:) -> [NestedFieldOffset]`：expanded
  嵌套树。在 SwiftLayout 内完成解析（多镜像 universe、按 mangled name 跨闭包定位 descriptor、逐层重建泛型环境、
  在解析所得 image 上算偏移），renderer 只负责树 → `// ├──` 注释的呈现。
- `fieldLayout(ofStruct:/ofClass:)` 抽出 `in image:` 参数，使嵌套树能在依赖镜像里计算。

### 4. 渲染细节

- end offset：优先取下一字段偏移；末字段用 `fields[i].layout.size`（静态每字段都有）。
- Type Layout：MachOFile 走 `configuration.staticTypeLayoutComment(_:)`，由 `TypeLayoutInfo` 直接渲染默认格式。
- Enum Layout：静态版 `computeEnumLayout`——payload size/XI 经 `provider.typeLayout(forMangledTypeName:)`，
  枚举自身大小经 `typeLayout(forDescriptor:)`，multi-payload 的 spare bytes 经 `__swift5_mpenum`（section 读，
  MachOFile 本就可读），复用 `SwiftInspection.EnumLayoutCalculator.calculate{MultiPayload,TaggedMultiPayload,SinglePayload}`。

## 正确性验证

- `StaticLayoutVsRuntimeTests`（既有）已逐字段证明 SwiftLayout 偏移 == 运行期 accessor。
- 新增 `SwiftDeclarationRenderingTests`：renderer<MachOFile> 经 facade 取出的 `fieldOffsets` ==
  `StaticLayoutCalculator` 直算结果（传递性即证 renderer == 运行期），并验证无 provider 时降级为 nil、
  Type Layout / Enum Layout 注释如期渲染。**不在该 target 内重做进程内 metadata 物化**（对部分类型会触发
  不可捕获的 trap，且已被 `StaticLayoutVsRuntimeTests` 覆盖）。
- 端到端：`swift-section interface --emit-offset-comments <file>` 现对离线文件产出 200 条 `// Field offset:`
  （此前为零）；`SymbolTestsCoreInterfaceSnapshotTests` 快照纯新增 431 行 offset/type-layout 注释（已重录）。
- 回归全绿：SwiftLayoutTests 37、SwiftPrintingTests 18、SwiftDumpTests 65、SwiftInterfaceTests 52、
  新增 4、CoverageInvariant 1。

## 已知限制

- **`typeLayoutTransformer` 仅作用于运行期路径**：transformer 类型绑定运行期 `TypeLayout`，无法从静态
  `TypeLayoutInfo` 在 `MachOSwiftSection` 外合成（其 init 仅 `@testable` 可见，且给核心模型加 public init
  会牵动覆盖率不变量、属层级越界），故 MachOFile 路径恒走默认格式。
- **tuple 字段的 Type Layout 无逐元素分解**：`TypeLayoutInfo` 不携带元素信息，静态路径输出单行聚合布局。
- expanded 树对深层泛型实例化按 SwiftLayout 现状逐子树降级（停止递归而非错算）。
- 跨模块解析默认走依赖闭包（系统 dyld cache）；`.singleImage` 下跨模块字段降级。`@rpath` 未展开（沿用
  SwiftLayout 闭包 MVP 限制）。

## CLI 触达

- `swift-section interface --emit-offset-comments` / `--emit-expanded-field-offsets`（既有 flag，现走静态路径）。
- `swift-section dump` 新增 `--emit-field-offsets`、`--emit-type-layout`、`--emit-enum-layout`、
  `--emit-expanded-field-offsets`。interface CLI 暂未暴露 type-layout / enum-layout flag（可后续补）。

相关：[StaticLayoutEngine.md](StaticLayoutEngine.md)、[StaticLayoutDependencyClosure.md](StaticLayoutDependencyClosure.md)、
[FieldMetadataRenderingMigration.md](FieldMetadataRenderingMigration.md)。
