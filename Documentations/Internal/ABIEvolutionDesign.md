# ABI Evolution —— 多版本二进制 ABI 演化追踪（设计与实现）

> 面向维护者的设计说明。记录 `SwiftDiffing` 模块中 evolution（N ≥ 2 个版本的
> ABI 生命线追踪）能力的动机、模型、算法与 CLI 接线，以及作为其地基一并落地的
> snapshot 持久化设施（版本头 + provenance + `snapshot` 子命令 + JSON 输出）。
>
> 配套文档：双侧 diff 引擎见 [`ABIDiffDesignAndLimitations.md`](ABIDiffDesignAndLimitations.md)。
> evolution 完整继承那份文档记录的全部局限（`@frozen` 不可恢复、`ABIKey`
> 跨侧不对称、`keyed` 碰撞丢弃、extension bucket 粒度等），本文不重复展开。

## 动机

`ABIDiffer` 只能回答"两个版本之间变了什么"。对同一模块的一串版本
（例如 iOS 17 / 18 / 26 三份 dyld shared cache 里的同一框架），更有价值的问题是
**每个声明的生命线（lineage）**：它在哪个版本出现、在哪个版本被改、在哪个版本
消失、有没有消失后又回归。这正好落在 diff 引擎两个既有性质的延长线上：

1. **diff 是 Mach-O-free 的纯值计算** —— N 个二进制只需各索引一次、冻结成 N 个
   `ABISnapshot`，之后的演化分析完全在值数据层进行，天然支持"历史版本给存档
   JSON、新版本给二进制"的混合输入；
2. **`ABIKey` 身份体系直接推广** —— 一条 lineage 就是一个 `identityKey` 在有序
   快照序列中的 出现 / 缺席 / payload 变化 序列。

## 落点

放在 `SwiftDiffing` 模块内（不新建模块）：lineage 聚合需要复用
`MemberRecord` / `ABIKey` / keyed 索引的内部细节，独立模块会被迫公开这些内部
API。CLI 命令名为 `evolution`。

---

## Phase 0 —— snapshot 持久化地基

evolution 的使用方式依赖 baseline 存档（N 次索引是瓶颈，演化计算是毫秒级），
所以先补齐三件挂账（同时清掉三条 TODO(P2)）：

### 0-1. `ABISnapshotDocument` —— 带版本头的持久化信封

`ABISnapshot` 保持纯 ABI 数据不动（`Equatable` 语义仍是"同 ABI"）。新增：

```swift
public struct ABIProvenance: Sendable, Codable, Equatable {
    public var label: String?             // 用户可读的版本标签（"17.0"）
    public var binaryPath: String?        // 来源二进制路径（cache 场景含 image 名）
    public var generatorVersion: String?  // 生成工具版本（BundledVersion）
    public var createdAt: Date?
}

public struct ABISnapshotDocument: Sendable, Codable, Equatable {
    public static let currentFormatVersion = 1
    public let formatVersion: Int
    public var provenance: ABIProvenance?
    public var snapshot: ABISnapshot
}
```

- **版本头语义**：`MemberRecord` 的键字符串（`"field:"`、`"tag:N|"`、`"|acc:"`、
  `"extbucket:"` 等）是事实上的持久化格式。**任何 key scheme 变更都必须 bump
  `currentFormatVersion`**，让旧 baseline 显式失效而不是被静默误读。
- 自定义 `init(from:)`：先读 `formatVersion`（缺失 → `missingFormatVersion`，
  不等于当前值 → `unsupportedFormatVersion(found:supported:)`），再解其余字段，
  错误信息可直接面向 CLI 用户。
- 编解码统一走 `ABIJSON`（`.iso8601` 日期 + `.sortedKeys` + `.prettyPrinted`），
  同一快照编码两次字节一致，baseline 可以进 git。

### 0-2. `ABIDiff` provenance 头

`ABIDiff` 增加 `oldProvenance` / `newProvenance: ABIProvenance?`（默认 nil，
既有调用点不受影响）；`ABIDiffer.diff(old:new:)` 增加对应默认参数，并新增
`diff(old: ABISnapshotDocument, new: ABISnapshotDocument)` 便捷入口。

### 0-3. CLI

- 新增 `swift-section snapshot <binary> [--label 17.0] [-o baseline.json]`：
  索引一个二进制并写出 `ABISnapshotDocument` JSON（缺省 stdout）。
- `swift-section diff` 接受快照文件作为任一侧输入（嗅探：首个非空白字节为
  `{` → 按 document 解码，否则按 Mach-O 加载）。`--interface` 需要 live
  builder，故两侧必须都是二进制（validate 报错）。
- `swift-section diff --json`：输出 `ABIDiff` 的 JSON（含 provenance），供 CI
  与后续工具消费。与 `--interface` / `--summary-only` 互斥。

## Phase 1 —— evolution 模型与算法

### 模型（全部 `Sendable + Codable + Equatable` 纯值）

```swift
public struct ABIEvolution {
    public let versions: [ABIVersionDescriptor]     // 有序版本轴，count == N ≥ 2
    public let types: [ContainerLineage]
    public let protocols: [ContainerLineage]
    public let typeExtensions: [ContainerLineage]
    public let protocolExtensions: [ContainerLineage]
    public let typeAliasExtensions: [ContainerLineage]
    public let conformanceExtensions: [ContainerLineage]
    public let globalVariables: [MemberLineage]
    public let globalFunctions: [MemberLineage]
}

public struct ABIVersionDescriptor { label: String; provenance: ABIProvenance? }

public struct LineageEvent {
    public let versionIndex: Int        // 事件落在 versions[versionIndex]，∈ 1...N-1
    public let status: ChangeStatus     // added / removed / modified（复用 diff 的词汇）
    public let oldSignature: String?
    public let newSignature: String?
}

public struct MemberLineage {
    public let key: ABIKey
    public let kind: MemberKind
    public let presence: [Bool]         // N 项，逐版本"是否存在"
    public let events: [LineageEvent]   // 非空（空事件的 lineage 不收录）
}

public struct ContainerLineage {
    public let key: ABIKey
    public let name: String
    public let containerKind: ContainerKind
    public let presence: [Bool]
    public let events: [LineageEvent]           // 仅容器级 added / removed
    public let memberLineages: [MemberLineage]
}
```

语义约定（与双侧 diff 保持一致，全部有测试锁定）：

- **事件 = 相邻转换**。`versionIndex == i` 的事件描述 `versions[i-1] → versions[i]`
  这一步。`presence` 是逐版本的权威存在位图（含"移除后回归"），事件是变化清单。
- **收录规则与 diff 相同**：member lineage 仅在 `events` 非空时收录；container
  lineage 在自身有事件或有成员 lineage 时收录。全程无变化的 API 不出现在结果里
  （全量矩阵视图属于后续可选项）。
- **容器缺席的转换不枚举成员**：与 `ABIDiff` "added/removed 容器的
  `memberChanges` 为空（整个容器就是变更）" 一致，成员级事件只在**相邻两个版本
  容器都存在**时计算。容器在 v2 消失、v3 回归时：容器有 removed@2 + added@3
  两条事件，其成员即使跨缺口发生了 retype 也不单独报事件（双侧 diff 同样看不见，
  一致性优先）。成员的 `presence` 定义为"容器存在 ∧ 成员存在"。
- **签名变更 = 断链**。function 换签名 = 换 symbol = 一条 lineage 终结 +
  一条开始（继承自 identity 设计）。同容器内的 rename 关联启发式属于后续项。
- **modified 容器不设容器级事件**：由成员事件派生（reporter 侧汇总），避免模型
  内冗余两份。

### 算法（`ABIEvolutionBuilder`）

不做 N−1 次 pairwise diff 再 join，而是直接建 **key → 逐版本记录** 矩阵：

```
每个容器轴（types / protocols / 4 个 extension bucket）：
  1. 每个版本的 [ContainerSnapshot] 按 key 建索引（keyedFirstWins，
     碰撞语义与 diff 完全一致）
  2. 对 key 全集（按 sortKey 排序）：
     presence[i] = 该版本存在该容器
     容器事件：presence 的相邻翻转（absent→present = added，反之 removed）
     成员矩阵：对相邻两版本容器都存在的转换，按 identityKey 比对
       （缺→有 = added；有→缺 = removed；都在且 payloadKey 不同 = modified，
        签名取自对应侧的 MemberRecord.signature）
  3. name/kind 取最后一次出现的版本（最新命名）
globals：同成员矩阵，视作容器恒存在。
```

- 入口：`evolution(of documents: [ABISnapshotDocument], labels: [String]? = nil)`。
  标签解析优先级：显式 `labels` > `provenance.label` > `"v\(index+1)"`。
  `labels` 数量不匹配或 document 数 < 2 抛 `ABIEvolutionError`。
- `keyedFirstWins` 从 `ABIDiffer` 的私有 `keyed` 提为模块内共享函数（首个保留、
  其余丢弃的已知局限原样继承，文档注释随迁）。
- **一致性保证**：N == 2 时，evolution 的事件集与 `ABIDiffer.diff` 的变更集
  一一对应（测试锁定），两条路径不可能给出不同结论。

### 兼容性推广（`Compatibility.swift` 扩展）

- `ABIEvolution.transitionCompatibilities: [Compatibility]`（N−1 项）：某一步
  存在 removed / modified 事件 → `.breaking`，否则 `.additive`。
- `hasBreakingChange` / `firstBreakingTransitionIndex` 供 CLI `--fail-on-breaking`
  与报告使用。`@frozen` 附加说明与双侧 diff 相同。

### 报告（`ABIEvolutionReporter`）

纯 `ABIEvolution -> String`。版式：

```
ABI evolution across 3 versions: 17.0 → 18.0 → 26.0

Transitions:
  17.0 → 18.0: 2 added · 1 removed · 1 modified · ABI-breaking
  18.0 → 26.0: no changes

Types:
  [●●○] SwiftUI.Foo
      - removed in 26.0
      [●○○] func bar() -> ()
          - removed in 18.0
      [●●○] x: Swift.Int
          ~ modified in 18.0: x: Swift.Int → x: Swift.String
```

`●`/`○` 为逐版本存在位图；成员行缩进在所属容器下。

## Phase 2 —— CLI `evolution` 命令

```
swift-section evolution <path>... \
    [--labels 17.0,18.0,26.0] [--architecture arm64e] \
    [--dyld-shared-cache --cache-image-name SwiftUICore | --cache-image-path …] \
    [--json] [--summary-only] [--fail-on-breaking] [--output-path report.txt]
```

- `<path>...` ≥ 2 个，按时间序排列；每个可以是 Mach-O / fat 二进制、dyld shared
  cache（`--dyld-shared-cache` 时统一从每份 cache 提取同一 image —— 跨 OS 版本
  追踪系统框架正是首要用例），或 Phase 0 的快照 JSON（嗅探规则同 diff）。
- `--labels` 逗号分隔，数量须等于路径数；缺省时二进制取路径 basename、快照取
  provenance label。
- 输出：文本 timeline 报告（默认）/ `--json`（`ABIEvolution` JSON）/
  `--summary-only`（仅 Transitions 段 + 结论行）。
- `--fail-on-breaking`：任一转换 breaking 时以非零码退出。
- 加载 + 索引 + 冻结的逐输入流程与 diff 共享 `ABISnapshotInputLoader`
  （swift-section Utilities），避免两个命令漂移。

## 测试计划（`Tests/SwiftDiffingTests/`）

沿用现有 ABIDifferTests 的手工构造 `MemberRecord` / `ContainerSnapshot` 风格
（纯值、无 Mach-O）：

1. **document 编解码**：round-trip、缺版本头报 `missingFormatVersion`、版本不符
   报 `unsupportedFormatVersion`、编码字节稳定（sortedKeys）。
2. **lineage 基本形**：introduced / removed / modified / 移除后回归
   （presence 位图 + 事件序列逐项断言）。
3. **N == 2 与 ABIDiff 一致**：同输入下事件集与 `diff(old:new:)` 变更集一致。
4. **容器缺口语义**：容器消失期间成员不产生事件；回归时只报容器 added。
5. **enum case tag 演化**：中插 case 在插入版本报 modified（tag 折入 payload）。
6. **收录规则**：全程无变化的容器/成员不出现在结果中；`isEmpty` 正确。
7. **标签解析**：显式 labels > provenance > 序号；数量不匹配抛错。
8. **兼容性推广**：逐转换 additive/breaking 与 `firstBreakingTransitionIndex`。
9. **reporter**：小型 evolution 的整段文本断言（确定性输出）。

## 后续项（不在首轮范围）

- rename / re-sign 启发式关联（同容器内 add+remove 配对提示）。
- 全量矩阵视图（含未变化 API 的 API × 版本表）。
- per-conformance 归属等 diff 侧挂账 —— evolution 会自动受益，无需
  evolution 侧改动。
- 注释接口的时间线版（每行标注 introduced-in）。

## 首轮落地后的增量（第三批）

- **per-conformance / per-`where`-block 归属（已落地）**：extension 容器按
  (target, protocol, where 指纹, retroactive) 拆分，evolution **零改动**自动获得
  per-conformance lineage（一个 conformance 的出现/消失就是一条容器 lineage）。
  key scheme 变更 ⇒ `currentFormatVersion` bump 到 3。设计见
  [`PerConformanceAttribution.md`](PerConformanceAttribution.md)。

## 首轮落地后的增量（第二批）

- **`keyed` 碰撞诊断通道（已落地）**：`ABISnapshot.keyCollisions()` 独立扫描
  每个 keying 作用域，`ABIDiff.diagnostics`（逐侧）与
  `ABIEvolution.keyCollisionsByVersion`（逐版本）上浮结果，两个 reporter 渲染
  Warnings 段。first-wins 比较行为不变，丢弃不再静默。
- **enum case `indirect` 折入 payload key（已落地）**：同名同 tag 同类型的
  `indirect` 切换现在报 `.modified`。key scheme 变更 ⇒
  `currentFormatVersion` bump 到 2，版本 1 baseline 显式失效（版本头首次按
  设计发挥作用）。
