# SymbolIndexStore 内存优化专题

日期：2026-08-09（覆盖 2026-07 至 2026-08 的三波优化）；最后更新：2026-08-28（回填 0002/0003 落地、262 MB 曲线与 opaque 索引的结构键形态）

本文是 `SymbolIndexStore` 内存表示演进的专题汇总：三波优化各自解决什么、最终的存储模型长什么样、付出了哪些约束、实测收益多少。行文参照上游 swift-demangling 的同类专题 `Documentations/SubtreeInterning.md`（那篇讲 `Node` 树的全子树 hash-consing，是本文第一波的上游地基）。术语（sweep、腿、名字来源、detach、物化等）首次出现不再逐个展开，见[术语表](../Glossary.md)。

## 动机

`SymbolIndexStore` 是符号查询的底座：RuntimeViewer 每打开一个镜像，就对它做一次 sweep——遍历全量符号表 + export trie，把每个 Swift 符号 demangle 一次并分类进各查询索引。这份索引是长命的（用户浏览期间一直服务查询），所以它的**驻留表示**直接决定 RuntimeViewer 的稳态内存。

优化前的驻留表示在三个层面上都是「把便宜的东西复制成贵的」：

1. demangle 结果驻留为 class `Node` 树——每节点 48 字节 malloc 对象，且全局 `NodeCache` 随浏览无界增长（五镜像负载实测 110 万 `Node`、进程 842 MB）；
2. 各级缓存（`MetadataReaderCache`、逐名字的 mini `NodeStore`）延续 class 树持有形态，迁移后仍残留 18.4 万 `Node`；
3. 每个符号名驻留为独立 `String`（49.4 万个 / 68.7 MiB）——而这些名字的原文本来就躺在镜像 mmap 的 LINKEDIT 字符串表里（clean 页、不计 footprint），eager 拷贝等于把免费页复制成付费脏页。

## 范围

本文只覆盖 `MachOSymbols` 模块（`SymbolIndexStore` / `SymbolTable` / `DemangledSymbol`）及其直接协作的缓存层。两个相邻但不属于本文的战线：`Node` 存储本身的优化在上游 swift-demangling（见其 `SubtreeInterning.md` 与 evolution 0008/0010）；声明模型（`TypeDefinition` 等）的驻留优化是[提案 0002](../Evolutions/0002-declaration-model-descriptor-slimming.md)（Implemented）。

## 三波优化

### 第一波：NodeStore 迁移——class 树换 arena 存储（2026-07，Stage 0–5）

上游把 demangle 结果从 class `Node` 树换成 arena `NodeStore`（12 字节/节点的扁平缓冲 + `(store, index)` 引用），本仓库跟进分五个阶段迁移：build sweep 改为 cache-free 的 transient demangle（瞬时树分类后即弃，intern 进每镜像一个 `NodeStoreBuilder`）；`Symbol` 表压缩；声明层全面换持 `NodeReference`；散点全部改 transient demangling，让全局 `NodeCache` 彻底停止随浏览增长。

这一波真正解决的是**无界增长**：迁移前后 `Node` 实例 110 万 → 18.4 万，进程 842 → 434 MB。代价是引入了 store-identity 与结构相等两种 `NodeReference` 语义，跨 store 键必须走 `StructuralNodeReferenceKey`——Stage 5a 的 override/vtable 注释丢失回归就是这个坑（详见 [NodeStoreMigrationPlan.md](NodeStoreMigrationPlan.md)）。

### 第二波：小 store 合并与缓存清退（2026-08-08）

两项收尾把第一波的残留清干净：

- **`SharedNodeStore` 汇入**（上游 evolution 0010）：`NodeReference(interning:)` 逐名字新建私有 mini store 的形态（6.7 万个 store、跨名字去重被切断）收敛为按作用域共享的 `InternedNodeReferenceCache`——镜像键作用域随镜像驱逐，进程键作用域服务无 Mach-O 上下文的调用方。见 [SharedNodeStoreMigration.md](SharedNodeStoreMigration.md)。
- **`MetadataReaderCache` 清退**：三张缓存字典从持有 class `Node` 树改持 `NodeReference`（存进上述作用域 store），公开 API 与 103 处调用点零改动。RuntimeViewer 实景存活 `Node` 207,489 → **44**（−99.98%）。见 [MetadataReaderCacheRetirement.md](MetadataReaderCacheRetirement.md)。

### 第三波：符号名 offset 化（2026-08-08，[提案 0001](../Evolutions/0001-symbol-name-offsetization.md)）

第一、二波之后的全景剖析把头号大户定位到 49.4 万个驻留符号名 `String`。0001 把它们换成字符串表引用、按需物化：

- **`SymbolTable`**：每个唯一符号名一行 16 字节 `SymbolRow`（canonical offset + `PackedNameReference`），不再驻留任何名字 `String`。名字来源分两腿——镜像行直指 mmap 的 LINKEDIT 字符串表（零拷贝，要求镜像保持加载），文件行与 export-trie 名进表自有的私有连续缓冲。
- **sweep 收集按 reader 分腿**：镜像腿在 `nameC` 指针上做字节级 `isSwiftSymbol` 判定（`nameBytesHaveSwiftManglingPrefix`，与 `String` 版逐条等价、测试钉住），非 Swift 符号从头到尾不物化名字；文件腿保持 `String` 面。
- **名字查找退役字典换二分**：build 期临时去重字典 freeze 时丢弃，查询走名字序 permutation（`rowsSortedByName`）上的字节级二分。
- **vend 面按需物化**：`Symbol` / `DemangledSymbol` 的公开形态不变，名字在读取时从表物化；存进声明模型的长命值仍需 detach（`SymbolTableRetentionTests` 钉住六个存储点）。

实施期的三处偏差（`Span` 家族运行时可用性 macOS 26+ 改用 `UnsafeBufferPointer`、`RigidArray` 借用人体工学不足改精确容量 `Array`、搭车项裁剪）全部记录在 0001 决策日志。

## 今天的存储模型

一个镜像的 `Storage` 冻结后由这些部分组成：`SymbolTable`（行 + 双名字来源 + 名字序 permutation）；`rootNodeIndexByTableRow`（每行的 demangle 根节点，arena 内 4 字节索引，`nil` 裁决也缓存——demangler 拒绝过的名字不再重试）；一组分类索引（全部以 4 字节 `UInt32` 行号引用符号，桶是「单元素内联、多元素才落堆」的 `SymbolRowBucket`——[提案 0003](../Evolutions/0003-symbol-row-bucket-flattening.md)，其中 opaque 描述符查找为 `[StructuralNodeReferenceKey: UInt32]` 的单次 hash probe，2026-08-13 起）；late-name 路径的可追加 side store 服务 sweep 之外的零星名字。整个 `Storage` 随镜像驱逐（`removeSubIndexer(_:)`）整体释放。

## 取舍与影响面

- **镜像卸载**：镜像行的名字读取依赖镜像保持加载——`dlclose` 后 mapped 基址悬垂。RuntimeViewer 与系统框架场景从不卸载，记为接受项（0001「风险与接受的约束」）。
- **文件腿构建期峰值**：build 期去重字典的 `String` 键与私有缓冲在 freeze 前短暂持有同一批名字字节两份，实测 maxRSS +15 MiB，freeze 后回落；镜像腿无此代价。稳态是目标指标，峰值记录在案。
- **查询 CPU**：名字查找从字典 O(1) 变二分 log₂(19 万) ≈ 18 次字节比较，实测 interface 生成 wall-clock 持平（72.5s vs 70.0s，噪声带内）。若日后 profiling 出热点，退路是字节哈希索引（结构兼容）。
- **detach 纪律**：共享表模型把「长命值必须 detach」升格为硬契约，新增存储点忘记 detach 会被 `SymbolTableRetentionTests` 逮住。
- **键语义纪律**：跨 store 的 `NodeReference` 键一律 `StructuralNodeReferenceKey`，裸键只在单 store 批次内安全——AGENTS.md「Symbol indexing」段维护着键位清单。

## 实测收益（RuntimeViewer 五镜像稳态）

| 指标 | 优化前 | 三波之后 |
|---|---|---|
| 进程 footprint | 842 MB（NodeStore 迁移前）/ 470–480 MB（第三波前基线） | **322 MB** |
| 存活 `Node`（class 实例） | 1,101,318 | 44 |
| 驻留符号名 `String` | 494,000 个 / 68.7 MiB | 0（StringStorage 全类 784k / 84.2 → 356k / 31.3 MiB） |
| `SymbolIndexStore` 簇 | 214.6 MiB | 120.9 MiB |
| 索引期瞬态峰值 | 893 MB | 808 MB |

11 小时长跑复核无漂移（堆 285 vs 干净跑 283 MiB）；用户观察到的「反复飙 800+ MB 后回落」确认为 sweep 瞬态（28 并发工人的临时缓冲，完即释放），非泄漏。

本文完稿后，0003（行号桶扁平化，本模块）与相邻战线的 0002（声明模型 descriptor 化）于 2026-08-09 落地，五镜像稳态进一步降至 **262 MB**、索引瞬态峰值 808 → 613 MB——全曲线 842 → 470–480 → ~450 → 322（0001）→ **262 MB**（0002+0003）。逐项数字见 ProjectEvolutionLog 第 35/36 节。

## 后续可选方向

- ~~**`[UInt32]` 行号桶扁平化**~~ **已落地（2026-08-09）**：45 万个小数组桶（38.8 MiB）换单元素内联的 `SymbolRowBucket`——[提案 0003](../Evolutions/0003-symbol-row-bucket-flattening.md)（Implemented；RV 复测 38.8 → 7.2 MiB，超预期）。
- ~~**声明模型 descriptor 化**~~ **已落地（2026-08-09）**：相邻簇（41.3 + 33.4 MiB）的同方法论治理——[提案 0002](../Evolutions/0002-declaration-model-descriptor-slimming.md)（Implemented；与 0003 合计把稳态推到 262 MB，见上表注记）。
- **sweep 限流 / 分批**：用索引速度换瞬态峰值（800+ MB 尖峰摊平），RuntimeViewer 侧候选、未拍板。
- **上游 demangle 字节入口**：sweep 的 demangle 输入仍需一个瞬时 `String`，等上游 swift-demangling 的 demangle-bytes 提案落地后一行替换（与 0001 解耦对接，注意 `Span` 家族的部署下限坑）。
