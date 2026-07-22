# 2026-07-22 - keyed 碰撞诊断通道 + enum case indirect 折入 + 计时测试加固

## 1. 问题 / 任务

evolution 首批落地后继续清 `SwiftDiffing` 挂账，按价值排序取三件：

1. **`keyed` 碰撞静默丢弃**（最实质的正确性缺口）：first-wins 索引在键碰撞时丢弃后续
   记录且不比较，可能把一次 removal（breaking）误判为 compatible。现实来源：合并后的
   extension bucket 里两个条件 extension（`where T: P` vs `where T: Q`）的同名成员
   （mangling 不编码 where 子句）。
2. **enum case `indirect` 切换不可见**：`makeCase` 按 `tag` + payload 类型建键，同名
   同 tag 同类型下 `indirect` 切换（inline 存储 ↔ 堆上 box，真实 ABI 变化）漏报。
3. **`differentKeysParallelViaAsyncLet` 计时测试 flaky**：全量并行跑套件时必挂。

## 2. 探索与调研

### 关键发现

- **碰撞是快照的性质，不是 diff 的性质**：两个条件 extension 撞键在单个
  `ABISnapshot` 内即可检测（扫描每个 keying 作用域的重复 identity），不必在
  `threeWayMatch` 里穿针引线传诊断——`ABISnapshot.keyCollisions()` 独立扫描 +
  结果挂到 `ABIDiff`/`ABIEvolution` 上，管线零侵入。
- **indirect 折入是 key scheme 变更**：payload key 格式变化会让 version-1 baseline
  被静默误读——这正是上一批版本头设计要防的场景，`currentFormatVersion` bump 到 2
  即可让旧 baseline 显式失效（版本头首次实战）。
- **计时测试 flaky 的根因是绝对预算太小**：0.10s×4 并行、固定 0.30s 预算，满负载
  并行跑套件时调度噪声 0.22–0.38s 直接吃穿预算（实测 0.32/0.48s 两次失败），单独跑
  3/3 通过（~0.11s）。兄弟测试 `differentKeysParallelViaTaskGroup` 用
  「serial ceiling × 0.5」惯用法（8×0.2s → 预算 0.8s）从未 flake——绝对余量足够大。

## 3. 最终方案

1. 诊断通道：`ABIKeyCollision`（key + 容器名 + 被丢弃记录的签名）+
   `ABIDiffDiagnostics`（逐侧）；`ABISnapshot.keyCollisions()` 按 first-wins 同规则
   扫描容器轴 / 容器成员 / globals；`ABIDiffer.diff` 计算并挂到
   `ABIDiff.diagnostics`（空则 nil）；`ABIEvolutionBuilder` 逐版本挂到
   `ABIEvolution.keyCollisionsByVersion`；两个 reporter 各渲染 Warnings 段
   （空 diff 也照常告警）。first-wins 比较行为不变；`keyedFirstWins` 的 TODO(P2)
   注释改写为「上浮，不再静默」。
2. `makeCase` 折入 `indirect`：payload key `tag:N|indirect|…`、签名
   `indirect case x`；`currentFormatVersion` 1 → 2，history 注释记录原因。
3. 计时测试对齐兄弟测试惯用法：0.40s×4，预算 = serial ceiling(1.6s) × 0.5 = 0.8s。

## 4. 实际执行与改动

### 改动清单

- 新增 `Sources/SwiftDiffing/ABIDiagnostics.swift`；`ABIDiff`/`ABIDiffer`/
  `ABIEvolution`/`ABIEvolutionBuilder`/两个 Reporter/`Keying.swift` 接线；
  `MemberRecord.makeCase` + `ABISnapshotDocument.currentFormatVersion`；
  `Tests/MachOCachesTests/SharedCacheTests.swift` 预算改写。
- 测试：新增 `ABIDiagnosticsTests.swift`（扫描/挂载/渲染 7 用例）、
  `ABIDifferTests` 补 indirect 切换用例（61 个测试全过）。
- 文档：`ABIDiffDesignAndLimitations.md`（局限 3 降级为「已上浮」、局限 4 的
  indirect 残留标记已修、对照表更新）、`ABIEvolutionDesign.md` 第二批增量节、
  AGENTS.md 模块条目同步。

### 验证

- 全量 `swift test --skip IntegrationTests`：**1227 个测试全绿**——包括此前满负载
  必挂的计时测试在同等负载下通过。注意 xcsift 曾把带失败的 swift-testing 输出
  误报为 success，验证以原始输出的 `Test run with …` 行为准。
- 端到端：version-1 的 Geometry baseline 被新工具显式拒绝
  （`Unsupported ABI snapshot format version 1 (this tool supports 2)`），重新生成后
  evolution 输出与首批一致。

### 与原方案的差异

无。提交：`e7e8aee`（诊断通道）、`b98c56f`（indirect）、`cfaa2a8`（计时测试）、
`b679a74`（文档），推送 `main`。

## 5. 修复细节：为什么这样改

- **为什么保留 first-wins 而不是分开比较碰撞成员**：分开比较需要知道每条成员属于哪个
  conformance / 条件块（per-conformance 归属，局限 5），那是跨 `SwiftIndexing`/
  `SwiftDeclaration` 的模型层工程。诊断通道先保证「结论不会悄悄弱于表面」，归属落地后
  碰撞源将结构性消失。
- **为什么 `indirect` 进 payload 而不是 identity**：case 的身份是源码名（重命名 =
  add+remove）；`indirect` 是同一 case 的表示变化，语义上是 `.modified`。
