# SemanticTransformer 迁移 —— Transformer 模板机制从 RuntimeViewerCore 搬入库侧

日期：2026-07-19
状态：已完成（范围修订：ObjC 侧模块按用户指示暂留 RV）
影响模块：新增 `SemanticTransformer`；`SwiftInspection`、`SwiftDeclarationRendering`、`SwiftPrinting`、`swift-section`；RuntimeViewerCore 已同步（Swift 侧删模板改 re-export、接线缩为一次 `applyTransformers` 调用；ObjC 侧模块保留在 RV）

## 动机

RuntimeViewer 的设置界面提供「注释模板」定制（token 模板 + 预设），但模板引擎、
token 定义、预设目录此前全部住在 RuntimeViewerCore ——库输出注释、RV 再用闭包
transformer 包一层模板重渲染。用户定案：**模板机制整体搬进本仓库，RV 只保留 UI
交互**。前一轮已把 enum-layout 模板搬入（`EnumLayoutCommentTemplate`），本轮把
`Transformer` 命名空间的 **Swift 侧 5 个模块**搬齐并统一（ObjC 侧按用户指示
暂留 RV，见下）。

## 架构

- **新 target `SemanticTransformer`**（零依赖，位于依赖图底部）：
  `Transformer` 命名空间 + `Module` 协议 + **Swift 侧 5 个模块** +
  `SwiftConfiguration` 聚合。模块清单：
  - `SwiftFieldOffset`、`SwiftMemberAddress`、`SwiftVTableOffset`
    （单行 token 模板 + 模板目录）
  - `SwiftTypeLayout`（11 个 token；**flags 输入改为可选** —— 静态离线路径知道
    size/stride/alignment/XI 但不知道 VWT flags，缺失 token 渲染为 `"unknown"`）
  - `SwiftEnumLayout`（三层模板：策略行 / 逐 case 块 / 逐字节行；吸收了前一轮
    `EnumLayoutCommentTemplate` 的引擎——line-token 条件行 + 空行丢弃 +
    `fixedBitsPhrase` 位区间叙述 + 4 个预设 detailed/explained/standard/compact）
- **ObjC 侧暂留 RV**（用户指示）：`CType`（C 原语替换，依赖 `Semantic` 的
  `SemanticString`）、`ObjCIvarOffset`、`ObjCConfiguration` 与聚合持久化
  `Configuration` 保留在 RuntimeViewerCore，以「扩展库侧 `Transformer`
  命名空间」的形式声明（沿用 MetaCodable）；待 ObjC 渲染管线有库侧归宿时再迁。
- **Codable 持久化契约**：库侧不引入 MetaCodable。Swift 侧模块与聚合配置手写
  missing-key-tolerant 解码（`decodeIfPresent ?? default`），属性名与 RV 旧
  `@Codable` 持久化 key 保持一致（`isEnabled`/`template`/`caseTemplate`/
  `memoryOffsetTemplate`/`useHexadecimal`/`replacements`/`labeledTemplate`），
  RV 已存储的设置 JSON 直接可解。
- **SwiftInspection 桥接**（`Transformer+EnumLayoutProjection.swift`）：
  `LayoutResult`/`EnumCaseProjection` → 模板 Input 的构造、
  `renderStrategyComment(for:)`/`renderCaseComment(for:)` 便利、
  `description(indent:prefix:template:)` 包装。内置默认渲染
  `EnumCaseProjection.description(indent:prefix:)` 委托 `.detailed` 预设 ——
  单一来源，等价性由单测锁定。
- **闭包工厂 + `applyTransformers`**（`SwiftDeclarationRendering/
  TransformerClosureFactory.swift` 与 `SwiftPrinting/
  SwiftDeclarationPrintConfiguration+Transformers.swift`）：
  `Transformer.SwiftConfiguration` 的启用模块物化为既有的六个闭包槽
  （memberAddress/vtable/fieldOffset/typeLayout/enumLayout/enumLayoutCase），
  发射点零改动；`applyTransformers(_:)` 一次装载（禁用的模块清回内置渲染）。
  这正是 RV 原来 5 个 `build*Transformer` 函数的库侧化 —— RV 侧删掉 181 行。
- **CLI**：`swift-section dump --enum-layout-style` 改为
  `Transformer.SwiftEnumLayout.Preset`，经 `applyTransformers` 装载
  （`detailed` 不装载，走内置路径，输出逐字节等同）。

## RV 兼容语义（引擎内保留）

1. **auto-append**（`appendsOmittedDetails`，默认开）：case 模板未引用任何
   字节信息 token（`fixedBytesSummary`/`fixedBytesLine`/`memoryChangesDetail`）
   时，自动在其后追加 pattern note 与 fixed-bytes 行 —— RV 旧目录里的
   `classic` 等模板行为不变。compact 预设显式关掉该开关。
2. **partial-mask 安全**：逐字节模板不含 mask-aware token
   （`fixedBitMask`/`fixedBitMaskBinaryPadded`/`fixedBitsPhrase`/
   `offsetDescription`）时，部分固定字节不经模板渲染、回退 mask-scoped 内置
   措辞 —— 防止 `[0]=0x00` 式整字节过度声明（RV 原有的 bypass 泛化进引擎）。
3. **行为差异（有意）**：`${caseType}` 的值从 "Payload"/"Empty" 改为
   "payload case"/"empty case"；`SwiftEnumLayout` 的默认模板从
   strategyOnly/classic-standard 改为 `.detailed` 预设（与内置渲染一致）。
   已持久化的自定义模板不受影响（值随 JSON 携带）。

## RuntimeViewerCore 侧

- `Transformer/` 目录收缩为三个文件：`Transformer.swift`（`@_exported import
  SemanticTransformer` shim + RV 本地的 `ObjCConfiguration` / 聚合
  `Configuration` 扩展）、`Transformer+CType.swift`、
  `Transformer+ObjCIvarOffset.swift` —— RV 全工作区（设置 UI 的
  `Templates.all`/`Token.displayName`/`CType.Presets` 引用）零改动编译。
- `RuntimeSwiftSection.buildPrintConfiguration`：5 个 build* 闭包工厂删除，
  改为 `newConfiguration.applyTransformers(transformer)`（仅在 transformer
  变更时重装 —— 闭包按 identity 参与配置 Equatable，每次重建会误清接口缓存）。
- `TransformerTests` 精简为 re-export 冒烟 + 持久化 round-trip（引擎测试
  已由本仓库 `TransformerModuleTests`/`EnumLayoutCommentTemplateTests` 覆盖）。

## 测试

- 本仓库：`TransformerModuleTests`（Swift 侧各模块渲染、聚合配置、
  Codable round-trip、缺 key 宽容解码）+ `EnumLayoutCommentTemplateTests`
  （13 个：detailed≡内置等价、explained 位区间、auto-append 兼容、
  mask 安全回退、自定义 token、hex 模式等）。全量 1200 测试 / 233 suites
  全绿，快照零漂移（默认渲染路径未变）。
- RV：`TransformerTests` 保留 re-export 冒烟 + ObjC 侧模块（CType 最长匹配等）
  + 聚合持久化 round-trip；RuntimeViewerCore 全套仅 1 个既有环境性失败
  （`RelationshipsTests` 的 NSCoding anchor，与本迁移无关）。

## 已知边界

- 静态（`MachOFile`）路径的 type-layout 注释仍走内置格式（闭包 transformer
  以 runtime `TypeLayout` 为输入类型），与迁移前行为一致；`SwiftTypeLayout.Input`
  的可选 flags 已为将来接通静态路径备好。
- `Transformer.Module` 协议保持 RV 形状（`Parameter`/`Input`/`Output` +
  `displayName`），设置 UI 直接消费。
