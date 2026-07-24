# NodeStore 迁移计划（SymbolIndexStore → arena 存储）

- **状态**: Stage 0–4 Completed（见「实施记录」）；Stage 5 提案待批准（见文末「Stage 5 提案」）
- **日期**: 2026-07-24
- **最后更新**: 2026-07-24
- **分支**: `feature/node-store-migration`（worktree `.claude/worktrees/node-store-migration`，Demangling 经主检出 `.claude/worktrees/swift-demangling` 处的**真实 git worktree**（swift-demangling `feature/node-store`）以路径依赖解析——原先的符号链接方案因目标 worktree 被外部清理导致 SwiftPM manifest 缓存把解析钉回 remote，已改为本仓库领地内的 worktree）
- **前置**: swift-demangling `feature/node-store` 分支合入 `main`（本包以路径依赖解析 `../swift-demangling` 的 main）；开发期先经上述符号链接直连该分支
- **上游依据**: swift-demangling `evolution/0001-node-store-arena.md`（Phase 1–3 已落地并验收）

## 背景与动机

RuntimeViewer 与 MachOSwiftSection 的内存主项在 `MachOSymbols/SymbolIndexStore.swift`。对其 `Storage` 的解剖显示占用分两类：

1. **Node 树驻留（主项之一）**：`demangledNodeBySymbol: [Symbol: Node]` 持有每个符号的完整 class 树；各索引字典里的 `DemangledSymbol.demangledNode` 是同一批根引用。以 interned class 形态计，量级为唯一子树集 × 48B/节点（上游实测 12.9 MB / 49k 符号档）。更severe的是**生命周期**：`demangleAsNode` 默认全树 interning，规范节点永驻全局 `NodeCache.shared`——`SharedCache` 淘汰某镜像的 `Storage` 后内存并不归还，除非全局 `clear()`（粗粒度，殃及所有镜像）。
2. **Symbol/字符串/索引结构（另一主项，本次 Stage 3 处理）**：mangled name `String`、`nlist` existential（~40B 容器/份）、`symbolsByOffset` 每符号双条目、`DemangledSymbol` 在多个索引中的复本。

上游 swift-demangling 已交付（proposal 0001）：

- `NodeStore` / `NodeStoreBuilder`（12B/节点 arena、hash-consing、open-addressing intern 表、**cache-free** 批量 `demangle(_:)`——不再向全局 `NodeCache` 泄漏任何东西）；
- `NodeReference`（16B 值句柄，O(1) `==`/`hash`）：`kind`/`text`/`index`/`children`/`Sequence`(preorder)/`first(of:)`/`identifier`/`textUTF8` 全部镜像 `Node`；
- 零物化消费：`reference.print(using:)`（与 Node 路径逐字节一致）、`TypeDecoder.decodeMangledType(node: NodeReference)`；
- 桥接消费：`mangleAsString(some DemanglingNode)`、`materialize()`（按索引 memo，保留 DAG 共享）；
- `builder.intern(kind:children:)` 等直接构造 API（wrapper 节点不再绕道 `Node`）；
- `@_spi(Internals)`：`DemanglingPrinter`（自定义富 target 直印 store）与 `StackSafeExecutor`。

上游 Phase 3 验收（本机 dyld cache SwiftUI 语料 234,232 符号，debug）：619,688 唯一节点 → 8.75 MB 平铺存储（14.1 B/节点）；store 构建 25.3s **快于** interning Node 路径 28.5s；构建期 footprint 增量 ≈ 留存 + ~1 MB 瞬态。

**目标**：Node 树驻留项 ~4× 压缩且按镜像整体回收；全局 `NodeCache` 增长归零；`Storage` 构建高水位消除；Stage 3 后 Symbol 侧复本收敛。

## 分期

### Stage 0 — 基线量化（半天）

在 `SymbolIndexStore.buildStorage` 前后埋点采集 per-image 指标并留档：`phys_footprint` 增量、`NodeCache.shared.count/subtreeCount` 增量、构建耗时、各索引条目数。作为 Stage 1/3 的对照基线，也决定 Stage 3 的优先级。

### Stage 1 — `SymbolIndexStore.Storage` 核心迁移（主体工作）

1. `Storage` 每 MachO 持有一个冻结的 `nodeStore: NodeStore`。
2. `DemangledSymbol.demangledNode: Node` → `NodeReference`（包内 API；`@_spi(ForSymbolViewer)` 消费者 RuntimeViewer 需同步适配，见「影响面」）。
3. `demangledNodeBySymbol: [Symbol: Node]` → `[Symbol: NodeReference]`。
4. `MemberSymbols` 内层 `OrderedDictionary<Node, [IndexedSymbol]>` 与 `opaqueTypeDescriptorSymbolByNode` 的键 → `NodeReference`：结构哈希 O(树) 变 O(1)（store 内索引相等 ⇔ 结构相等），构建与查询双收益。
5. typeNode 构造：`Node.create(kind: .type, child: node)` + `print` → `builder.intern(kind: .type, children: [contextIndex])` + `reference.print(using: .interfaceTypeBuilderOnly)`（零物化，输出逐字节一致已由上游验证）。
6. **构建管线换形**：现在是 `concurrentMap { demangleAsNode }` 全量并发——所有 class 树同时驻留且全部进全局 NodeCache。改为逐符号 `builder.demangle(symbol.name)`（cache-free）后立刻索引。上游实测单线程 store 构建已快于并发前的单路径基线；builder 是单写者 `~Copyable`，如实测吞吐不足再评估分块并行 + 合并（目前上游无跨 store 合并 API，列为 open question，不阻塞本期）。
7. 索引期的只读分类（`processMemberSymbol`/`processThunkAttributeSymbol`/`isGlobal`/`identifier`）直接在 `NodeReference` 上进行——所需成员均已镜像。`MachOSymbols` 内 `Node` 扩展（`isGlobal`/`isAccessor`/`hasAccessor`）改写为 `DemanglingNode` 泛型扩展。
8. `demangledNode(for:)` 的迟到符号回退路径（store 冻结后不可插入）：保留小型 side cache `[Symbol: Node]`（罕见路径，用 `internsSubtrees: false` 且量小）。

**验收**：现有 `SymbolIndexStoreTests` + 快照测试全绿；Stage 0 指标对比达到 Node 树项 ~4× 与 NodeCache 零增长。

### Stage 2 — 消费端（先用默认策略，按需再深化）

- **默认策略：按需物化**。UI 是「点开一个符号渲染一个」：`reference.materialize()`（保共享）喂现有 `NodePrintable` 栈 / `printSemantic`，SemanticString 的 context、type-reference scope、delegate 全保真。瞬态成本毫秒级以下，驻留收益不受影响。**Stage 2 只改取数处的一行调用**。
- 列表行 / 搜索预览等纯文本场景：`reference.print(using:)` 零物化直出。
- `TypeDecoder` 消费者（SwiftSpecialization、StaticTypeLayoutResolver）：换用 `decodeMangledType(node: NodeReference)` 即可；ABIKey / ABIDiffing 的 remangle 用 `mangleAsString(reference)`（物化桥，瞬态）。
- **可选 Stage 2b（仅当全库批量渲染 interface 成为瓶颈，如 swift-section `InterfaceCommand`）**：`NodePrintable` 协议栈泛型化到 `DemanglingNode`（机械 `Node` → `SomeNode`；`printCache` 键换 `PrintCacheIdentity`；`pushTypeReferenceScope` 内的 remangle 已有泛型入口）。注意 store 路径下上游引擎的 scope hooks 收到 nil（类型跳转标识降级）——做 2b 前需先在 swift-demangling 侧把 hook 参数抽象过 `DemanglingNode`，届时以小提案跟进。

### Stage 3 — Symbol 表压缩（store 不覆盖的第二主项）

1. 单一平铺 `symbols: [Symbol]` 表，各索引与 `symbolsByOffset` 存 `UInt32` 表索引；双 offset 键指向同一条目（消除每符号双份 `Symbol` 复本）。
2. `nlist: (any NlistProtocol)?` existential → 压缩为实际消费的少数字段（或索引期即弃）。
3. `DemangledSymbol` 收敛为 `(symbolTableIndex: UInt32, node: NodeReference)` 量级的紧凑值。

### Stage 4 — 验收与文档

- Stage 0 同口径复测，逐镜像记录 before/after；
- `MachOFixtureSupport` 快照（interface 输出）逐字节不变；
- 更新本文档状态与实测数据，必要时同步 `AGENTS.md`/`CLAUDE.md` 的架构描述。

## 影响面

- `MachOSymbols`（核心）、`SwiftInterface` / `SwiftPrinting` / `SwiftDeclarationRendering`（取数处）、`SwiftSpecialization` / `SwiftLayout` / `SwiftDiffing`（TypeDecoder/remangle 调用点）；
- **RuntimeViewer**：经 `@_spi(ForSymbolViewer)` 消费 `DemangledSymbol` 的部分需同步适配（字段类型 `Node` → `NodeReference`，按需 `materialize()`）；
- 受影响模块需 `import Demangling`（公共面即可），仅富 target 直印才需要 `@_spi(Internals) import Demangling`。

## 风险与缓解

| 风险 | 缓解 |
|---|---|
| store 冻结后不可增量插入，迟到符号无处放 | side cache `[Symbol: Node]`（罕见路径）；如未来需要增量，评估 per-image 重建或上游多 store 合并 |
| `DemangledSymbol` 字段类型变更破坏 RV | 同一批次修改两仓；必要时短期提供 `demangledNode` 的物化兼容属性过渡 |
| 单写者 builder 限制并行构建吞吐 | 上游实测单线程已快于旧基线；不足再做分块 + 合并（open question） |
| SemanticString 零物化直印的 scope 降级 | Stage 2 默认按需物化（全保真）；2b 前先抽象上游 scope hooks |

## Non-Goals（本计划不做）

- 上游 `Remangler` 的无构造泛型引擎（上游已决策保持 Node 引擎 + 物化桥）；
- store 序列化 / mmap 符号数据库（proposal 0001 Phase 4，另行立项）；
- `NodeCache` 本身的行为变更（迁移后其增长压力自然消失）。

## 实施记录

### Stage 0 — 基线（2026-07-24，本机 SwiftUI image，debug 构建，`SymbolIndexStoreBaselineTests`）

| 指标 | 旧管线（main @ 7f7fe48） |
|---|---|
| 构建耗时 | 28.6s（独占）/ 36.2s（并行负载下） |
| 构建期 `phys_footprint` 增量 | 266–272 MB |
| 释放 `Storage` + `malloc_zone_pressure_relief` 后 | 残留 ~92 MB（回收 180 MB / 272 MB） |
| `NodeCache` 增长 | +19,345 叶、+559,976 子树——**进程级永驻，跨镜像累积，无法随镜像淘汰回收** |
| 索引条目 | demangled 202,603；member 17,049；methodDescriptor 2,209；global 82；offset 表 170,919；opaque 2,115；typeInfo 4,191 |

### Stage 1 + Stage 2（消费端）落地（2026-07-24，同口径复测）

| 指标 | 迁移后（NodeStore） | 对比 |
|---|---|---|
| 构建耗时 | 30.7s（并行负载下） | **快于同负载旧管线 36.2s（-15%）**，独占口径 +8%（28.6 → 31.0s），远优于 <2× 预算 |
| 构建期 `phys_footprint` 增量 | 302 MB | +30 MB（pending→populate 转换期两套索引共存的瞬态峰值，Stage 3 可收） |
| 释放 `Storage` 后 | 残留 ~66 MB（回收 236 MB / 302 MB） | **稳态残留低 26 MB，且残留全为 malloc 未归还页——无任何逻辑驻留** |
| `NodeCache` 增长 | **0 叶、0 子树** | 泄漏归零；`Storage` 释放即整镜像回收 |
| `NodeStore` 本体 | 7 MB / 579,291 唯一节点（12.7 B/节点） | 对比旧版 interned class 树 ~12.9 MB + 全局缓存表 |
| 索引条目 | 与基线逐项一致 | 语义保真 |

### 实施要点（与原方案的偏差）

1. **分类跑在瞬态树上，而非 `NodeReference` 上**：`NodeStoreBuilder` 无读访问且 `freeze()` 后不可再 intern（typeNode wrapper 必须在构建期造），故构建循环为「`demangleAsNodeTransient`（`@_spi(Internals)` 新导出）→ 分类逻辑在瞬态 `Node` 树上原样运行 → `builder.intern` 入 arena」；索引先以 `NodeIndex` 形态收集（`PendingStorage`），`freeze()` 后一次性转换为 `NodeReference` 形态（`Storage.populate`）。分类代码（`processMemberSymbol` 族）几乎零改动。
2. **查询 API 公共签名保持 `Node` 入参**：`memberSymbols(of:for:node:)` / `opaqueTypeDescriptorSymbol(for:)` 的实参来自 MetadataReader 的 canonical 树（Explore 调用点审计确认），键则是 store 内 `NodeReference`。上游新增 `NodeReference.structurallyEquals(_ node: Node)`（零物化跨表示结构相等，text 走字节比较 + String 兜底），查询在 name 桶内线性匹配（桶内键极少）。
3. **迟到符号统一收敛为 `NodeReference`**：冻结 store 不可插入，迟到符号（build 扫描外，如 resilient witness 的显式 requirement symbol）经 per-symbol mini `NodeStoreBuilder` demangle+freeze，late cache 存 `[Symbol: NodeReference]`；`demangledNode(for:)` 保持 `Node?` 返回（materialize 桥），十余个下游调用点零改动，新增 `demangledNodeReference(for:)` / `MetadataReader.demangleSymbolReference` 供 matcher 零物化路径。
4. **消费端（原 Stage 2 主体已一并落地）**：matchers（Override/Protocol/Extension/ProtocolConformance）切 `demangleSymbolReference` + `OrderedSet<NodeReference>`（visited 集 O(1) 哈希）；`DefinitionBuilder` 的 dedup / methodDescriptor / vtable lookup 键换 `NodeReference`（hash-consing 令键比较 O(树) → O(1)）；renderer 边界（`demangleResolver.resolve`、`Definition` 模型 `node` 字段、`ExtensionName`）按计划物化。`isGlobal`/`isAccessor`/`hasAccessor`/`accessorKind`/`isStoredVariable` 泛型化到 `DemanglingNode`（`where Self: Sequence<Self>`）。
5. **上游配套（swift-demangling `feature/node-store`）**：`@_spi(Internals) demangleAsNodeTransient`、`NodeReference.structurallyEquals(_:)`（+3 测试）、`NodeReference: CustomStringConvertible`（物化桥，调试用）、`isKind(of:)` / `children.second` 上收到 `DemanglingNode` 协议扩展（删除 `Node` 具体副本）。
6. **已知残留（Stage 3 候选）**：构建瞬态峰值 +30 MB（pending/最终两套索引在转换期共存，可改为逐字典迁移消峰）；`symbolsByOffset` / `Symbol` 复本压缩即原 Stage 3 范围。
7. **测试环境备注**：`SwiftInterfaceBuilderTests` / `SwiftDiffableInterfaceBuilderTests` / `XcodeMachOFileDumpTests` 依赖本机 Xcode fixture glob（`XcodeMachOFileName.swift:456`），在未改动的 main 上同样 fatal——预先存在的环境问题，与迁移无关，验收时以 `--skip` 排除。

### 验收与测试策略调整（2026-07-24）

按用户决定，`IntegrationTests` 整体退出验收路径（其中依赖 `/Applications/Xcode-26.4.0.app` 硬编码路径的三个 suite 在本机因 Xcode 已升级至 26.5.0 而 glob 失败并 `fatalError` 崩进程——该问题在未改动的 main 上同样存在，属测试基建债，不在本迁移范围内修复）。验收改为「快照对比 + fixture 单元测试」：

1. **快照以 main 为基准逐字节对比**：先在 main（`7f7fe48`，旧管线）上运行 `SymbolTestsCoreInterfaceSnapshotTests` + `SymbolTestsCoreDumpSnapshotTests`（60 个快照测试）确认已提交基准与 main 输出一致；再在迁移 worktree 上运行同一套快照测试——**60/60 逐字节一致**。fixture 为自建 `SymbolTestsCore.framework`（无外部 Xcode 依赖；worktree 经符号链接复用主检出 `Tests/Projects/SymbolTests/DerivedData` 的构建产物）。
2. **启用 `MachOSymbolsTests` target**（Package.swift 中原已定义但被注释）并新增 `SymbolIndexStoreFixtureTests`（8 个用例）：build 管线 cache-free 不变量（叶身份断言——所有测试 target 共享单进程，全局 `NodeCache` 计数断言天然竞态，改用「transient demangle 两次得到结构相等但 `!==` 的叶实例」这一并发免疫口径；进程级零增长量测留在手动运行的 `SymbolIndexStoreBaselineTests`）、全符号零物化打印与 `demangleAsNode` 管线逐字节对齐、`memberSymbols(of:for:node:)` 对每个 `NodeReference` 键桶经 `structurallyEquals` 命中、`symbols(of:)`/`typeInfo`/`opaqueTypeDescriptorSymbol` 与 storage 桶一致、`demangledNode`/`demangledNodeReference` 互证、迟到符号 mini store 回退与缓存稳定性。
3. **修复 `SharedCache` 并发时序 flake**：`concurrentCallsForDifferentKeysRunInParallel` 原以墙钟阈值断言并行（CPU 饱和即假失败），改为确定性并行证据——所有 build 经信号量互相等待进入闭包，若 resolve 对不同 key 串行（锁跨 build）则死锁，由宽松超时转为失败而非挂死。

### Stage 3 — Symbol 表压缩落地（2026-07-24）

1. **`Symbol` 去掉 `nlist` existential**：`(any NlistProtocol)?` 存储属性（40B existential 容器/份）删除。审计确认其唯一实际消费者是采集期的 undefined-external 过滤（`N_EXT + N_UNDF`），且该过滤发生在 MachOKit 符号上、早于 `Symbol` 构造——存进 `Symbol` 后即为纯死重。压缩为采集期提取的 `isExternal: Bool` 存储位；`Symbol` 显式 `Sendable`，stride 64B → **32B**。公共 init 由 `init(offset:name:nlist:)` 改为 `init(offset:name:isExternal:)`（RuntimeViewer 源码审计确认无 `.nlist` / `DemangledSymbol` 直接消费者，仅经 `.symbol.name` / `.addressString` 取值）。
2. **平铺符号表**：`Storage.symbolTable: [Symbol]` 每唯一符号名一行（存 canonical 即 cache-adjusted 偏移）；`tableRowByName: [String: UInt32]`（键与表行共享字符串存储）；`rootNodeIndexByTableRow: [NodeIndex?]` 平行数组承接原 `demangledNodeBySymbol` 的值侧。全部索引（`symbolRowsByKind` / member×3 / global / opaque / `symbolRowsByOffset`）改存 4B `UInt32` 行号；member/opaque 键从 16B `NodeReference` 改为 4B `NodeStore.NodeIndex`（出口按需 `nodeStore.reference(at:)` 重建）。**双 offset 键共用同一行**——每符号双份 `Symbol` 复本消除；`symbols(for:in:)` 出口按查询键重建 `Symbol(offset: queriedOffset, ...)`，与旧的 per-key 复本语义逐字节一致。
3. **`DemangledSymbol` 压缩为 32B**：`(symbolTable: [Symbol]（共享缓冲，8B 指针）, symbolTableRow: UInt32, demangledNode: NodeReference)`；`symbol` 变为计算属性，`@dynamicMemberLookup` 转发不变。公共 `init(symbol:demangledNode:)` 保留为单行表兼容路径（测试与 `ExtensionDefinition` 的显式构造点）。索引出口从行号现场构造值，原先每条索引条目 ~80B 内联 `Symbol`+`NodeReference` 复本全部消失。
4. **pending→populate 双索引窗口整个消除**：构建期分类索引直接以最终行号形态累积（`RowIndexes`），`freeze()` 后 `Storage.init` 纯移动字典——原 `PendingStorage`→`populate()` 转换pass（Stage 1 记录的 +30 MB 瞬态峰值来源）删除。`Storage` 全部索引字段现为 `let`（仅 late-symbol cache 为 `@Mutex var`）。
5. **`demangledNodeReference(for:)` 查找重写**：从 `[Symbol: NodeReference]` 字典命中改为 `tableRowByName[name]` + canonical offset 校验 + 平行数组取根——与旧 `(offset, name)` 键哈希语义严格等价（offset 不匹配 / demangle 失败仍落 late mini-store 路径）。
6. **测试同步**：`SymbolIndexStoreFixtureTests` 适配行号布局并新增 2 用例——`compactValueLayouts`（`Symbol` / `DemangledSymbol` stride ≤ 32B 的紧凑性不变量）与 `offsetQueriesRebuildSymbolsWithQueriedOffset`（双键共行后出口 offset 重建语义，逐 offset 键对账行数与名称）；`SymbolIndexStoreBaselineTests` 改读新字段并输出 `symbolTable` 行数/stride。
7. **过程备注（环境）**：布局变更后 SwiftPM 增量构建未能把 `MachOSymbols` 的 struct 布局变化传播到全部依赖模块（先是陈旧目标文件的 linker 错，touch 后链接通过但运行期在 `Symbol.init` 内按旧布局 outlined destroy 直接 SIGSEGV）——`swift package clean` 全量重建后消失。此类跨模块布局变更建议直接 clean 构建。

### Stage 4 — 最终验收与复测（2026-07-24，SwiftUI image，debug，独占口径同 Stage 0）

| 指标 | Stage 0 旧管线 | Stage 1+2 | Stage 3 |
|---|---|---|---|
| 构建耗时（独占） | 28.6s | 31.0s | **24.5s（快于旧管线 14%）** |
| 构建期 `phys_footprint` 增量 | 266–272 MB | 302 MB | **68 MB** |
| 释放 `Storage` + pressure relief 后 | 残留 ~92 MB | 残留 ~66 MB | **残留 49 MB**（回收 38 MB / 68 MB 增量） |
| `NodeCache` 增长 | +19,345 叶 / +559,976 子树 | 0 / 0 | 0 / 0 |
| `NodeStore` 本体 | — | 7 MB / 579,291 唯一节点 | 7 MB / 579,291（与 Stage 1 完全一致，语义保真旁证） |
| Symbol 侧驻留 | nlist 盒 + 双份条目 + 索引内联复本（数十 MB 级） | 同旧形态 | `symbolTable` 202,603 行 × 32 B ≈ 6.2 MB + 共享字符串 + 各索引 4B 行号 |
| 索引条目 | 基线 | 逐项一致 | 逐项一致（demangled 202,603；member 17,049；methodDescriptor 2,209；global 82；offset 表 170,919；opaque 2,115；typeInfo 4,191） |

- 构建耗时的下降来自：populate 转换 pass 删除、每符号双份 `Symbol` 构造与 existential 装箱消失、索引累积只搬 4B 行号。
- 构建期增量从 302 MB 收敛到 68 MB：双索引瞬态窗口消除 + Symbol 复本/existential 盒清零是主贡献；残余 68 MB 为 NodeStore + 表 + 索引 + malloc 未归还页。
- 验收测试：`SymbolTestsCore` 快照 60/60 逐字节一致 + `SymbolIndexStoreFixtureTests` 10/10 + `SharedCacheTests` 全绿（**79 tests / 5 suites passed**，Stage 3 代码 + 本地 feature 分支解析口径复跑确认）。

## Stage 5 提案 — 声明层零物化（Definition/富文本打印迁移到 `NodeReference`）

- **状态**: 提案，待批准
- **日期**: 2026-07-24
- **动机**: Stage 0–4 落地后 RuntimeViewer 实测 `Node` 实例 1,091,575 → 336,095、进程内存 628.5 MB → 478.6 MB。布局侧已无肉可挖（实测：`Payload` 枚举 17 B（最大 case 16 B + 判别位无空位可藏）、`kind` 2 B、对象头 16 B → 实例 41 B → malloc 桶 48 B；手工位压缩到 32 B 桶收益仅 ~5.4 MB 且需放弃安全枚举，不做）。剩余 33.6 万实例的**来源**才是下一刀。

### 剩余 `Node` 的来源盘点（2026-07-24 调研）

1. **Definition/Name 值类型长期持有物化树**（主项）：`VariableDefinition.node`、`FunctionDefinition.node`、`SubscriptDefinition.node`、`FieldDefinition.typeNode`、`ExtensionDefinition.genericSignature`、`TypeName.node`、`ProtocolName.node`、`ExtensionName.node`（`DefinitionName` 协议要求 `var node: Node`）。`DefinitionBuilder` 与 `SwiftDeclarationIndexer` 在构建处逐一 `.materialize()`——store 里本来就有的共享子树被展开成独立 class 树，随声明缓存驻留。
2. **仍走 interning `demangleAsNode` 的散点**：`MetadataReader`（symbolic reference 密集）、`RuntimeFieldLayoutBackend`、`TypedDumper`、`ClassHierarchyDumper`、`Symbol.demangledNode`。这些把规范树**永久钉进全局 `NodeCache.shared`**，镜像关闭也不回收。
3. **打印桥接物化**：`SwiftDump` 各 dumper 的 `demangleResolver.resolve(for: node.materialize())`（瞬态，但高频）。

### 前置（5·0）— swift-demangling 侧小改

`DemanglingPrinter` 富 target 走 store 时唯一的语义缺口在 `NodePrinter.swift:198`：`target.pushTypeReferenceScope(name as? Node)` 对 `NodeReference` 恒传 `nil`，富 target 的 type-reference 身份作用域（`SemanticString` 用它 remangle 出 identifier scope）丢失。修法：

- `NodePrinterTarget.pushTypeReferenceScope(_ node: Node?)` → `pushTypeReferenceScope(_ node: @autoclosure () -> Node?)`；引擎侧传 `name.materializedNode`。
- `@autoclosure` 保证 String target（默认空实现，从不求值）**零成本**——现有 store 零物化打印路径不回退；只有 `SemanticString` 实现真正求值，物化只发生在 nominal 引用节点（子树小，且紧接的 `mangleAsString` 本来就要整棵遍历）。
- 协议签名变更破坏外部 conformance：已知 conformance 仅 `SemanticString`（MachOSwiftSection 内，我方可控）与库内默认实现，同步改。
- 守护测试：store 路径 String target 打印全程零 `Node` 分配（现有字节一致快照 + 新增分配哨兵）。

### 5a — SwiftDeclaration 值类型换持 `NodeReference`

- 上列全部 `Node` 存储属性 → `NodeReference`（`DefinitionName` 协议要求同步改）；`OverrideSymbolMatcher` 等取 `typeNode: Node` 参数的内部接口跟随。
- `DefinitionBuilder` / `SwiftDeclarationIndexer` 删除全部构建期 `.materialize()`——sweep 手里本来就是 `NodeReference`。
- `NodeReference` 自带对 `NodeStore` 的强引用（16 B 值：store ref + index），生命周期自洽：声明活着 → store 活着；镜像声明缓存整体淘汰 → store 随之整体回收（正是本计划的回收模型）。
- RuntimeViewer 适配面（feature/node-store-adoption 分支）：`mangleAsString(typeName.node)` 类调用点经既有 `mangleAsString(some DemanglingNode)` 泛型桥**无感**；少数构树点（`wrappedAsType(base.typeName.node)`、`nodesByParameter` 字典等）显式 `.materialize()` 或改存 `NodeReference`。已确认 RV 未使用 `DemangleResolver.builder`。

### 5b — SwiftPrinting 富文本引擎泛型化（工作量主体）

- `NodePrintable` 协议族（`NodePrintable` / `InterfaceNodePrintable` / `TypeNodePrintable` / `FunctionTypeNodePrintable` / `BoundGenericNodePrintable` / `DependentGenericNodePrintable`）+ 4 个具体 printer（Variable/Function/Subscript/Type）：具体 `Node` → `associatedtype SomeNode: DemanglingNode`，模式照抄上游 `DemanglingPrinter` 的泛型化。
- `printCache: [ObjectIdentifier: Target]`（DAG 记忆化）→ 泛型 memo key：SwiftPrinting 本地协议（`Node` → `ObjectIdentifier(self)`；`NodeReference` → 自身，O(1) `Hashable`）。store 里子树共享以共享 index 存在，memo 命中率不变。
- `DemangleResolver` 增加 `resolve(for: some DemanglingNode)`：`.options` 走 `DemanglingPrinter<SemanticString, SomeNode>` 零物化；`.builder` 维持公开的 `(Node) async throws -> SemanticString` 闭包签名、内部 `materializedNode` 桥（公开 API 不破坏，物化只剩这一条路径）。
- `NodeReference.printSemantic(using:)`（经 `@_spi(Internals) DemanglingPrinter`，落在 SwiftDeclarationRendering）。
- `SwiftDump` dumpers：`symbol.demangledNode.materialize()` → 直接传 `NodeReference`。

### 5c — 散点 `demangleAsNode` 去钉扎（`NodeCache` 停止增长）

- 来源盘点第 2 类调用点全部改走 transient 解码（`demangleAsNodeTransient` 已 `@_spi(Internals)` 导出）：树仍是 `Node` 的场合不再钉进全局 cache，随消费方释放。
- 需要长期持有的 metadata 派生树（field type、runtime generic signature 等，不经 symbol store）：`SwiftDeclarationIndexer` 每次索引 pass 维护一个**辅助 `NodeStoreBuilder`**，transient 树经既有 `builder.intern(_ node: Node)` 灌入，pass 结束 `freeze()`，声明持有辅助 store 的 `NodeReference`。辅助 store 与主 symbol store 不共享去重（frozen store 不可再写），文本/子树少量重复可接受（metadata 树规模远小于符号全集）。
- 注意 `NodeStoreBuilder` 是 `~Copyable` 非线程安全：intern 段必须收敛在 indexer 的单线程/单 actor 执行段内（现有 sweep 已满足，需在改动中保持）。

### 验收

- 既有三件套全绿且逐字节一致：`SymbolTestsCore` interface 快照 60/60（该快照走 SwiftInterface → SwiftPrinting 富文本引擎 → 字符串投影，恰好兜住 5b 的文本回归）+ `SymbolIndexStoreFixtureTests` + `SharedCacheTests`。
- **补语义 token 抽查**：字符串投影盖不住 `pushTypeReferenceScope` 的身份作用域（只影响 token 元数据不影响文本）——对若干典型声明断言 `SemanticString` 的 identifier scope 序列与 `Node` 路径一致。
- 同口径内存复测：目标 `Node` 常驻 336k → < 5 万（残余应只剩 `.builder` 桥瞬态与 RV 显式物化点）；`NodeCache` 增长维持 0/0 且**存量不再随浏览增长**；进程 footprint 复测记录。

### 风险与缓解

| 风险 | 缓解 |
|---|---|
| `pushTypeReferenceScope` 签名变更是 swift-demangling 公开协议破坏性改动 | 已知 conformance 全部在我方两仓内；`@autoclosure` 方案在 String 路径零求值，配分配哨兵测试守住零物化不回退 |
| 5b 泛型化触及 ~11 文件的 async mutating printer，回归面大 | interface 快照逐字节兜底 + 语义 token 抽查；分 PR：5·0+5c（小）→ 5a（中）→ 5b（大）→ RV 适配（中），每步独立可验收 |
| `Node` 结构性 `Hashable` 误用作 memo key 导致性能回退 | memo key 协议显式区分：`Node` 用 `ObjectIdentifier`，`NodeReference` 用值本身；review checklist 明确禁止直接 `hash` 泛型节点 |
| 辅助 store 与主 store 文本重复 | 规模评估后可接受；如实测超预期，后续可让 indexer 直接在辅助 builder 上 `demangle(_:)`（省掉 transient `Node` 中转） |
| RV 侧 `typeName.node` 类型变化波及面 | `mangleAsString` 泛型桥无感；其余调用点编译期暴露，逐点 `.materialize()`；RV 在独立 adoption 分支，可整体验证后合入 |

### 预期收益

- `Node` 常驻实例 336k → 数万以内；按 ~70 B/节点全口径（实例 48 B + `.text` String 堆存储 + `manyChildren` 数组缓冲）估算回收 **15–20 MB**，且 `NodeCache` 永久钉扎清零后，长时间浏览不再单调增长。
- 声明持树成本从 48 B/节点 class 树降为辅助/主 store 的 ~12–14 B/节点 arena + 16 B/根句柄。

### Stage 5·0 + 5c + 5a 落地（2026-07-24）

- **5·0（上游）**：`NodePrinterTarget.pushTypeReferenceScope` 改为 `@autoclosure () -> Node?`，引擎侧传 `materializedNode`——String target 从不求值（store 纯文本路径保持零物化），`SemanticString` 惰性求值拿到完整作用域身份。新增 `NodePrinterScopeTests`（双表示作用域序列一致性）。`demangleAsNodeTransient` 增加 `symbolicReferenceResolver` 参数；新增 `@_spi(Internals) Node.createTransient` 工厂族。
- **5c**：`MetadataReader`（28 处 `create` + 5 处解码）、`RuntimeFieldLayoutBackend`、`TypedDumper`、`ClassHierarchyDumper`、`Symbol.demangledNode`、`ResolvedTypeReference+`、`GenericContext+Dump` 的无界构造/解码全部转 transient——`NodeCache` 停止随浏览增长。有界单例（`firstGenericParamType`、AnyObject 约束）保留 interning。
- **5a**：声明层全部换持 `NodeReference`。上游新增 `NodeReference(interning:)`、跨 store `structurallyEquals(_ other: NodeReference)`、`structuralHash(into:)`；`memberSymbols(of:for:node:)` 增加 `NodeReference` 重载。成员定义直持主 store 引用（构建期 4 处 `materialize()` 删除）；extension 成员路径的 `ExtensionName`/`genericSignature` 直用主 store 键（原每键物化删除）；metadata 派生树以 mini store 承接，`TypeDefinition.index(in:)` 的字段树按类型批量共享一个 store。`Name` 类型自定义结构语义 `Hashable` 与 wire 兼容 `Codable`。打印边界暂留 5 处显式 `materialize()` 桥（`SwiftDeclarationPrinter` 3 处 printer 入口 + where 子句 + `leafNameNode`×2），5b 泛型化时消除；`NodeReference.printSemantic`（零物化富文本）已就位并接管 `SwiftDiffableInterfaceRenderer`。
- **验收**：MachOSwiftSection 98 tests / 15 suites 全绿（interface 快照逐字节一致、fixture、diffing、substitution、attribute inference）；swift-demangling 定向 44/7 全绿 + 全量复跑。
- **事故记录 — 测试语料符号无效 + xcsift 假绿**：`DemanglingTests` corpus 中的 `$s7SwiftUI4TextV_10FoundationE9formatterAcA…` 自引入（5788472，NodeStore 之前）就是**无效符号**（系统 `swift-demangle` 同样拒绝，`TextV` 后多一个 `_`），理应一直红。此前未暴露是因为 `swift test 2>&1 | xcsift; echo $?` 捕获的是 **xcsift 的退出码**而非 `swift test` 的，多轮「全绿」不可信。已替换为真实生成的同复杂度符号 `$s11ExampleBase0A4TextV0A6AddonsE9formatter7subjectAcA0A5StyleV_xtcSyRzlufC`（跨模块 extension + `SyRzl` 约束 + `ufC`），并对三个测试文件的全部 mangled 字面量过系统 demangler 校验。**教训：管道给 xcsift 时用 `${pipestatus[1]}` 取真实退出码，或验收时直接看原生输出。**

### Stage 5b 范围调整 — 全量泛型化缩水为 5b-lite（2026-07-24，实施期决策）

原方案把 SwiftPrinting 的异步富文本引擎（`NodePrintable` 协议栈 ~1,600 行）全量泛型化到 `DemanglingNode`。实施 5a 后重估：

- **收益已在 5a 兑现**：原方案预期靠 5b 消除的「打印路径常驻物化」实际上被 5a 的直持 `NodeReference` 消掉了——打印入口的 `materialize()` 只剩**瞬态**分配（单声明签名树、微秒级、打印完即释放），常驻内存零贡献。
- **成本高于预估**：摸底发现引擎内有 5 处「合成 `Node` 再打印」的模式（`.static` 包装、labelList 插入/合成），泛型 `SomeNode` 下无法表达（合成结果是 `Node`，塞不回 `SomeNode` 递归），需要逐处重写为非合成形态，回归面大。
- **5b-lite 实际落地**：`DemanglingNode.printSemantic`（协议扩展，零物化富文本，任意表示）；`DemangleResolver.resolve(for: some DemanglingNode)`（`.options` 零物化直印，`.builder` 保持公开 `Node` 闭包签名、仅该路径物化）；SwiftDump dumpers 的 6 处 `resolve(for: X.materialize())` 直传 `NodeReference`——高频瞬态物化点清零。
- **保留的显式物化桥**（低频/瞬态，全量泛型化的剩余标的，暂不做）：`SwiftDeclarationPrinter` 3 处 printer 入口 + where 子句子节点 + `leafNameNode` ×2 + `SwiftPrinting+Headers`/`ClassDumper` 的 thunk 构树点 + RV 特化构树 2 处。
- **重启条件**：若后续 profiling 显示 interface 全量导出（swift-section `InterfaceCommand` 之类批量场景）的瞬态树分配成为吞吐瓶颈，再按原方案泛型化（届时合成点重写方案：labelList 合成改计数循环，`.static` 包装改 printer 状态位）。
