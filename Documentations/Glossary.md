# 术语表

本项目专有名词与约定用法。

跨项目通用的术语（ABI 与源码兼容性之别、demangle、descriptor 的一般含义、Mach-O、metadata、dyld shared cache 等）收录在全局术语表中，本表只收本项目特有的，不重复登记。全局表不在本仓库内，位于 iCloud Global 镜像的 `Documentations/Glossary.md`。

## 收录范围

**收**：

- 项目自造词与内部代号
- 本项目内反复出现的缩写
- 通用术语在本项目里的**特定含义**
- 容易混淆的近义词对，说明如何区分

**不收**：语言与框架的通用术语（Swift 的 `optional`、`enum` 等）。查官方文档即可，收进来只会稀释真正需要解释的内容。

## 维护约定

提案或专题文章引入新术语时，**同批次**登记进本表。文档里首次出现该术语时展开一次并链到这里，之后不必每篇重复解释。

## 术语

按英文名 / 标识符字母序排列。

### A/B（渲染 A/B 验证）

大重构后的强制验证流程：两个检出（基线 commit 与候选分支）对同一批真实二进制（系统 dyld cache、模拟器 runtime、in-process 镜像）各跑一遍 `dump` + `interface`，输出必须**逐字节一致**。它验证的是「重构没有改变任何输出」，不是「输出是对的」。

- **主要出现在**：`Scripts/run-rendering-ab-verification.py`
- **延伸阅读**：[SystemFrameworkRenderingVerification.md](Internal/SystemFrameworkRenderingVerification.md)

### anchor 协议（anchor protocol）

一条 same-type 约束的 subject 里，关联类型所**限定的声明协议**——`τ_1_0.[Swift.Sequence]Element == [A]` 的 anchor 是 `Swift.Sequence`（mangling 层限定形式，demangle 后保留在 `dependentAssociatedTypeRef` 的第二个 child）。注意 anchor 是 canonicalization 后**继承链最上层的原始声明者**，不一定是源码 sugar 写在哪个协议上（`Collection<[A]>` 的约束 anchor 是 Sequence），也不一定在 opaque 组合成员之内。opaque 尖括号参数的归属裁决以它为第一信号。

- **主要出现在**：`Sources/SwiftInterface/OpaqueSameTypeConstraint.swift`、`SwiftInterfaceBuilderOpaqueTypeProvider`
- **延伸阅读**：[提案 0006](Evolutions/0006-opaque-primary-associated-type-attribution.md)、[OpaqueReturnTypeResolution.md](Internal/OpaqueReturnTypeResolution.md) §2.2

### bucket（桶）

分类索引里「一个键对应的一组符号表行号」（如 `symbolRowsByOffset` 的值、`MemberSymbolRows` 的叶子）。旧形态是 `[UInt32]` 小数组——绝大多数桶只有一个元素，却各付一次堆分配；提案 0003 落地后值形态为 `SymbolRowBucket`（单元素内联于字典槽，第二个元素起才落堆数组），迭代序保持插入序。

- **主要出现在**：`Sources/MachOSymbols/SymbolIndexStore.swift`、`Sources/MachOSymbols/SymbolRowBucket.swift`
- **延伸阅读**：[提案 0003](Evolutions/0003-symbol-row-bucket-flattening.md)
- **延伸阅读**：[提案 0003](Evolutions/0003-symbol-row-bucket-flattening.md)

### detach（脱表，`detachedFromSharedTable()`）

把一个查询期 vend 出来的 `DemangledSymbol` 从共享 `SymbolTable` 上摘下来、换成自带单行表的独立值。共享表对「vend 十万个、随手丢弃」是正确的取舍，但**存进声明模型的长命值必须先 detach**——一个存活值会把整张表（几十万行 + 对镜像映射内存的引用）钉在内存里，让按镜像回收失效。六个存储点由 `SymbolTableRetentionTests` 钉住；查询路径**不要** detach。

- **主要出现在**：`Sources/MachOSymbols/DemangledSymbol.swift`、AGENTS.md「Symbol indexing」段
- **延伸阅读**：[提案 0001](Evolutions/0001-symbol-name-offsetization.md)

### 等价类塌缩（equivalence-class collapse）

Requirement Machine 最小化泛型签名时，把 pin 到同一具体类型的多个关联类型并成一个等价类、只保留 canonical anchor 一条 same-type 约束的行为。后果：源码写了两处 primary sugar（`Collection<[A]> & TestCollection<[A]>`），descriptor 里只剩 anchor 在 Sequence 的一条——`TestCollection` 的 pin **物理上消失**，且与「TestCollection 的同名关联类型根本没被 pin」在二进制里**逐字节同形**，解析端只能按名字推断（见「名字兜底」）。

- **主要出现在**：opaque type descriptor 的 generic requirements；`SwiftInterfaceBuilderOpaqueTypeProvider` 的归属规则 3
- **延伸阅读**：[OpaqueReturnTypeResolution.md](Internal/OpaqueReturnTypeResolution.md) §2.2、[提案 0006](Evolutions/0006-opaque-primary-associated-type-attribution.md)「提议方案」

### emission strategy（发射策略）

diff / evolution 两条对比渲染路共享结构遍历核心（`InterfaceUnionWalker`）之后各自剩下的那一半：遍历器负责**结构**（N 路匹配与并集排序、extension 容器拆分、成员构造、类别调度、body 组合序），策略（`InterfaceUnionEmitting`）负责**呈现**——同一个匹配结果如何变成行（`+`/`-` 标记 vs 生命周期注解）、容器 header 如何裁决（两侧配对 vs 最新可渲染）、容器如何装配。真正语义不同的部分（`HeaderOutcome` 配对、注解锚点、两套格式层）只住在策略里，绝不上浮进遍历器。

- **主要出现在**：`Sources/SwiftInterface/InterfaceUnionWalker.swift`（协议与遍历器）、`SwiftDiffableInterfaceRenderer.swift`（`DiffUnionStrategy`）、`SwiftEvolutionInterfaceRenderer.swift`（evolution 策略）
- **延伸阅读**：[提案 draft-unify-interface-renderers](Evolutions/draft-unify-interface-renderers.md)

### late-name 路径（`lateDemangledNode(forName:)`）

sweep 覆盖范围之外的名字走的旁路：demangle 后 intern 进 `Storage` 自持的一个可追加 side store，名字 → 裁决字典保证一个名字只 demangle 一次（拒绝也缓存为 `nil` 裁决、不再重试）。与主表冻结不可变的性质相对。

- **主要出现在**：`Sources/MachOSymbols/SymbolIndexStore.swift`

### leg（腿，reader-split）

同一逻辑按 reader 类型分出的并行实现路径，口语记作「镜像腿 / 文件腿」：`MachOImage`（进程内映射，符号名可直指 LINKEDIT 字符串表、零拷贝）与 `MachOFile`（离线文件，名字须读进私有缓冲）。0001 的 sweep 收集与名字来源都是按腿分叉的。

- **主要出现在**：`Sources/MachOSymbols/SymbolIndexStore.swift`（`buildStorageSweep`）、`Sources/MachOSymbols/SymbolTable.swift`

### lifecycle annotation（生命周期注解）

演进并集接口里每条「变过的」声明行尾的注释：`// [●●○] removed in 26.0` —— 存在位图（每版本一位，文件头图例映射位置到版本标签）+ 按 ` · ` 连接的事件短语（added / removed / modified in 版本；modified 带 `旧签名 → 新签名`，两侧文本相同时省略箭头段）。**没有注解本身就是信息**：全程存在且从未变化。注解事实唯一来源是 `ABIEvolution` 的 lineage 查表，渲染器不自行推导。

- **主要出现在**：`Sources/SwiftInterface/EvolutionMarking.swift`、`EvolutionAnnotationIndex.swift`
- **延伸阅读**：[提案 draft-swift-evolution-interface-builder](Evolutions/draft-swift-evolution-interface-builder.md)

### materialize（物化）

从轻量引用（表行号、descriptor、`NodeReference`）按需构造出完整值（`String`、wrapper、`Node` 树）的动作，与「驻留」相对。本项目的内存优化主线就是「驻留只留定位信息，重内容用时物化、用完即弃」：0001 物化符号名，0002 物化 wrapper。物化纪律：每处理一个对象至多物化一次、局部贯穿，不做 per-access。

- **延伸阅读**：[提案 0001](Evolutions/0001-symbol-name-offsetization.md)、[提案 0002](Evolutions/0002-declaration-model-descriptor-slimming.md)

### 名字兜底（name fallback）

opaque 尖括号参数归属的第三条规则：协议无任何 anchor 命中时，若它**自身声明**了与约束同名的关联类型、该名字候选约束**恰一条**、且候选的 anchor **不在组合成员之内**，则把参数挂给它——用于恢复被「等价类塌缩」吃掉的 sugar（`TestCollection<[A]>`）。「anchor 在组合外」的限定是防捏造判据：anchor 协议自己在组合里时，其余同名成员写没写 sugar 无从知道（塌缩与未 pin 同形），挂了就是编造。

- **主要出现在**：`SwiftInterfaceBuilderOpaqueTypeProvider.attributedConstraints`
- **延伸阅读**：[提案 0006](Evolutions/0006-opaque-primary-associated-type-attribution.md)「提议方案」规则 3、[OpaqueReturnTypeResolution.md](Internal/OpaqueReturnTypeResolution.md) §3.3

### name source（名字来源）

`SymbolTable` 里一行的名字字节从哪里读：**mapped 字符串表**（`MachOImage` 行直指镜像 mmap 的 LINKEDIT 字符串表，clean 页、零拷贝，代价是要求镜像保持加载）或**私有缓冲**（`MachOFile` 行与 export-trie 解码名，字节存进表自有的连续缓冲）。`PackedNameReference` 用 1 个 bit 区分两者。

- **主要出现在**：`Sources/MachOSymbols/SymbolTable.swift`
- **延伸阅读**：[提案 0001](Evolutions/0001-symbol-name-offsetization.md)

### NodeStore / NodeReference

上游 swift-demangling 的 arena 存储：demangle 结果不再是 class `Node` 树，而是扁平缓冲里的节点（12 字节/节点）加一个 `(store, index)` 引用。本仓库的符号索引、声明模型、各级缓存全部换持 `NodeReference`。注意它的 `Hashable` 是 store 身份语义——见「store-identity vs 结构相等」。

- **主要出现在**：上游 `swift-demangling`；本仓库消费面见 AGENTS.md「Symbol indexing」段
- **延伸阅读**：[NodeStoreMigrationPlan.md](Internal/NodeStoreMigrationPlan.md)

### permutation 二分（permutation binary search）

不给数据本体排序，而是另存一条「按某序排列的下标数组」（permutation），查询时在这条下标序列上二分。`SymbolTable.rowsSortedByName` 即名字序 permutation：行本体保持插入序不动，名字查找二分这条 `[UInt32]`。替代了被退役的名字键字典 `tableRowByName`。

- **主要出现在**：`Sources/MachOSymbols/SymbolTable.swift`（`row(forName:)`）
- **延伸阅读**：[提案 0001](Evolutions/0001-symbol-name-offsetization.md)

### row / `SymbolRow`（行）

`SymbolTable` 的最小单位：每个唯一符号名一行，16 字节（canonical offset + `PackedNameReference`），行号（`UInt32`）是全部分类索引引用符号的方式。「一名一行」意味着按名字查询的语义是纯函数——同名必同行。

- **主要出现在**：`Sources/MachOSymbols/SymbolTable.swift`

### store-identity vs 结构相等（structural equality）

`NodeReference` 的两种相等语义，混用会静默出错：intrinsic `Hashable` 按**store 身份**（同一 store 里的同一下标才相等），跨 store 的结构相同树不相等；**结构相等**（`structurallyEquals` / `StructuralNodeReferenceKey`）逐节点比对，跨 store 成立。规则：键和查询可能来自**不同 store** 的任何 `Dictionary` / `Set` 必须用 `StructuralNodeReferenceKey`，裸 `NodeReference` 键只在单一 hash-consed store 内部安全。踩过的坑：override/vtable 注释丢失、subscript getter/setter 分桶、merged thunk 重复输出。

- **主要出现在**：`Sources/MachOSymbols/StructuralNodeReferenceKey.swift`；键位清单见 AGENTS.md「Symbol indexing」段

### sweep（构建扫描）

对一个镜像的**全量符号一遍扫过**的批处理构建过程：`SymbolIndexStore` 首次索引某镜像时，`buildStorageSweep` 遍历整张符号表 + export trie，收集行、对每个 Swift 符号 demangle 一次、把结果分类进各查询索引——与之相对的是查询期的按需单点操作。RuntimeViewer 语境里「按需索引 sweep」指用户打开某镜像才触发这一遍构建；sweep 期的临时缓冲是瞬态内存峰值的来源（完即释放）。

- **主要出现在**：`Sources/MachOSymbols/SymbolIndexStore.swift`（`buildStorageSweep`）
- **延伸阅读**：[提案 0001](Evolutions/0001-symbol-name-offsetization.md)、[SymbolIndexStoreMemoryOptimization.md](Internal/SymbolIndexStoreMemoryOptimization.md)

### trailing objects

Swift runtime 的 descriptor 布局惯例：固定头之后按 flags 跟着可变数量的附加记录（vtable 方法描述符、resilient witnesses、泛型上下文等），源自 C++ 侧的 `TrailingObjects` 模板。本仓库的高层 wrapper 构造时把它们全部解析成 Swift 数组——0002 要治理的驻留正是这些解析产物。

- **主要出现在**：`Sources/MachOSwiftSection/Models/`（各 wrapper 的 `initialize` 尾部解析）

### union interface（并集接口）

`evolution --interface` 的输出形态：N 个版本所有声明的**并集**只渲染一次的 Swift 接口——每条声明由「最后一个拥有它的版本」的模型与 printer 渲染文本，变化写进生命周期注解，同一成员改签名不裂成多行。与「逐 transition 串联 diff」（同一声明重复出现 N−1 次）和「只渲染最新版 + since 注解」（丢中间版本细节）相对。排序规则：最新版本声明序为脊柱，不在最新版的声明按其最后存在版本的顺序追加。

- **主要出现在**：`Sources/SwiftInterface/SwiftEvolutionInterfaceRenderer.swift`（`matchAcrossVersions`）
- **延伸阅读**：[提案 draft-swift-evolution-interface-builder](Evolutions/draft-swift-evolution-interface-builder.md)

### wrapper vs descriptor（高层包装 vs 描述符）

同一个二进制实体的两级表示，易混淆：**descriptor**（`ClassDescriptor`、`ProtocolConformanceDescriptor` 等）是原始布局 + 位置的薄值（几十字节，可随时重读）；**wrapper**（`Class` / `Struct` / `Enum` / `ProtocolConformance` / `Protocol` / `TypeContextWrapper`）是构造时急切解析全部 trailing objects 的完整值（内联数百字节 + 堆数组）。规则口诀：descriptor 可驻留，wrapper 应物化。

- **主要出现在**：`Sources/MachOSwiftSection/Models/`
- **延伸阅读**：[提案 0002](Evolutions/0002-declaration-model-descriptor-slimming.md)
