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
