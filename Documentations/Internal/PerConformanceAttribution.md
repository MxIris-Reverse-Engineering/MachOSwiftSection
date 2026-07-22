# Per-Conformance / Per-Where-Block 归属（设计与实现）

> 面向维护者的设计说明。关闭 [`ABIDiffDesignAndLimitations.md`](ABIDiffDesignAndLimitations.md)
> 的局限 5（extension 变更只能归到 `ExtensionName` 粒度），并兑现局限 3 的
> 「把碰撞成员分开比较」。涉及 `SwiftDeclaration`（模型）、`SwiftIndexing`（接线）、
> `SwiftDiffing`（主体）、`SwiftInterface`（diffable renderer）四层，
> snapshot 持久化格式随之 bump 到 **version 3**。

## 动机：总账 → 明细账

拆分前，快照阶段把一个 target 的所有 `ExtensionDefinition`（多个 conformance、每个
条件块、合成 typealias 块）摊平合并进一个按 `extbucket:<kind>|<target>` 建键的
`ContainerSnapshot`。结论在这个粒度上是对的，但有四个盲区：

1. **归因不了**——报告只能说 `extension SwiftUI.Text` 变了，说不出是哪个 conformance；
2. **键碰撞的唯一现实来源**——两个条件 extension（`where T: P` vs `where T: Q`）的
   同名成员（mangling 不编码 where 子句）摊平后撞键，first-wins 丢弃（有诊断兜底但
   仍未比较）；
3. **条件收紧/放宽不可见**——conditional conformance 的 requirement 列表存在
   conformance descriptor 里、是真实 ABI，但不参与任何键；
4. **associated-type witness 不参与 diff**——`ExtensionDefinition.associatedTypes` 的
   name 访问器 Mach-O-bound，Mach-O-free 的快照投影够不着。

**关键事实**（调研结论）：所需信息在索引期全部在手上。
`SwiftDeclarationIndexer` 创建 conformance extension 时（`protocolConformancesByTypeName`
双层循环），protocol 名就是循环变量；where 子句已经通过
`MetadataReader.buildGenericSignature(for: protocolConformance.conditionalRequirements)`
以纯 `Node` 存进了 `genericSignature`。唯一 Mach-O-bound 的是
`AssociatedTypeRecord.name(in:)` / `substitutedTypeName(in:)`——索引期解析成字符串即可。

## 设计决策：拆容器，而非挂标签

conformance / extension 容器按 **(target, protocol, where 指纹, isRetroactive)** 拆分，
每个子组一个 `ContainerSnapshot`：

- 新增/移除一个 conformance = 干净的**容器级** added/removed；
- 每个条件块是独立比较作用域 → 碰撞源结构性消失；
- where 子句变更 = 容器身份变更 = removed+added——兑现 `ContainerChange` 文档既有
  doctrine（"container-level non-member payload 折入 ABIKey 身份"；`isRetroactive`
  同样借此真正折入）。

放弃的替代方案（合并 bucket + 成员归因标签）：兼容现有报告形状，但新 conformance
仍是成员碎片、碰撞照旧、表达力弱，不取。

## 分层改动

### 1. SwiftDeclaration（模型）

`ExtensionDefinition` 新增两个索引期写入的 Mach-O-free 字段：

```swift
public let conformingProtocolName: ProtocolName?      // conformance extension 才非 nil
public package(set) var resolvedAssociatedTypeWitnesses: [AssociatedTypeWitnessProjection]

public struct AssociatedTypeWitnessProjection: Sendable, Codable, Equatable {
    public let name: String                // associated type 名
    public let substitutedTypeText: String // witness 类型的 demangle 打印
}
```

### 2. SwiftIndexing（接线）

- conformance extension 创建点把循环里的 `protocolName` 传入；
- 同处把 `associatedType`（若有）的 records 解析成 `AssociatedTypeWitnessProjection`
  （machO 在手；解析失败的 record 跳过并走既有 event 告警路径）；
- typealias-only 块（无 conformance 的剩余 associated types）protocol 保持 nil，
  P1-9 的 typealias-only 归并逻辑不动。

### 3. SwiftDiffing（主体）

- **子键**（`ABIDiffer` 公开静态方法，替代旧 `extensionBucketKey(for:)` 的共享角色）：

  ```
  extbucket:<kindToken>|<target sortKey>|proto:<protocol ABIKey sortKey 或 "-">|where:<genericSignature ABIKey sortKey 或 "-">|retro:<0/1>
  ```

  protocol / where 指纹用 `ABIKey.makeUnwrappingType` / `ABIKey.make` 走 remangle-优先
  老路（跨工具链的结构差异风险与局限 2 同类，接受）。
- `extensionBucketSnapshots`：每个 `ExtensionName` 内按子键分组，一个子组 = 一个
  `ContainerSnapshot`，成员只在子组内合并。
- `ContainerSnapshot` 增加 `conformedProtocolName: String?` / `whereClauseText: String?`
  （报告名渲染 `Target: Protocol where …`）。
- `memberRecords(of: ExtensionDefinition)` 投影 witness：
  `MemberRecord.makeAssociatedTypeWitness(name:substitutedTypeText:)`，identity
  `assocwitness:<name>`（与 protocol 侧 `associatedType:` 命名空间区分——那是
  requirement 的存在性，这是 witness 的绑定），payload 折入类型文本 ⇒ 同名 witness
  换绑报 `.modified`。
- `ABISnapshotDocument.currentFormatVersion` **2 → 3**（key scheme + snapshot schema
  双变更），version-2 baseline 显式拒绝。

### 4. SwiftInterface（diffable renderer）

`renderExtensionBucketsUnits` 从 `ExtensionName` 桶级匹配改为子键级匹配（复用同一
静态方法），header 携带 `: Protocol` 与 `where` 子句。可断言套件无 diffable renderer
快照（仅 IntegrationTests 手检），输出形状变化不破坏测试。

## 语义后果

| 变更 | 之前 | 之后 |
|---|---|---|
| 新增/移除 conformance | bucket 内成员碎片 | 容器级 added/removed（名字带 `: Protocol`） |
| 条件 extension 同名成员 | 撞键，first-wins + 诊断 | 各自独立容器，正常比较 |
| where 子句变更 | 完全不可见 | removed+added（身份变更） |
| `isRetroactive` 切换 | 不可见 | removed+added |
| associated-type witness 换绑 | 不参与 diff | `.modified`（`assocwitness:` 命名空间） |
| evolution | 桶级 lineage | 自动获得 per-conformance lineage（零改动） |

诊断通道（`ABISnapshot.keyCollisions()`）保留：拆分后碰撞在真实二进制上应趋于零，
仍出现即为值得人工审视的异常。

## 测试策略

- 子键分组为可对 Node 单测的纯函数（沿用 `ABIDifferTests` 手工构造风格）。
- 用例：同 target 双 conformance 拆两容器；增删单个 conformance 报容器级事件；
  where 变更报 removed+added；同名成员分属两个条件块不再碰撞（且不再进诊断）；
  witness 换绑报 modified；retroactive 切换报 removed+added；typealias-only 归并
  不回退；formatVersion 3 拒绝 v2。
- fixture 端到端：SymbolTestsCore `CollectionConformances`（多 conformance 类型）
  自比对为空且容器拆分正确。

## 已知局限（继承）

- protocol / where 指纹依赖 remangle 确定性——与局限 2 同类的跨工具链结构差异风险。
- 非 conformance 的成员 extension（符号扫描产生的 `typeExtensions` 桶）只有 where
  维度可拆（无 protocol）；无 `genericSignature` 的定义共享 `where:"-"` 子组，
  行为与拆分前一致。
