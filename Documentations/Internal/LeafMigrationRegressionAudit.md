# Leaf Migration Regression Audit

对 `aa233bc`（"refactor(swift): extract SwiftDeclarationRendering, make SwiftDump a
leaf"，首发 0.12.0-beta.6）及其直接配套提交（`ebb04d3` 等）的全面回归审计记录。
触发背景：该重构线已确认造成过多个用户可见断裂（见「历史断裂记录」），其中特化定义
绑定渲染回归由 [SpecializedInterfaceBoundRenderingRestoration.md](SpecializedInterfaceBoundRenderingRestoration.md)
修复；本文记录审计方法、仍存活的问题清单（待逐项决定是否修复）与已核对干净的面。

## 方法

以 `aa233bc^` 为基线（字段布局引擎以 `ebb04d3^` 为基线——该引擎实际在 `ebb04d3`
搬迁），三路并行逐行比对至当前工作区：

1. struct/enum/class 头部与字段/枚举 case 渲染（旧 `*Dumper.declaration/name/fields`
   vs 新 `renderTypeDeclarationHeader` / `renderModelFields` / `printField` /
   `printEnumCase`）；
2. protocol / extension / associated-type 渲染；
3. 机制搬迁与依赖裁剪（`git show aa233bc --name-status --find-renames` 全量溯源：
   11 个 `R100` 逐字节移动、1 个 `R093`、4 个新抽取）。

## 仍存活的问题（按严重性；均未修复，待决定）

### 1. 多 payload 枚举 Enum Layout 注释：错误容忍丢失 + 每枚举线性重扫

- 旧：`MultiPayloadEnumDescriptorCache`（`ebb04d3^:Sources/SwiftDump/Dumper/EnumDumper.swift:249-286`）
  每 image 构建一次 `[Node: MultiPayloadEnumDescriptor]`，构建循环整体
  `do/catch { print(error) }` 并发布**部分** map——单个 descriptor demangle 失败只让
  那一个枚举查不到、降级到 `calculateTaggedMultiPayload` 仍出注释。
- 新：`RuntimeFieldLayoutBackend.multiPayloadEnumDescriptor(for:in:)`
  （`Sources/SwiftDeclarationRendering/RuntimeFieldLayoutBackend.swift:681-691`）
  内联线性扫描且 `throws`，错误经 `computeEnumLayout` 传播到 `try? await`
  （`:539`）→ `enumLayout == nil`：**section 中任一坏 descriptor 都会抑制该枚举的
  Enum Layout 策略行与全部 per-case 块**。同时每枚举重扫 + 重 demangle 全部
  descriptor，`--print-enum-layout` 下 O(N) → O(N·M)。
- 文档状态：性能退化有记录（`FieldMetadataRenderingMigration.md:53`），容错丢失无。
- 建议：恢复 per-image 一次性构建的部分 map（或至少把单条失败降回单枚举降级）。

### 2. 嵌套 field-offset 展开：深度截断诊断丢失，测试钉在死常量上

- 旧：`walkNestedExpandedFieldOffsets` 触达深度上限时经 `@Loggable` 发
  `#log(.info, …)`（`ebb04d3^:Sources/SwiftDump/Protocols/TypedDumper.swift:522-551`）。
- 新：`RuntimeFieldLayoutBackend.swift:200-201` 直接返回空 `SemanticString()`——截断
  完全静默。
- 复合问题：`nestedFieldOffsetExpansionDepthLimit` 现有两份——活值在
  `SwiftDeclarationRendering/FieldLayoutRenderer.swift:15`，死副本在
  `SwiftDump/Protocols/TypedDumper.swift:23`（doc 注释仍承诺已不存在的 `#log`）；而
  `Tests/SwiftDumpTests/NestedFieldOffsetExpansionDepthLimitTests.swift`
  `@testable import SwiftDump`，`#expect(… == 16)` 钉的是**死副本**。
- 建议（廉价）：测试改指 SwiftDeclarationRendering 的活值、删除死副本、在
  `RuntimeFieldLayoutBackend` 恢复 `#log`（`FieldMetadataRenderingMigration.md:107`
  已建议删副本）。

### 3. Void payload 的枚举 case 丢括号，dump / interface 两路不一致

- 旧（dump 路径至今仍是）：按 `!mangledTypeName.isEmpty` gating → `case a()`
  （`Sources/SwiftDump/Dumper/EnumDumper.swift:105-115`）。
- 新（interface 路径）：按渲染文本 gating——`payloadText != "()"`
  （`Sources/SwiftPrinting/SwiftDeclarationPrinter+Members.swift`，`printEnumCase`）
  → `case a`。同一枚举两路输出不同；无 baseline 覆盖，实际触发罕见。
- 建议：二选一统一（倾向 interface 形式更接近源码，可改 dump 路径对齐并记录）。

### 4. 字段渲染失败：整型报错 → 静默空行

- 旧：`dumper.fields` 为 `try await`，单字段的 `fieldName` / `mangledTypeName` /
  类型解析抛错会让整个类型的打印失败并向上传播。
- 新：`renderModelFields` 先发 `BreakLine()` + `Indent(level:)`，`printField` /
  `printEnumCase` 内部 `printCatchedThrowing` 吞错并 `print(error)` 到 stdout——
  产物是类型体中一行**空缩进行**加一条无归属 stdout 输出。
- 建议：失败字段渲染成显式占位注释（如 `// <field render failed: …>`），既保留
  健壮性又不产生幽灵空行。

### 5. extension conformance 子句在 protocol 引用解析失败时被静默抑制

- 旧：`dumpProtocolName` 对 nil protocol 节点塌缩为空 `SemanticString`（非 nil），
  输出悬空的 `extension Foo: `（外加 `@retroactive` / global-actor 标记）。
- 新：`Sources/SwiftPrinting/SwiftDeclarationPrinter.swift:234-235` 的
  `try?` + optional-chain 使 nil 节点 → 整个子句（含 `@retroactive` / actor 标记）
  被丢弃，输出 `extension Foo`。
- 新输出更干净，但丢了 retroactive/actor 信号且无文档。建议：接受现状并记录，或
  为不可解析引用渲染占位（`extension Foo /* : <unresolved> */`）。

### 6. SwiftDump 中的死代码副本（漂移风险）

- `AssociatedTypeDumper.mergedRecords` + `collectUniqueRecords`
  （`Sources/SwiftDump/Dumper/AssociatedTypeDumper.swift:84`、`:117`）——interface
  路径在 `SwiftDeclarationPrinter+Headers.swift` 持有等价复制品后，SwiftDump 原件
  已无任何调用者。
- `nestedFieldOffsetExpansionDepthLimit` 死副本（见问题 2）。
- 建议：删除，或显式标注 deprecated-in-favor-of。

### 7. layout 注释错误路径多打一个空行（"verbatim" 声明不精确处）

- `storedFieldComments` / `enumCaseComments` 把旧 `try await …dumpTypeLayout` 改为
  `try? await`（`RuntimeFieldLayoutBackend.swift:119`、`:137`），且 `:137-138`
  在 `try?` 失败后仍无条件置位 `isTypeLayoutPrinted` → `:142` 的
  `if isTypeLayoutPrinted { BreakLine() }` 在失败路径多发一个空行。
- 严格比旧行为（整体抛错）健壮，但与文件头 "Behaviour is the pre-split
  implementation, verbatim" 不符。建议：置位移进成功分支，头注释补勘误。

## 相邻发现（非 `aa233bc` 引入，由 `245c1c1` 引入）

- diff 路径的 extension 头用 `conformingProtocolName.node.printSemantic(using: .default)`
  而非 `.interfaceTypeBuilderOnly`，且缺 `@retroactive` / global-actor 标记——与
  `printExtensionHeader` 对同一 extension 的拼写不一致
  （`Sources/SwiftInterface/SwiftDiffableInterfaceRenderer.swift:265-276`）。
- diff/snapshot 的 associated-type witness 投影按 **name 单键**去重且不做
  `resolveOpaqueType`（`Sources/SwiftIndexing/SwiftDeclarationIndexer.swift:615-627`）：
  同名不同 witness 的第二条被静默丢弃；opaque witness 以 `some P` 形态参与 diff 而
  interface 打印的是解析后的 underlying type。

## 历史断裂记录（已修复，佐证该重构线的风险面）

1. `aa233bc` 落地时 interface 路径丢失全部 metadata 注释（offset / type layout /
   expanded tree / enum layout），各 print 开关静默失效——6 小时后 `ebb04d3` 以
   `FieldLayoutRenderer` 体系修复。`LeafMigrationPlan.md` 的 "Phase 4 SKIPPED" 记述
   未点明这次输出丢失。
2. `ebb04d3` 对特化泛型把 in-process 绝对地址喂给 Mach-O 相对解析器（SIGBUS，
   `try?` 不可捕获）——`6eebaf4` 以 `DumperMetadataContext.resolvedMetadataWrapper()`
   修复。
3. 特化定义绑定渲染回归（头部 unbound + 字段不替换）——2026-07-30 修复，见
   [SpecializedInterfaceBoundRenderingRestoration.md](SpecializedInterfaceBoundRenderingRestoration.md)。

## 已核对干净的面

- struct/enum/class 头部：actor / distributed actor 判定、superclass 三分支
  （直接 mangled name / resilient / inverted-protocols-only）、泛型签名 +
  invertible protocol 集合、`displayParentName` 与 bare-name 分支——逐字节等价。
- 字段/枚举 case 框架：存储关键字推导（flags 折叠与旧节点检查谓词等价，特化场景
  reference storage 无 runtime metadata、旧路径同样回退原始节点）、`indirect` /
  tuple payload / `MemberDeclaration` 样式、BreakLine/Indent 框架与末尾 BreakLine、
  注释发射顺序与 gating（当前树，经 `ebb04d3` 修复后）。
- protocol 头部（inherited 列表、where 子句）、associatedtype 行、merged
  associated-type typealias 块（dedup key / `substitutedTypeName` /
  `resolveOpaqueType` / 顺序）、stripped symbolic requirement 与
  default-implementation extension 的 gating 与位置。
- 搬迁保真：`demangledOverrideSymbol`（原 `ClassDumper.demangledSymbol`）、
  `ParentClassVTableCache`、`Node.resolveOpaqueType`、`isProtocolInherited` /
  `extract(where:)`、`DemangleResolver`、`DumperConfiguration` →
  `DeclarationRenderConfiguration`（所有默认值 bit-identical）、
  `ResolvedTypeReference+` / `ProtocolConformance+` 抽取——全部逐字节或仅可见性/
  注释差异。被删的 ~240 行全部有下落，无行为丢失。
- 依赖与 SPI 面：无 `@_spi` group 增删改；`SwiftDeclarationRendering` 同时注册为
  target 与 `.library` product；无 macro 依赖被误删。（注：RuntimeViewer 侧
  `@_spi(Support) import SwiftDeclarationRendering` 的 SPI 限定为惰性——该模块并无
  `@_spi(Support)` 符号，无害。）
