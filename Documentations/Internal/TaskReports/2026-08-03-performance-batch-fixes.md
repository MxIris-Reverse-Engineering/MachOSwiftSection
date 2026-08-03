# 2026-08-03 性能批次：失败名裁决、名字去重缓存、dump 路径引用化

## 问题

[2026-08-02 审查记录](../Reviews/2026-08-02-node-store-migration-pr97-review.md)与既有台账合并后，`feature/node-store-migration` 剩 19 条待处理。维护者批准「立即可修」与「中等重构」两组同批执行：

1. 失败名重试 + 锁内 demangle（`SymbolIndexStore`，上一轮实测失败名路径 6.3 倍慢、8 线程争用 1.97 倍）；
2. 25 处 `NodeReference(interning:)` 逐名开 arena；
3. 打印器每成员 materialize（7 处）；
4. dump 路径 `demangledNode` 调用点（5 处，每次 `materialize()`）。

## 调研

- **失败名**：`demangledNodeReference` 的快路径条件是「表内有行**且** root 非 nil」，于是 sweep 期间 demangle 失败的名字每次查询都穿透到 `lateDemangledNode`，在锁内重付一次失败的 demangle。核对上游源码：`NodeStoreBuilder.demangle` 就是 `demangleAsNodeTransient` + intern——与 sweep 同一个 demangler、同一拒绝集，所以「表内失败 = 永远失败」，表裁决可以直接回答。
- **interning 批量化**：原修法「每镜像共用一个 builder」不可行——`NodeReference` 必须在 `freeze()` 之后才能发出，而名字在调用流深处即用即取（字典键、定义构造），两阶段重排等于重写索引器。一次性测量（临时测试，已删）证明真正的浪费是**重复**：fixture 上 745 个驻留名字引用、730 个 mini store、只有 472 个结构唯一树（重复率 1.55×；`conformingProtocolName` 180 处全是重复重灾区）。因此正确形态是**结构去重缓存**，不是共享 builder。
- **打印器 materialize**：临时计量（7 处包 `TemporaryMaterializeProfiling`，已删）——fixture 全量导出打印墙钟 2768.8 ms，materialize 合计 32.6 ms / 1313 次，占 **1.18%**。而根治需把 `NodePrintable` 五协议栈（约 1700 行）泛型化到 `DemanglingNode`，且栈内有 3 处**构造** Node 的地方（`.static` 包装 ×3、labelList 合成 ×2）纯引用无法表达，需局部重设计。
- **dump 路径**：五个调用点拿到 `Node` 后只做 `first(of:)` / `print` / `resolve(for:)` / visited 去重——全部有引用等价物；`DemangleResolver.resolve(for:)` 已有 `some DemanglingNode` 重载；`ProtocolConformanceDumper:184` 已示范引用化写法。
- **意外发现**：`indexExtensions` 丢 `await` 那条早间刚裁决「不修」（前提「`NodeReference` 无 async print」对 0.5.0 属实），上游当日就把 print 便利方法整体迁到 `DemanglingNode` 协议扩展并补 async 变体（`f913742`，发布为 **0.5.1**；同时删除 `Node`/`NodeReference` 的具体同步 `print`）——前提失效，改裁决为已修，依赖随之升 `from: "0.5.1"`。本地兄弟检出先于发布就到了该内容，这也是构建中 async 上下文突然强制 `await` 的真实原因（当时误归因于 scratch 污染的部分已在下文更正）。

## 方案

1. `demangledNodeReference`：表内名字以表裁决为准（root 为 nil → 返回 nil）；`lateDemangledNode`：锁外 demangle + 锁内 insert-if-absent（输者弃 store 返回胜者），字典改 `[String: NodeReference?]` 缓存拒绝裁决（用 `updateValue` 规避 optional-值字典下标赋 nil 即删键的坑）。
2. 新增 `InternedNodeReferenceCache`（`Sources/MachOSymbols/`）：`SharedCache` 派生，镜像键（`storage(in:)`）+ 进程键（type-keyed `storage()`，服务无 `machO` 的 in-process 助手）双入口；桶按 `Node` 结构哈希、命中经 `structurallyEquals` 校验；minting 与 late 缓存同款锁外构造 + 锁内仲裁。25 处调用点全部改走缓存（`Extensions.swift` 14、`SwiftDeclarationIndexer` 6、`SwiftSpecialization` 4、`ProtocolDefinition` 1）；`SwiftSpecialization` 补 `.target(.MachOSymbols)` 依赖；`SwiftDeclarationIndexer.deinit` 的 per-image 清理加一行。
3. 打印器 materialize：**裁决为暂不修**（1.18%，重开条件：大镜像剖析出显著占比）。
4. dump 路径：五处迁 `demangleSymbolReference`；`validNode` ×2 返回 `NodeReference?`；visited 集合 ×4 与 `distributedFunctionNodes` 换 `StructuralNodeReferenceKey`；`_requirementName` 直接引用打印；`indexExtensions` 恢复 `await`。

## 实际执行

按方案落地，代码改动集中在 `SymbolIndexStore.swift`、新文件 `InternedNodeReferenceCache.swift`、`Extensions.swift`、`SwiftDeclarationIndexer.swift`、三个 Dumper、`Package.swift`（一行依赖）。新增测试：

- `SymbolIndexStoreFixtureTests`：`rejectedLateNameCachesItsFailure`（**修复前红**——临时还原旧行为验证，断在裁决未被缓存）、`tableCoveredNameNeverEntersLateCache`、`concurrentLateQueriesShareOneStore`（16 任务并发同名，胜者唯一）。
- 新套件 `InternedNodeReferenceCacheTests`（5 项）：重复共享 store（`store ===`）、不同树不混淆、并发单胜者、`remove(for:)` 驱逐后重铸、进程作用域去重。
- 为可测性在 `Storage` 加了内部钩子 `lateDemangleVerdictForTesting(forName:)`、`InternedNodeReferenceCache.Storage.cachedReferenceCountForTesting`。

## 验证

- fixture 复测：驻留名字 mini store 730 → **471**（= 472 结构唯一，去重完全），mini store 字节 84,795 → 57,752（−32%）。
- 快照套件全绿：SwiftInterfaceTests 53 项（含逐字节 interface 快照）、SwiftIndexingTests / SwiftSpecializationTests / MachOSymbols 各套件 146 项、SwiftDumpTests（随全量套件）。输出零变化。
- 全量 `swift test --skip IntegrationTests`（独立 scratch 干净构建）：见任务末尾结果。

## 偏离与教训

- **两次环境事故，一次误归因**：(a) 本机 fixture 二进制（7/31）旧于 fixture 源码（8/2 加的 `AccessorFunctionReferences`），interface 快照丢整块尾部类型——AGENTS.md 环境漂移检查第 1 条的教科书案例，按处方重建后消除；(b) 会话中 shell 工作目录被重置回主仓库（main 分支），若干构建/测试跑错了检出，且主仓库与 worktree **共用了同一个 SwiftPM scratch 目录**，混入 main 分支（0.4.x 符号时代）的陈旧目标文件，制造出「测试匹配 0 项」和链接期 undefined symbol——worktree 换独立 scratch（`/tmp/claude/SwiftPM/MachOSwiftSection-worktree-node-store`）干净重建后消失。**教训：不同检出绝不共用 scratch。** 更正：当时一并归因于 scratch 污染的「async 上下文强制 `await`」**不是**污染假象——那是兄弟检出已含 0.5.1 内容（具体同步 `print` 被删）的真实编译语义，`await` 修复因此是必要且正确的。
- 打印器 materialize 从「修」改为「数据裁决不修」——先测后改的纪律恰好挡下了一次高风险低收益重构。
- `indexExtensions` 的 await 裁决当日两翻：不修 →（新事实）→ 已修。错误前提（漏查 `DemanglingNode` 协议扩展）已在审查记录第三节原文处标注。
