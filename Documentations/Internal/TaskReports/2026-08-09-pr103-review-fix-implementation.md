# 2026-08-09 — PR #103 review 发现的修复实施

## 问题

PR #103（`feature/node-store-migration` → `main`，103 文件，+6880/−874）的 max 级 code review 产出 15 条经四问验证的发现（1 Blocker / 4 High / 6 Medium / 4 Low），由 review 会话移交本会话实施。用户批准：**B1（swift-demangling 远端 pin 指向不含所需 API 的版本区间）跳过、由用户自行处理上游发版**，其余 14 条全部修复。

## 调研

- 逐条走读清单指向的代码，其中三条的关键前提在动手前被推翻或修正（全部与 review 会话往返确认、留痕于清单文档的 revision 注记）：
  - **M1**：建议修法（`try?` 改路由到 thrown-resolution 分支）与现状行为完全重合，写不出失败先行的测试；review 会话复核后进一步发现该 `try?` 在库内不可达（唯一调用点之前必然先走传播式 `index(in:)`），发现降级为 Low，修法改定为「公开入口裸 `try` 传播 + 直调公开 API 的契约测试」。
  - **H3**：`Int(segment)` trap 一半被推翻——MachOKit 从 opcode 的 4-bit immediate 解码 segment index（≤15），uleb 只用于 offset；真实威胁面是原始 uleb 的 repeat count（2^40 自旋挂死）与 wrap 后错归因。
  - **L3**：建议的 achievable-rank 早退不可靠（持有 dylib 命中时未扫描的 subcache 仍可能藏着 framework 本体，提前停复发当年 SwiftUI→axbundle 误解析）；实测全扫描仅 43 ms，推翻「数千次构造」的代价估计。
- **M2 的开放半问（有没有消费者真的卸载被索引的镜像）用实验闭合**：macOS 26 上 dlopen/dlclose 探针证明含 Swift 内容的镜像（连无类的都算）被 dyld pin 死永不 unmap；唯一能卸载的纯 C dylib 不含 Swift 前缀符号名、不产生 mapped 行。
- **M5 的建议修法（detach 时拷出 node store）读码推翻**：存储该 symbol 的定义自身 `node` 字段就是同店 `NodeReference`（记录在案的 per-image recycling model），拷贝零回收。

## 最终方案

- **代码修复 11 条**：H1（统计快照 `PreparationStatistics` 清退前冻结）、H2（扩展索引早退补 `isIndexed`）、H3（bind 解码器段界 bound）、H4（A/B 脚本零对比即失败 + 硬失败传播）、M1（`printExtensionHeader` 物化失败传播）、M3（`PackedNameReference` failable 化，sweep 跳过 / standalone clamp）、M4（`isBind` 补 LC_DYLD_INFO 回退）、M6（per-image 缓存驱逐移交最后存活 indexer 的进程级登记表）、L1（嵌套子定义 per-child catch）、L2（fixture 编译管道先排空 + 目录清理）、L4（测试去采样上限、排序全量）。
- **裁决 3 条**（[ReviewAdjudications.md](../ReviewAdjudications.md) A4–A6）：M2 不修（触发面结构性不可达，两个建议缓解均拒绝）；M5 按建议不修（改为文档写准 + `storedDeclarationSymbolsShareTheDefinitionsNodeStore` 钉住共享契约）；L3 优化不做（机制不可靠 + 代价噪声级，强制配套测试落地）。
- 每条修复先写修复前失败的回归测试，与代码同 commit 落盘、永久保留。

## 实际执行

按清单建议的批次顺序推进（B1 跳过后共 6 批、12 个 commit）：

1. 清单文档入库（`0f0f45f8`，Roadmaps/ 既有惯例）→ H2（`dcf8b0e4`）→ H1（`d07257fc`，同批补 evolution 0002 源码兼容性补记 + 决策日志行）→ M4（`b3bffa0d`）。
2. H3（`c36a3a2e`，segment-imm 推翻记入清单；恶意流回归测试按用户指示跳过，合法路径由 4 个 `LegacyDyldInfoBindTests` 钉住）→ M3（`711304f3`，修复前 precondition trap 实录：`symbol name byte length exceeds the 22-bit budget` 杀掉 runner）。
3. H4（`c07b7189`，修复前空输出根实测返回 0 → 假绿）→ L2（`d738ed41`）→ L4（`9036c72b`）。
4. M6（`b7308b21`，修复前实录：先亡 indexer 抽走存活 indexer 的全部三缓存；新增 `SymbolTestsHelper` fixture case 隔离并行套件）→ M5/M2 裁决（`83fca3eb`）。
5. M1（`a6dbf980`，修复前实录：期望抛错但没抛）→ L1（`351b5ee9`，修复前实录：子类型 `.offsetOutOfBounds` 逃逸丢弃整个父类型；测试第一版误用进程内 `Struct(descriptor:)` 重载把 offset 当指针解引用 SIGSEGV，改用 raw-descriptor 注入后干净抛错）→ L3（`3a9a373f`）。
6. 文档收尾（本报告所在 commit）：ProjectEvolutionLog 补 0002/0003/本批次三节 + 修 TaskReports 坏链接；AGENTS.md 同步。

## 验证

- 每条修复：失败先行 → 修复 → 转绿（各 commit message 记录失败形态）。
- 快照 / 打印面：175 tests / 21 suites 全绿（L1 的 builder 重构健康路径逐字节不变）。
- 收尾全量 `swift test --skip IntegrationTests`（本地兄弟依赖 + worktree 专属 scratch）全绿——B1 未决期间 CI 不可用，全量结果见收尾 commit。

## 偏差

- **H3 的恶意流回归测试按用户指示跳过**（「继续，跳过这个测试」）——加固逻辑无新增测试直接落地，合法解码路径由既有 4 测试钉住；留痕于清单 H3 revision 注记与 commit message。
- **三条按裁决而非按建议修**（M2/M5/L3，见上）；裁决与复审条件全部留档 A4–A6。
- **一次误用探针**：L1 测试第一版用错 `Struct(descriptor:)` 无上下文重载（进程内语义）导致测试自身 SIGSEGV，与被测路径无关；改用 `TypeDefinition` 的 raw-descriptor package init 后按预期抛错。
- 全程在 `feature/node-store-migration` worktree 实施；`--filter "DyldCache"` 曾一度误匹配进 IntegrationTests 的维护者套件（其自身崩溃与本批次无关），随即改用精确过滤复验。
