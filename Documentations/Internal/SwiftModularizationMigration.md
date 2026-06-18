# Swift Declaration / Interface Modularization — Migration Guide

供 review：重构前的内容被挪到了哪里。这条 `feature/swift-diffing` 线上的「大重构」由三步组成：

1. **SwiftInterface 单体 → 分层模块**（PR #92 / `47b5961`）
2. **SwiftDump 渲染件 → SwiftDeclarationRendering（leaf 迁移）**（`d447e3b` 计划 / `aa233bc`）
3. **字段 metadata 渲染抽取 + 成员顺序确定性修复**（本分支后续提交，详见
   [`FieldMetadataRenderingMigration.md`](FieldMetadataRenderingMigration.md)）

外加新增模块 **SwiftDiffing**（ABI 差分）。

> 文件移动均由 `git show -M -C --summary <commit>` 的 rename 检测得出，下表是逐文件的去向。

---

## 1. SwiftInterface 单体 → 分层模块（`47b5961`）

重构前 `Sources/SwiftInterface/` 是一个大单体（模型 + 索引 + 打印 + 节点打印器 + 属性推断 + 泛型特化 + 编排）。拆成了 6 个分层模块，`SwiftInterface` 只留下薄薄的编排器。

### 1.1 → `SwiftDeclaration`（共享声明模型）

| 重构前 | 现在 |
|---|---|
| `SwiftInterface/Components/Definitions/*`（TypeDefinition / ProtocolDefinition / ExtensionDefinition / FunctionDefinition / SubscriptDefinition / VariableDefinition / FieldDefinition / Accessor / OrderedMember / Definition(+) / **DefinitionBuilder**） | `SwiftDeclaration/Components/Definitions/*` |
| `SwiftInterface/Components/Kinds/*`（AccessorKind / ExtensionKind / FunctionKind / TypeKind） | `SwiftDeclaration/Components/Kinds/*` |
| `SwiftInterface/Components/Names/*`（DefinitionName / TypeName / ProtocolName / ExtensionName） | `SwiftDeclaration/Components/Names/*` |
| `SwiftInterface/Extensions.swift` | `SwiftDeclaration/Extensions.swift` |
| `SwiftInterface/SwiftInterfaceEvents.swift` | `SwiftDeclaration/Events/SwiftIndexEvents.swift` ⟵ **类型重命名** |

### 1.2 → `SwiftIndexing`（从 Mach-O 构建模型）

| 重构前 | 现在 | 重命名 |
|---|---|---|
| `SwiftInterface/SwiftInterfaceIndexer.swift` | `SwiftIndexing/SwiftDeclarationIndexer.swift` | `SwiftInterfaceIndexer` → `SwiftDeclarationIndexer` |
| `SwiftInterface/SwiftInterfaceEventReporter.swift` | `SwiftIndexing/SwiftIndexEventReporter.swift` | `SwiftInterfaceEventReporter` → `SwiftIndexEventReporter` |
| `SwiftInterface/SwiftInterfaceEventsHandlers.swift` | `SwiftIndexing/SwiftIndexEventsHandlers.swift` | …Handlers 同步改名 |

### 1.3 → `SwiftPrinting`（把模型渲染成 Swift 源码）

| 重构前 | 现在 | 重命名 |
|---|---|---|
| `SwiftInterface/SwiftInterfacePrinter.swift` | `SwiftPrinting/SwiftDeclarationPrinter.swift` | `SwiftInterfacePrinter` → `SwiftDeclarationPrinter` |
| `SwiftInterface/NodePrintables/*`（NodePrintable / TypeNodePrintable / BoundGeneric… / DependentGeneric… / FunctionType… / Interface… / …Delegate） | `SwiftPrinting/NodePrintables/*` | |
| `SwiftInterface/NodePrinter/*`（Type / Function / Subscript / Variable NodePrinter） | `SwiftPrinting/NodePrinter/*` | |
| `SwiftInterface/SemanticExtensions/SemanticComponents.swift` | `SwiftPrinting/SemanticExtensions/SemanticComponents.swift` | |
| `SwiftInterface/SwiftInterfaceBuilderConfiguration.swift` 的打印配置部分 | `SwiftPrinting/SwiftDeclarationPrintConfiguration.swift`（copy 拆出） | `SwiftInterfacePrintConfiguration` → `SwiftDeclarationPrintConfiguration` |

### 1.4 → `SwiftAttributeInference`（推断 `@propertyWrapper`/`@objc` 等）

| 重构前 | 现在 |
|---|---|
| `SwiftInterface/AttributeInference/TypeAttributeInferrer.swift` | `SwiftAttributeInference/TypeAttributeInferrer.swift` |
| `SwiftInterface/AttributeInference/MemberAttributeInferrer.swift` | `SwiftAttributeInference/MemberAttributeInferrer.swift` |

### 1.5 → `SwiftSpecialization`（运行期泛型特化）

| 重构前 | 现在 |
|---|---|
| `SwiftInterface/GenericSpecializer/GenericSpecializer.swift` | `SwiftSpecialization/GenericSpecializer.swift` |
| `SwiftInterface/GenericSpecializer/ConformanceProvider.swift` | `SwiftSpecialization/ConformanceProvider.swift` |
| `SwiftInterface/GenericSpecializer/Models/Specialization{Request,Result,Selection,Validation}.swift` | `SwiftSpecialization/Specialization*.swift` |

### 1.6 `SwiftInterface`（保留：薄编排器）

只剩：`SwiftInterfaceBuilder.swift`、`SwiftInterfaceBuilderConfiguration.swift`、
`SwiftInterfaceBuilderDependencies.swift`、`SwiftInterfaceBuilderExtraDataProvider.swift`、
`SwiftInterfaceBuilderOpaqueTypeProvider.swift`、`DependencyPath.swift`——把
indexing + printing 串成完整 interface dump。

### 1.7 对应的测试也搬了家

`Tests/SwiftInterfaceTests/` 里相应测试迁到
`SwiftAttributeInferenceTests` / `SwiftIndexingTests` / `SwiftPrintingTests` /
`SwiftSpecializationTests`。

---

## 2. SwiftDump 渲染件 → `SwiftDeclarationRendering`（leaf 迁移，`aa233bc`）

把 `SwiftDump` 里**与具体 dumper 无关的渲染基元**抽到新的底层模块
`SwiftDeclarationRendering`，使 `SwiftDump` 变成 leaf；`SwiftDump` 与 `SwiftPrinting`
都依赖 `SwiftDeclarationRendering`（彼此不依赖）。

| 重构前 | 现在 | 备注 |
|---|---|---|
| `SwiftDump/Utils/DumperConfiguration.swift` | `SwiftDeclarationRendering/DeclarationRenderConfiguration.swift` | `DumperConfiguration` 保留为 `typealias = DeclarationRenderConfiguration`，含全部 `*Comment` 构建器与 `*Transformer` |
| `SwiftDump/Utils/DemangleResolver.swift` | `SwiftDeclarationRendering/DemangleResolver.swift` | |
| `SwiftDump/Utils/ParentClassVTableCache.swift` | `SwiftDeclarationRendering/ParentClassVTableCache.swift` | |
| `SwiftDump/Extensions/ContextDescriptorWrapper+Dump.swift` | `SwiftDeclarationRendering/Extensions/同名` | |
| `SwiftDump/Extensions/GenericContext+Dump.swift` | 同上 | |
| `SwiftDump/Extensions/Keyword+Swift.swift` | 同上 | |
| `SwiftDump/Extensions/MetadataWrapper+Dump.swift` | 同上 | type-layout 渲染（`dumpTypeLayout`） |
| `SwiftDump/Extensions/{Node+,OpaqueType+,ResilientSuperclass+Dump,SemanticString+,String+}.swift` | 同上 | |

新增（leaf 迁移时一并加入 SwiftDeclarationRendering）：
`Extensions/{GenericRequirement+Inherited, Node+OpaqueType, ProtocolConformance+, ResolvedTypeReference+}.swift`。

> `SwiftDump` 现在只保留真正的 dumper（`StructDumper`/`EnumDumper`/`ClassDumper`/…、
> `Dumper`/`TypedDumper` 协议、`DumperMetadataContext`、`.dump(using:in:)` 公开 API）。

---

## 3. 字段 metadata 渲染抽取 + 成员顺序确定性（本分支后续）

- **新增** `SwiftDeclarationRendering/FieldLayoutRenderer.swift`（+`FieldLayoutRenderer+Enum.swift`）：
  把「`// Field offset` / `// Type Layout` / expanded-offset 树 / enum 布局/spare-bit」的
  渲染从 `SwiftDump` 的 `StructDumper`/`ClassDumper`/`EnumDumper.fields` 与
  `TypedDumper`（expanded-offset 走查 + 静态泛型替换）抽成**单一真源**，由 SwiftDump 三个
  dumper 与 `SwiftPrinting.SwiftDeclarationPrinter` 共用——修复了拆分后 model 打印器在
  MachOImage 上**丢失全部 type layout + 运行期 field offset** 的回归。
- **`SwiftDeclaration/Components/Definitions/DefinitionBuilder.swift`**：把 3 处普通
  `Dictionary` 迭代改 `OrderedDictionary`，消除重载下标 / 合并 `@objc func` 在 model
  接口里的跨运行顺序漂移。

详细的「重构前位置 → FieldLayoutRenderer」对照、行为保证、验证结果与既有问题，见
[`FieldMetadataRenderingMigration.md`](FieldMetadataRenderingMigration.md)。

---

## 4. 新增模块：`SwiftDiffing`

`feature/swift-diffing` 的核心功能——在声明模型上做 ABI 差分（按 remangled `Node`
归一、递归集合差分）。纯模型 peer（不依赖 Mach-O），只依赖 `SwiftDeclaration` + `Demangling`。
配套 `swift-section diff` 命令。

---

## 5. 当前模块依赖层级（重构后）

```
swift-section (CLI)
└── SwiftInterface（薄编排器：SwiftInterfaceBuilder）
        └── SwiftIndexing · SwiftPrinting · SwiftSpecialization · SwiftAttributeInference · SwiftDiffing
                └── SwiftDeclaration（共享声明模型）
                        ├── SwiftDeclarationRendering（共享渲染基元；SwiftDump 也依赖它）
                        └── SwiftDump（leaf：descriptor 级 dumper）
                                └── SwiftInspection → MachOSwiftSection → MachOFoundation → …
```

要点：
- **SwiftPrinting 与 SwiftIndexing 是 peer**，互不依赖（都只依赖 SwiftDeclaration）。
- **SwiftDump 是 leaf**：除 `swift-section` 与 `MachOFixtureSupport` 外无人依赖它；渲染基元在
  SwiftDeclarationRendering，供 dump 路径与 model-print 路径共用。

## 6. 类型重命名速查

| 重构前 | 现在 |
|---|---|
| `SwiftInterfacePrinter` | `SwiftDeclarationPrinter`（SwiftPrinting） |
| `SwiftInterfaceIndexer` | `SwiftDeclarationIndexer`（SwiftIndexing） |
| `SwiftInterfaceEvents` | `SwiftIndexEvents`（SwiftDeclaration） |
| `SwiftInterfaceEventReporter` | `SwiftIndexEventReporter`（SwiftIndexing） |
| `SwiftInterfacePrintConfiguration` | `SwiftDeclarationPrintConfiguration`（SwiftPrinting） |
| `DumperConfiguration` | `DeclarationRenderConfiguration`（SwiftDeclarationRendering；旧名保留为 typealias） |
