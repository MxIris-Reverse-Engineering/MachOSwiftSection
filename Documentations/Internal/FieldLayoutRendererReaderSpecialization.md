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
不调 accessor，即可算出 struct/class 字段 offset、每字段类型的 `StaticTypeLayout`、resilient class 字段起点、
以及跨模块字段（经依赖闭包）。本次改造把 `FieldLayoutRenderer` 拆成两套按 reader 特化的实现，
并把 SwiftLayout 接到 MachOFile 路径上，使离线输出**与 MachOImage 全量对齐**。

## 设计

### 1. 泛型 facade + 两套特化实现（**编译期** witness 分派，零运行时 `as?`）

`FieldLayoutRenderer<MachO>` 仍是调用方看到的泛型类型，但退化为**瘦分派 facade**：保留存储属性、
`init`、`enumValue`，以及 6 个调用方入口（`fieldOffsets`、`storedFieldComments`、`enumLayout`、
`enumPrefixComments`、`enumCaseComments`）。分派**不在运行时判断 reader 类型**，而是由类型系统在编译期选定：

```swift
public protocol FieldLayoutRenderable: MachOSwiftSectionRepresentableWithCache {
    static func renderFieldOffsets(_ state: FieldLayoutRenderState, machO: Self) -> [Int]?
    // storedFieldComments / enumLayout / enumPrefixComments / enumCaseComments
    // + makeStaticFieldLayoutProvider / precomputedStaticAggregateFieldLayout
}
package struct FieldLayoutRenderer<MachO: FieldLayoutRenderable> {
    package var fieldOffsets: [Int]? { MachO.renderFieldOffsets(renderState, machO: machO) }  // 无 as?
}
```

每个入口转发到 `MachO.render…` 的协议 witness；对具体实例化（如 CLI 的 `FieldLayoutRenderer<MachOFile>`）
编译器单态化为静态直调。`MachOFile`/`MachOImage` 各自 conform 提供两套实现。

**两个 non-final-class 约束（关键设计）**：`MachOFile`/`MachOImage` 是 MachOKit 的 non-final class，
协议 witness 里 `Self` 不能嵌套在泛型类型中（`FieldLayoutRenderer<Self>` 非法）。故 witness 用
`machO: Self`（**参数位置**，合法）+ 一个**非泛型** public `FieldLayoutRenderState`（打包 type/metadata/
configuration/isGeneric/staticAggregateFieldLayout，不含 `Self`）传递 renderer 状态，绕开该限制；
`FieldLayoutRenderer` 因此无需 public，仍是 `package`。

- `RuntimeFieldLayoutBackend.swift`（`struct`，持 `state + machO: MachOImage`）：原运行期实现整体移入，
  入口改名匹配协议；便利转发器（`type`/`metadata`/`configuration`/…）使方法体几乎零改动（含 PAC-fault-avoiding
  的泛型实参静态替换）。`extension MachOImage: FieldLayoutRenderable` 薄转发到它。**行为零改动。**
- `StaticFieldLayoutBackend.swift`（`struct`，持 `state + machO: MachOFile`）：SwiftLayout 静态实现，
  `extension MachOFile: FieldLayoutRenderable` 薄转发。

**约束传染**：`FieldLayoutRenderable` refine `MachOSwiftSectionRepresentableWithCache`，沿构造 renderer 的整条
泛型链机械传染——`Dumpable`/`NamedDumpable`/`ConformedDumpable`/`Dumper` 协议要求、`Struct/Class/Enum` dumper、
`SwiftDeclarationPrinter`、`SwiftInterfaceBuilder`/`SwiftDiffableInterfaceBuilder` 及 dump/interface 测试辅助。
只有 `MachOFile`/`MachOImage` conform，故所有真实调用方不受影响（interface 快照无变化）。

> 早期曾用运行时 `self as? FieldLayoutRenderer<MachOImage>/<MachOFile>` 分派；现已全面改为上述编译期 witness，
> 渲染路径零运行时类型转换（printer 选 provider、init 预算 aggregate 也都走 witness）。

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
- Type Layout：MachOFile 走 `configuration.staticTypeLayoutComment(_:)`，由 `StaticTypeLayout` 直接渲染默认格式。
- Enum Layout：静态版**统一收口到 SwiftLayout 引擎**——`provider.enumCaseLayoutResult(forDescriptor:)`
  返回逐 case 投影（`EnumLayoutBridge.enumCaseLayoutResult`，内部按 single-/multi-payload 分派并移植 runtime
  公式）。此前 backend 自行拼装 payload size / spare bytes / `EnumLayoutCalculator`，现全部下沉到引擎，backend
  只做渲染。**放开泛型 enum**：引擎能不特化解析的泛型 enum（class-bound payload 参数、或 payload 不引用参数）
  照常渲染 enum-layout 注释（此前一律 `!isGeneric` 跳过）；真正需要实参的 enum 返回 nil、无注释。
- 泛型 enum 的 payload Type Layout / 字段 Type Layout 经
  `provider.typeLayout(forMangledTypeName:inContextOfDescriptor:)`——在**该 descriptor 的上下文**里 lower，
  故 class-bound 参数 payload 与 metatype thinness 都能正确判定（裸 `typeLayout(forMangledTypeName:)` 缺上下文，
  无法解析泛型参数 payload）。
- **未知偏移显式化**：字段偏移算不出时不再静默省略注释，而是渲染 `// Field offset: unknown (<原因>)`
  （`DeclarationRenderConfiguration.unknownFieldOffsetComment`，原因来自 `LayoutUnknownReason` 的可读描述），
  让读者区分「引擎算不了」与「开关没开」；字段**自身**类型布局（多数仍可解析）照常在下方渲染
  （`StaticLayoutCalculator` 现即使偏移不可信也会尽力解析每字段 `layout`）。

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
  `StaticTypeLayout` 在 `MachOSwiftSection` 外合成（其 init 仅 `@testable` 可见，且给核心模型加 public init
  会牵动覆盖率不变量、属层级越界），故 MachOFile 路径恒走默认格式。
- **tuple 字段的 Type Layout 无逐元素分解**：`StaticTypeLayout` 不携带元素信息，静态路径输出单行聚合布局。
- expanded 树对深层泛型实例化按 SwiftLayout 现状逐子树降级（停止递归而非错算）。
- **泛型 enum 的 enum-layout 注释已放开**（class-bound / 无参数 payload），但**依赖实参**的泛型 enum
  （payload 为裸 `T`）仍返回 nil、不渲染——与字段路径的降级语义一致。
- 跨模块解析默认走依赖闭包（系统 dyld cache）；`.singleImage` 下跨模块字段降级。`@rpath` 未展开（沿用
  SwiftLayout 闭包 MVP 限制）。

## CLI 触达

- `swift-section interface --emit-offset-comments` / `--emit-expanded-field-offsets`（既有 flag，现走静态路径）。
- `swift-section dump` 新增 `--emit-field-offsets`、`--emit-type-layout`、`--emit-enum-layout`、
  `--emit-expanded-field-offsets`。interface CLI 暂未暴露 type-layout / enum-layout flag（可后续补）。

相关：[StaticLayoutEngine.md](StaticLayoutEngine.md)、[StaticLayoutDependencyClosure.md](StaticLayoutDependencyClosure.md)、
[FieldMetadataRenderingMigration.md](FieldMetadataRenderingMigration.md)。
