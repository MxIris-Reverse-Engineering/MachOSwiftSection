# SharedNodeStore 迁移：三条小 store 流水线汇入每镜像共享 store

> **状态：Implemented（2026-08-08 批准并同日落地）**——落地记录与「与方案的差异」见文末。

## 一句话

上游 swift-demangling 提案 0010 落地了 `SharedNodeStore`（长生命周期、线程安全、intern 即发放永久有效 `NodeReference`、无 freeze 屏障），本仓库三条「每树 / 每类型 / 每晚到名字铸一个小 `NodeStore`」的流水线因此可以全部汇入每镜像一个共享 store——RuntimeViewer 五镜像实测的 14,451 个 `NodeStore` 实例预期降到个位数。

## 改动位置（先看这里）

| 位置 | 改什么 |
|---|---|
| `Sources/MachOSymbols/InternedNodeReferenceCache.swift` | `Storage` 的结构哈希桶 `[Int: [NodeReference]]` 整层退役，换为持一个 `SharedNodeStore`；`reference(interning:)` 的实现变一句 `store.intern(node)`。**类本身保留**——`SharedNodeStore` 不认识 Mach-O 镜像，per-image / per-process 两个作用域的键控与 `SharedCache` 驱逐接线是它继续存在的理由。31 个调用点（7 个文件）的公开 API 不变，零波及。 |
| `Sources/SwiftDeclaration/Components/Definitions/TypeDefinition.swift:164–195` | `fieldNodeStoreBuilder` + `freeze()` 的每类型批量 store 删除，字段树改走 `InternedNodeReferenceCache.shared.reference(interning:in:)` 汇入镜像 store（顺带获得跨类型的结构去重，今天每类型一个 store 是拿不到的）。 |
| `Sources/MachOSymbols/SymbolIndexStore.swift:256–275` | `lateDemangledNode(forName:)` 的 builder-per-name 删除，`Storage` 自持一个 late-names 专用 `SharedNodeStore`，demangle 改 `lateStore.demangle(name)`。名字 → 裁决字典**保留**（拒绝的 `nil` 裁决与成功 memo 都还需要，`SharedNodeStore` 不按名字缓存拒绝）；insert-if-absent 舞蹈保留但竞态后果变良性——双方 demangle 各自 intern 到同一 store，结构去重保证拿到同一引用，「loser 弃店」一段整个删掉。 |

## 明确不动的部分

- **主 sweep 的 `NodeStoreBuilder` 路径**（`SymbolIndexStore.buildStorageSweep`）：一次性构建 + freeze 是它的正确形态，上游验收明确该路径不受影响。`reserveCapacity(expectedSymbolCount:)` 保持。
- **`Name` 类型的结构语义 `Hashable` 与全部 `StructuralNodeReferenceKey` 键控容器**：跨 store 混用仍是常态（主 symbol store 的引用 vs 共享 store 的引用；驱逐重建后新旧 store 并存）。上游提到「单镜像 scope 内可退回固有实现」是微优化且引入正确性前提，不做；同 store 快路径在 `structurallyEquals` 内部自动生效，收益不需要任何改动就到手。
- **新 store 不做容量预留**：0009 的系数按符号语料标定，上游明确警告名字树负载的文本维度可能低估；这些 store 本性是增量增长，退化上界有界（退休链 ≤1×）。后续如需调优用 `capacityUtilization` 校准。

## 关键设计取舍

- **`lateDemangledNode` 的 store 自持而非共用镜像 cache store**：`InternedNodeReferenceCache` 是 `SharedCache`，会被内存压力驱逐重建；`SymbolIndexStore.Storage` 不随之。若共用，驱逐后 cache 换了新 store 而 `Storage` 还引着旧的，两 store 并存——无正确性问题但混乱。自持让 store 生命周期与 `Storage` 严格一致（`removeSubIndexer` 一起释放），代价是每镜像 2 个 store 而不是 1 个，可忽略。
- **驱逐后的内存回收语义与今天一致**：`SharedNodeStore` 被 scope 释放后，存活的外部引用继续保活底层存储（intern 停止、读取不坏）——mini store 今天就是这个语义，无回归；真正回收仍以「外部引用也放掉」为条件。

## 验收计划

1. 全量 `swift test --skip IntegrationTests` 全绿；fixture interface 快照逐字节一致（输出零变化是硬约束）。
2. `InternedNodeReferenceCache` 相关测试口径更新：驻留计量从「mini store 730 → 471」变为「store 实例数 → 每 scope 1」。
3. `SymbolIndexStoreFixtureTests` 的 late-path 三条性质测试（拒绝缓存、表内名不进 late、并发共店）语义保持，断言从 one-store-per-name 改 one-shared-store。
4. RuntimeViewer 侧复测五镜像 memory graph（swift-demangling 会话约定在本迁移落地后做实景验证：14,451 store 实例的下降只有小 store 真正退役后才可观测）。

## 落地前置条件

- swift-demangling `feature/node-store` 分支的 0010 提交（`9997830`→`bb1f81c`）目前**只在对方本地 worktree，尚未 push**。本机经 `.claude/worktrees/` 兄弟符号链接可解析，但任何无 sibling 的环境会静默回落远端旧版（`SharedNodeStore` 不存在，编译失败还算好的；更险的是快照 A/B 失真——见 AGENTS.md 环境漂移检查第 2 条）。**上游 push（及后续版本发布）先行，本迁移再落。**

## 落地记录（2026-08-08）

三处均按上表实施：`InternedNodeReferenceCache.Storage` 换持一个 `SharedNodeStore`（哈希桶层与 get-or-mint 舞蹈整体删除，类文档注释改写为「作用域键控 + 驱逐」的新分工）；`TypeDefinition.index(in:)` 的字段树两阶段（builder → freeze → map）收敛为单阶段直接经缓存 intern 进镜像 store；`lateDemangledNode` 的 builder-per-name 换 `Storage` 自持的 `lateNameStore.demangle(name)`，「loser 弃店」段删除、名字 → 裁决字典保留。AGENTS.md「Symbol indexing」段的四处措辞同步（late 路径、缓存分工、字段树去重范围、跨 store 常态的论据）。

**验证**：干净重建零 warning；全量 `swift test --skip IntegrationTests` **1337 tests 全绿、0 失败**（与迁移前完全同数，含 interface 快照逐字节断言）；`InternedNodeReferenceCacheTests` 五条行为断言与 `SymbolIndexStoreFixtureTests` 三条 late-path 性质测试**原样通过、未改一行**——同 store、去重、驱逐重铸、并发单赢家这些行为在 `SharedNodeStore` 背书下语义保持。

**实景复测（验收计划第 4 条，2026-08-08 闭环）**：RuntimeViewer 重索引同一批五镜像后的 memory graph——`NodeStore` 实例 **14,451 → 15（−99.9%）**，落在「每镜像一个共享 store + 自持 late side store + per-process 外壳」的意图形状内；存活 `Node` 208,809 → 207,489（预期内小降：该计数的主体不是本迁移的标的）。数字已回填上游 0010 决策日志（swift-demangling `feature/node-store` @ 9464265）。

## 与方案的差异

1. **验收计划第 2 条落空（良性）**：预期要更新口径的驻留计数断言实际不存在——`cachedReferenceCountForTesting` 全库无使用者，已随哈希桶层一并删除；行为断言无需任何改动。
2. **落地前置条件被用户裁决豁免（2026-08-08）**：未等上游 `feature/node-store` 分支 push，本地经 sibling 符号链接先行落地。在上游 push 前，本分支在无 sibling 的环境不可构建（`SharedNodeStore` 解析不到），该风险用户知情接受；上游 push 后自动消除。

## 上游 API 摘要（详见 swift-demangling `Documentations/NodeStoreArena.md` 共享 store 一节）

`SharedNodeStore`: `intern(_ tree: Node) -> NodeReference`（锁内串行、结构去重、引用永久有效）、`demangle(_:isType:symbolicReferenceResolver:) throws -> NodeReference`（解析在锁外）、`reserveCapacity(expectedSymbolCount:)`、观测属性 `capacityUtilization` / `nodeCount` / `storageByteCount`。一个实例只有一个 `NodeStore` 身份——同 scope 引用的固有 `==`/`hash` 即结构相等。上游验收：同形状负载 store 实例 14,000 → 1、冷启动 footprint 8.0 → 2.9 MiB、malloc 减半、耗时 −43%；439,522 符号打印对拍零差异；TSan 全绿。
