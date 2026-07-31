# Leaf Migration Regression Fixes

一次性修复 [LeafMigrationRegressionAudit.md](LeafMigrationRegressionAudit.md) 列出的全部
7 个存活问题，硬性目标是**重构后的逻辑与重构前（`aa233bc^`）一致**，并以跨提交差分
harness + 新增单元测试双重钉住。

## 修复清单（与审计条目一一对应）

### 1. 多 payload 枚举描述符缓存恢复（审计 #1）

- 新增 `SwiftDeclarationRendering/MultiPayloadEnumDescriptorCache.swift`——逐字恢复
  `ebb04d3` 删除的 `EnumDumper` 私有缓存（`SharedCache` 子类，per-image 一次构建，
  构建循环整体 `do/catch { print(error) }` 发布**部分** map，查找非抛错）。
- `RuntimeFieldLayoutBackend` 的两个调用点（`computeEnumLayout` 与 `spareBitAnalysis`）
  改为查缓存；内联的抛错线性扫描 `multiPayloadEnumDescriptor(for:in:)` 删除。
- 语义恢复：单个坏 descriptor 只让它自己的枚举 miss（降级 tagged 投影仍出注释），
  不再让整个 image 的多 payload 枚举布局注释被 `try?` 全部吞掉；每 image 一次扫描，
  消除 O(N·M) 重扫。
- `Package.swift`：`SwiftDeclarationRendering` 新增 `.target(.MachOCaches)` 与
  `FoundationToolbox`（`@Mutex`）依赖。

### 2. 嵌套 field-offset 深度截断诊断恢复（审计 #2）

- `RuntimeFieldLayoutBackend` 加回 `@Loggable` 与
  `emitNestedFieldOffsetDepthLimitWarning(for:)`（`#log(.info, …)`），深度触顶不再静默。
  subsystem/category **保留旧字符串**（`com.machoswiftsection.swift-dump` /
  `TypedDumper.nestedFieldOffsetExpansion`），既有日志过滤器继续命中。
- `TypedDumper` 的死常量副本与死 `@Loggable` 删除；
  `NestedFieldOffsetExpansionDepthLimitTests` 改 `import SwiftDeclarationRendering`
  钉活值（此前 `@testable import SwiftDump` 钉的是死副本，活值改动测试不红）。

### 3. Void payload 枚举 case 括号统一（审计 #3）

- 主 interface 路径（`renderModelFields`）改走新增的
  `printThrowingEnumCase(_:level:substitutedTypeNode:hasPayload:)`，payload 有无按
  **field record 的 mangled type name 是否为空**判定（旧 `EnumDumper` gating）——
  `case a(Void)` 恢复为 `case a()`，与 dump 路径拼写一致。ABI 依据：Void payload
  case 参与 payload-case 计数，是真 payload case，裸 `case a` 会把它与空 case 混同。
- diff 渲染器继续用原 `printEnumCase`（按渲染文本 gating、逐成员吞错）——那是它
  重构前就有的独立契约，不属于回归面。

### 4+7. 错误传播契约恢复（审计 #4、#7）

问题的根源是 leaf 迁移把主 interface 路径改道到 diff 渲染器的宽松原语上
（`printCatchedThrowing` 吞错、`try?` 注释），而重构前主路径是 `try await dumper.fields`
整体传播。恢复为：

- `RuntimeFieldLayoutBackend.storedFieldComments` / `enumCaseComments` →
  `async throws`，`dumpTypeLayout` 恢复 `try await`（错误传播；
  `isTypeLayoutPrinted` 只在成功后可达，错误路径多打空行的问题随之消失）。
- `FieldLayoutRenderable` 协议对应 witness 与 `FieldLayoutRenderer` facade 同步
  `throws` 化；`StaticFieldLayoutBackend`（离线路径）的非抛错实现继续满足协议，
  行为不变。
- dump 路径三个 dumper 的调用点加 `try`（恢复旧 dump 行为）。
- `renderModelFields` → `async throws`：field records 与每条 record 的
  mangledTypeName 恢复 `try` 读取；字段/枚举 case 改走 `printThrowingField` /
  `printThrowingEnumCase`——单字段失败让整个类型渲染抛错（旧契约），不再产生
  幽灵空缩进行 + 无归属 stdout `print(error)`。

### 5. extension conformance 子句塌缩语义恢复（审计 #5）

`printExtensionHeader` 区分两种失败：`protocolNode` **返回 nil** → 空名字但子句照发
（旧 `dumpProtocolName` 的悬空 `extension Foo: @retroactive ` 形态）；**抛错** → 整个
子句丢弃（旧 `try?` 语义）。迁移后的 optional-chain 把两者混同，导致
`@retroactive` / global-actor 标记随子句一起被静默吞掉。

### 6. SwiftDump 死代码删除（审计 #6）

- `AssociatedTypeDumper.mergedRecords` + `AssociatedTypeRecordDedupKey` +
  `collectUniqueRecords`（interface 路径持有等价复制品后已无调用者）。
- `TypedDumper` 的 `nestedFieldOffsetExpansionDepthLimit` 死副本与死 `@Loggable`
  （见修复 2）。

## 验证方法：跨提交差分 harness

独立 SPM 包 `differential-harness`（scratch 工具，不入库；源码与用法完整记录在
[TaskReports/2026-07-31-leaf-migration-regression-fixes.md](TaskReports/2026-07-31-leaf-migration-regression-fixes.md)）：
dlopen 目标镜像 → 对每个 type descriptor 走 dump 路径（全注释开）+ 对整个 image 走
interface 路径（plain），两个 checkout 各构建一份（`.package(path:)` 指向对应
worktree），同一二进制跑两遍 diff。

语料：SymbolTestsCore fixture（366 类型；旧提交在 noncopyable/~Copyable 元数据上有
当时未修的 SIGSEGV，`--skip` 跳过 3 类）+ 专门构造的 `EdgeCaseFixture.dylib`
（Void payload、spare-bits/tagged 多 payload、indirect、引用存储等 13 类型）。

收敛结果（`aa233bc^` vs 修复后）：

| 语料 | diff 行数 | 内容 |
| --- | --- | --- |
| edge plain | **0** | 逐字节一致（修复前差 6 行——正是 Void 括号回归） |
| fixture plain | 20 | 全部为 SE-0452 整数泛型实参打印的**有意修复**（旧版丢参数打出 `InlineArray<, Bool>`） |
| edge / fixture comments | 259 / 696 | 全部为枚举布局注释措辞的**有意演进**（detailed 模板、case 名、encoding 行）；按类型统计的注释块**存在性** 371/371 完全一致 |

修复前后对比（同为当前代码）：仅 edge 语料 Void 括号 2 处 ×2 遍变化，其余 0 diff——
修复零附带输出变化。

## 新增测试

- `SwiftDeclarationRenderingTests/MultiPayloadEnumDescriptorCacheTests`：
  fixture `__swift5_mpenum` 全量入索引、未知 node 非抛错 miss、全部非泛型多 payload
  枚举布局非 nil（wholesale-suppression 回归 trip-wire）。
- `SwiftPrintingTests/EnumCaseRenderingParityTests`：进程内 fixture 枚举
  `VoidPayloadRenderingFixtureEnum`——interface 路径保留 `case unitPayload()` 括号、
  空 case 保持裸形；dump 与 interface 两路 case 行集合完全相等。
- `SwiftDumpTests/NestedFieldOffsetExpansionDepthLimitTests` 改钉
  `SwiftDeclarationRendering` 活值。

## 影响面

- **RuntimeViewer 零代码改动**：所有变化在库内；`printTypeDefinition` 签名不变。
  用户可见改善——坏 descriptor 的 image 里多 payload 枚举布局注释不再整体消失、
  点击枚举节点不再线性重扫、Void payload case 恢复括号、字段渲染失败不再留幽灵
  空行（恢复为整类型报错，与 v2.1.0-beta.7 之前一致）。
- **`swift-section` dump 输出不变**（健康路径逐字节一致，差分钉过）；interface 输出
  仅 Void payload case 恢复括号。
- **API 面**：`FieldLayoutRenderer.storedFieldComments` / `enumCaseComments` 与对应
  `FieldLayoutRenderable` witness 变为 `throws`（`package` / 库内 SPI 面；对外无破坏）。
  `renderModelFields` 为 SwiftPrinting 内部方法。
- 与并行进行的 NodeStore 迁移（`feature/node-store`）存在冲突面：本批触及
  `RuntimeFieldLayoutBackend` / `SwiftDeclarationPrinter+Members` /
  `SwiftDeclarationPrinter+Headers`，合并时需按本文语义为准做冲突消解
  （`FieldDefinition.typeNode` 在该迁移中变为 `NodeReference`，
  `printThrowingEnumCase` 的 `payloadTypeNode` 取值处需随之适配）。
