# Specialized Interface Bound Rendering Restoration

恢复 interface 打印路径对「用户驱动特化（specialized）定义」的绑定渲染：头部打印绑定名
（`Box<Int>` 而非 `Box<A> where A: …`），字段类型经特化 metadata 替换（`let value: Int`
而非 `let value: A`）。

## 动机：一次由 leaf 迁移引入的回归

`aa233bc`（"refactor(swift): extract SwiftDeclarationRendering, make SwiftDump a leaf"，
首发 0.12.0-beta.6）把 interface 打印从「实例化 SwiftDump dumper」改为 SwiftPrinting
自渲染（model-driven）。旧路径中特化定义的替换机制全部长在 `TypedDumper` 上
（`boundDumpedMetatype` / `fieldDemangledTypeNode` / `resolveBoundDumpedTypeName`），
随 SwiftDump 变成 leaf 后 interface 路径不再经过它们，于是：

- 头部退化为 unbound 形式——[LeafMigrationPlan.md](LeafMigrationPlan.md) 的
  as-shipped deviations 里承认了这一点（"renders with an **unbound** header … Not
  exercised by tests"）；
- 字段替换实际上也一并丢失——plan 里 "fields still substitute" 的说法与实际不符：
  为字段设计的 `FieldDefinition.substitutedTypeNode` 方案从未落地（`git log -S` 只在
  文档中出现），字段节点始终来自 `FieldRecord.demangledTypeNode(in:)` 的原始字节
  demangle。仍在替换的只有 layout 注释引擎（`RuntimeFieldLayoutBackend`），造成
  「注释正确、正文错误」的反差（RuntimeViewer 用户报告的现象：
  `RawCodable<NSVerticalDirection>` 节点正文仍是 `struct RawCodable<A> where …` +
  `var wrappedValue: A`，而 `// Type Layout` 已是特化布局）。

RuntimeViewer 侧 v2.1.0-beta.1 ~ beta.7（对应上游 ≤ 0.12.0-beta.5）行为正常，
beta.8/beta.9 吃进 0.12.0-beta.6+ 后受影响。

## 方案：把旧机制镜像到 SwiftDump 之外

约束：SwiftPrinting 不允许依赖 SwiftDump（leaf 迁移的核心成果），因此不是「把 dumper
接回来」，而是把替换机制下沉到两条路径共享的 `SwiftDeclarationRendering`：

1. **`BoundDumpedTypeNameRenderer` 下移**（`SwiftDump/Protocols/TypedDumper.swift` →
   `SwiftDeclarationRendering/BoundDumpedTypeNameRenderer.swift`，逐字搬移）。它只依赖
   `DemangleResolver`，本就与 dumper 状态无关；`TypedDumper.resolveBoundDumpedTypeName`
   继续转发到它，dump 路径零变化。既有直测该 enum 的
   `SwiftDumpTests/BoundDumpedTypeNameRendererTests` 已 `import SwiftDeclarationRendering`，
   无需改动。
2. **新增 `SpecializedMetadataNodeSubstitution`**（SwiftDeclarationRendering）——旧
   `TypedDumper` 替换成员的 `MetadataWrapper` 版镜像：
   - `boundTypeNode(for:)`：metadata 指针 bitcast 成 `Any.Type` →
     `_mangledTypeName` → demangle，得到绑定形式的类型节点
     （旧 `boundDumpedMetatype()` + `boundDumpedTypeNode()`）；
   - `substitutedFieldTypeNode(for:metadata:in:)`：
     `RuntimeFunctions.getTypeByMangledNameInContext(_:specializedFrom:in:)` 解析字段
     mangled name → `_mangledTypeName` → demangle（旧 `resolveFieldMetatype` +
     `fieldDemangledTypeNode` 的 specialized 分支；value/class metadata 两个受限实现
     本就相同，收敛为对 wrapper 的 case 分派，与
     `RuntimeFieldLayoutBackend.resolveFieldMetatype` 同型）。
3. **SwiftPrinting 接线**：
   - `printTypeDefinition` 在 `isSpecialized` 时把 `typeDefinition.metadata` 传给
     `renderTypeDeclarationHeader(…, specializedMetadata:)`；有 bound 节点时头部改走
     `BoundDumpedTypeNameRenderer.render`，并跳过泛型签名子句（否则会打出
     `Box<Int><A: Hashable>`）、保留 invertible-protocol 标记与 class 的 superclass
     段——与旧 `StructDumper`/`EnumDumper`/`ClassDumper.declaration` 的 `isBound`
     分支逐一对应；
   - `renderModelFields` 对每条 field record 尝试
     `substitutedFieldTypeNode`，结果经 `printField` / `printEnumCase` 新增的
     `substitutedTypeNode` 覆盖参数生效；`nil`（runtime 解析失败、非
     `MachOImage`、旧 runtime 无 `_mangledTypeName`）逐字段回退 unbound 节点——
     与旧 dumper 完全一致的 best-effort 契约。

### 为什么是 metadata 驱动而不是静态节点替换

特化时的 `typeArgumentNodesByParameter` 理论上可以做纯语法的 τ_0_0 → 实参节点替换
（`GenericArgumentEnvironment` 思路），但 runtime 驱动是重构前的原始行为，且强于
静态替换：`A.RawValue` 这类 `dependentMemberType` 引用由 runtime 按 conformance
witness 解析为最终具体类型，静态替换只能得到 `Int.RawValue` 形式。本次目标是
「恢复重构前逻辑」，故原样镜像 runtime 方案。

## 影响面

- 头部/字段绑定渲染只在 `isSpecialized && metadata != nil` 时激活；普通（未特化）
  定义、diff 渲染器（`renderTypeDeclarationHeader` / `printField` 新参数均有默认值）、
  dump 路径（机制原样保留在 `TypedDumper`，仅 enum 搬家）行为不变。
- 消费方 RuntimeViewer 无需改动：`RuntimeSwiftSection` 一直调用
  `printer.printTypeDefinition(specializedDefinition)`，变化全部发生在库内。

## 测试

`SwiftSpecializationTests.GenericTypeNameSubstitutionEndToEndTests` 新增
"specialized definition prints a bound header and substituted field types"：对
`TestUnconstrainedStruct<A>` 特化到 `Int` 后打印，断言含
`TestUnconstrainedStruct<Swift.Int>` 与 `let a: Swift.Int`、不含 `<A>` 与 `where`——
钉住 leaf 迁移时 "Not exercised by tests" 的缺口。全量回归：SwiftPrintingTests /
SwiftDumpTests / SwiftSpecializationTests / SwiftInterfaceTests / SwiftDiffingTests
全绿。

## 私有类型的运行时名字（2026-09-23）

RuntimeViewer 报告：macOS 26.7 上把 AppKit 的 `WindowPortal<A>` 特化成 `WindowPortal<AppKit.ButtonContent>`，头部打成 `struct .WindowPortal<AppKit.ButtonContent>`。对方随后扫了 AppKit 里全部 102 个能特化的泛型类型，同一个原因有三种表现：

- 名字开头多一个点（16 例），例如 `class ._NSLayerView<CGDrawingLayer>: __C.NSView`。
- 私有的嵌套类型丢掉整条父链：`enum .Phase`，离线名字是 `AppKit.InProcessAnimation.Bridged.Phase`。
- 私有类型当泛型实参时丢模块名：`<AXPocketMode>`，而非私有类型是 `<AppKit.ButtonContent>`。

### 根因

特化后的名字全部来自运行时：`_mangledTypeName` → `swift_getMangledTypeName` → `_swift_buildDemanglingForMetadata`。编译器把每个最外层的 `private` / `fileprivate` 类型挂在一个 anonymous context 描述符下面（`lib/IRGen/GenDecl.cpp` 的 `getAddrOfParentContextDescriptor`："Wrap up private types in an anonymous context for the containing file unit so that the runtime knows they have unstable identity"；RuntimeViewer 会话的探针统计，AppKit 26.7 的 879 个 Swift 类型里有 227 个挂在 anonymous context 下）。运行时拼名字时对 anonymous context 没有更多信息，就用描述符地址充当名字：`AnonymousContext("$<地址>", <父上下文>, TypeList())`（`stdlib/public/runtime/Demangle.cpp` 的 `_buildDemanglingForContext`，注释自称 "unstable mangling"）。

这个节点到了打印器：

- interface 打印器没有它的分支，整棵子树连同里面的 `Module` 都打成空串。`BoundDumpedTypeNameRenderer` 的 `.structure` / `.class` / `.enum` 分支又无条件在父节点后面写 `.`，于是名字开头多一个点。`TypeNodePrintable.printType`（字段类型、泛型实参走这里）只在父节点真的写出内容时才写分隔符，所以那里没有点，但模块和外层类型一起丢了。
- dump 路径用的是 Demangling 自带的打印器：`DemangleOptions.default` 下打成 `Module.(unknown context at $600001234)`，`.interface` 选项下同样打成空。

离线命名从来不会遇到这个节点：`SymbolicDemangler.buildContextDescriptorMangling` 遇到 anonymous context 时，查得到它的符号就还原成 `privateDeclName`（interface 打印器只打名字本身），查不到就跳过、直接用父上下文。dyld shared cache 里没有本地符号，所以 AppKit 这类镜像永远是后者。

### 修复

- 新增 `SwiftDeclarationRendering/RuntimeTypeNameDemangling.swift`。`node(forMetatype:)` 是库里把运行时 metatype 变成节点的唯一入口：`_mangledTypeName` → `demangleAsNodeTransient` → 把每个 anonymous context 换成它的父节点（child 1），结果与离线命名在 shared cache 里得到的一致。demangler 对同一个 substitution 的每次 back-reference 返回同一个实例，树其实是 DAG，所以替换过程按对象身份 memoize；不含 anonymous context 的子树原样返回同一个实例。
- 五处调用点全部改走它：`SpecializedMetadataNodeSubstitution`（interface 的头部与字段类型）、`TypedDumper`（dump 的头部与字段类型，原先是逐字重复的一份实现）、`RuntimeFieldLayoutBackend`（布局注释里 `.type` 泛型实参与 pack 元素，此前打出 `(unknown context at $…)`）、`InProcessAccessorFunctionResolution`（进程内求 kind-9 witness）。Sources 里现在只有这个文件直接调用 `_mangledTypeName`，新增的运行时名字来源也必须走它。
- `BoundDumpedTypeNameRenderer`：父节点渲染为空时不再写分隔符，与 `TypeNodePrintable.printType` 同一规则。它兜住的是打印器仍然拼不出来的上下文，见下文 extension context。

为什么不给 interface 打印器加一个 `.anonymousContext` 分支：那样只修了 interface 打印器，dump 与布局注释用的 Demangling 打印器照样打出 `(unknown context at $…)`；而且地址本身没有任何值得打印的信息，在源头去掉比让每个打印器各自忽略更一致。

为什么不自己实现 `_mangledTypeName`：讨论过，可行——ABI 模型能读运行时处理的全部 metadata 种类，`SymbolicDemangler` 能从描述符拼出上下文名。但这等于移植约 700 行 C++（`_swift_buildDemanglingForMetadata`，加上从同型约束反推非 key 泛型参数的 `_gatherWrittenGenericParameters`），之后每个 Swift 版本新增的函数类型标志都要跟进；而对 interface 输出，结果与「保留 `_mangledTypeName` + 去掉 anonymous context」一字不差。留待以后单独立项。

### 没有覆盖的：extension context

类型声明在另一个模块的类型的 extension 里时（`extension NSView { enum Invalidations { … } }`），父上下文是 extension context，interface 打印器同样没有它的分支、打成空。这个问题离线路径也有——macOS 26.5.2 的 AppKit 导出里写的就是 `Invalidations.Tuple<A1, B1>`，缺 `NSView.`——与运行时名字无关，本批不修，作为下一批。本批之后这类特化头部只是不再带开头的点（`struct Tuple<…>`）。RuntimeViewer 的扫描里有 4 例：`NSView.Invalidating`、`NSView.Invalidations.Tuple`、`NSViewController.ViewLoading`、`NSWindowController.WindowLoading`。

### 测试

- `SwiftSpecializationTests/SpecializedRuntimeTypeNameTests`（6 条，走 RuntimeViewer 用的 `printTypeDefinition`）：私有泛型类型的头部；嵌在普通类型里的私有类型（anonymous context 在链中间）；私有类型作泛型实参，头部与字段各一条；展开字段偏移注释里的私有实参；跨模块 extension 里的类型不再以点开头。
- `MachOSwiftSectionTests/SpecializedDumperFieldTypeTests.specializedPrivateStructDeclarationKeepsItsModule`：dump 路径的头部。
- 修复前 7 条全红，症状与报告一致：`struct .RuntimeNamedPrivateBox<Swift.Int> {`、`struct .RuntimeNamedPrivateNestedBox<Swift.Int> {`、`<RuntimeNamedPrivateArgument>`、`element (SwiftSpecializationTests.(unknown context at $110c34ea0).RuntimeNamedPrivateArgument)`、`struct .RuntimeNamedExtensionBox<Swift.Int> {`；修复后全绿。
- 进程内 kind-9 witness 那一处没有专门的测试：在测试镜像里造出「kind-9 引用 + 私有 witness」不现实，它与另外四处共用同一个函数。
