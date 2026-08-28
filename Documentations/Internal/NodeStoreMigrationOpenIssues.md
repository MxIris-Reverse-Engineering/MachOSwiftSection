# NodeStore 迁移遗留问题清单

本文记录 `feature/node-store-migration` 分支上**已确认但尚未修复**的问题，供后续按优先级处理。每条注明成因、影响面、以及"该在哪里修"（有几条的正确修复位置在上游 `swift-demangling`，不在本仓库）。

产生方式：2026-07-28 对该分支做了两轮代码审查 + 一轮结论复核。第一轮的复核记录见 [TaskReports/2026-07-28-review-verification-and-fixes.md](TaskReports/2026-07-28-review-verification-and-fixes.md)，其中三条已修（`printSemantic` 换用引擎预算入口、`registerRow` 去重、dyld 缓存镜像选择的 Catalyst 平局与子缓存遍历）；第二轮又指出前述修复自身的两处缺口，已于 2026-07-29 补完，见 [TaskReports/2026-07-29-catalyst-rank-and-row-dedup-followup.md](TaskReports/2026-07-29-catalyst-rank-and-row-dedup-followup.md)。

此后又有两轮独立的审查事件，各自的记录见 [Reviews/2026-07-31-node-store-migration-review.md](Reviews/2026-07-31-node-store-migration-review.md) 与 [Reviews/2026-08-02-node-store-migration-pr97-review.md](Reviews/2026-08-02-node-store-migration-pr97-review.md)。两份审查记录带有本台账没有的**实测数据**与**裁决结论**；本台账与它们冲突时，以审查记录为准，并回头修订本台账（第 3、5、12 条即因此修订过）。

第一节记录那两条已闭环的缺口（保留成因以备回溯）。**第二节起是仍然打开的**，其中已被裁决为"不修"的条目就地标注，不再删除，以便后续审查对照跳过。

---

## 一、上一轮修复自身的缺口（已于 2026-07-29 修复）

这两条是 2026-07-28 那批修复引入或未覆盖的，让已经宣称修好的问题只修了一部分，因此优先处理。两条都已修完并有测试，保留在此以记录成因。

### 1. ~~Catalyst 降级只覆盖了 framework 形态，plain dylib 仍然平局~~ ✅

`DyldCache+.swift` 的 `matchRank` 把 `/System/iOSSupport` 的判断写在了 `<name>.framework` 分支**内部**。一个既不在 `<name>.framework` 下、叶名又以 `.dylib` 结尾的镜像走不到那个判断，于是原生与 Catalyst 两份同名 dylib 双双落在 2 级，胜负重新取决于缓存文件的枚举顺序——正是这次排序机制要根除的那类不确定性。

本机实测存在的碰撞：

```
/System/Library/Frameworks/OpenGL.framework/Versions/A/Libraries/libGLVMPlugin.dylib
/System/iOSSupport/System/Library/Frameworks/OpenGLES.framework/Versions/A/Libraries/libGLVMPlugin.dylib
```

`-n libGLVMPlugin` 对两者都返回 2 级。另有 `/System/iOSSupport/usr/lib/swift/libswift{QuickLook,HomeKit,PencilKit}.dylib` 一组，目前**没有**原生同名物，属于"将来会踩"而非当下已坏。

**修复方式**：拆成两步打分。先按路径形态定基准分（framework 0 / dylib 1 / 其他 2），乘以 `rankStepsPerPathShape`（2）拉开间距；再对 `/System/iOSSupport` 下的**任何形态**统一加 `catalystSupportRootPenalty`（1）。得到的全序是：

| 排名 | 含义 |
| --- | --- |
| 0 | 原生 canonical framework（唯一能拿 `bestMatchRank` 的，提前退出因此仍然成立） |
| 1 | Catalyst framework |
| 2 | 原生 plain dylib |
| 3 | Catalyst plain dylib |
| 4 | 原生 bundle / 其他 |
| 5 | Catalyst bundle / 其他 |

留出间距是关键：惩罚项永远不会把某个形态顶到下一个形态的分位上，所以"降级只是同形态内的平局裁决、不是重新归类"。否则一个没有 Swift 元数据的原生 `.axbundle` 就能压过 Catalyst 的 framework 二进制——那正是整套排序最初要解决的问题。

**新增测试**：`catalystPlainDylibLosesToItsNativeNamesake`、`supportRootPenaltyNeverCrossesAShapeBoundary`。

### 2. ~~`appendRowIfAbsent` 是线性扫描，桶变大就退化成 O(n²)~~ ✅

`registerRow` 的去重改成了 `symbolRowsByOffset[offset]?.contains(row)`，对桶做线性扫描。注释里断言"桶实际上只有一两行"，但没有任何东西保证这一点——不同符号名合法地共享同一地址（桶之所以是数组就是因为这个），而退化偏移（0，或 stripped / dyld 缓存镜像里被大量别名的地址）可以攒到上千行。那样每次登记都是 O(桶大小)，整趟采集变成 O(n²)。

**修复方式**：两个重复成因各自用 O(1) 判据挡掉，完全不扫桶。

- 原始偏移与规范偏移相同 → 比较两个偏移即可（本来就有）。
- 同名同址的两条符号表条目折叠到同一行 → **只有本来就存在的行才可能在桶里**。新行的索引取自 `symbolTable.count`，严格大于此前发出的所有行号，所以任何桶都不可能装着它。于是 `canonicalRow` 改为返回 `(row, isNewRow)`，`registerRow` 只在 `isNewRow == false` 时才检查。

真正会扫桶的只剩"同一个名字重复出现"这一种情况，而重名条目本身就罕见；上千个不同名字堆在同一偏移的退化场景——也就是原本会导致 O(n²) 的那个——现在一次都不扫。导出符号那趟循环有 `tableRowByName[...] == nil` 前置条件，必然是新行，因此彻底不进检查。

---

## 二、公开 API 语义问题

### 3. ~~两个公开查询 API 的字典键从结构相等翻成了身份相等~~ —— 裁决已被推翻，**已修**（2026-08-14）

`memberSymbols(of:excluding:in:)` 与 `allOpaqueTypeDescriptorSymbols(in:)` 原本返回 `OrderedDictionary<Node, …>`。`Node` 的 `==` 是结构相等，所以外部调用方拿任意来源的节点做下标查询都能命中。现在键是 `NodeReference`，其 `==` 为 `store === store && index == index`。调用方用自己 demangle 出来的节点查询会**恒定返回 nil，且没有任何编译错误**。

**裁决：不修。** 依据是 `SymbolIndexStore` 在**类型层面**就是 SPI——`SymbolIndexStore.swift:13-14` 带 `@_spi(ForSymbolViewer)` 与 `@_spi(Internals)`。成员要被访问必须先能命名该类，而命名它必须带对应的 `@_spi(...) import`，所以 SPI 性由类继承而来（逐个方法标注是多余的）。契约既然只对包内与已知 SPI 消费方成立，保证包内正确即可。

包内正确性已核实：

- `memberSymbols(of:excluding:in:)` 包内唯一调用点 `SwiftDeclarationIndexer.swift:663`，在 `:684` 只做 `for (node, memberSymbols) in memberSymbolsByName` 遍历，全程无下标查询；返回字典的键全部出自同一个 `storage.nodeStore`，同 store 内下标相等本就是正确的去重语义。
- `allOpaqueTypeDescriptorSymbols(in:)` 在 `Sources/` 与 `Tests/` 中**零调用点**。
- RuntimeViewer 的 `main` 与 `feature/node-store-adoption` 两条分支均未调用这两个 API。

若将来要重新打开：正确修法是 vend `StructuralNodeReferenceKey`（或 `Node`）作键，或不暴露裸字典而改提供查询方法；修复位置在本仓库 `Sources/MachOSymbols/SymbolIndexStore.swift`。

> **2026-08-14 更新 —— 本条的「不修」裁决已被推翻，两处均已按上述修法改为 `StructuralNodeReferenceKey` 键。** 上面记录的事实（类型级 SPI、包内调用点只遍历、RuntimeViewer 零调用）复核后仍然成立；推翻的理由是同一 bug 类已经真实造成过一次回归（Stage 5a 掉 `override` 关键字与 vtable offset 注释，单条版正是为此改成结构化键，这两个批量版是那次修复漏下的），且修复成本是每处一行。完整裁决见 [`ReviewAdjudications.md` A9](ReviewAdjudications.md)——**该条目是这一裁决的权威记录，本条不再单独维护**。

---

## 三、性能问题

### 4. `structuralHash` 每个文本节点分配一个 `String`

`StructuralNodeReferenceKey.hash` 委托给上游 `NodeReference.structuralHash`，后者对文本节点执行 `hasher.combine(text)`，而 `NodeReference.text` 会走 `NodeStore.text(offset:length:)` → `String(decoding:as:)`——每个标识符/模块节点每次哈希都堆分配一次。迁移前的 `Node` 键组合的是节点里**已经存在**的 `String`。

影响面不小：`TypeName` / `ProtocolName` / `ExtensionName` 是 `SwiftDeclarationIndexer` 里几乎每个索引的键，`DefinitionBuilder` 还会对**整棵符号根节点**每个成员构造两次 `StructuralNodeReferenceKey`。

**正确修法**：改哈希 `textUTF8`（`NodeReference` 上已有，返回 `ArraySlice<UInt8>`，零拷贝）而非 `text`。

**修复位置**：**上游 `swift-demangling`** 的 `Sources/Demangling/Store/NodeReference.swift`，不是本仓库。本仓库这一侧无法绕开。

**上游 `0.5.0` 状态（2026-08-03 核对）：仍然打开。** `structuralHash` 已重写为委托给 `structuralDigest()`——显式帧栈迭代 + 按节点下标记忆化（`digestByIndex`），重复子树只哈希一次，是实打实的改进。但 `nodeContents` 依旧是 `.text(store.text(offset:length:))`，而 `seededDigestHasher` 直接 `hasher.combine(contents)`，所以**每个文本节点仍然分配一个 `String`**。

**终审（2026-08-03，随 0.5.1 升级）：按上游设计关闭，不再等修复。** 上游维护者说明按设计不改（单一编码源换来的跨表示一致性，见 [ReviewAdjudications.md](ReviewAdjudications.md) A2 的两轮事故史）；重开条件只剩 profiling 证据。

### 5. `memberSymbols(of:for:node:)` 改为线性扫描 + 逐候选全树比对（量级可忽略，属可选优化）

迁移前是 `memberSymbolsByKind[$0]?[name]?[node]`，一次字典查找。现在两个重载都走 `rowsByTypeNodeIndex.elements.first(where: { …structurallyEquals(node) })`——对桶里每个键做一次结构化树遍历直到命中。`TypeDefinition.index` 会为 allocator、变量、静态变量、函数、静态函数、下标各调一次。

> **不要把它当回归。** 本条早期措辞称"从 O(1) 退化"，两次审查（2026-07-31 第六节、2026-08-02 第四节）先后纠正过同一处误判，故在此就地写清：
>
> - 迁移前那次字典查找**并不免费**——`swift-demangling` `0.4.5` 的 `Node.hash(into:)` 是 `hasher.combine(children)` 递归，**哈希一次就要走完整棵树**。
> - 桶里装的是"同一类型名下的不同 type node"，实测 6,720 个桶中 **99.60% 只有 1 个元素**，最大 6（`SwiftUI.Coordinator`）。
>
> 所以实际是"一次全树哈希"换成"一次全树结构比对"，量级相当，不存在倍数退化。

**可选优化**：在 `Storage.init` 里一次性建一份 `[StructuralNodeReferenceKey: NodeStore.NodeIndex]` 旁路索引——opaque 查找侧最终就是这么修的（2026-08-13 起为 `opaqueTypeDescriptorSymbolRowByMemberNode: [StructuralNodeReferenceKey: UInt32]` 单次 hash probe）。注意本条早先点名的 `opaqueTypeDescriptorEntriesByMemberIdentifier`（按 `DemanglingNode.identifier` 分桶）是已被裁定不充分并移除的过渡手法——identifier 是成员名，SwiftUI 的 `some View` 实现几乎全叫 `body`，单桶数百项、桶内扫描仍是二次方；照抄它会复现已修掉的问题。收益上限受限于上述实测，排期时不应优先于真正的回归项。

**修复位置**：本仓库 `Sources/MachOSymbols/SymbolIndexStore.swift`。

### 6. ~~build sweep 由并行改为串行，且每个符号都无条件跨线程往返~~ —— 跨线程往返已修 ✅（2026-08-02，本仓库侧）

原来是 `symbolArray.concurrentMap { try? demangleAsNode($0.name) }`，N 路并行。现在是单趟顺序循环，且每次 `demangleAsNodeTransient` 走的是 `StackSafeExecutor.execute`（不是打印/重编码路径用的 `executeWithinStackBudget`）。`buildStorage` 跑在 512 KB 栈的线程上，于是一个框架里几十万个符号，**每一个**都付一次线程池提交 + 信号量等待，而且没有并行来摊薄。

~~**正确修法**：`demangleAsNodeTransient` 应当像打印器那样改用带预算的入口。~~

~~**修复位置**：**上游 `swift-demangling`** 的 `DemangleInterface.swift`。本仓库改不动。~~

**修复（2026-08-02）——「只能上游修」的判断被推翻**：不必动上游入口。`buildStorageImpl` 把整趟 sweep 包进 `StackSafeExecutor.withLargeStack`（函数体移入 `buildStorageSweep`，外层留薄壳）：一次 hop 把整个 sweep 放上 8 MB 栈线程，此后每次 demangle 的栈探测都就地通过，N 次往返变 1 次。`withLargeStack` 的收益是「(批内调用次数 − 1) × 单次跳转成本」，所以必须包住循环——包住单次调用净收益为零。实测（SwiftUI iOS 18.5，10 万符号档）build sweep 1317 → 701 ms（1.88x）。**「串行」半边保持现状**：sweep 仍是单趟顺序循环，未恢复迁移前的 N 路并行——hop 摊销已回收大头，并行恢复无独立立项。记录见 [TaskReports/2026-08-02-review-reproduction-and-retention-fix.md](TaskReports/2026-08-02-review-reproduction-and-retention-fix.md) 与 ProjectEvolutionLog 第 23 节。

### 7. `ABIKey.make` 泛型化后每个 key 都要 materialize 整棵树

`ABIKey.make(for:)` / `makeUnwrappingType(for:)` 泛型化到 `DemanglingNode` 之后，走的是 `mangleAsString` 的 `DemanglingNode` 重载，其实现是 `mangleAsString(node.materializedNode)`。而 `TypeName.node` / `ProtocolName.node` / `FieldDefinition.typeNode` / `FunctionDefinition.node` 现在全是 `NodeReference`，于是构建 `ABISnapshot` 时每个类型、协议、扩展容器、成员、字段的 key 都会重建一整棵类树再丢掉。

**正确修法**：`mangleAsString` 增加一条 store 原生路径（上游），或 `ABIKey` 改成每个声明 materialize 一次而非每个 key 一次（本仓库）。

**修复位置**：上游或本仓库 `Sources/SwiftDiffing/ABIKey.swift`，取决于选哪条路。

**上游 `0.5.0` 状态（2026-08-03 核对）：仍然打开。** `mangleAsString(_ node: some DemanglingNode)` 的实现依旧是 `mangleAsString(node.materializedNode)`（`RemangleInterface.swift:49`）；根治需要 `Remangler` 泛型化到 `DemanglingNode`。本仓库侧每个 key 本来只 materialize 一次，无重复可省。

**终审（2026-08-03，随 0.5.1 升级）：按上游设计关闭。** 0.5.1 保持桥接并在文档注释里写明理由（Remangler 遍历中构造临时辅助节点、非只读消费者，桥接成本瞬态且不触及 store 驻留内存目标）；裁决与复审条件见 [ReviewAdjudications.md](ReviewAdjudications.md) A1。

---

## 四、代码卫生

### 8. `Symbol.isExternal` 在符号表里恒为 `false`

采集局部符号的循环已经用 `where … && !symbol.nlist.isExternal` 过滤掉了外部符号，导出符号循环走默认参数 `isExternal: false`。所以 `symbolTable` 里没有任何一行能是 `true`，`if !symbol.isExternal` 的守卫永远成立、是死代码。而 `Symbol.swift` 的注释声称这个标志是被提取出来供后续查询的，与实际不符。该字段只有在非索引存储的 `Symbol.resolve` 路径（`asCurrentSymbol`）上才可能非 `false`。

过滤和守卫二者必有其一冗余，需要挑一个删掉并修正注释。

### 9. ~~`lateDemangledNode(forName:)` 在持锁期间 demangle~~ ✅ 已修（2026-08-03）

`demangleAsNodeTransient` 会走 `StackSafeExecutor.execute`，在 512 KB 栈线程上无条件提交线程池并 `semaphore.wait()`。于是一次 miss 会**在持有 per-image 互斥锁的情况下**跨线程等待不定时长，该镜像上所有查询晚绑定名字的线程都排在它后面；线程池饱和时持锁时间无上界。

注意这是**刻意的权衡**：代码注释写明查找与插入必须同处一个临界区，否则两个并发 miss 会各自冻结一份 mini store，把同一名字的引用分裂到不同 store 里。所以修的时候要保住这个保证。

**修复（2026-08-03，按上面的修法落地并加固）**：锁外 demangle、锁内 insert-if-absent（后写者丢弃自己的 store、返回胜出者），单 store 保证由 `concurrentLateQueriesShareOneStore` 回归测试钉住。同批一并修了两个相邻问题：(a) **拒绝结果同样缓存**（`nil` 裁决）——demangle 是名字的纯函数，失败一次即永远失败，旧行为「不缓存失败以便重试」只是每次重付一次失败的 demangle（上一轮实测失败名 43.4 ms vs 缓存命中 6.9 ms）；(b) `demangledNodeReference(for:in:)` 对**表内 demangle 失败的名字**直接以 sweep 裁决回答 `nil`，不再穿透到 late 路径在锁内重试（`NodeStoreBuilder.demangle` 就是 `demangleAsNodeTransient` + intern，拒绝集一致，核实于上游源码）。回归测试：`rejectedLateNameCachesItsFailure`（修复前红，断在裁决未被缓存上）、`tableCoveredNameNeverEntersLateCache`。

### 10. ~~`ProtocolConformanceDumper` 里一个分支还在 materialize~~ ✅ 已修（2026-08-03）

同一个 `switch requirement` 块里，`case .element` 和 `Self.demangledSymbol(...)` 都已改走 `MetadataReader.demangleSymbolReference` 留在 store 上，唯独 `case .symbol` 仍调 `MetadataReader.demangleSymbol` 把整棵树 materialize 出来，只为交给 `demangleResolver.resolve(for:)`——而后者现在有 `some DemanglingNode` 重载，可以直接吃引用。既多余，又会让下一个维护者误以为这个不一致是有意的。

**修复（2026-08-03）**：该分支连同 dump 路径其余四处 `demangleSymbol` 调用点（`ClassDumper.validNode` / `ProtocolDumper.validNode` / `ProtocolConformanceDumper._requirementName` / `ClassDumper` override 的 `case .symbol`）一并迁到 `demangleSymbolReference`，visited 集合与 `distributedFunctionNodes` 换 `StructuralNodeReferenceKey` 键（后者顺带省掉每 thunk 一次 materialize）。`MetadataReader.demangleSymbol(for:in:)` 保留 `Node` 契约但包内已无热调用方。快照测试（SwiftDumpTests / SwiftInterfaceTests）逐字节不变。

### 11. 两处 `throws` 是迁移残留

`ExtensionDefinition._symbol(for:typeName:visitedNodes:)` 与 `ProtocolDefinition` 里对应的那个，唯一的抛出调用已被换成不抛出的 `demangleSymbolReference`，函数体里不再有任何 `try`，但签名仍是 `throws`，调用点仍写 `try`。删掉 `throws` 之后，周围 `if let` 链里真正会抛的调用（`resilientWitness.implementationSymbols(in:)`、`Symbols.resolve`）才看得出来。

---

## 五、分支状态

### 12. ~~落后 `main` 五个提交，`AGENTS.md` 两侧都改过~~ —— 前提已过期，但压着两条仍然成立的事项

**过期部分**（2026-07-31 首次指出，2026-08-03 复测确认）：分支现在只落后 `main` 两个提交（`fed0acf` / `f8c6992`），且二者只改动 `.github/workflows/macOS.yml`；以合并基点为准两侧改动文件**零交集**。所述 `AGENTS.md` 冲突不存在——分支的 `AGENTS.md` 已同时包含 `main` 的 `--enum-layout-template` 章节与新的 NodeStore 段落。原"先 rebase 再谈合并"的处理顺序随之作废。

**仍然成立的两条**：

1. **`ProjectEvolutionLog.md` 的小节撞号与死链**（2026-08-28 复测：死链已修，撞号仍在）：`## 20.` 出现两次（「引用存储（weak/unowned）对 existential 的宽度修复」与「注释模板的命令行入口」），第二个 `## 20.` 起后续节号整体偏 1、错位延续至今（文件现已写到 `## 50.`，牵动的交叉引用越攒越多，正名成本随时间上涨）。死链半边已闭环：348 行的链接现指向实际存在的 `TaskReports/2026-07-25-cache-image-selection-and-rv-index-lifecycle.md`。撞号是在本分支内部成型的，与 rebase 无关，**可以先修**（原文"演进日志小节应在 rebase 之后补"的理由已不成立）。
2. **交互从未被跑过**：`main` 的 `TransformerOptionGroup` 与本分支的 `DemangleResolver` / `printSemantic` / `FieldDefinition.typeNode` 改动之间的交互没有任何测试覆盖。这条与 rebase 状态无关，合并前仍需处理。
