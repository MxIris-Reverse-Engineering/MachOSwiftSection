# NodeStore 迁移计划（SymbolIndexStore → arena 存储）

- **状态**: Draft
- **日期**: 2026-07-24
- **前置**: swift-demangling `feature/node-store` 分支合入 `main`（本包以路径依赖解析 `../swift-demangling` 的 main）
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
