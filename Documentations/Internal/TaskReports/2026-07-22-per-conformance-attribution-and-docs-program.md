# 2026-07-22 - per-conformance 归属 + 文档第一公民批次

## 1. 问题 / 任务

两条线合并为一个批次（用户确认文档为第一公民，且要求记录整个库的演进）：

1. **per-conformance / per-`where`-block 归属**：extension 变更只能归到
   `ExtensionName`（target+kind）粒度——报告说不出是哪个 conformance 变了；
   conformance 增删表现为成员碎片；条件收紧/放宽完全不可见；associated-type
   witness 因 Mach-O-bound 不参与 diff；条件块摊平是键碰撞的唯一现实来源。
2. **文档体系补账**：建立整库演进记录、补近期 task report 缺口、补 `0.13.0`
   changelog、把文档纪律固化进 AGENTS.md。

## 2. 探索与调研

### 关键发现

- **归属信息在索引期全部在手上**：`SwiftDeclarationIndexer` 创建 conformance
  extension 时 protocol 名就是循环变量；where 子句已经以纯 `Node` 存进
  `genericSignature`（`buildGenericSignature(for: conditionalRequirements)`）。
  唯一 Mach-O-bound 的是 `AssociatedTypeRecord.name(in:)` /
  `substitutedTypeName(in:)`——索引期解析成字符串即可。
- **文档体系盘点**（两个并行探索代理）：仓库有四种文档载体（Internal 设计文档 /
  TaskReports / Changelogs / Roadmaps）但互不索引、无编年总入口；877 个提交
  15 个工作弧中 3 个最老的 arc 零文档、2026-06 中旬以来 5 个 arc 缺 task report、
  Changelogs 仅覆盖 19 个正式版本中的 3 个（`0.13.0.md` 缺失且违反
  `Version.swift` 的 bump 契约）；用户的 evolution-proposal skill 未在本仓库
  采纳且模板缺失、并与产品功能 `swift-section evolution` 撞名。

### 用户决策（AskUserQuestion 确认四项）

编年 Ledger（不引入 `evolution/` 提案目录）；老 arc 只做 ledger 条目级回填；
TaskReports 只补本对话两批；Changelog 只补 `0.13.0`。

## 3. 最终方案

见 [PerConformanceAttribution.md](../PerConformanceAttribution.md)（spec 先于代码
提交）。核心：**拆容器而非挂标签**——快照按 (target, protocol, where 指纹,
`isRetroactive`) 分组，一个子组一个 `ContainerSnapshot`；子键
`extbucket:<kind>|<target>|proto:…|where:…|retro:…` 作为 `ABIDiffer` 公开静态
方法与 diffable renderer 共享；witness 以 `assocwitness:` 命名空间参与成员
diff；`currentFormatVersion` bump 到 3。

## 4. 实际执行与改动

### 改动清单

- 文档批次 1（先行）：`ProjectEvolutionLog.md`（16 节编年 + 维护约定）、
  TaskReports ×2 回填、`Changelogs/0.13.0.md`、`Documentations/README.md`、
  AGENTS.md 文档纪律。
- 文档批次 2：`PerConformanceAttribution.md` spec。
- 实现：`SwiftDeclaration`（`conformingProtocolName` +
  `AssociatedTypeWitnessProjection` + package 纯值 init + `absorbAssociatedTypes`）、
  `SwiftIndexing`（创建点传参 + `resolvedWitnessProjections` 解析 + 归并改走
  absorb）、`SwiftDiffing`（`extensionContainerSnapshots` 分组、
  `extensionContainerKey` 双层 API、`ContainerSnapshot` 归属字段、
  `MemberRecord.makeAssociatedTypeWitness` + `MemberKind.associatedTypeWitness`、
  formatVersion 3）、`SwiftInterface`（renderer 子键匹配 + `: Protocol` /
  where 头）。
- 测试：`ABIExtensionAttributionTests.swift` 8 用例（键合成纯函数、冻结拆分、
  碰撞消解、conformance 增删容器级、where/retroactive 身份翻转、witness 换绑、
  absorb 去重）。

### 验证

- SwiftDiffingTests 69 全过；全量 `swift test --skip IntegrationTests`
  **1235 个测试全绿**（以原始输出 `Test run with …` 行为准）。
- 端到端（Geometry fixtures v4/v5：多 conformance + 条件 conformance 演化）：
  `diff` 报 `- Geometry.Point: Swift.CustomStringConvertible`（容器级）、
  `Box: Marker` 的 where 变更 removed+added；`diff --interface` 的 extension
  header 携带 `: Protocol` 与 where 子句；`evolution` 输出 per-conformance
  lineage。

### 与原方案的差异

无实质偏差。测试侧为 Mach-O-free 构造增加了 `ExtensionDefinition` 的 package
纯值 init（spec 未显式列出，属测试地基）。
