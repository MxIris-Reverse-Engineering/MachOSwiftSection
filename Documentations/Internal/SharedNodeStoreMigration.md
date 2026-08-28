# SharedNodeStore 迁移：三条小 store 流水线汇入每镜像共享 store

> **状态：Implemented（2026-08-08 批准并同日落地）**——落地记录与「与方案的差异」见文末。最后更新：2026-08-28（表述层重写，技术内容不变）。

## 导读

这篇文档记录一次「化零为整」的缓存合并。背景问题：本仓库有三条代码路径，各自的习惯都是「要存一棵 demangle 树，就新铸一个小 `NodeStore`（节点存储缓冲）装它」——每棵树一个、每个类型一个、每个晚到的名字一个。RuntimeViewer 索引五个系统镜像后实测攒出了 **14,451 个 `NodeStore` 实例**，而且各个 store 之间没有任何结构去重（重复的子树各存一份）。

转机是上游 swift-demangling 提案 0010 落地了 `SharedNodeStore`：一种长生命周期、线程安全的共享节点存储——往里 intern（结构去重后存入）一棵树立刻拿到永久有效的 `NodeReference`，不再有「必须先 freeze 才能读」的屏障。旧的小 store 形态正是为绕开那道屏障发明的；屏障没了，三条流水线就能全部汇入每镜像一个共享 store。落地后实测：**store 实例 14,451 → 15（−99.9%）**，全部测试原样通过。

该读本文的人：维护 `InternedNodeReferenceCache`、`TypeDefinition` 字段索引或 `SymbolIndexStore` late-name 路径的人，以及想知道「为什么这三处长得如此一致」的人。

## 改动位置（先看这里）

三处改动，一处一行：

| 位置 | 改什么 |
|---|---|
| `Sources/MachOSymbols/InternedNodeReferenceCache.swift` | `Storage` 里的结构哈希桶 `[Int: [NodeReference]]` 整层退役，换成持有一个 `SharedNodeStore`；`reference(interning:)` 的实现缩成一句 `store.intern(node)`。**类本身保留**，因为它做的事 `SharedNodeStore` 不会做：`SharedNodeStore` 不认识 Mach-O 镜像，per-image / per-process 两个作用域的键控、以及和 `SharedCache` 内存压力驱逐的接线，是这个类继续存在的理由。31 个调用点（分布在 7 个文件）的公开 API 不变，零波及。 |
| `Sources/SwiftDeclaration/Components/Definitions/TypeDefinition.swift:164–195` | 删除 `fieldNodeStoreBuilder` + `freeze()` 的「每类型一个批量 store」两阶段流程。字段类型树改走 `InternedNodeReferenceCache.shared.reference(interning:in:)`，直接汇入镜像 store。顺带拿到一项旧形态给不了的收益：跨类型的结构去重——每类型各一个 store 时，两个类型共用的子树只能各存一份。 |
| `Sources/MachOSymbols/SymbolIndexStore.swift:256–275` | 删除 `lateDemangledNode(forName:)` 的「每个名字铸一个 builder」形态。`Storage` 自持一个 late-names 专用的 `SharedNodeStore`，demangle 改为 `lateStore.demangle(name)`。名字 → 裁决字典**保留**——拒绝名的 `nil` 裁决和成功结果的 memo 都还需要，`SharedNodeStore` 不按名字缓存拒绝。insert-if-absent 的写入流程保留，但竞态的后果从「有害」变「良性」：两个线程同时 miss 时，双方各自 demangle、各自 intern 进同一个 store，结构去重保证它们拿到同一个引用，于是原来处理「输家丢弃自己那个 store」的一整段代码直接删除。 |

## 明确不动的部分

- **主 sweep 的 `NodeStoreBuilder` 路径**（`SymbolIndexStore.buildStorageSweep`）。一次性构建 + freeze 就是它的正确形态：sweep 的全部写入发生在一个批次里，freeze 屏障对它不是负担。上游验收明确该路径不受影响。`reserveCapacity(expectedSymbolCount:)` 的容量预留保持。
- **`Name` 类型的结构语义 `Hashable`，以及所有用 `StructuralNodeReferenceKey` 键控的容器**。跨 store 混用引用仍然是常态——主 symbol store 的引用和共享 store 的引用会同处一个字典；驱逐重建之后新旧 store 也会并存。上游提过「单镜像 scope 内可以退回固有实现」，但那是个微优化，还引入了一个正确性前提，不做。同 store 的快路径在 `structurallyEquals` 内部自动生效，这份收益不需要任何改动就到手。
- **新 store 不做容量预留**。上游提案 0009 的预留系数是按符号语料标定的，上游明确警告：名字树负载的文本维度可能被低估。这些 store 本性是增量增长，退化上界有界（退休链 ≤1×）。后续若需调优，用观测属性 `capacityUtilization` 校准。

## 关键设计取舍

- **late 路径的 store 为什么自持、不共用镜像 cache 的 store**。`InternedNodeReferenceCache` 是 `SharedCache`，会被内存压力驱逐再重建；`SymbolIndexStore.Storage` 不随之重建。如果共用，驱逐一发生，cache 换上了新 store，而 `Storage` 还引着旧的——两个 store 并存。这没有正确性问题（旧引用照常可读），但状态混乱。自持让 store 的生命周期与 `Storage` 严格一致，`removeSubIndexer` 时一起释放。代价是每镜像 2 个 store 而不是 1 个，可忽略。
- **驱逐后的内存回收语义与今天一致**。`SharedNodeStore` 被作用域释放后，存活的外部引用会继续保活底层存储——intern 停止、读取不坏。mini store 今天就是这个语义，所以无回归；真正的内存回收仍以「外部引用也全部放掉」为条件。

## 验收计划

1. 全量 `swift test --skip IntegrationTests` 全绿；fixture interface 快照逐字节一致——输出零变化是硬约束。
2. `InternedNodeReferenceCache` 相关测试的计量口径更新：从「mini store 730 → 471」的驻留计数，改为「store 实例数 → 每 scope 1」。
3. `SymbolIndexStoreFixtureTests` 的三条 late-path 性质测试（拒绝结果被缓存、表内名字不进 late 路径、并发查询共享一个 store）语义保持，断言从 one-store-per-name 改成 one-shared-store。
4. RuntimeViewer 侧复测五镜像 memory graph。这一条只能在落地后做（swift-demangling 会话约定的实景验证）：14,451 个 store 实例的下降，只有小 store 真正退役之后才观测得到。

## 落地前置条件

swift-demangling `feature/node-store` 分支上的 0010 提交（`9997830`→`bb1f81c`）当时**只在对方本地 worktree，尚未 push**。本机经 `.claude/worktrees/` 的兄弟符号链接可以解析到它；但任何没有 sibling 目录的环境会静默回落到远端旧版——`SharedNodeStore` 不存在，编译失败还算好的结局，更危险的是快照 A/B 对比悄悄失真（见 AGENTS.md 环境漂移检查第 2 条）。所以计划是：**上游先 push（及后续版本发布），本迁移再落。**（这一条后来被豁免，见「与方案的差异」。）

## 落地记录（2026-08-08）

三处均按改动位置表实施：

- `InternedNodeReferenceCache.Storage` 换持一个 `SharedNodeStore`——哈希桶层与 get-or-mint 流程整体删除，类的文档注释改写为「作用域键控 + 驱逐」的新分工。
- `TypeDefinition.index(in:)` 的字段树处理从两阶段（builder → freeze → map）收敛为单阶段，直接经缓存 intern 进镜像 store。
- `lateDemangledNode` 的 builder-per-name 换成 `Storage` 自持的 `lateNameStore.demangle(name)`；「输家弃店」一段删除；名字 → 裁决字典保留。
- AGENTS.md「Symbol indexing」段同步了四处措辞：late 路径、缓存分工、字段树去重范围、「跨 store 是常态」的论据。

**验证**：干净重建零 warning；全量 `swift test --skip IntegrationTests` **1337 tests 全绿、0 失败**——与迁移前完全同数，含 interface 快照的逐字节断言。`InternedNodeReferenceCacheTests` 的五条行为断言与 `SymbolIndexStoreFixtureTests` 的三条 late-path 性质测试**原样通过、未改一行**：同 store、去重、驱逐重铸、并发单赢家，这些行为在 `SharedNodeStore` 背书下语义完整保持。

**实景复测（验收计划第 4 条，2026-08-08 闭环）**：RuntimeViewer 重索引同一批五镜像后的 memory graph——`NodeStore` 实例 **14,451 → 15（−99.9%）**，正落在「每镜像一个共享 store + 一个自持的 late side store + per-process 外壳」的意图形状内。存活 `Node` 208,809 → 207,489，预期内的小降：这个计数的主体不是本迁移的标的（它属于下一篇 [MetadataReaderCacheRetirement.md](MetadataReaderCacheRetirement.md) 处理的缓存）。数字已回填上游 0010 决策日志（swift-demangling `feature/node-store` @ `9464265`）。

## 与方案的差异

1. **验收计划第 2 条落空（良性）**：预期要更新口径的驻留计数断言实际并不存在——`cachedReferenceCountForTesting` 全库没有使用者，已随哈希桶层一并删除。行为断言无需任何改动。
2. **落地前置条件被用户裁决豁免（2026-08-08）**：没有等上游 `feature/node-store` 分支 push，本地经 sibling 符号链接先行落地。在上游 push 之前，本分支在无 sibling 的环境不可构建（`SharedNodeStore` 解析不到）；该风险用户知情接受，上游 push 后自动消除。

## 上游 API 摘要

详见 swift-demangling `Documentations/NodeStoreArena.md` 的共享 store 一节。要点：

- `SharedNodeStore` 的接口：`intern(_ tree: Node) -> NodeReference`（锁内串行、结构去重、返回的引用永久有效）；`demangle(_:isType:symbolicReferenceResolver:) throws -> NodeReference`（demangle 解析在锁外执行）；`reserveCapacity(expectedSymbolCount:)`；观测属性 `capacityUtilization` / `nodeCount` / `storageByteCount`。
- 一个实例自始至终只有一个 `NodeStore` 身份——所以同 scope 引用的固有 `==`/`hash` 就是结构相等。
- 上游验收数字：同形状负载下 store 实例 14,000 → 1；冷启动 footprint 8.0 → 2.9 MiB；malloc 次数减半；耗时 −43%；439,522 个符号的打印对拍零差异；TSan 全绿。
