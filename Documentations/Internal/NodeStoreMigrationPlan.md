# NodeStore 迁移计划（SymbolIndexStore → arena 存储）

- **状态**: Stage 0–4 Completed（见「实施记录」）；Stage 5 已落地；Stage 5 回归修复见文末「Stage 5a 回归修复」
- **日期**: 2026-07-24
- **最后更新**: 2026-08-28（本次为表述层重写：拆长句、展开行话、每节先结论，技术内容与所有数据不变。正文实施记录止于 2026-08-08 节；2026-07-26 批次第 6 条带有替换后记）
- **分支**: `feature/node-store-migration`。worktree 位于 `.claude/worktrees/node-store-migration`。依赖的 Demangling 包通过主检出 `.claude/worktrees/swift-demangling` 处的**真实 git worktree**（swift-demangling 的 `feature/node-store` 分支）以路径依赖解析。原先用符号链接指向那个 worktree，但目标被外部清理后，SwiftPM 的 manifest 缓存把解析钉回了 remote 版本，所以改成了本仓库领地内的 worktree。
- **前置**: swift-demangling 的 `feature/node-store` 分支合入其 `main`（本包以路径依赖解析 `../swift-demangling` 的 main）；开发期先经上述方式直连该分支
- **上游依据**: swift-demangling 的提案 `evolution/0001-node-store-arena.md`（NodeStore arena 存储；其 Phase 1–3 已落地并验收）

## 导读

这份文档是一次大型内存重构的计划书加实施日志。要解决的问题是：符号索引（`SymbolIndexStore`）把每个符号的 demangle 结果驻留为一棵棵 class 对象树，又让全局缓存随浏览无限增长，RuntimeViewer 打开几个系统框架就吃掉数百 MB 且永不归还。解决办法是把树搬进 arena——一整块连续缓冲，节点平铺存放、按下标互相引用——并让每个镜像的全部数据能随镜像一起整体释放。

最终结果（全部已落地）：常驻的 `Node` class 实例约 4 倍压缩、全局 `NodeCache` 增长归零、构建期内存增量从约 270 MB 降到 68 MB、构建反而快了 14%，且输出与旧管线逐字节一致。

文档结构是「计划在前、按时间序的实施记录在后」。靠后的批次会修正靠前批次的做法；已知被替换的方案在原处保留了后记标注。适合两类读者：想了解 `MachOSymbols` 现今存储模型由来的维护者，以及要在类似仓库做同类迁移、想借鉴踩坑记录的人。术语（sweep、物化、腿等）首次出现会展开一句，详细定义见[术语表](../Glossary.md)。

## 背景与动机

先解释两个贯穿全文的词。**demangle** 是把编译器编码过的符号名（如 `$s7SwiftUI4TextV`）还原成结构化类型信息的过程，结果是一棵语法树；传统表示是 **`Node` class 树**——每个语法成分一个独立的堆对象。**interning**（也叫 hash-consing）指相同内容只存一份、后来者复用引用的去重手段。

RuntimeViewer 与 MachOSwiftSection 的内存大头在 `MachOSymbols/SymbolIndexStore.swift`。对其 `Storage`（每个镜像一份的索引数据）解剖后，占用分两类：

1. **Node 树驻留（主项之一）**。`demangledNodeBySymbol: [Symbol: Node]` 字典持有每个符号的完整 class 树；各索引字典里 `DemangledSymbol.demangledNode` 存的是同一批树的根引用。按 interning 后的 class 形态计，体积约为唯一子树数 × 每节点 48 B（上游在一个 4.9 万符号的样本上实测 12.9 MB）。比体积更严重的是**生命周期**：demangle 的默认入口 `demangleAsNode` 会把整棵树 intern 进全局缓存 `NodeCache.shared`，这些「规范节点」进程级永驻——`SharedCache` 淘汰某个镜像的 `Storage` 后，这部分内存并不归还，除非调全局 `clear()`。而 `clear()` 是粗粒度操作，会把所有镜像的缓存一起清掉。
2. **Symbol / 字符串 / 索引结构（另一主项，本计划的 Stage 3 处理）**。包括：每符号一个 mangled name `String`；`nlist` 的 existential 容器（existential 即 `any` 协议类型的装箱形态，每份约 40 B）；`symbolsByOffset` 给每个符号存两个条目；`DemangledSymbol` 值在多个索引里各存一份复本。

上游 swift-demangling 已经交付了替代表示（其提案 0001）：

- `NodeStore` / `NodeStoreBuilder`：每节点 12 B 的 arena、hash-consing 去重、open-addressing 的 intern 查找表，以及 **cache-free** 的批量 `demangle(_:)`——完全不碰全局 `NodeCache`，不再向它泄漏任何东西；
- `NodeReference`：16 B 的值类型句柄（store 引用 + 下标），`==` 和 `hash` 都是 O(1)；`kind`/`text`/`index`/`children`/`Sequence`(preorder)/`first(of:)`/`identifier`/`textUTF8` 等成员全部镜像 `Node` 的接口；
- 零物化消费：`reference.print(using:)` 直接从 arena 打印（与 Node 路径逐字节一致）、`TypeDecoder.decodeMangledType(node: NodeReference)`。「物化」（materialize）指把 arena 里的节点重新展开成传统 class `Node` 树——零物化就是不做这一步；
- 桥接消费：`mangleAsString(some DemanglingNode)`、`materialize()`（按下标记忆化，保留树内共享子树的 DAG 结构）；
- `builder.intern(kind:children:)` 等直接构造 API，让包装节点不再绕道 `Node`；
- `@_spi(Internals)` 出口：`DemanglingPrinter`（自定义富文本 target 直接打印 store）与 `StackSafeExecutor`。

上游 Phase 3 的验收数据（本机 dyld cache 的 SwiftUI 语料 234,232 个符号，debug 构建）：619,688 个唯一节点存成 8.75 MB 平铺缓冲（合每节点 14.1 B）；store 构建 25.3 秒，**快于** interning Node 路径的 28.5 秒；构建期 footprint（进程物理内存占用）增量约等于最终留存量加 ~1 MB 瞬态。

**目标**：Node 树驻留项约 4 倍压缩，且能按镜像整体回收；全局 `NodeCache` 增长归零；`Storage` 构建的内存高水位消除；Stage 3 完成后 Symbol 侧的复本收敛。

## 分期

以下是迁移动工前的分期计划。实际落地与计划的偏差记录在后文「实施记录」。

### Stage 0 — 基线量化（半天）

先测后改。在 `SymbolIndexStore.buildStorage` 前后埋点，逐镜像采集并留档四组指标：`phys_footprint` 增量、`NodeCache.shared.count/subtreeCount` 增量、构建耗时、各索引条目数。这份基线既是 Stage 1/3 的对照，也决定 Stage 3 的优先级。

### Stage 1 — `SymbolIndexStore.Storage` 核心迁移（主体工作）

1. `Storage` 为每个 MachO 持有一个冻结（freeze，即构建完成后转为只读）的 `nodeStore: NodeStore`。
2. `DemangledSymbol.demangledNode: Node` 改为 `NodeReference`。这是包内 API，但经 `@_spi(ForSymbolViewer)` 消费它的 RuntimeViewer 需要同步适配，见「影响面」。
3. `demangledNodeBySymbol: [Symbol: Node]` 改为 `[Symbol: NodeReference]`。
4. `MemberSymbols` 内层的 `OrderedDictionary<Node, [IndexedSymbol]>` 与 `opaqueTypeDescriptorSymbolByNode` 的键改为 `NodeReference`。收益是键哈希从 O(树大小) 变 O(1)——同一个 store 内下标相等就等价于结构相等——构建和查询两头都受益。
5. typeNode 的构造从「`Node.create(kind: .type, child: node)` 再 `print`」改为「`builder.intern(kind: .type, children: [contextIndex])` 再 `reference.print(using: .interfaceTypeBuilderOnly)`」。零物化，输出逐字节一致已由上游验证。
6. **构建管线换形**。现状是 `concurrentMap { demangleAsNode }` 全量并发——代价是所有 class 树同时驻留、并且全部进全局 NodeCache。改为逐符号 `builder.demangle(symbol.name)`（cache-free）后立刻索引。上游实测单线程 store 构建已快于并发旧管线的单路径基线。builder 是单写者的 `~Copyable` 类型，若实测吞吐不足，再评估分块并行加合并——上游目前没有跨 store 合并 API，此点列为 open question，不阻塞本期。
7. 索引期的只读分类逻辑（`processMemberSymbol`/`processThunkAttributeSymbol`/`isGlobal`/`identifier`）直接在 `NodeReference` 上运行——所需成员它都镜像了。`MachOSymbols` 里给 `Node` 写的扩展（`isGlobal`/`isAccessor`/`hasAccessor`）改写为 `DemanglingNode` 泛型扩展。
8. `demangledNode(for:)` 的迟到符号回退路径：store 冻结后不能再插入，所以 build 扫描没覆盖到的符号保留一个小型 side cache `[Symbol: Node]`。这是罕见路径，用 `internsSubtrees: false` 且量小。

**验收**：现有 `SymbolIndexStoreTests` 加快照测试全绿；对照 Stage 0 基线，Node 树项达到约 4 倍压缩、NodeCache 零增长。

### Stage 2 — 消费端（先用默认策略，按需再深化）

- **默认策略是按需物化**。UI 的使用模式是「点开一个符号渲染一个」：用 `reference.materialize()`（保留共享子树）喂给现有的 `NodePrintable` 打印栈和 `printSemantic`，SemanticString 的 context、type-reference scope、delegate 全部保真。瞬态成本毫秒级以下，不影响驻留收益。**Stage 2 因此只需要改取数处的一行调用。**
- 列表行、搜索预览这类纯文本场景：`reference.print(using:)` 零物化直接输出。
- `TypeDecoder` 的消费者（SwiftSpecialization、StaticTypeLayoutResolver）：换用 `decodeMangledType(node: NodeReference)` 即可。ABIKey / ABIDiffing 的 remangle 用 `mangleAsString(reference)`——经过物化桥，但是瞬态的。
- **可选的 Stage 2b**（只在全库批量渲染 interface 成为瓶颈时做，比如 swift-section 的 `InterfaceCommand`）：把 `NodePrintable` 协议栈泛型化到 `DemanglingNode`。做法是机械替换 `Node` → `SomeNode`；`printCache` 的键换成 `PrintCacheIdentity`；`pushTypeReferenceScope` 内的 remangle 已有泛型入口。注意一个坑：store 路径下上游引擎的 scope hooks 会收到 nil，类型跳转标识会降级——做 2b 前需要先在 swift-demangling 侧把 hook 参数抽象过 `DemanglingNode`，届时以小提案跟进。

### Stage 3 — Symbol 表压缩（store 不覆盖的第二主项）

1. 改为单一平铺的 `symbols: [Symbol]` 表；各索引与 `symbolsByOffset` 只存 `UInt32` 表下标；一个符号的两个 offset 键指向同一条目，消除每符号双份 `Symbol` 复本。
2. `nlist: (any NlistProtocol)?` 这个 existential 压缩成实际被消费的少数字段（或在索引期用完即弃）。
3. `DemangledSymbol` 收敛成 `(symbolTableIndex: UInt32, node: NodeReference)` 量级的紧凑值。

### Stage 4 — 验收与文档

- 按 Stage 0 同口径复测，逐镜像记录 before/after；
- `MachOFixtureSupport` 快照（interface 输出）逐字节不变；
- 更新本文档的状态与实测数据，必要时同步 `AGENTS.md`/`CLAUDE.md` 的架构描述。

## 影响面

- 模块：`MachOSymbols`（核心）；`SwiftInterface` / `SwiftPrinting` / `SwiftDeclarationRendering`（取数处）；`SwiftSpecialization` / `SwiftLayout` / `SwiftDiffing`（TypeDecoder 与 remangle 调用点）。
- **RuntimeViewer**：经 `@_spi(ForSymbolViewer)` 消费 `DemangledSymbol` 的部分需同步适配——字段类型从 `Node` 变 `NodeReference`，需要树的地方按需 `materialize()`。
- 受影响模块加 `import Demangling`（公共接口面即够用）；只有自定义富文本 target 直接打印 store 的场合才需要 `@_spi(Internals) import Demangling`。

## 风险与缓解

| 风险 | 缓解 |
|---|---|
| store 冻结后不可增量插入，迟到符号无处放 | side cache `[Symbol: Node]`（罕见路径）；如未来需要增量，评估 per-image 重建或上游多 store 合并 |
| `DemangledSymbol` 字段类型变更破坏 RV | 同一批次修改两仓；必要时短期提供 `demangledNode` 的物化兼容属性过渡 |
| 单写者 builder 限制并行构建吞吐 | 上游实测单线程已快于旧基线；不足再做分块 + 合并（open question） |
| SemanticString 零物化直印的 scope 降级 | Stage 2 默认按需物化（全保真）；2b 前先抽象上游 scope hooks |

## Non-Goals（本计划不做）

- 上游 `Remangler` 的无构造泛型引擎——上游已决策保持 Node 引擎加物化桥的形态；
- store 序列化 / mmap 符号数据库——那是上游提案 0001 的 Phase 4，另行立项；
- `NodeCache` 本身的行为变更——迁移完成后它的增长压力自然消失。

## 实施记录

以下按时间序记录每个批次的实际落地情况，包括与计划的偏差、事故和后续审查修复。

### Stage 0 — 基线（2026-07-24，本机 SwiftUI image，debug 构建，`SymbolIndexStoreBaselineTests`）

迁移前旧管线的基线数据如下表。最值得注意的是最后两行：`NodeCache` 的增长是进程级永驻、跨镜像累积、无法随镜像淘汰回收的——这正是本次迁移要根除的问题。

| 指标 | 旧管线（main @ 7f7fe48） |
|---|---|
| 构建耗时 | 28.6s（独占）/ 36.2s（并行负载下） |
| 构建期 `phys_footprint` 增量 | 266–272 MB |
| 释放 `Storage` + `malloc_zone_pressure_relief` 后 | 残留 ~92 MB（回收 180 MB / 272 MB） |
| `NodeCache` 增长 | +19,345 叶、+559,976 子树——**进程级永驻，跨镜像累积，无法随镜像淘汰回收** |
| 索引条目 | demangled 202,603；member 17,049；methodDescriptor 2,209；global 82；offset 表 170,919；opaque 2,115；typeInfo 4,191 |

### Stage 1 + Stage 2（消费端）落地（2026-07-24，同口径复测）

核心迁移完成后同口径复测。结论：NodeCache 泄漏归零、稳态残留下降，代价是构建期瞬态峰值暂时上升 30 MB（Stage 3 会收掉）。

| 指标 | 迁移后（NodeStore） | 对比 |
|---|---|---|
| 构建耗时 | 30.7s（并行负载下） | **快于同负载旧管线 36.2s（-15%）**，独占口径 +8%（28.6 → 31.0s），远优于 <2× 预算 |
| 构建期 `phys_footprint` 增量 | 302 MB | +30 MB（pending→populate 转换期两套索引共存的瞬态峰值，Stage 3 可收） |
| 释放 `Storage` 后 | 残留 ~66 MB（回收 236 MB / 302 MB） | **稳态残留低 26 MB，且残留全为 malloc 未归还页——无任何逻辑驻留** |
| `NodeCache` 增长 | **0 叶、0 子树** | 泄漏归零；`Storage` 释放即整镜像回收 |
| `NodeStore` 本体 | 7 MB / 579,291 唯一节点（12.7 B/节点） | 对比旧版 interned class 树 ~12.9 MB + 全局缓存表 |
| 索引条目 | 与基线逐项一致 | 语义保真 |

### 实施要点（与原方案的偏差）

1. **分类逻辑跑在瞬态树上，而不是计划的 `NodeReference` 上**。原因是 `NodeStoreBuilder` 没有读访问接口，而且 `freeze()` 之后就不能再 intern（typeNode 包装节点必须在构建期造）。所以构建循环变成三步：先用 `demangleAsNodeTransient`（上游为此新导出的 `@_spi(Internals)` 入口，transient 指树用完即扔、不进任何缓存）得到瞬态 `Node` 树；分类逻辑在这棵树上原样运行；再 `builder.intern` 存入 arena。索引先以 `NodeIndex` 形态收集（`PendingStorage`），`freeze()` 后一次性转换为 `NodeReference` 形态（`Storage.populate`）。这样分类代码（`processMemberSymbol` 一族）几乎零改动。
2. **查询 API 的公共签名保持 `Node` 入参**。`memberSymbols(of:for:node:)` 与 `opaqueTypeDescriptorSymbol(for:)` 的实参来自 MetadataReader 的 canonical 树（用 Explore 审计过全部调用点确认），而键是 store 内的 `NodeReference`——两种表示要能互相比较。上游为此新增 `NodeReference.structurallyEquals(_ node: Node)`：零物化的跨表示结构相等，文本比较走字节、String 兜底。查询在按名字分的桶内线性匹配，桶内键极少。
3. **迟到符号统一收敛为 `NodeReference`**。冻结的 store 插不进新内容，所以 build 扫描之外的符号（例如 resilient witness 的显式 requirement symbol）经一个 per-symbol 的 mini `NodeStoreBuilder` demangle 加 freeze，late cache 存 `[Symbol: NodeReference]`。`demangledNode(for:)` 保持返回 `Node?`（经物化桥），十余个下游调用点零改动；另新增 `demangledNodeReference(for:)` 和 `MetadataReader.demangleSymbolReference`，给 matcher 提供零物化路径。
4. **消费端（原 Stage 2 的主体）一并落地**。四个 matcher（Override/Protocol/Extension/ProtocolConformance）切到 `demangleSymbolReference`，visited 集合用 `OrderedSet<NodeReference>`（哈希 O(1)）；`DefinitionBuilder` 的去重、methodDescriptor、vtable 查找的键换 `NodeReference`（hash-consing 让键比较从 O(树) 降到 O(1)）；渲染边界（`demangleResolver.resolve`、`Definition` 模型的 `node` 字段、`ExtensionName`）按计划物化。`isGlobal`/`isAccessor`/`hasAccessor`/`accessorKind`/`isStoredVariable` 泛型化到 `DemanglingNode`（约束 `where Self: Sequence<Self>`）。
5. **上游配套改动**（swift-demangling `feature/node-store` 分支）：`@_spi(Internals) demangleAsNodeTransient`；`NodeReference.structurallyEquals(_:)`（附 3 个测试）；`NodeReference: CustomStringConvertible`（物化桥，调试用）；`isKind(of:)` / `children.second` 上收到 `DemanglingNode` 协议扩展，删除 `Node` 上的具体副本。
6. **已知残留（Stage 3 候选）**：构建瞬态峰值 +30 MB（pending 和最终两套索引在转换期共存，可改为逐字典迁移消峰）；`symbolsByOffset` 与 `Symbol` 复本的压缩即原 Stage 3 范围。
7. **测试环境备注**：`SwiftInterfaceBuilderTests` / `SwiftDiffableInterfaceBuilderTests` / `XcodeMachOFileDumpTests` 依赖本机 Xcode 的 fixture glob（`XcodeMachOFileName.swift:456`），在未改动的 main 上同样 fatal——这是预先存在的环境问题，与迁移无关，验收时用 `--skip` 排除。

### 验收与测试策略调整（2026-07-24）

按用户决定，`IntegrationTests` 整体退出验收路径。直接原因：其中三个 suite 硬编码了 `/Applications/Xcode-26.4.0.app` 路径，本机 Xcode 已升级到 26.5.0，glob 失败后 `fatalError` 直接崩掉测试进程。该问题在未改动的 main 上同样存在，属于测试基建债，不在本迁移范围内修复。验收改为「快照对比 + fixture 单元测试」：

1. **快照以 main 为基准逐字节对比**。先在 main（`7f7fe48`，旧管线）上运行 `SymbolTestsCoreInterfaceSnapshotTests` + `SymbolTestsCoreDumpSnapshotTests`（共 60 个快照测试），确认已提交的基准与 main 输出一致；再在迁移 worktree 上跑同一套——**60/60 逐字节一致**。fixture 是自建的 `SymbolTestsCore.framework`，无外部 Xcode 依赖；worktree 经符号链接复用主检出 `Tests/Projects/SymbolTests/DerivedData` 的构建产物。
2. **启用 `MachOSymbolsTests` target**（Package.swift 里原本已定义但被注释掉）并新增 `SymbolIndexStoreFixtureTests`（8 个用例），覆盖：build 管线的 cache-free 不变量——这里有个口径调整：所有测试 target 共享单进程，全局 `NodeCache` 的计数断言天然竞态，所以改用「transient demangle 两次得到结构相等但 `!==` 的叶实例」这一并发免疫口径做叶身份断言，进程级零增长量测留在手动运行的 `SymbolIndexStoreBaselineTests`；全符号零物化打印与 `demangleAsNode` 管线逐字节对齐；`memberSymbols(of:for:node:)` 对每个 `NodeReference` 键桶经 `structurallyEquals` 命中；`symbols(of:)`/`typeInfo`/`opaqueTypeDescriptorSymbol` 与 storage 桶一致；`demangledNode`/`demangledNodeReference` 互证；迟到符号 mini store 回退与缓存稳定性。
3. **修复 `SharedCache` 的并发时序 flake**。`concurrentCallsForDifferentKeysRunInParallel` 原来以墙钟阈值断言并行性，CPU 一饱和就假失败。改为确定性的并行证据：所有 build 经信号量互相等待进入闭包——若 resolve 对不同 key 是串行的（锁跨 build），就会死锁，由宽松超时转为失败而不是挂死。

### Stage 3 — Symbol 表压缩落地（2026-07-24）

1. **`Symbol` 去掉 `nlist` existential**。删除 `(any NlistProtocol)?` 存储属性（每份 40 B 的 existential 容器）。审计确认它唯一的实际消费者是采集期的 undefined-external 过滤（`N_EXT + N_UNDF`），而这个过滤发生在 MachOKit 符号上、早于 `Symbol` 构造——存进 `Symbol` 之后就是纯死重。压缩为采集期提取的一个 `isExternal: Bool` 存储位。`Symbol` 显式标注 `Sendable`，stride 从 64 B 降到 **32 B**。公共 init 由 `init(offset:name:nlist:)` 改为 `init(offset:name:isExternal:)`——对 RuntimeViewer 源码审计确认没有 `.nlist` 或 `DemangledSymbol` 的直接消费者，都只经 `.symbol.name` / `.addressString` 取值。
2. **平铺符号表**。`Storage.symbolTable: [Symbol]` 每个唯一符号名一行，存 canonical 偏移（即 dyld cache 场景下 cache-adjusted 过的偏移）；`tableRowByName: [String: UInt32]` 做名字到行号的映射（键与表行共享字符串存储）；`rootNodeIndexByTableRow: [NodeIndex?]` 平行数组承接原 `demangledNodeBySymbol` 的值侧。全部索引（`symbolRowsByKind` / member×3 / global / opaque / `symbolRowsByOffset`）改存 4 B 的 `UInt32` 行号；member/opaque 索引的键从 16 B 的 `NodeReference` 改为 4 B 的 `NodeStore.NodeIndex`，出口按需用 `nodeStore.reference(at:)` 重建。**一个符号的两个 offset 键共用同一行**——每符号双份 `Symbol` 复本就此消除；`symbols(for:in:)` 出口按查询键重建 `Symbol(offset: queriedOffset, ...)`，与旧的按键复本语义逐字节一致。
3. **`DemangledSymbol` 压缩为 32 B**。字段变为 `(symbolTable: [Symbol]（共享缓冲，8 B 指针）, symbolTableRow: UInt32, demangledNode: NodeReference)`；`symbol` 变成计算属性，`@dynamicMemberLookup` 转发不变。公共的 `init(symbol:demangledNode:)` 保留为单行表兼容路径，服务测试与 `ExtensionDefinition` 的显式构造点。索引出口从行号现场构造值——原先每条索引条目约 80 B 的内联 `Symbol`+`NodeReference` 复本全部消失。
4. **pending→populate 的双索引窗口整个消除**。构建期分类索引直接以最终行号形态累积（`RowIndexes`），`freeze()` 后 `Storage.init` 只做纯移动——原 `PendingStorage`→`populate()` 转换 pass（Stage 1 记录的 +30 MB 瞬态峰值来源）删除。`Storage` 的全部索引字段现在都是 `let`，只有 late-symbol cache 是 `@Mutex var`。
5. **`demangledNodeReference(for:)` 查找重写**。从 `[Symbol: NodeReference]` 字典命中改为「`tableRowByName[name]` 查行号 + canonical offset 校验 + 平行数组取根」三步——与旧的 `(offset, name)` 键哈希语义严格等价（offset 不匹配或 demangle 失败仍落到 late mini-store 路径）。
6. **测试同步**。`SymbolIndexStoreFixtureTests` 适配行号布局并新增 2 个用例：`compactValueLayouts`（`Symbol` / `DemangledSymbol` 的 stride ≤ 32 B 紧凑性不变量）与 `offsetQueriesRebuildSymbolsWithQueriedOffset`（双键共行后出口 offset 的重建语义，逐 offset 键对账行数与名称）；`SymbolIndexStoreBaselineTests` 改读新字段并输出 `symbolTable` 行数与 stride。
7. **过程备注（环境坑）**。布局变更后 SwiftPM 增量构建没能把 `MachOSymbols` 的 struct 布局变化传播到全部依赖模块：先是陈旧目标文件报 linker 错，touch 之后链接通过，但运行期在 `Symbol.init` 里按旧布局跑 outlined destroy 直接 SIGSEGV。`swift package clean` 全量重建后消失。此类跨模块布局变更建议直接 clean 构建。

### Stage 4 — 最终验收与复测（2026-07-24，SwiftUI image，debug，独占口径同 Stage 0）

三个阶段的纵向对比。结论：Stage 3 之后构建比旧管线快 14%，构建期内存增量从约 270 MB 降到 68 MB，NodeCache 增长保持归零。

| 指标 | Stage 0 旧管线 | Stage 1+2 | Stage 3 |
|---|---|---|---|
| 构建耗时（独占） | 28.6s | 31.0s | **24.5s（快于旧管线 14%）** |
| 构建期 `phys_footprint` 增量 | 266–272 MB | 302 MB | **68 MB** |
| 释放 `Storage` + pressure relief 后 | 残留 ~92 MB | 残留 ~66 MB | **残留 49 MB**（回收 38 MB / 68 MB 增量） |
| `NodeCache` 增长 | +19,345 叶 / +559,976 子树 | 0 / 0 | 0 / 0 |
| `NodeStore` 本体 | — | 7 MB / 579,291 唯一节点 | 7 MB / 579,291（与 Stage 1 完全一致，语义保真旁证） |
| Symbol 侧驻留 | nlist 盒 + 双份条目 + 索引内联复本（数十 MB 级） | 同旧形态 | `symbolTable` 202,603 行 × 32 B ≈ 6.2 MB + 共享字符串 + 各索引 4B 行号 |
| 索引条目 | 基线 | 逐项一致 | 逐项一致（demangled 202,603；member 17,049；methodDescriptor 2,209；global 82；offset 表 170,919；opaque 2,115；typeInfo 4,191） |

- 构建耗时的下降来自三处：populate 转换 pass 删除；每符号双份 `Symbol` 构造与 existential 装箱消失；索引累积只搬 4 B 行号。
- 构建期增量从 302 MB 收敛到 68 MB：双索引瞬态窗口消除加 Symbol 复本与 existential 盒清零是主贡献；残余的 68 MB 是 NodeStore + 表 + 索引 + malloc 未归还页。
- 验收测试：`SymbolTestsCore` 快照 60/60 逐字节一致 + `SymbolIndexStoreFixtureTests` 10/10 + `SharedCacheTests` 全绿（**79 tests / 5 suites passed**，Stage 3 代码加本地 feature 分支解析口径复跑确认）。

## Stage 5 提案 — 声明层零物化（Definition/富文本打印迁移到 `NodeReference`）

- **状态**: 提案，待批准
- **日期**: 2026-07-24
- **动机**: Stage 0–4 落地后 RuntimeViewer 实测：`Node` 实例 1,091,575 → 336,095，进程内存 628.5 MB → 478.6 MB。`Node` 自身的布局侧已无肉可挖——实测其 `Payload` 枚举 17 B（最大 case 16 B，判别位没有空位可藏）、`kind` 2 B、对象头 16 B，实例共 41 B、落入 48 B 的 malloc 桶；手工位压缩到 32 B 桶只能省约 5.4 MB，还要放弃安全枚举，不做。所以剩余 33.6 万个实例的**来源**才是下一刀要砍的。

### 剩余 `Node` 的来源盘点（2026-07-24 调研）

1. **Definition/Name 值类型长期持有物化树**（主项）：`VariableDefinition.node`、`FunctionDefinition.node`、`SubscriptDefinition.node`、`FieldDefinition.typeNode`、`ExtensionDefinition.genericSignature`、`TypeName.node`、`ProtocolName.node`、`ExtensionName.node`（`DefinitionName` 协议要求 `var node: Node`）。`DefinitionBuilder` 与 `SwiftDeclarationIndexer` 在构建处逐一调 `.materialize()`——store 里本来就有的共享子树被展开成独立 class 树，随声明缓存驻留。
2. **仍走 interning `demangleAsNode` 的散点**：`MetadataReader`（symbolic reference 密集）、`RuntimeFieldLayoutBackend`、`TypedDumper`、`ClassHierarchyDumper`、`Symbol.demangledNode`。这些把规范树**永久钉进全局 `NodeCache.shared`**，镜像关闭也不回收。
3. **打印桥接物化**：`SwiftDump` 各 dumper 的 `demangleResolver.resolve(for: node.materialize())`——瞬态，但高频。

### 前置（5·0）— swift-demangling 侧小改

`DemanglingPrinter` 用富文本 target 走 store 时，唯一的语义缺口在 `NodePrinter.swift:198`：`target.pushTypeReferenceScope(name as? Node)` 对 `NodeReference` 恒传 `nil`，富文本 target 的 type-reference 身份作用域（`SemanticString` 用它 remangle 出 identifier scope）就丢了。修法：

- `NodePrinterTarget.pushTypeReferenceScope(_ node: Node?)` 改为 `pushTypeReferenceScope(_ node: @autoclosure () -> Node?)`；引擎侧传 `name.materializedNode`。
- `@autoclosure` 保证 String target（默认空实现，从不求值）**零成本**——现有 store 零物化打印路径不回退；只有 `SemanticString` 的实现真正求值，而且物化只发生在 nominal 引用节点上——子树小，且紧接着的 `mangleAsString` 本来就要遍历整棵树。
- 协议签名变更会破坏外部 conformance，但已知 conformance 只有 `SemanticString`（在 MachOSwiftSection 内，我方可控）与库内默认实现，同步改。
- 守护测试：store 路径 String target 打印全程零 `Node` 分配（现有字节一致快照 + 新增分配哨兵）。

### 5a — SwiftDeclaration 值类型换持 `NodeReference`

- 上面列的全部 `Node` 存储属性改为 `NodeReference`（`DefinitionName` 协议要求同步改）；`OverrideSymbolMatcher` 等取 `typeNode: Node` 参数的内部接口跟随。
- `DefinitionBuilder` / `SwiftDeclarationIndexer` 删除全部构建期 `.materialize()`——sweep 手里本来就是 `NodeReference`。
- `NodeReference` 自带对 `NodeStore` 的强引用（16 B 值：store 引用 + 下标），生命周期自洽：声明活着，store 就活着；镜像的声明缓存整体淘汰，store 随之整体回收——正是本计划的回收模型。
- RuntimeViewer 适配面（feature/node-store-adoption 分支）：`mangleAsString(typeName.node)` 这类调用点经既有的 `mangleAsString(some DemanglingNode)` 泛型桥**无感**；少数构树点（`wrappedAsType(base.typeName.node)`、`nodesByParameter` 字典等）显式 `.materialize()` 或改存 `NodeReference`。已确认 RV 未使用 `DemangleResolver.builder`。

### 5b — SwiftPrinting 富文本引擎泛型化（工作量主体）

- `NodePrintable` 协议族（`NodePrintable` / `InterfaceNodePrintable` / `TypeNodePrintable` / `FunctionTypeNodePrintable` / `BoundGenericNodePrintable` / `DependentGenericNodePrintable`）加 4 个具体 printer（Variable/Function/Subscript/Type）：具体 `Node` 改为 `associatedtype SomeNode: DemanglingNode`，模式照抄上游 `DemanglingPrinter` 的泛型化。
- `printCache: [ObjectIdentifier: Target]`（DAG 记忆化）改为泛型 memo key：SwiftPrinting 本地协议，`Node` 用 `ObjectIdentifier(self)`、`NodeReference` 用自身（O(1) `Hashable`）。store 里的子树共享以共享下标的形式存在，memo 命中率不变。
- `DemangleResolver` 增加 `resolve(for: some DemanglingNode)`：`.options` 分支走 `DemanglingPrinter<SemanticString, SomeNode>` 零物化；`.builder` 分支维持公开的 `(Node) async throws -> SemanticString` 闭包签名、内部经 `materializedNode` 桥——公开 API 不破坏，物化只剩这一条路径。
- `NodeReference.printSemantic(using:)`（经 `@_spi(Internals) DemanglingPrinter`，落在 SwiftDeclarationRendering）。
- `SwiftDump` 的 dumpers：`symbol.demangledNode.materialize()` 改为直接传 `NodeReference`。

### 5c — 散点 `demangleAsNode` 去钉扎（`NodeCache` 停止增长）

- 来源盘点第 2 类的调用点全部改走 transient 解码（`demangleAsNodeTransient` 已 `@_spi(Internals)` 导出）：树仍是 `Node` 的场合不再钉进全局 cache，随消费方释放。
- 需要长期持有的 metadata 派生树（field type、runtime generic signature 等，不经 symbol store）：`SwiftDeclarationIndexer` 每次索引 pass 维护一个**辅助 `NodeStoreBuilder`**，transient 树经既有的 `builder.intern(_ node: Node)` 灌入，pass 结束 `freeze()`，声明持有辅助 store 的 `NodeReference`。辅助 store 与主 symbol store 不共享去重（frozen store 不可再写），文本与子树的少量重复可接受——metadata 树的规模远小于符号全集。
- 注意 `NodeStoreBuilder` 是 `~Copyable`、非线程安全：intern 段必须收敛在 indexer 的单线程/单 actor 执行段内。现有 sweep 已满足，改动中需保持。

### 验收

- 既有三件套全绿且逐字节一致：`SymbolTestsCore` interface 快照 60/60（该快照走 SwiftInterface → SwiftPrinting 富文本引擎 → 字符串投影，恰好兜住 5b 的文本回归）+ `SymbolIndexStoreFixtureTests` + `SharedCacheTests`。
- **补语义 token 抽查**：字符串投影盖不住 `pushTypeReferenceScope` 的身份作用域——它只影响 token 元数据、不影响文本——所以对若干典型声明断言 `SemanticString` 的 identifier scope 序列与 `Node` 路径一致。
- 同口径内存复测：目标是 `Node` 常驻 336k → 5 万以内（残余应只剩 `.builder` 桥的瞬态与 RV 显式物化点）；`NodeCache` 增长维持 0/0 且**存量不再随浏览增长**；进程 footprint 复测记录在案。

### 风险与缓解

| 风险 | 缓解 |
|---|---|
| `pushTypeReferenceScope` 签名变更是 swift-demangling 公开协议破坏性改动 | 已知 conformance 全部在我方两仓内；`@autoclosure` 方案在 String 路径零求值，配分配哨兵测试守住零物化不回退 |
| 5b 泛型化触及 ~11 文件的 async mutating printer，回归面大 | interface 快照逐字节兜底 + 语义 token 抽查；分 PR：5·0+5c（小）→ 5a（中）→ 5b（大）→ RV 适配（中），每步独立可验收 |
| `Node` 结构性 `Hashable` 误用作 memo key 导致性能回退 | memo key 协议显式区分：`Node` 用 `ObjectIdentifier`，`NodeReference` 用值本身；review checklist 明确禁止直接 `hash` 泛型节点 |
| 辅助 store 与主 store 文本重复 | 规模评估后可接受；如实测超预期，后续可让 indexer 直接在辅助 builder 上 `demangle(_:)`（省掉 transient `Node` 中转） |
| RV 侧 `typeName.node` 类型变化波及面 | `mangleAsString` 泛型桥无感；其余调用点编译期暴露，逐点 `.materialize()`；RV 在独立 adoption 分支，可整体验证后合入 |

### 预期收益

- `Node` 常驻实例 336k → 数万以内。按全口径每节点约 70 B 估算（实例 48 B + `.text` 的 String 堆存储 + `manyChildren` 数组缓冲），回收 **15–20 MB**；且 `NodeCache` 的永久钉扎清零后，长时间浏览不再单调增长。
- 声明持树的成本从每节点 48 B 的 class 树，降为辅助/主 store 的每节点约 12–14 B arena 加每根 16 B 句柄。

### Stage 5·0 + 5c + 5a 落地（2026-07-24）

- **5·0（上游）**：`NodePrinterTarget.pushTypeReferenceScope` 改为 `@autoclosure () -> Node?`，引擎侧传 `materializedNode`——String target 从不求值（store 纯文本路径保持零物化），`SemanticString` 惰性求值拿到完整作用域身份。新增 `NodePrinterScopeTests`（双表示作用域序列一致性）。`demangleAsNodeTransient` 增加 `symbolicReferenceResolver` 参数；新增 `@_spi(Internals) Node.createTransient` 工厂族。
- **5c**：`MetadataReader`（28 处 `create` + 5 处解码）、`RuntimeFieldLayoutBackend`、`TypedDumper`、`ClassHierarchyDumper`、`Symbol.demangledNode`、`ResolvedTypeReference+`、`GenericContext+Dump` 的无界构造与解码全部转 transient——`NodeCache` 停止随浏览增长。有界的单例（`firstGenericParamType`、AnyObject 约束）保留 interning。
- **5a**：声明层全部换持 `NodeReference`。上游新增 `NodeReference(interning:)`、跨 store 的 `structurallyEquals(_ other: NodeReference)`、`structuralHash(into:)`；`memberSymbols(of:for:node:)` 增加 `NodeReference` 重载。成员定义直接持主 store 引用（构建期 4 处 `materialize()` 删除）；extension 成员路径的 `ExtensionName`/`genericSignature` 直接用主 store 键（原先每个键都要物化，删除）；metadata 派生树以 mini store 承接，`TypeDefinition.index(in:)` 的字段树按类型批量共享一个 store。`Name` 类型自定义结构语义的 `Hashable` 与 wire 兼容的 `Codable`。打印边界暂留 5 处显式 `materialize()` 桥（`SwiftDeclarationPrinter` 3 处 printer 入口 + where 子句 + `leafNameNode`×2），等 5b 泛型化时消除；`NodeReference.printSemantic`（零物化富文本）已就位并接管 `SwiftDiffableInterfaceRenderer`。
- **验收**：MachOSwiftSection 98 tests / 15 suites 全绿（interface 快照逐字节一致、fixture、diffing、substitution、attribute inference）；swift-demangling 定向 44/7 全绿加全量复跑。
- **事故记录 — 测试语料符号无效 + xcsift 假绿**：`DemanglingTests` corpus 里的 `$s7SwiftUI4TextV_10FoundationE9formatterAcA…` 自引入起（5788472，NodeStore 之前）就是**无效符号**——系统 `swift-demangle` 同样拒绝它，`TextV` 后多了一个 `_`——理应一直红。此前没暴露，是因为验收命令 `swift test 2>&1 | xcsift; echo $?` 捕获的是 **xcsift 的退出码**而不是 `swift test` 的，多轮「全绿」不可信。已替换为真实生成的同复杂度符号 `$s11ExampleBase0A4TextV0A6AddonsE9formatter7subjectAcA0A5StyleV_xtcSyRzlufC`（跨模块 extension + `SyRzl` 约束 + `ufC`），并把三个测试文件的全部 mangled 字面量过了一遍系统 demangler 校验。**教训：管道给 xcsift 时用 `${pipestatus[1]}` 取真实退出码，或验收时直接看原生输出。**

### Stage 5b 范围调整 — 全量泛型化缩水为 5b-lite（2026-07-24，实施期决策）

原方案要把 SwiftPrinting 的异步富文本引擎（`NodePrintable` 协议栈约 1,600 行）全量泛型化到 `DemanglingNode`。实施 5a 之后重估，决定缩水：

- **收益已在 5a 兑现**。原方案预期靠 5b 消除的「打印路径常驻物化」，实际上被 5a 的直持 `NodeReference` 消掉了——打印入口的 `materialize()` 只剩**瞬态**分配（单个声明的签名树、微秒级、打印完即释放），对常驻内存零贡献。
- **成本高于预估**。摸底发现引擎内有 5 处「合成一个 `Node` 再打印」的模式（`.static` 包装、labelList 的插入与合成），在泛型 `SomeNode` 下无法表达——合成结果是 `Node`，塞不回 `SomeNode` 的递归——需要逐处重写为非合成形态，回归面大。
- **5b-lite 实际落地的内容**：`DemanglingNode.printSemantic`（协议扩展，零物化富文本，任意表示可用）；`DemangleResolver.resolve(for: some DemanglingNode)`（`.options` 零物化直印，`.builder` 保持公开的 `Node` 闭包签名、只有该路径物化）；SwiftDump dumpers 的 6 处 `resolve(for: X.materialize())` 直传 `NodeReference`——高频的瞬态物化点清零。
- **保留的显式物化桥**（低频/瞬态，是全量泛型化的剩余标的，暂不做）：`SwiftDeclarationPrinter` 3 处 printer 入口 + where 子句子节点 + `leafNameNode` ×2 + `SwiftPrinting+Headers`/`ClassDumper` 的 thunk 构树点 + RV 特化构树 2 处。
- **重启条件**：若后续 profiling 显示 interface 全量导出（swift-section `InterfaceCommand` 这类批量场景）的瞬态树分配成为吞吐瓶颈，再按原方案泛型化。届时合成点的重写方案：labelList 合成改计数循环，`.static` 包装改 printer 状态位。

### Stage 5a 回归修复 — override/vtable 查询字典漏用结构相等键（2026-07-25）

**症状**：offline `interface`（`MachOFile` 路径）对 iOS 18.5 模拟器 `SwiftData.framework` 的 `Schema.Attribute` 丢失全部 `override` 关键字与配套的 `// VTable offset:` 注释（main 上 5 个，迁移分支 0 个）。范围极窄且与数据相关：iOS 26.5 的**同一个类**正常（5→5），SwiftUI/SwiftUICore 的数百个 override 全部一致，两侧构建内均确定性。发现手段：用 main worktree 对 6 个模拟器二进制（SwiftUI/SwiftUICore/SwiftData × iOS 18.5/26.5）× {dump, interface, 全 `--emit-*` 变体} 共 18 份整文件快照做 A/B diff——16/18 逐字节一致，仅这 2 份有差异。

**根因**：Stage 5a 把 `TypeDefinition.index(in:)` 的 `methodDescriptorLookup` / `vtableOffsetLookup` 从 `[Node: …]`（结构相等键）换成了裸 `[NodeReference: …]`。而 `NodeReference` 固有的 `Hashable`/`==` 是 **store-identity** 语义——比较的是「同一个 store 里的同一个下标」，不是结构相等。这两个字典的**键**来自 override 描述符的实现符号：`SymbolIndexStore.demangledNodeReference(for:)` 对落在 build sweep 之外的符号会新建一个 **per-symbol mini store**。**查询**用的却是成员符号，来自 `memberSymbols`、在主 store 里。两边结构相等但 store 不同，查表必然 miss，override 和 vtable 注释一起丢。iOS 18.5 那批 override 实现符号恰好落进了 mini store，26.5 的都在主 store，所以只有前者复现。这正是 `Name` 类型当初改结构语义 `Hashable` 时规避的同一个陷阱——这两个裸字典漏改了。还有一个放大因素：`TypeDefinition.index` 的 offset 兜底表（`implOffsetDescriptorLookup`/`implOffsetVTableSlotLookup`）**只从 `methodDescriptors` 建**，`methodOverrideDescriptors`/`methodDefaultOverrideDescriptors` 没进兜底表，所以 override 方法只有 `NodeReference` 这一条路，一 miss 就彻底丢。

**修复**：新增 `StructuralNodeReferenceKey`（`package` 级，放在 `SwiftDeclaration`，照 `Name` 类型的做法用 `structurallyEquals` + `structuralHash`），把 `methodDescriptorLookup` / `vtableOffsetLookup` 的键类型改为它，插入端（`TypeDefinition.index` 5 处）与查询端（`DefinitionBuilder` 4 处）统一包装。只动这对跨 store 的查询字典；分组与去重用的其余 `NodeReference` 键容器（`accessorsByNode`、`canonicalIndexBy*Node`、`pendingMergedBy*Node`、`visitedNodes`）都在单个 `memberSymbols` 批次内使用——同一个 hash-consed store 里结构相等就是下标相等——判断为安全，不动。（这个「其余容器安全」的判断后来被证明是错的，见 2026-07-26 批次第 3 条。）

**验收**：全量 1263 tests / 242 suites 全绿（含直接覆盖此功能的 `outputContainsOverrideKeyword` / `outputContainsVTableOffsetComments`），外加新增的 `StructuralNodeReferenceKeyTests` 4 个用例——其中 `structuralKeyDictionaryHitsAcrossStores` 精确复刻生产形态：裸 `NodeReference` 字典 miss、结构键 hit。修复后**三种读取来源的快照对 main 全部逐字节一致**：MachOFile 38/38（iOS 15.5 / 16.4 / 17.5 / 18.5 / 26.5 / 27.0b1 / 27.0b2 的可用三件套，含全注释变体）、DyldCache 18/18（macOS 宿主 cache + iOS 27.0b3 / b4 模拟器 cache）、MachOImage 6/6（宿主三件套 in-process）。基线快照与复现 harness 固化在 `MachOSwiftSection-Baselines/main-27726bc/`（62 份 + SHA256 清单），后续迭代以此为准；详见 `Documentations/Internal/TaskReports/2026-07-25-node-store-override-regression-and-baselines.md`。

**附带发现并已修复（既存缺陷，非本次迁移引入）**：`DyldCache.machOFile(by: .name(_:))` 的匹配曾是「`imagePath.lastPathComponent.deletingPathExtension == name` 且第一个命中即返回」，而 cache 内叶名不唯一——iOS 27 同时存在 `/System/Library/Frameworks/SwiftUI.framework/SwiftUI` 与 `/System/Library/AccessibilityBundles/SwiftUI.axbundle/SwiftUI`，于是 `swift-section --dyld-shared-cache -n SwiftUI` 会静默选中先枚举到的 axbundle。axbundle 没有 Swift 元数据，后果是 dump 输出 0 字节、interface 只剩 4 行 import，而且退出码还是 0。

修复：`DyldCacheImageSearchMode` 增加 `matchRank(forImagePath:)`，把「命中」从布尔改为**分级**——`<name>.framework` 内的规范二进制（含 macOS 的 `Versions/A/` 形态）为最佳级 0，`.dylib` 为 1，其它同叶名负载（`.axbundle`/`.bundle`/…）为 2；`bestMatch(in:)` 取最佳级、遇到 0 级立即短路，所以常见路径的开销与原先的 first-match 相同；`.path` 精确匹配恒为 0 级、行为完全不变。平局保留最早者，结果对给定 cache 确定。

验收：`DyldCacheImageSearchTests` 6 个用例（纯路径运算，不需要磁盘上的 cache）；端到端 `-n SwiftUI` 由 0 字节变为 9,131,212 字节且与 `-p` 生成的基线**逐字节一致**，`-n SwiftUICore` / `-n SwiftData` / macOS 宿主 cache 全部无回归。

### 审查修复批次 — mini store 增殖的根因与跨 store 键的收口（2026-07-26）

对分支全量 diff 跑代码审查后的修复批次。核心结论是**多条症状同源**：`demangledNodeReference` 的命中条件里多了一个 offset 判等，让整条 dyld shared cache 路径退化到 per-symbol mini store；而 mini store 一增殖，下游一批裸 `NodeReference` 键就静默失效。逐条：

1. **`demangledNodeReference` 去掉 offset 判等**。建表时 dyld cache 的行存的是 canonical offset（`rawOffset - sharedRegionStart`），而 `symbols(for:in:)` 是拿**查询时传入的** offset 重建 `Symbol` 的——两边天然不同，判等必然失败，于是整个镜像的每个符号都会新建一个 mini store。这个条件在语义上本就多余：demangle 结果只是名字的函数，`tableRowByName` 一名一行、重名后写覆盖，offset 比较只能否决合法命中、无法消歧。**同一 offset 对应多个符号是正常情形**——它们名字不同，按名字查各自命中各自的行，不受影响。late cache 的键同理从 `Symbol` 改为 `String`。
2. **late demangle 收进单一临界区**。原实现是先查后建（check-then-act）：两个线程同时 miss 会各自 freeze 一个 mini store，同一个符号返回**两个不同 store** 的引用，下游任何结构去重都变成 run-to-run 抛硬币。改为 `lateDemangledNode(forName:)`，查、建、存在同一个锁内完成。
3. **`StructuralNodeReferenceKey` 下沉到 `MachOSymbols`，并覆盖全部跨 store 集合**。上一批（Stage 5a 回归修复）只改了 override/vtable 那对字典，当时判断「其余容器都在单批次内使用」——这个判断是**错的**：`Definition+.setDefinitions` 喂给 `DefinitionBuilder` 的符号里，混有走 `MetadataReader.demangleSymbolReference`（mini store）的分支。本批改齐：`accessorsByNode`（不改的话 subscript 的 getter/setter 会分进两个桶，只有 setter 的那个桶被 `contains(.getter)` 检查丢弃）、`canonicalIndexByFunctionNode` / `canonicalIndexByAllocatorNode`（不改的话 merged thunk 与其规范符号对不上，同一个 `func`/`init` 输出两遍），以及五处 `visitedNodes` 的 `OrderedSet`（不改的话同一个实现符号会被两个 witness 重复认领）。
4. **dyld cache 选图排序改为跨 cache 生效**。上一批加的排名是「逐 cache 文件分别排序、第一个有任何匹配的 cache 直接返回」——于是当 axbundle 在先扫的 cache、framework 在 subcache 时，依然会选中 axbundle，正是该修复本想消除的情形。改为跨全部 cache 文件累积排名（`accumulateBestMatch(in:into:)`），只在拿到最高级时早退；`mainCache` 为 nil 时也返回已累积的最佳而不是 nil。
5. **同一行不重复入桶**。exported symbol 分支在 canonical 与 raw offset 相等时（`MachOImage`，或 `startOffset == 0` 的文件）会把同一行 append 两次，让每个 `for symbol in symbols` 循环把该符号跑两遍。两个分支统一走 `registerRow`，按「canonical ≠ raw 才写第二个键」判断。
6. **opaque 描述符查找恢复 O(1)**。`opaqueTypeDescriptorSymbol(for:)` 原来是对全局桶做线性扫加逐项结构遍历，而它的调用频次是「每个打印出来的 `some` 返回类型一次」——在 SwiftUI 上两个量级都是千级，乘起来就是瓶颈。改为构建期按 `DemanglingNode.identifier` 分桶（该属性对 `Node` 与 `NodeReference` 是同一份协议实现，结构相等必然同桶），桶内再结构比较。**后记（2026-08-13）：identifier 分桶被实测证明不充分并已替换**——identifier 是成员名，SwiftUI 的 `some View` 实现几乎全叫 `body`，单桶数百项、桶内扫描仍是二次方；现为 `opaqueTypeDescriptorSymbolRowByMemberNode: [StructuralNodeReferenceKey: UInt32]` 的单次 hash probe，查询侧以 `StructuralNodeReferenceKey(querying:)` 拿裸查询树直接探测（不物化、不 intern）。
7. **`printSemantic` 栈保护统一**。`Node` 的具体重载没有 `StackSafeExecutor` 包裹而泛型版有，且具体重载的解析优先级更高——结果所有 `Node` 调用方实际走的都是没保护的那条。上游的 `NodePrinter<Target>` 本身就是 `DemanglingPrinter<Target, Node>` 的薄包装，输出等价，所以直接删掉具体重载。

**驳回一条**：审查建议把 `DemangledSymbol` 的单元素数组换成内联 `Symbol` 的双 case 枚举以省掉一次分配，并声称「仍在 32 字节内」。实测不成立——`Symbol` 自身就是 32 字节，换枚举后整个值涨到 48 字节，`compactValueLayouts` 直接失败；而经共享表下发的这种值有数十万份。取舍已写进该初始化器的文档注释。

**显式不改一条**：`ClassDumper.distributedFunctionNodes` 每个 actor 类算两遍、且逐 thunk 物化。消除它需要给一个 `Sendable` 值类型加可变引用缓存，而该路径只在使用 distributed actor 的二进制里执行——本项目日常面对的框架里为零；查询侧拿的是 `Node`，集合改结构键反而要为每个方法 intern 一个 mini store。判断为不值得。

**验收**：`swift package clean` 后全量 **1273 tests / 244 suites 全绿**；对冻结基线 `main-27726bc` 的三源整文件快照对比**全部逐字节一致**（File 38/38、DyldCache 18/18、Image 6/6，共 62 份）。有个覆盖盲点要单独补：快照 harness 一律用 `-p`（按路径）选 cache 镜像，而 `-p` 恒为最高排名，测不到第 4 项的排序逻辑——所以另对 iOS 27.0 beta 3 模拟器 cache 补跑了 `-n {SwiftUI, SwiftUICore, SwiftData}`（按名字选图），三者与对应 `-p` 输出逐字节一致（9,131,212 / 8,191,268 / 271,114 字节），这才是第 4 项真正的覆盖。（改完 `Storage` 字段后增量构建再次出现运行期 SIGSEGV，clean 重建后消失——与 Stage 3 过程备注记录的现象相同。）

### 内存图驱动的驻留收口 — 容量预留 + 残余 cached demangle 清零（2026-08-08）

RuntimeViewer 索引 Foundation + libswiftCore + AppKit + SwiftUI + SwiftUICore 五个镜像后的 memory graph 计数：存活 `Node` 208,809 个、`NodeStore` 14,451 个。swift-demangling 侧的会话（feature/node-store 分支）在本仓库定位来源后转来三项计划，本批落地前两项：

1. **主 sweep 容量预留**。`SymbolIndexStore` 的 `NodeStoreBuilder` 构造后紧跟 `builder.reserveCapacity(expectedSymbolCount: totalSymbolCount)`——上游提案 0009 的 API，按语料标定的每符号系数，一次性预留三块缓冲与 intern 槽表。上游实测：每镜像构建期 ≥1 MiB 的 realloc 拷贝从 12 次降到 4 次（剩下 4 次就是预留本身），冷启动 footprint 尖峰减半。预留语义是 growing-only 且不改变 interning 结果，输出零变化。
2. **最后两处 cached `demangleAsNode` 转 transient**。`SwiftLayout.ObjCClassIndex`（runtime name → 限定名字符串，树用完即弃）与 `SwiftDeclarationRendering.SpecializedMetadataNodeSubstitution`（metatype 名 → 渲染即弃）此前把整棵树永久 intern 进全局 `NodeCache`（不淘汰），是存活 `Node` 的主要来源之一。两处改 `demangleAsNodeTransient`（`@_spi(Internals)` import 跟进），Sources 下 cached `demangleAsNode(` 调用点全库清零——Stage 5c 的收口补全。
3. **小 store 流水线显式不动**。三条流水线——`InternedNodeReferenceCache`、`TypeDefinition` 字段树的批量 store、`lateDemangledNode` 的 mini store——是对「builder 一次性 freeze、冻结前拿不到可读引用」这一上游真实缺口的正确规避，也是那 14,451 个 store 的主要来源。上游已起草提案 0010（swift-demangling `Evolutions/0010-appendable-shared-node-store.md`，当时 Draft）：`SharedNodeStore` 长生命周期、线程安全、intern 即发放稳定 `NodeReference`、无 freeze 屏障。落地后三条流水线可汇入每镜像一个共享 store（预期 store 数 14,451 → 约 6，`TypeName` 相等比较拿到同 store 下标快路径）。0010 落地前不重构。**后记：0010 当日 Implemented，三条流水线的迁移随即批准并同日落地——设计、验证与差异见 [SharedNodeStoreMigration.md](SharedNodeStoreMigration.md)。**
