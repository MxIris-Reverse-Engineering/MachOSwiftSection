# 2026-07-21 - ABI Evolution：多版本演化追踪与 snapshot 持久化

## 1. 问题 / 任务

`SwiftDiffing` 只能回答「两个版本之间变了什么」。用户提出：在此基础上实现一个
"SwiftEvolution"——指定 2 个以上的二进制（例如同一框架在 iOS 17/18/26 三份 dyld
shared cache 里的版本），追踪每个声明的生命线：哪个版本出现、哪个版本被改、哪个
版本消失、有没有消失后回归。

同时盘点 SwiftDiffing 现存问题，作为实现的前置清账。

## 2. 探索与调研

### 调研内容

- 通读 `SwiftDiffing` 全部 8 个源文件（约 1200 行）+ `DiffCommand` +
  `ABIDiffDesignAndLimitations.md`。
- 盘点问题分三类：本质局限（`@frozen` 不可恢复、`ABIKey` 跨侧不对称——修不了，只能
  文档化）；代码挂账（11 处 `TODO(P2)`）；工程缺口（CLI 无 `snapshot` 子命令、无
  机器可读输出——`ABISnapshot` 设计目标就是 baseline 持久化但 CLI 必须两个二进制同时
  在场）。

### 关键发现

1. **架构天然适配 N 版本推广**：diff 是 Mach-O-free 的纯值计算（`ABIModule` →
   `ABISnapshot` 冻结后与二进制无关），`ABIKey` 身份体系直接推广——一条 lineage 就是
   一个 `identityKey` 在有序快照序列中的 出现/缺席/payload 变化 序列。
2. **`ABISnapshot` 无版本头**：`"field:"`/`"tag:N|"`/`"|acc:"` 键字符串是事实上的持久化
   格式，key scheme 演进会静默误读旧 baseline——做持久化之前必须先补版本头（TODO(P2)
   挂账之一）。
3. **瓶颈在索引不在演化计算**：大框架单次索引数十秒，lineage 矩阵是毫秒级——所以
   snapshot 持久化不是锦上添花，而是 evolution 的使用方式本身（历史版本用存档 JSON、
   新版本给二进制的混合输入）。

### 候选方案

- 实现方式：(a) N−1 次相邻 pairwise diff 后按 key join；(b) 直接建
  key → 逐版本 presence/payload 矩阵。选 **(b)**：更简单，且「v3 移除、v5 回归」是
  矩阵的自然产物而非 join 特例。
- 模块归属：独立 `SwiftEvolution` 模块 vs 放进 `SwiftDiffing`。用户拍板**放进
  SwiftDiffing**（lineage 聚合要复用 `MemberRecord`/`ABIKey` 内部细节，独立模块会被迫
  公开内部 API；且 `SwiftEvolution` 与语言的 Swift Evolution 撞名）。

## 3. 最终方案

三阶段（spec 先行，写入 [ABIEvolutionDesign.md](../ABIEvolutionDesign.md)）：

- **Phase 0（持久化地基，顺手清 3 条 TODO(P2)）**：`ABISnapshotDocument`
  （`formatVersion` 版本头，decode 时缺失/不符即典型错误）+ `ABIProvenance`
  （label/路径/工具版本/时间）+ `ABIJSON` 单一编码方言（ISO-8601 + sortedKeys，
  字节稳定可进 git）；`ABIDiff` 增加 old/new provenance。
- **Phase 1（演化核心）**：`ABIEvolution` 模型（`ContainerLineage`/`MemberLineage`：
  presence 位图 + 相邻转换 `LineageEvent`）+ `ABIEvolutionBuilder`（N 路矩阵）+
  `ABIEvolutionReporter`（timeline 报告）+ `transitionCompatibilities` 逐转换判定。
  关键语义：成员事件只在容器于相邻两版本都存在时计算（与双侧 diff 的「added/removed
  容器不枚举成员」一致）；N=2 时与 `ABIDiffer.diff` 逐事件一致（测试锁定）。
- **Phase 2（CLI）**：`swift-section snapshot`（索引一次存 baseline）、
  `swift-section evolution`（≥2 个输入按时间序，二进制/dyld cache/快照 JSON 混用，
  `--labels`/`--summary-only`/`--json`/`--fail-on-breaking`）、`diff` 接受快照输入 +
  `--json`。三命令共享 `ABISnapshotInputLoader`（嗅探：首个非空白字节 `{` → JSON）。

## 4. 实际执行与改动

### 改动清单

- `Sources/SwiftDiffing/`：新增 `ABIProvenance.swift`、`ABISnapshotDocument.swift`
  （含 `ABIJSON`）、`ABIEvolution.swift`、`ABIEvolutionBuilder.swift`、
  `ABIEvolutionReporter.swift`、`Keying.swift`（`keyedFirstWins` 从 `ABIDiffer` 私有
  方法提为模块内共享）；`ABIDiff`/`ABIDiffer`/`Compatibility` 扩展。
- `Sources/swift-section/`：新增 `SnapshotCommand.swift`、`EvolutionCommand.swift`、
  `Utilities/ABISnapshotInputLoader.swift`；`DiffCommand` 支持快照输入 + `--json`。
- `Tests/SwiftDiffingTests/`：新增 `ABISnapshotDocumentTests.swift`、
  `ABIEvolutionTests.swift`（+8 → 61 个测试）。
- 文档：`ABIEvolutionDesign.md`（spec）、`ABIDiffDesignAndLimitations.md` 交叉引用、
  `Documentations/README.md` 索引、README CLI 章节（补 diff/snapshot/evolution 三节）、
  AGENTS.md 补 SwiftDiffing 模块条目（此前完全缺失）。

### 验证

- `swift build 2>&1 | xcsift`；SwiftDiffingTests 53 全过；全量
  `swift test --skip IntegrationTests` 1219 个测试仅 1 失败——
  `SharedCacheTests.differentKeysParallelViaAsyncLet`，为既有负载敏感计时断言
  （单独跑 3/3 过），与本批无关（次日批次加固）。
- 端到端冒烟：scratchpad 编三个演化版本的 `libGeometry{1,2,3}.dylib`，跑通
  snapshot → diff（快照输入、`--json`）→ evolution（混合输入、`--fail-on-breaking`
  退出码 1、陈旧版本号快照拒绝）。报告正确呈现 init 换签名断链、字段 retype、
  enum case tag 重编号、容器缺口语义。

### 与原方案的差异

- `FileHandle.read(upToCount:)` 因部署目标（< macOS 10.15.4）不可用，换用
  `readData(ofLength:)`。
- 其余按方案落地，无偏差。

提交：`76fcfbd`（持久化）、`01c513e`（演化核心）、`9996966`（CLI）、`ee897c5`（文档），
推送 `main`。
