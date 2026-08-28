# SymbolIndexStore 内存优化专题

日期：2026-08-09（覆盖 2026-07 至 2026-08 的三波优化）；最后更新：2026-08-28（8 月中回填了 0002/0003 落地、262 MB 曲线与 opaque 索引的结构键形态；本日做表述层重写，技术内容不变）

## 导读

这篇文档回答一个问题：`SymbolIndexStore`——RuntimeViewer 浏览二进制时的符号查询底座——的内存占用是怎么从 842 MB 降到 262 MB 的。答案分三波优化：第一波把 demangle 结果从堆上的 class 对象树换成紧凑的连续缓冲存储；第二波把散落各处的小缓存合并、清退；第三波把几十万个驻留的符号名字符串换成「指向原始数据的引用 + 用时再取」。每一波各解决一类浪费，本文逐波讲清它解决什么、付出了什么约束，最后给出实测数字和当前的存储模型全貌。

该读本文的人：想了解 `SymbolIndexStore` 为什么长成今天这样的维护者，以及想沿用同一套方法论治理其它内存大户的人。行文参照上游 swift-demangling 的同类专题 `Documentations/SubtreeInterning.md`——那一篇讲 `Node` 树的全子树 hash-consing（对结构相同的子树只存一份、共享引用），是本文第一波优化的上游地基。

本文会用到一批项目术语：[sweep](../Glossary.md)（对一个镜像全量符号做一遍 demangle 和分类的构建扫描）、[腿](../Glossary.md)（同一逻辑按 reader 类型拆成的两条代码路径，比如「镜像腿」和「文件腿」）、[名字来源](../Glossary.md)（符号名字节实际存放的地方）、[detach](../Glossary.md)（把一个值从共享表上摘下来、换成自带数据的独立副本）、[物化](../Glossary.md)（materialize，从紧凑表示按需重建出完整对象）。首次遇到时正文会给一句解释，完整定义见[术语表](../Glossary.md)。

## 动机：为什么是它

结论先行：`SymbolIndexStore` 的驻留表示直接决定 RuntimeViewer 的稳态内存，而优化前它在三个层面上都在「把便宜的东西复制成贵的」。

它为什么这么关键：RuntimeViewer 每打开一个镜像，就对它做一次 sweep——遍历全量符号表加 export trie（Mach-O 里记录导出符号的前缀树结构），把每个 Swift 符号 demangle 一次，分类装进各查询索引。这份索引是长命的：用户浏览期间它一直在服务查询，不会被释放。所以它内存里长什么样（驻留表示），就是进程稳态内存的大头。

优化前的三层浪费，恰好对应后面的三波优化：

1. **demangle 结果驻留为 class `Node` 树**。每个节点是一个 48 字节的 malloc 对象；更糟的是全局 `NodeCache` 会随浏览无界增长——打开的镜像越多，缓存越大，永不回收。五镜像负载实测：110 万个 `Node` 实例、进程 842 MB。
2. **各级缓存延续了 class 树的持有形态**。`MetadataReaderCache`（metadata 读取层的 demangle 结果缓存）和逐名字新建的 mini `NodeStore` 都还抱着完整的 class 树。第一波迁移完成后，这些缓存里仍残留 18.4 万个 `Node`。
3. **每个符号名驻留为独立的 `String`**：49.4 万个，共 68.7 MiB。而这些名字的原文本来就躺在镜像 mmap 进来的 LINKEDIT 字符串表里。那是 clean 页——内容和磁盘一致、系统可随时回收再按需换入，不计入进程 footprint（物理内存占用）。把它们逐个拷成堆上的 `String`，等于把免费的内存复制成付费的脏页。

## 范围

本文只覆盖 `MachOSymbols` 模块（`SymbolIndexStore` / `SymbolTable` / `DemangledSymbol`）及其直接协作的缓存层。

两条相邻的战线不属于本文：

- `Node` 存储本身的优化在上游 swift-demangling 仓库，见其 `SubtreeInterning.md` 与 evolution 0008（字节扫描器）/ 0010（`SharedNodeStore`，可长期追加的共享节点存储）。
- 声明模型（`TypeDefinition` 等）的驻留优化是本仓库[提案 0002](../Evolutions/0002-declaration-model-descriptor-slimming.md)（让声明对象不再终身持有全量解析的胖 wrapper，已 Implemented）。

## 三波优化

### 第一波：NodeStore 迁移——class 树换 arena 存储（2026-07，Stage 0–5）

**这一波解决的是无界增长**：迁移前后 `Node` 实例从 110 万降到 18.4 万，进程从 842 MB 降到 434 MB，而且全局 `NodeCache` 从此彻底停止随浏览增长。

做法是跟进上游的存储形态更换。上游把 demangle 结果从 class `Node` 树换成了 arena 式的 `NodeStore`：所有节点放进一整块扁平的连续缓冲（每节点 12 字节），外界拿到的不再是对象指针，而是一个「(store, index)」形式的轻量引用 `NodeReference`。本仓库分五个阶段（Stage 0–5）迁移：

- build sweep 改为 cache-free 的 transient demangle：demangle 出一棵瞬时树，分类完就丢弃，需要留存的经 intern（结构去重后存入）进每镜像一个 `NodeStoreBuilder`；
- `Symbol` 表压缩；
- 声明层全面换持 `NodeReference`；
- 其余散点全部改 transient demangling。

**代价是引入了两种相等语义**。`NodeReference` 的固有 `==` 是 store-identity 语义：同一个 store 里的同一个下标才相等。两棵结构完全相同、但存在不同 store 里的树，固有 `==` 判为不等。所以任何键和查询可能来自不同 store 的字典，都必须改用结构语义的包装键 `StructuralNodeReferenceKey`。Stage 5a 的 override/vtable 注释丢失回归就是踩了这个坑——详见 [NodeStoreMigrationPlan.md](NodeStoreMigrationPlan.md)。

### 第二波：小 store 合并与缓存清退（2026-08-08）

**这一波把第一波的残留清干净**，两项收尾：

- **`SharedNodeStore` 汇入**（上游 evolution 0010）。问题：`NodeReference(interning:)` 每处理一个名字就新建一个私有 mini store，五镜像实测攒出 6.7 万个 store，而且跨名字的结构去重被完全切断（每个 store 各存各的，重复子树没法共享）。修法：收敛为按作用域共享的 `InternedNodeReferenceCache`——镜像键作用域随镜像一起驱逐；进程键作用域服务那些没有 Mach-O 上下文的调用方。详见 [SharedNodeStoreMigration.md](SharedNodeStoreMigration.md)。
- **`MetadataReaderCache` 清退**。它的三张缓存字典本来直接持有整棵 class `Node` 树，是残留 `Node` 的最大持有主体。修法：字典值换成 `NodeReference`，树体存进上述作用域 store；公开 API 与 103 处调用点零改动。RuntimeViewer 实景复测：存活 `Node` 从 207,489 降到 **44**（−99.98%）。详见 [MetadataReaderCacheRetirement.md](MetadataReaderCacheRetirement.md)。

### 第三波：符号名 offset 化（2026-08-08，[提案 0001](../Evolutions/0001-symbol-name-offsetization.md)）

**这一波拿掉了当时的头号大户**：前两波完成后做全景剖析，堆里最大的单项是 49.4 万个驻留符号名 `String`。提案 0001 把它们换成「字符串表引用 + 按需物化」——平时只存一个指向原始字节的紧凑引用，真要用名字时再临时构造 `String`。四个组成部分：

- **`SymbolTable`**：每个唯一符号名一行，每行是 16 字节的 `SymbolRow`（canonical offset + `PackedNameReference`，后者是名字位置的打包引用），表里不再驻留任何名字 `String`。名字来源分两条腿：镜像行直指 mmap 的 LINKEDIT 字符串表（零拷贝，但要求镜像保持加载）；文件行和 export-trie 解码出来的名字进表自有的私有连续缓冲。
- **sweep 收集按 reader 分腿**：镜像腿直接在 `nameC` 指针上做字节级的 `isSwiftSymbol` 判定（`nameBytesHaveSwiftManglingPrefix`，与 `String` 版逐条等价、有测试钉住），非 Swift 符号从头到尾不物化任何名字；文件腿保持 `String` 界面。
- **名字查找退役字典、换二分**：build 期的临时去重字典在 freeze（冻结为只读形态）时丢弃；查询改走名字序 permutation（`rowsSortedByName`，一个按名字排序的行号排列）上的字节级二分查找。
- **vend 面按需物化**：`Symbol` / `DemangledSymbol` 的公开形态不变，名字在读取时从表里物化。存进声明模型的长命值仍需 detach——先摘下共享表、换成独立副本，否则一个存活的值就把整张表钉在内存里。`SymbolTableRetentionTests` 钉住全部六个存储点。

实施期与提案有三处偏差：`Span` 家族运行时可用性是 macOS 26+、高于本包部署下限，改用 `UnsafeBufferPointer`；`RigidArray` 借用人体工学不足，改用精确容量的普通 `Array`；若干搭车项被裁剪。全部记录在 0001 的决策日志。

## 今天的存储模型

一个镜像的 `Storage` 冻结后由四部分组成：

1. **`SymbolTable`**：行表 + 双名字来源 + 名字序 permutation（见第三波）。
2. **`rootNodeIndexByTableRow`**：每行符号的 demangle 根节点，以 arena 内 4 字节索引表示。demangler 拒绝过的名字也缓存一个 `nil` 裁决——同一个名字不会被重试第二次。
3. **一组分类索引**：全部以 4 字节 `UInt32` 行号引用符号。桶（一个键对应的多行集合）用的是「单元素内联、多元素才落堆」的 `SymbolRowBucket`——[提案 0003](../Evolutions/0003-symbol-row-bucket-flattening.md) 的产物，因为绝大多数桶只有一个元素，不值得每个都付一次堆分配。其中 opaque 描述符查找自 2026-08-13 起是 `[StructuralNodeReferenceKey: UInt32]` 的单次 hash probe。
4. **late-name 路径的可追加 side store**：服务 sweep 覆盖之外的零星名字（见[术语表](../Glossary.md)「late-name 路径」）。

整个 `Storage` 随镜像驱逐（`removeSubIndexer(_:)`）整体释放。

## 取舍与影响面

这套表示不是免费的，五条约束按代价从「环境假设」到「维护纪律」排列：

- **镜像卸载**：镜像行的名字读取依赖镜像保持加载——`dlclose` 之后 mapped 基址就悬垂了。RuntimeViewer 与系统框架场景从不卸载镜像，所以记为接受项（见 0001「风险与接受的约束」一节）。
- **文件腿的构建期峰值**：build 期去重字典的 `String` 键与私有缓冲，在 freeze 前会短暂持有同一批名字字节两份。实测 maxRSS 增加 15 MiB，freeze 后回落；镜像腿没有这个代价。稳态内存是目标指标，峰值如实记录在案。
- **查询 CPU**：名字查找从字典的 O(1) 变成二分——log₂(19 万) ≈ 18 次字节比较。实测 interface 生成 wall-clock 持平（72.5s vs 70.0s，噪声带内）。若日后 profiling 出热点，退路是加一个字节哈希索引，与现有结构兼容。
- **detach 纪律**：共享表模型把「长命值必须 detach」升格为硬契约。理由：一个不 detach 的存活值会把整张几十万行的表钉住不放。新增存储点忘记 detach 会被 `SymbolTableRetentionTests` 逮住。
- **键语义纪律**：跨 store 的 `NodeReference` 键一律用 `StructuralNodeReferenceKey`；裸 `NodeReference` 键只在单 store 批次内安全（那里结构相等恰好与下标相等重合）。AGENTS.md 的「Symbol indexing」段维护着完整的键位清单。

## 实测收益（RuntimeViewer 五镜像稳态）

下表对比三波优化前后的五项指标。「优化前」一列给两个基线：842 MB 是 NodeStore 迁移前的起点，470–480 MB 是前两波完成、第三波开始前的中间基线。

| 指标 | 优化前 | 三波之后 |
|---|---|---|
| 进程 footprint | 842 MB（NodeStore 迁移前）/ 470–480 MB（第三波前基线） | **322 MB** |
| 存活 `Node`（class 实例） | 1,101,318 | 44 |
| 驻留符号名 `String` | 494,000 个 / 68.7 MiB | 0（StringStorage 全类 784k / 84.2 → 356k / 31.3 MiB） |
| `SymbolIndexStore` 簇 | 214.6 MiB | 120.9 MiB |
| 索引期瞬态峰值 | 893 MB | 808 MB |

两条补充观察：

- 11 小时长跑复核无漂移（堆 285 MiB，对照干净跑的 283 MiB）——没有慢性泄漏。
- 用户观察到的「内存反复飙到 800+ MB 又回落」确认是 sweep 瞬态：28 个并发工人的临时缓冲，sweep 完成即释放，不是泄漏。

**本文完稿后曲线继续下探**：0003（行号桶扁平化，本模块）与相邻战线的 0002（声明模型 descriptor 化）于 2026-08-09 落地，五镜像稳态进一步降至 **262 MB**，索引瞬态峰值从 808 降到 613 MB。全曲线：842 → 470–480 → ~450 → 322（0001）→ **262 MB**（0002+0003）。逐项数字见 ProjectEvolutionLog 第 35/36 节。

## 后续方向（含已落地注记）

- ~~**`[UInt32]` 行号桶扁平化**~~ **已落地（2026-08-09）**：45 万个小数组桶（38.8 MiB）换单元素内联的 `SymbolRowBucket`——[提案 0003](../Evolutions/0003-symbol-row-bucket-flattening.md)（Implemented；RuntimeViewer 复测该簇 38.8 → 7.2 MiB，超预期）。
- ~~**声明模型 descriptor 化**~~ **已落地（2026-08-09）**：相邻的声明模型簇（41.3 + 33.4 MiB）用同一套方法论治理——[提案 0002](../Evolutions/0002-declaration-model-descriptor-slimming.md)（Implemented；与 0003 合计把稳态推到 262 MB，见上表注记）。
- **sweep 限流 / 分批**：用索引速度换瞬态峰值，把 800+ MB 的尖峰摊平。RuntimeViewer 侧候选，未拍板。
- **上游 demangle 字节入口**：sweep 的 demangle 输入目前仍需为每个名字构造一个瞬时 `String`。等上游 swift-demangling 的 demangle-bytes 提案落地后，这里一行替换即可消掉（与 0001 解耦对接；注意 `Span` 家族的部署下限坑）。
