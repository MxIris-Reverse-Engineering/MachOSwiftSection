# 0003 - SymbolIndexStore `[UInt32]` 行号桶扁平化：单元素桶内联化

- **状态**: Implemented
- **作者**: JH
- **创建日期**: 2026-08-09
- **最后更新**: 2026-08-09
- **所属愿景**: 无
- **关联提案**: [0001](0001-symbol-name-offsetization.md)（其「非目标」一节点名本案为下一篇候选；`symbolRowsByOffset` 的 offset 键表 12.2 MiB 即 0001 引入的形态）。与 [0002](0002-declaration-model-descriptor-slimming.md) 正交（不同簇、不同模块），可独立实施
- **实现分支 / PR**: `feature/node-store-migration`（拟，待批准后实施）
- **配套文档**: 暂无

## 摘要

RV 实测堆里有 **38.8 MiB / 45 万个小 `[UInt32]` 数组**，来源是 `SymbolIndexStore.Storage` 的行号桶：`symbolRowsByOffset: [Int: [UInt32]]`（12.2 MiB）与三族 `MemberSymbolRows` 嵌套字典的叶子桶。绝大多数桶只有一个元素，却各付一次堆分配（Array 存储头 + malloc 桶圆整 ≈ 48 B）外加字典槽里 8 B 的引用。本案引入「单元素内联、多元素才落堆」的小桶类型替换 `[UInt32]` 桶值，预估省 **15–25 MiB**，零公开 API 变化。

## 动机

- 0001 落地时已点名（其「非目标」：44 万个单元素桶，当时估 ~28 MiB；0001 后 RV 实测簇为 38.8 MiB / 45 万个，含新 offset 键表 12.2）。
- 一个符号 offset / 一个成员键在绝大多数情况下只对应一行——`[UInt32]` 的通用性为「偶发多行」让全体单行桶付堆分配，是纯粹的表示浪费。
- 每桶节省估算：今天单元素桶 = 字典槽 8 B 引用 + 堆上 ~48 B（32 B Array 头 + 16 B malloc 槽）；内联后 = 字典槽 ~16 B、零堆分配。约省 40 B/桶 × 45 万 ≈ 17 MiB，与预估带吻合。

## 前期调研

### 现状代码怎么走的

- `Storage.symbolRowsByOffset: [Int: [UInt32]]`（`SymbolIndexStore.swift:196`）：sweep 期 `append` 累积（`:443`），查询侧单点消费 `symbol(atRow:offset:)`（`:920`）。
- `Storage.MemberSymbolRows = OrderedDictionary<String, OrderedDictionary<NodeStore.NodeIndex, [UInt32]>>`（`:133`）：三族（member / methodDescriptor / protocolWitness，`:184-188`），叶子桶同样 append 累积、查询侧整桶物化。
- `globalSymbolRowsByKind` / `symbolRowsByKind`（`:159/190`）：按 kind 聚合的**大**桶，数量个位数到几十，不在本案范围。

### 验证过什么

- 0001 的 RV heap 复测把 `[UInt32]` 簇钉在 38.8 MiB / 45 万个（malloc 归属），量级可信。
- 单元素占比未逐桶实测（malloc 档案只给总量）；落地时在 freeze 处加一次性统计断言辅助验收（预期 ≥ 85% 单元素，与 0001 期「44 万单元素」的旧测量一致）。

## 提议方案

新增 `SymbolRowBucket`（`MachOSymbols` 内部类型）：

```swift
enum SymbolRowBucket {
    case single(UInt32)
    case multiple([UInt32])
}
```

- `append(_:)` 语义：空槽首插走 `single`；第二个元素起迁移为 `multiple`（一次两元素数组分配）。
- 提供 `Sequence` / `count` / `contains(_:)` 薄接口，查询路径零拷贝迭代。
- 替换范围：`symbolRowsByOffset` 的值、三族 `MemberSymbolRows` 的叶子桶。查询 API 的返回形态（`[DemangledSymbol]` 等）不变——桶在出口物化，与今天相同。

### 非目标

- `OrderedDictionary` 自身的 ordering 表开销与 `MemberSymbolRows` 的 String 键：另一个问题域（键人口是打印名，见 0001 非目标），不动。
- 按 kind 聚合的大桶（`symbolRowsByKind` / `globalSymbolRowsByKind`）：数量少、本就该是数组，不动。
- CSR（compressed sparse row）全量平铺：见「替代方案考量」。

## 详细设计

- 布局：`case single` 载荷 4 B + tag，enum 内联 ≤ 16 B（`compactValueLayouts` 加断言钉住）；字典槽从 8 B 引用变 ~16 B 内联值，堆分配从每桶一次降为仅多元素桶一次。
- sweep 期就地累积形态不变（`symbolRowsByOffset[offset, default: .empty].append(row)` 句式），无需 build/freeze 双形态——这是选 enum 而非 CSR 的直接原因。
- `mayAlreadyBeListed` 去重探测（`:440`）改走 `contains(_:)`。
- 迭代顺序保持插入序（`multiple` 数组序即插入序，`single` 天然有序），查询输出字节不变。

### 风险与接受的约束

- `multiple` 桶比今天多付一次「single → 两元素数组」的迁移拷贝：仅多行桶付、每桶一次，量级忽略不计。
- enum 内联 16 B 使字典槽变宽：单元素占比越低收益越薄；按 ≥ 85% 单元素估算净省仍在 15–25 MiB 带内，freeze 期统计为验收证据。

## 替代方案考量

- **CSR 全量平铺**（一条大 `[UInt32]` + 每键 range）：驻留最省，但 sweep 期需要 build 态（每键临时桶）→ freeze 态（平铺）的双形态转换，且三族嵌套字典的叶子层都要陪着改形态；enum 方案 90% 的收益、1/3 的改动面。被否——若日后 profiling 证明字典槽变宽是新瓶颈再升级，结构兼容。
- **`[UInt32]` 换 `ContiguousArray<UInt32>` / 预留容量**：不解决「堆分配次数 = 桶数」的根因。被否。
- **swift-collections 现成类型**：无「inline-one 小数组」稳定 API（`InlineArray` 是定长语义，SE-0453）；自写 20 行 enum 即可。被否。

## 影响

### 源码兼容性（source compatibility）

**纯内部 / 无破坏。** `SymbolRowBucket` 与 `Storage` 各字典的值类型都在 `MachOSymbols` 内部（`Storage` 非 public）；全部查询 API 的签名与返回形态不变，输出字节不变。

### ABI 兼容性（条件项）

不适用——SPM 源码分发（项目类型声明见 `Documentations/README.md`）。

### 下游影响

- 仓库内：仅 `MachOSymbols`（`SymbolIndexStore.swift` + 新类型文件）。
- 下游仓库：零源码改动，重编译即得收益。RV 为验收方。

### 文档与示例

- AGENTS.md「Symbol indexing」段补一句桶表示；`Documentations/README.md` 索引同步。

## API 演进与废弃策略

- 无公开 API 变化，无废弃需求；随下一次常规版本发布，changelog 记录内存收益。

## 落地步骤

1. ✅ `SymbolRowBucket` 实现 + 布局断言（`compactValueLayouts` 钉 `stride ≤ 16`）+ 单测（append 迁移、迭代序、`contains`——`symbolRowBucketAppendMigrationAndIterationOrder`）。
2. ✅ `symbolRowsByOffset` 与三族 `MemberSymbolRows` 叶子桶替换（`demangledSymbols(atRows:)` 泛化为 `some Sequence<UInt32>`，查询出口形态不变）；单元素占比统计落为 `Storage.bucketFormStatisticsForTesting()`——常驻单测 `rowBucketsAreDominatedBySingleRowForm` 断言并打印，另在 IntegrationTests 的 baseline 指标里加了一行。fixture（SymbolTestsCore，MachOFile leg）实测 **87.6% 单元素**（6687 单 / 948 多），达到 ≥85% 预期带。
3. ✅ 全量 `swift test --skip IntegrationTests` 1343 全绿（含新增 2 项桶单测，无删减）；渲染 A/B（iOS 18.5 模拟器 SwiftUI / SwiftData / SwiftUICore 的 dump + interface，另加宿主机 dyld shared cache 的 SwiftUI dump + interface——canonical/raw 双键注册正是本案改动面）全部逐字节一致（interface 输出剥离日志行首时间戳后比对）。
4. RV heap 复测：`[UInt32]` 簇 38.8 → 预期 ~15–20 MiB。**待下游拿到本分支后进行。**

## 决策日志

| 日期 | 变更 | 说明 |
|------|------|------|
| 2026-08-09 | Created as In Review | 0001「非目标」点名的候选正式立项；RV 实测簇 38.8 MiB / 45 万个为输入；用户批准立项（「可以，写提案」）。 |
| 2026-08-09 | In Review → Accepted | 用户审核通过（「审核通过，开始实现」），与 0002 同批开工，两案独立实施。 |
| 2026-08-09 | Accepted → Implemented | 落地步骤 1–3 完成：`SymbolRowBucket`（`RandomAccessCollection`，单元素内联、次元素起落堆、插入序迭代）替换四处桶；fixture 单元素占比 87.6%；全量 1343 绿；A/B 七对（含 dyld cache 两对）逐字节一致。步骤 4（RV heap 复测）待下游拿到分支后进行。 |
