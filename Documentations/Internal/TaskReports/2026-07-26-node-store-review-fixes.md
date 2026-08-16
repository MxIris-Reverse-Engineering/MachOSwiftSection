# NodeStore 迁移分支的代码审查修复

- **日期**: 2026-07-26
- **分支**: `feature/node-store-migration`
- **触发**: 对分支全量 diff 跑代码审查，返回 12 条发现；本次处理其中 9 条，驳回 1 条，
  显式不改 1 条，另 1 条为文档缺口。

## 一、问题

审查最有价值的结论是：**多条发现同源**。`SymbolIndexStore.demangledNodeReference`
命中冻结 arena 的条件里多了一个 offset 判等，导致整条 dyld shared cache 路径退化到
per-symbol mini store；而 mini store 增殖又让下游一批用裸 `NodeReference` 当键的字典/集合
静默失效。修一个条件能同时退掉四条症状。

## 二、调研

逐条回读源码核实，不直接采信 agent 结论：

1. **offset 判等**（`SymbolIndexStore.swift:743`）。建表时 dyld cache 的行存的是
   `rawOffset - sharedRegionStart`（306 行），而 `symbols(for:in:)`（733 行）是拿**查询时
   传入的 offset** 重建 `Symbol` 的。两边 offset 天然不同，判等必然失败。更关键的是这个
   条件**在语义上就是多余的**：demangle 结果只是名字的函数，而 `tableRowByName` 一名一行、
   重名后写覆盖，所以 offset 比较只能否决合法命中，永远无法用来消歧。
2. **跨 store 的裸键**。`DefinitionBuilder` 里 `methodDescriptorLookup` / `vtableOffsetLookup`
   已经是 `StructuralNodeReferenceKey`，紧挨着的 `accessorsByNode` /
   `canonicalIndexByFunctionNode` / `canonicalIndexByAllocatorNode` 却还是裸的；五处
   `visitedNodes` 也是 `OrderedSet<NodeReference>`。这些集合的输入确实混了 store——
   `ExtensionDefinition.swift:115` 就有一条走 `MetadataReader.demangleSymbolReference`
   的分支。规则本身是本分支自己写进 AGENTS.md 的。
3. **dyld cache 选图排序**（`DyldCache+.swift:76`）。上一个 commit 加的排序是**逐 cache 文件
   分别排序、第一个有任何匹配的 cache 直接返回**，跨 cache 不生效——axbundle 在先扫的 cache
   里、framework 在 subcache 里时，依然选中 axbundle，即该 commit 本想修的 bug。
4. **重复入桶**（`SymbolIndexStore.swift:323`）。exported symbol 分支在 raw 与 canonical
   offset 相等时把同一行 append 两次；上面的 nlist 分支有 `hasAdjustedOffset` 守卫，这个
   分支没有。
5. **opaque 描述符查找**（728 行）从 O(1) 字典查退化成全量线性扫 + 逐项结构遍历。
6. **`printSemantic` 重载**：`Node` 的具体重载没有 `StackSafeExecutor` 包裹，而泛型版有；
   具体重载优先级更高，所以 `Node` 调用方实际走的是没有栈保护那条。查上游确认
   `NodePrinter<Target>` 本身就是 `DemanglingPrinter<Target, Node>` 的薄包装，两者输出等价。

## 三、最终方案

- 去掉 offset 判等，改为纯按名字命中；late cache 的键从 `Symbol` 改为 `String`
  （同理：树只取决于名字），并把「查 + 建 + 存」收进同一个临界区。
- `StructuralNodeReferenceKey` 从 `SwiftDeclaration` **下沉到 `MachOSymbols`**——它要服务的
  mini store 就产生在这一层，而 `SwiftDeclaration` 本来就 import 了 `MachOSymbols`。
  下沉后 `MachOSymbols` 内部也能用它。
- 全部跨 store 集合改用该键：`DefinitionBuilder` 三处 + 五处 `visitedNodes`。
- `machOFile(by:)` 改为跨全部 cache 文件累积排名，只在拿到最高排名时早退。
- 入桶改走一个 `registerRow` 局部函数：canonical 与 raw 不同才写第二个键。
  **同一 offset 对应多个符号是正常情形**（名字不同），桶仍是列表，只是同一行不重复入。
- opaque 查找按成员 identifier 分桶（`DemanglingNode.identifier` 对 `Node` 和
  `NodeReference` 是同一份实现，结构相等必然同桶），桶内再做结构比较。
- 删掉 `Node.printSemantic` 具体重载，让 `Node` 走泛型版的栈保护路径。
- `SharedCacheTests` 的协调线程改用**限时**等待，且超时后照样 signal，避免失败时把 8 个
  build 永久钉在 `resolve` 里、把那些 key 永久留在 in-flight 态。

## 四、实际执行中的偏差

1. **驳回一条**：审查建议把 `DemangledSymbol` 的单元素数组换成内联 `Symbol` 的双 case 枚举
   以省掉一次分配，并断言「仍在 32 字节以内」。实测**不成立**——`Symbol` 自身就是 32 字节，
   换枚举后整个值涨到 48 字节，`compactValueLayouts` 直接失败。而经共享表下发的
   `DemangledSymbol` 有数十万份，为省下罕见路径上的一次分配把常见路径每个值撑大 16 字节
   是净亏。已回滚，并把这个取舍写进该初始化器的文档注释，防止下次再被提。
2. **显式不改一条**：`ClassDumper.distributedFunctionNodes` 每个 actor 类算两遍、且每遍要
   materialize 所有 distributed thunk 符号。想清掉需要给一个 `struct`（且要 `Sendable`）
   加可变引用型缓存；而这条路径只在使用 distributed actor 的二进制里执行，本项目日常面对的
   SwiftUI/SwiftData 里是零。另外查询侧（221 行）拿的是 `Node`，集合若改成结构键反而要为
   每个方法 intern 一个 mini store，更差。判断为不值得，保留原样。
3. **SIGSEGV 虚惊**：改完 `Storage` 字段后跑全量测试直接 signal 11。这是 AGENTS.md 已记录的
   已知现象——`MachOSymbols` 的布局变更 SwiftPM 增量构建传播不到位。`swift package clean`
   后全绿。

## 五、验证

- `swift build --build-tests`：0 error。
- `swift test --skip IntegrationTests`：**1273 tests / 244 suites 全部通过**（clean 重建后）。
- 对冻结基线 `main-27726bc` 的三源整文件快照对比**全部逐字节一致**：
  File 38/38、DyldCache 18/18、Image 6/6（共 62 份）。
- **补验 `-n`（按名称选图）路径**：快照 harness 一律用 `-p` 安装路径，而 `-p` 恒为最高排名，
  覆盖不到本次改的跨 cache 累积逻辑。对 iOS 27.0 beta 3 模拟器 cache（即同时存在
  `SwiftUI.framework/SwiftUI` 与 `SwiftUI.axbundle/SwiftUI` 的那个）另跑
  `dump --dyld-shared-cache … -n {SwiftUI, SwiftUICore, SwiftData}`，三者与对应的 `-p`
  输出**逐字节一致**（9,131,212 / 8,191,268 / 271,114 字节）。

## 六、文档同步

- `AGENTS.md`：更新 `demangledNodeReference` 的匹配语义、late store 的加锁语义、
  opaque 查找的分桶，以及 `StructuralNodeReferenceKey` 的新位置与完整适用清单
  （含四种「静默失效」的具体表现）。
- `Documentations/Internal/ProjectEvolutionLog.md`：补上整个 NodeStore 工作弧的第 19 节
  （此前该弧缺账本条目）。
- `Documentations/Internal/NodeStoreMigrationPlan.md`：追加本批次的实施记录。
