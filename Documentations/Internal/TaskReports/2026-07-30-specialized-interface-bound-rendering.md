# 2026-07-30 特化定义 interface 绑定渲染恢复

## 问题

RuntimeViewer 中对泛型类型做用户驱动特化后，侧边栏节点名正确
（`AppKit.RawCodable<AppKit.NSVerticalDirection>`），但 Content 区的 interface 正文
仍是 unbound 形式：头部 `struct RawCodable<A> where A: RawRepresentable, …`、字段
`var wrappedValue: A`；只有 `// Field Offset` / `// Type Layout` 注释反映了特化布局
（size 1 / extraInhabitantCount 254，正是 `NSVerticalDirection`）。用户指出
v2.1.0-beta.1 时代行为正常，怀疑是后续大重构改出来的。

## 调研

1. **现状链路**：`RuntimeSwiftSection.interface(for:)` → `printer.printTypeDefinition(
   specializedDefinition)`。特化只落在三处——`typeName`（侧边栏名）、`metadata`
   （layout 注释）、派生嵌套子类型；`renderTypeDeclarationHeader` 按文档注释明示只渲染
   descriptor 的 unbound 形式，`printField` 打印的 `field.typeNode` 是原始字节 demangle，
   全程无替换 pass。
2. **历史回溯**：RV v2.1.0-beta.1 锁定 MachOSwiftSection 0.12.0-beta.1。当时
   `SwiftInterfacePrinter.printTypeDefinition` 把 `typeDefinition.metadata` 交给
   SwiftDump dumper（`dumper.declaration` / `dumper.fields`），`TypedDumper` 上有完整的
   metadata 驱动替换：`boundDumpedMetatype()`（metadata → `Any.Type` →
   `_mangledTypeName` → 绑定名节点，且 `isBound` 时跳过泛型签名子句）与
   `fieldDemangledTypeNode(for:)`（`getTypeByMangledNameInContext(specializedFrom:)`）。
3. **肇事提交**：`aa233bc`（2026-06-17，leaf 迁移，首发 0.12.0-beta.6）。SwiftPrinting
   改为自渲染、不再实例化 dumper；替换机制留在 SwiftDump（interface 路径不再经过）。
   `LeafMigrationPlan.md` deviations 承认头部退化（"Not exercised by tests"），但
   "fields still substitute" 与实际不符——计划中的 `FieldDefinition.substitutedTypeNode`
   从未实现（`git log -S` 仅命中文档）。RV 侧 beta.8/beta.9 吃进 0.12.0-beta.6+ 后受影响。

## 方案（用户确认：与重构前逻辑一致）

不恢复 dumper 依赖（保住 leaf 迁移成果），把旧机制镜像到两条路径共享的
`SwiftDeclarationRendering`：

- `BoundDumpedTypeNameRenderer` 从 `TypedDumper.swift` 逐字下移（dump 路径经
  `resolveBoundDumpedTypeName` 转发，零变化；直测它的 SwiftDumpTests 本就
  `import SwiftDeclarationRendering`，无需改）。
- 新增 `SpecializedMetadataNodeSubstitution`：`boundTypeNode(for:)` 与
  `substitutedFieldTypeNode(for:metadata:in:)`，即旧 `TypedDumper` 四个替换成员的
  `MetadataWrapper` 版（value/class 两个受限实现本就相同，收敛为 case 分派）。
- SwiftPrinting 接线：`printTypeDefinition` 在 `isSpecialized` 时传
  `specializedMetadata`；`renderTypeDeclarationHeader` 有 bound 节点时走绑定名渲染并
  跳过泛型签名子句（保留 invertible 标记、class superclass 段，逐一对应旧
  `*Dumper.declaration` 的 `isBound` 分支）；`renderModelFields` 逐字段替换，失败
  逐字段回退 unbound；`printField` / `printEnumCase` 新增带默认值的
  `substitutedTypeNode` 参数（diff 渲染器调用点不受影响）。

选 runtime 驱动而非静态节点替换：前者是重构前原始行为，且 dependent member
（`A.RawValue`）能按 conformance witness 解析到最终具体类型。

## 执行与验证

- 代码：SwiftDeclarationRendering 2 个新文件、TypedDumper 删 enum 留指针注释、
  SwiftPrinting 3 文件接线。
- 测试：`GenericTypeNameSubstitutionEndToEndTests` 新增打印断言测试（绑定头部 +
  `let a: Swift.Int`、无 `<A>` / `where`），一次通过；回归
  SwiftPrintingTests / SwiftDumpTests / SwiftSpecializationTests（181 项）+
  SwiftInterfaceTests / SwiftDiffingTests（139 项）全绿。
- 文档：SpecializedInterfaceBoundRenderingRestoration.md、README 索引、
  ProjectEvolutionLog §21、LeafMigrationPlan deviations 补 Superseded/Amended 标注、
  AGENTS.md SwiftPrinting 条目。
- 另按用户要求对 `aa233bc` 整体做了三路并行回归审计（类型头部/字段渲染、
  protocol/extension 渲染、机制搬迁与依赖裁剪），完整记录（含证据行号与修复建议）
  见 [LeafMigrationRegressionAudit.md](../LeafMigrationRegressionAudit.md)。结论：

  **已随本批顺手修复**：diff 渲染路径的 `printTypeHeader` 未传 `specializedMetadata`
  （与主路径分叉；当前 diff builder 不走 `specializedChildren`，属潜在缺口）——已补参。

  **仍存活、待决定是否修复**（按严重性）：
  1. 多 payload 枚举 Enum Layout 注释的错误容忍丢失：`MultiPayloadEnumDescriptorCache`
     被删后（`RuntimeFieldLayoutBackend.multiPayloadEnumDescriptor(for:in:)` 内联线性
     扫描），任一 descriptor demangle 失败会抑制该枚举全部布局注释；旧实现发布部分
     map、单枚举降级到 tagged 投影仍出注释。附带每枚举 O(N·M) 重扫的性能退化
     （后者有文档，前者无）。
  2. 嵌套 field-offset 展开的深度截断 `#log` 诊断丢失（现完全静默）；
     `nestedFieldOffsetExpansionDepthLimit` 在 SwiftDump 留有死副本，且钉它的测试
     `@testable import SwiftDump` 钉的是死副本而非 SwiftDeclarationRendering 的活值。
  3. `case a()`（Void payload）在 interface 路径丢括号（按渲染文本 gating），dump
     路径仍打 `case a()`——两路对同一枚举输出不一致。
  4. 字段渲染失败时留下空缩进行 + 无归属 `print(error)`（旧行为：整个类型渲染报错）。
  5. extension 的 conformance 子句在 protocol 引用解析失败时被静默抑制并丢
     `@retroactive` / global-actor 标记（旧输出为悬空 `extension Foo: `，新输出
     arguably 更好，但无文档）。
  6. `AssociatedTypeDumper.mergedRecords` / `nestedFieldOffsetExpansionDepthLimit` 等
     SwiftDump 死代码副本（漂移风险）。
  7. `storedFieldComments` / `enumCaseComments` 的 `try` → `try?` 使错误路径多打一个
     空行（`isTypeLayoutPrinted` 在 `try?` 失败后仍无条件置位）。

  **历史断裂佐证**（已被上游修复）：`aa233bc` 落地当天 interface 丢过全部 metadata
  注释（6 小时后 `ebb04d3` 修复）；`ebb04d3` 引入特化泛型 SIGBUS（`6eebaf4` 修复）；
  加上本次绑定渲染回归，该重构线共产生过至少四个用户可见断裂。

  **核对干净面**：struct/enum/class 头部（actor/distributed、superclass 三分支、泛型
  签名 + invertible）、字段/枚举 case 框架与注释顺序、protocol 头部与 associatedtype、
  stripped requirement、`demangledOverrideSymbol` / `ParentClassVTableCache` /
  `resolveOpaqueType` 等全部搬迁逐字节等价；依赖边与 `@_spi` 面无变化。
  另注意 `245c1c1`（非 aa233bc）引入的两处 diff 路径不一致：diff 的 extension 头用
  `.default` 而非 `.interfaceTypeBuilderOnly` 且缺 `@retroactive`；snapshot 的
  associated-type witness 按 name 单键去重且跳过 `resolveOpaqueType`。

## 偏差

- 无实现层偏差；plan 文档中 "fields still substitute" 的错误记述已在
  LeafMigrationPlan.md 中以 Superseded 标注纠正，而非静默改写历史。
