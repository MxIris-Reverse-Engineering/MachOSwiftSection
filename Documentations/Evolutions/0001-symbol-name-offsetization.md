# 0001 - SymbolIndexStore 符号名 offset 化：驻留字符串换字符串表引用

- **状态**: Implemented
- **作者**: JH
- **创建日期**: 2026-08-08
- **最后更新**: 2026-08-08
- **所属愿景**: 无
- **关联提案**: 无（本仓库首篇）。跨仓库关联：swift-demangling 0008（字节扫描器）/ 0010（`SharedNodeStore`）为既有地基；其「demangle 入口收 `Span<UInt8>`」新提案与本案解耦对接（见「前期调研 · 上游接口」）
- **实现分支 / PR**: `feature/node-store-migration`
- **配套文档**: 无独立专题文章（收尾判断见决策日志）；维护者事实同步于 AGENTS.md「Symbol indexing」段，过程复盘见 [TaskReports/2026-08-08-symbol-name-offsetization.md](../Internal/TaskReports/2026-08-08-symbol-name-offsetization.md)

## 摘要

`SymbolIndexStore` 的每镜像存储把 49.4 万个符号名以 Swift `String` 驻留（68.7 MiB），而这些名字的原文本就躺在镜像 mmap 的字符串表里（clean 页、不计 footprint）——eager 拷贝等于把免费页复制成付费脏页。本提案把驻留形态换成「字符串表 offset + 按需物化」：行表存 16 字节紧凑行，名字读取经 `Span`/`UTF8Span` 访问层直达映射内存（镜像路径零拷贝零驻留；文件路径收进一次分配的私有连续缓冲），名→行字典整个退役换名字序二分，`isSwiftSymbol` 判定降到字节级让非 Swift 符号零分配。公开 API 与全部调用点零改动，预计拿回 ~70–100 MiB。

## 动机

RuntimeViewer 对 `MetadataReaderCache` 清退后 445 MB 稳态的全景剖析（footprint + vmmap + heap -sortBySize + MallocStackLogging 调用栈归属，五镜像组合：Foundation + libswiftCore + AppKit + SwiftUI + SwiftUICore）：

- 堆内存活 355 MiB 中 **`SymbolIndexStore` ≈ 215 MiB / 96 万分配，单项过半、头号大户**。
- 内部最大单项：**符号名字符串 68.7 MiB / 49.4 万个**——调用栈归属到 `MachOImage.Symbol.name.getter → String.init(cString:)`，`buildStorageSweep` 路径，占全进程 78 万个 StringStorage 的 71%。
- 其余细目：`canonicalRow` 大缓冲 41.8 MiB / 10 个（`symbolTable` 数组与 `tableRowByName` 字典的底层缓冲，5 镜像 × 2，含 `Array` 倍增生长后 freeze 原样驻留的容量冗余）；5 × `Dictionary<String, UInt32>`（`tableRowByName`）~20 MiB；`[MachOSymbols.Symbol]` 数组 24.5 MiB。
- 关键事实：这些名字的原文在镜像 mmap 的 LINKEDIT 字符串表里是 **clean 页**（可随时被系统回收再按需换入，不计入 footprint）；把它们逐个拷成堆上 `String` 的那一刻，免费内存变成了付费脏页。
- 用户指示（2026-08-08，经 swift-demangling 会话转达）：对 `SymbolIndexStore` 做符号名惰性化 / offset 化，方案与审批按本仓库规矩走。

RV 侧估算可作为空间 **~70–100 MiB**（预期堆存活 355 → ~255–285 MiB）。

## 前期调研

### 现状代码怎么走的

- `Sources/MachOSymbols/Symbol.swift:8`：公开值类型 `Symbol { offset: Int, name: String, isExternal: Bool }`，32 字节。
- `Sources/MachOSymbols/SymbolIndexStore.swift:144`：`Storage.symbolTable: [Symbol]`——每唯一符号名一行，name 即驻留 `String`；`:152` `tableRowByName: [String: UInt32]`，键与行表共享字符串存储（行表放掉 `String` 后它就是 68.7 MiB 的唯一持有者）。
- `Sources/MachOSymbols/SymbolIndexStore.swift:453`：sweep 收集循环 `for symbol in machO.symbols where symbol.name.isSwiftSymbol && !symbol.nlist.isExternal`——对**每一个**符号表条目（不分 Swift 与否，一个大框架几十万到上百万个）物化一个 `String` 只为做前缀判定；非 Swift 的当场丢弃，是 78 万 StringStorage 里另外 29% 瞬时 churn 的来源。
- `Sources/MachOSymbols/DemangledSymbol.swift:12`：持 `symbolTable: [Symbol]` + 行号 + `NodeReference`，32 字节预算由 `compactValueLayouts` 钉住；`detachedFromSharedTable()` 拷出单行表供声明模型长期持有（每镜像 ~1 万个）。
- 消费面排查：`storage.symbolTable` 在 `SymbolIndexStore.swift` / `DemangledSymbol.swift` 之外**零消费者**；所有 vend 面（`Symbols`、`symbols(for:in:)`、`DemangledSymbol.symbol`、`Symbol.resolve`）都物化 eager `Symbol` 返回——内部表示可以自由替换，公开 API 不动。

### 上游或依赖是否已具备能力

- **MachOKit（无需改动）**：`MachOImage.Symbol` 本来就带 `nameC: UnsafePointer<CChar>` 直指映射内存中的字符串表（MachOKit `MachOImage+Symbols.swift:13`），`Symbols` / `Symbols64` 序列公开 `stringBase`——镜像路径的 offset 化地基现成。`MachOFile.Symbol` 的名字经 `readString(offset: n_strx)` 按需文件读取，无常驻映射可指。
- **Swift 6.2 语言特性（工具链 6.3.3，全部可用）**：
  - `Span<UInt8>`（SE-0447）：对连续内存的安全非持有视图，裸指针构造的 unsafe 逃生门收敛在构造一行。
  - `UTF8Span`（SE-0464）：`bytesEqual(to:)` 是「精确字节相等」语义（提案明言比 `String.==` 的 Unicode 规范等价**更严**——mangled 名要的恰是字节精确）；`String(copying: UTF8Span)` 按需物化且不重复验证；`init(unsafeAssumingValidUTF8:)` 可对 ASCII 符号名免验证扫描。
  - `~Escapable`（SE-0446）：`Span` 家族不可逃逸——**不能存进 `Storage`**，只能作访问层在作用域内借出。SE-0507（borrow accessors）要 Swift 6.4，工具链未到，故借出形态用闭包式 API 而非 `@_lifetime` 标注属性（下划线属性不进库代码）。
- **swift-collections（实际解析 1.6.0）**：`BasicContainers` 模块的 `RigidArray`（定容、noncopyable，要求 Swift 6.2）已在稳定面——冻结时把累加 `Array` 一次移入定容缓冲，消掉倍增生长的容量冗余与读路径 COW 检查。需给相关 target 补 `BasicContainers` product 依赖并把 `from` 版本提到 1.6.0。

### 验证过什么

- export-trie 的名字（`exportedSymbols` 补录路径，`SymbolIndexStore.swift:463`）是 trie 遍历的**解码产物**，不在字符串表里——不能用 strtab offset 表示，需要溢出缓冲（这决定了行格式带来源位）。
- 全库唯一按 `ObjectIdentifier` 键控符号相关对象的用法已排查：无（`SwiftPrinting` 的 `printCache` 键的是 `Node`，与本案无关）。
- dyld cache 场景的字符串表页驻留形态可能与单镜像 mmap 不同——未实测，标注为**推测**，以 RV 落地后复测为准。

### 上游接口（可选跟进，不是落地前置）

swift-demangling 侧已预告：demangle 入口收字节（`Span<UInt8>`，0008 字节扫描器地基的自然延伸；对面会话当前就在实现 span-borrowed-views）可由他们起草新提案。我方明确**有兴趣但解耦**：本案先以 transient `String` 喂 demangler 落地（footprint 收益完整拿到），字节入口落地后 sweep 的 demangle 调用一行替换——彼时本案的 span 访问层与其入口签名无缝对接（名字字节 `Span` 直接透传），再消掉 Swift 名的瞬时 churn。需要的接口形态：`demangleAsNodeTransient` 的 `Span<UInt8>` 重载即可（late 路径人口小，`SharedNodeStore.demangle` 不必跟）。

## 提议方案

四步一体，全部收在 `MachOSymbols` 模块内部：

1. **行表紧凑化**：`Storage.symbolTable: [Symbol]` 换成 `SymbolTable` final class——`rows: [SymbolRow]`（16 字节/行，今天 32 + 一个 String 分配）+ 名字来源。名字来源两条腿：**镜像**——mapped 字符串表基址（零拷贝、零驻留）；**文件**——sweep 时把 Swift 名字节追加进一次分配的私有连续缓冲（无每对象头开销）。export-trie 溢出名两条腿都进私有缓冲，行内来源位区分——行格式与读取路径全 reader 统一。
2. **名→行字典退役**：`tableRowByName` 整个删除，替换为 `rowsSortedByName: [UInt32]` 名字序 permutation + 二分查找，比较经 `UTF8Span.bytesEqual` 直接对字节、不物化（49 万行 ≈ 3.7 MB vs 今天 ~20 MiB）。build 期仍用临时 `[String: UInt32]` 去重（freeze 时丢弃，只影响构建峰值不影响稳态）。
3. **字节级 `isSwiftSymbol`**：收集循环按 reader 分腿（`ObjCClassIndex` 的既有先例）——镜像腿在 `Span<UInt8>` 上做前缀判定，非 Swift 符号从此一个 `String` 都不建；文件腿沿用 `readString` 并把 Swift 名字节进私有缓冲。demangle/分类循环保持 reader 通用。
4. **vend 面按需物化**：`symbol(atRow:offset:)` / `demangledSymbol(atRow:)` / `detachedFromSharedTable()` 物化时经 `String(copying:)` 从名字来源建 `String`。公开 API 签名与行为不变。

### 非目标

- **44 万个单元素 `[UInt32]` 桶（~28 MiB，`symbolRowsByOffset` 与分类索引）**：正交问题（单元素内联 / CSR 扁平化），另案处理，候选下一篇提案。
- **打印名键控的字典**（`typeInfoByName`、`MemberSymbolRows` 类型名键、thunk 桶）：键是 `NodePrinter` 输出、不是符号表拷贝，人口与本账目无关。sweep 里每成员重复 print 类型名是纯 CPU 项，顺带记录、不在本案。
- **late-name 路径**（`lateNameStore` + 名字 → 裁决字典）：人口是 sweep 外零星查询名，不动。
- **声明模型的 detached symbol 语义**：`SymbolTableRetentionTests` 钉住的六个存储点，形态完全不变（detach 时物化 eager `String`，每镜像 ~1 万个，人口小）。
- **公开 API**：`Symbol` 对外仍是 `{ offset, name: String, isExternal }` 的 eager 值类型。
- **Swift 名 demangle 输入的瞬时 `String`**：等上游字节入口，见「前期调研 · 上游接口」。

## 详细设计

```swift
/// Retained row: 16 bytes. Today's row is a 32-byte `Symbol` plus one
/// retained `String` allocation (~139 bytes average including storage).
struct SymbolRow {
    var canonicalOffset: Int64
    /// Packed: name-source bit (mapped string table / private buffer),
    /// isExternal bit, byte length, and byte offset into the source.
    var packedNameReference: UInt64
}

/// Replaces the bare `[Symbol]`: rows plus the bytes their names point into.
/// `@unchecked Sendable` — all state immutable after freeze.
final class SymbolTable: @unchecked Sendable {
    /// MachOImage: base of the mmap'd LINKEDIT string table (clean pages;
    /// valid while the image stays loaded). `nil` for MachOFile tables.
    let mappedStringTableBase: UnsafeRawPointer?
    /// Swift-name bytes for MachOFile rows and export-trie overflow names —
    /// one contiguous allocation, appended during the sweep.
    let privateNameBuffer: [UInt8]
    let rows: [SymbolRow]
    /// Name-order permutation over `rows` — binary search replaces
    /// `tableRowByName`; comparisons run on bytes via `UTF8Span`.
    let rowsSortedByName: [UInt32]

    /// Scoped byte access (Span is ~Escapable and must not be stored).
    func withNameBytes<Result>(atRow row: UInt32, _ body: (Span<UInt8>) -> Result) -> Result
    func materializedName(atRow row: UInt32) -> String   // String(copying: UTF8Span)
    func row(forName name: String) -> UInt32?            // binary search, bytesEqual
}
```

- `DemangledSymbol`：`[Symbol]` + 行号 → `SymbolTable` 引用 + 行号，32 字节预算不变（8 + 4 + 16 + padding，`compactValueLayouts` 断言同步）。standalone / detached 形态经单行 eager 表达成（实现细节：`SymbolTable` 的 standalone 变体持 `[String]`）。
- 冻结缓冲容器：`rows` / `rowsSortedByName` / `rootNodeIndexByTableRow` freeze 时移入定容 `RigidArray`（或等价的精确容量 `Array` 拷贝），消掉倍增生长冗余。
- 顺带小件（搭车，不单独立项）：`rootNodeIndexByTableRow` 的 `Optional<NodeIndex>`（8 字节）换 `UInt32.max` 哨兵（省一半）；`symbolRowsByOffset` 从 `OrderedDictionary` 换普通 `Dictionary`（只按键查、从不按序遍历）。

### 风险与接受的约束

- **镜像卸载**：`SymbolTable` 持有的 mapped 基址在镜像被 `dlclose` 后悬垂——生命周期约束从「查询时读镜像」扩展到「vend 后物化名字时读镜像」（今天的 eager 拷贝免疫此事）。系统框架与 RV 的索引对象从不卸载；记为接受项。
- **dyld cache 的 MachOFile**：字符串表在 cache 的 LINKEDIT，走文件腿私有缓冲；页驻留形态未实测（见前期调研），RV 复测为最终裁判。
- **查找 CPU**：字典 O(1) → 二分 log₂(19 万) ≈ 18 次字节比较；mangled 名共享长前缀会让比较扫得深一点，对查询路径（含 `demangledOverrideSymbol` 候选探测环）预期足够便宜。若 profiling 显示热点，退路是字节哈希 `[UInt64: UInt32]` 索引（结构兼容，不影响其余部分）。
- **构建峰值**：build 期临时去重字典与今天的 `tableRowByName` 同量级，freeze 后释放。

## 替代方案考量

- **`Symbol.name` 改懒（enum 载荷 / 计算属性带上下文）**：公开值类型的 `Hashable` 语义与 32 字节布局全线波及、103+ 处消费点连锁改动——被否；内部表示换、vend 时物化的方案收益相同且零波及。
- **文件路径保留 eager `String`**：连续缓冲一次分配、只收原始字节（无 String 头与 malloc 桶开销，约省 1/3），且让行格式全 reader 统一——保留 eager 被否。
- **名字查找用字节哈希索引而非二分**：`[UInt64: UInt32]` 约 10–12 MB vs permutation 3.7 MB；二分为主、哈希为实测退路。
- **swift-collections 逐项裁决**（2026-08-08 调研，理由留档免得日后重吵）：`SortedSet` / `SortedDictionary`——`UnstableSortedCollections` trait（非稳定 API），且 B-tree 的强项是增删、我们的索引冻结后只读，平铺二分更优；`UniqueDictionary` / `RigidDictionary` / `UniqueSet`——`UnstableHashedContainers` trait，不进生产；`TrailingArray`——header + 尾随元素单分配对「类 + 两三条平铺数组」是省一两次分配的微优化，换 `ManagedBuffer` 式底层复杂度不值；`InlineArray`（SE-0453）——定长语义与变长桶无交集；`BitSet`——可作 `rootNodeIndexByTableRow` 的 nil 位图，但哨兵值等收益零新依赖；`TreeSet` / `TreeDictionary` / `Heap` / `Deque`——无场景；`Container` 协议族 / `InputSpan`（`UnstableContainersPreview`）——borrowed 遍历的未来方向，关注不构建。
- **给 SymbolIndexStore 造通用 arena 分配器**：被否——本案 + 桶扁平化（另案）落地后分配次数从 96 万降到几千，平铺数组就是 arena 的表达；Swift 集合不支持自定义分配器，手写哈希表换个位数 MiB 不值。

## 影响

### 源码兼容性（source compatibility）

**纯新增 / 无破坏。** 公开与 package 级 API 的签名、语义、返回值形态全部不变：`Symbol`、`Symbols`、`DemangledSymbol.symbol`、`Symbol.resolve`、`SymbolIndexStore` 的全部查询方法照旧。变化仅在 `MachOSymbols` 模块内部的驻留表示与 `Storage` 私有结构。`compactValueLayouts` 与 `SymbolTableRetentionTests` 钉住布局与 detach 契约不回归。

### ABI 兼容性（条件项）

不适用 —— 本库以 SPM 源码分发，使用方每次重新编译（项目类型声明见 `Documentations/README.md`；`Tests/Projects/SymbolTests` 开启 library evolution 是测试工程属性，非本库属性）。

### 下游影响

- 仓库内：`MachOSymbols` 为改动主体；`MachOFoundation` 及以上各层经既有 API 消费，无源码变化。`Package.swift` 给 `MachOSymbols` 补 `BasicContainers` product 依赖（swift-collections 本就在依赖图，`from` 提到 1.6.0）。
- 下游仓库（RuntimeViewer、MachOKitUI、SymbolViewer）：零源码改动，重编译即得内存收益。RV 是本案的验收方（footprint + heap 复测）。

### 文档与示例

- AGENTS.md「Symbol indexing」段同步新驻留模型（`SymbolTable` / span 访问层 / 二分查找 / 镜像卸载约束）。
- `Documentations/README.md` 索引与本提案状态同步。
- 落地时按「落地步骤」收尾判断决定是否另写实现说明。

## API 演进与废弃策略

- 无被替代的公开 API，无废弃标注需求。
- 无 semver major 跃迁：源码兼容的内部表示变更，随下一次常规版本发布（`Version.swift` bump 时在 changelog 记录内存收益）。

## 落地步骤

1. `SymbolRow` / `SymbolTable` / 名字来源 + `DemangledSymbol` 换持（`compactValueLayouts` 同步）——可独立构建。
2. sweep 收集阶段按 reader 分腿：镜像腿字节级 `isSwiftSymbol` + strtab offset 记录；文件腿私有缓冲；export-trie 溢出。
3. `tableRowByName` 退役 → permutation 二分（`UTF8Span.bytesEqual`）；build 期临时去重字典。
4. vend 面按需物化 + 搭车小件（哨兵值、`symbolRowsByOffset` 换普通 `Dictionary`、`RigidArray` 定容冻结）。
5. 新增等价性测试：字节版 `isSwiftSymbol` 对整个真实镜像符号表与 `String` 版逐条一致；二分对每行与旧字典命中一致；detach 物化正确。
6. 全量 `swift test --skip IntegrationTests` 全绿同数；`Scripts/run-rendering-ab-verification.py`（`USING_LOCAL_DEPENDENCIES=1`）三 reader 路径逐字节一致。
7. 性能：索引耗时（`prepare` on SwiftUI，预期**更快**——非 Swift 符号不再建 String）与 interface 生成 wall-clock 持平。
8. RV 复测 footprint + heap（对面协调）：预期堆存活 355 → ~255–285 MiB。
9. 收尾判断（写进决策日志）：是否需要实现说明（镜像卸载约束与名字来源双腿是「代码看不出来的决策」，倾向写）；新术语（「名字来源 / name source」「permutation 二分」等）是否进术语表。

## 落地记录

2026-08-08 实施完成（`feature/node-store-migration` 分支，与本提案同 commit）。

### 实际改动面

- `Sources/MachOSymbols/SymbolTable.swift`（新建）：`SymbolRow`（16 字节，`compactValueLayouts` 断言）、`PackedNameReference`（1 位名字来源 + 1 位 isExternal + 22 位长度 + 40 位偏移）、`SymbolTable`（mapped 基址 / 私有缓冲双名字来源 + `withNameBytes(atRow:)` closure-scoped 字节访问 + `row(forName:)` 字节级二分）、`SymbolTableBuilder`（build 期临时去重字典，freeze 时精确容量拷贝 + permutation 排序）、`compareSymbolNameBytes`（memcmp 序 + 长度 tiebreak）、`nameBytesHaveSwiftManglingPrefix`（字节级前缀判定，逐字节复刻上游 `getManglingPrefixLength` 的前缀集）。
- `SymbolIndexStore.swift`：`Storage.symbolTable` 换持 `SymbolTable`、`tableRowByName` 删除、`symbolRowsByOffset` 换普通 `Dictionary`；sweep 收集按 reader 分腿（镜像腿 `symbols64`/`symbols32` 直迭代取 `nameC`，非 Swift 符号零分配；文件与其它 reader 走原 `String` 面 + 私有缓冲）；demangle/分类循环与查询 API 从表按需物化。
- `DemangledSymbol.swift`：换持 `SymbolTable` 引用 + 行号（32 字节预算不变）；standalone/detached 经单行私有缓冲表；新增 `offset` / `isExternal` / `name` 具体快路径（dynamicMember 路径读 offset 不再整只物化 `Symbol`）。
- 测试：`SymbolTableEquivalenceTests.swift`（新建，镜像腿三项等价）+ fixture 套件文件腿二分/detach 测试 + 三处内部引用适配。
- 文档：AGENTS.md「Symbol indexing」段、本提案、演进日志第 34 节、任务报告，同批落地。

### 验证结果（落地步骤 5–7）

1. **等价性测试**（新增 4 项，全绿）：字节级 `isSwiftSymbol` 与 `String.isSwiftSymbol` 在 Foundation 镜像全符号表逐条一致；mapped 收集与 String 收集全等（行数 + last-wins canonical offset）；二分对每行自洽（镜像腿 + 文件腿）+ 负例；detach 物化正确。
2. **全量套件**：`swift test --skip IntegrationTests` **1341 tests / 256 suites 全绿**（改动前 1337 + 新增 4，同数吻合；快路径补丁后复跑同样全绿）。
3. **渲染 A/B**（`Scripts/run-rendering-ab-verification.py`，baseline `aa91b9b`，双侧 `USING_LOCAL_DEPENDENCIES=1` 且 sibling 均验证为 `fileSystem` 解析）：**96 对全部逐字节一致、0 不一致**（当前系统 dyld cache + iOS 15.5–27.0 七个模拟器 runtime + in-process MachOImage，dump + interface；skip 项均为旧 runtime 本就不含的框架，与上一次 A/B 同构）。
4. **性能与峰值内存**（iOS 18.5 模拟器 SwiftUI `interface`，双侧 release 三轮交错，`/usr/bin/time -l`）：wall-clock 中位 **72.5s（基线）vs 70.0s（候选）**，散布 61–79s，差异在噪声带内——持平；两侧输出再次逐字节一致。maxRSS 基线 383–390 MiB vs 候选 400–403 MiB——**文件腿构建期峰值 +~15 MiB（+4%）**：build 期去重字典retain 的 `String` 键与私有字节缓冲在 freeze 前短暂持有同一批名字字节的两份拷贝（提案「构建峰值」风险段只算了字典本身、漏了这层字节重复），freeze 丢弃字典后回落。镜像腿不付此代价（行直指 mapped 字符串表、无字节复制），而 RV 的目标指标是**稳态**驻留，最终以落地步骤 8 的 RV 复测为裁判。
5. **RV footprint + heap 复测**（落地步骤 8，2026-08-08 同日闭环；RuntimeViewer 重编零源码改动，环境经对面核对——sibling 解析、swift-demangling @ `9464265`、`USING_LOCAL_DEPENDENCIES=1`、无远端回退）：**全项落在或好于预期带**。
   - 干净跑绝对数：footprint 稳态 **445 → 322 MB（−123 MB，−28%）**，好于对面 350–375 的预期（MALLOC_SMALL 脏页 306 → 237，另有 65 MB reclaimable 在归还路上；MALLOC_LARGE 106 → 55）；堆存活 **355 → 283.3 MiB**（预期带 ~255–285 内），分配数 −33 万；索引期瞬态峰值 **893 → 808 MB**——sweep 期非 Swift 符号的 String churn 被字节级判定砍掉，在峰值上可见。
   - heap 按类对照：StringStorage **784,254 个 / 84.2 MiB → 356,094 个 / 31.3 MiB**（49.4 万条驻留符号名如预期消失）；5 × `Dictionary<String, UInt32>` 名表 20 MiB 从堆顶消失，代之 offset 键表 12.9 MiB；`[Symbol]` 24.5 MiB → `[SymbolRow]` 10.4 MiB（≈ 68 万行 × 16 字节，与行格式吻合）。
   - logging 跑归属复核：`SymbolIndexStore` 簇 **214.6 → 120.9 MiB**（预期 120–145 带内）；全进程 StringStorage 分配 96.8 → 36.4 MiB；无回归旁证——MetadataReader 1.4 MiB 不变、Demangling 22.6 不变、ObjC 索引 33.8 不变、NIO/Rx/声明模型持平。
   - RV 五镜像稳态累计曲线：470–480 →（MetadataReaderCache 清退）~450 →（本案）**322 MB**。

## 决策日志

| 日期 | 变更 | 说明 |
|------|------|------|
| 2026-08-08 | Created as Draft | 用户指示（经 swift-demangling 会话转达）：`SymbolIndexStore` 符号名惰性化 / offset 化。RV 全景剖析定位 68.7 MiB 驻留名字符串为堆内最大单项。 |
| 2026-08-08 | 调研补充 | Swift 6.2 `Span` / `UTF8Span` / `~Escapable` 与 swift-collections 1.6.0 稳定面逐项裁决（采用 `RigidArray`，否 `SortedDictionary` 等，理由见「替代方案考量」）。 |
| 2026-08-08 | 格式迁移 | 应用户要求由 `Documentations/Internal/SymbolNameOffsetization.md`（Draft，未提交）转为本 evolution 提案，内容全量并入；本篇为仓库 0001 号提案，`Evolutions/` 目录由此建立。 |
| 2026-08-08 | Accepted → In Progress | 用户审核通过（「审核通过，开始实现」），当日按「落地步骤」开始实施。 |
| 2026-08-08 | 实施偏差：Span 家族不可用 | 编译探针证实 `Span` / `Array.span` / `UTF8Span` 运行时可用性为 **macOS 26.0+**（`error: 'span' is only available in macOS 26.0 or newer`），而本包部署下限是 macOS 10.15 —— 核心路径无法无条件使用。字节访问层改用 `UnsafeBufferPointer<UInt8>`（同样的 closure-scoped 形态：`withNameBytes(atRow:)`；等价语义：`memcmp` 序 + 长度 tiebreak 代替 `bytesEqual`，`String(decoding:as: UTF8.self)` 代替 `String(copying:)`，修复语义与原 `String(cString:)` 一致）。存储表示、API 面与内存收益不变。 |
| 2026-08-08 | 实施偏差：RigidArray 放弃 | 同一部署下限问题的连带裁决：`RigidArray`（noncopyable）存进 class 属性后的 borrow 人体工学要到 SE-0507（Swift 6.4）才齐。改用提案括号里本就给出的等价退路——freeze 时精确容量 `Array` 拷贝（容量已精确者跳过拷贝），且因此**无需**给 `Package.swift` 加 `BasicContainers` 依赖、无需提 swift-collections 版本。 |
| 2026-08-08 | 实施偏差：搭车项裁剪 | `rootNodeIndexByTableRow` 的 `Optional<NodeIndex>` → `UInt32.max` 哨兵一项**放弃**：`NodeStore.NodeIndex` 的构造器是上游 internal（debug 布局还带 store tag），从原始 `UInt32` 重建索引需要新的上游 API，为 ~1.6 MB 不值得跨仓库开口子。`symbolRowsByOffset` 换普通 `Dictionary` 一项照做。另一实现细节：standalone `SymbolTable` 统一走私有字节缓冲表示（提案草绘的 `[String]` 变体不再需要——单一表示，读取路径零分支）。 |
| 2026-08-08 | Implemented + 收尾判断 | 验证结果见「落地记录」（1341 全绿、A/B 96 对逐字节一致、性能持平；文件腿构建期峰值 +4% 如实记录，RV 稳态复测为最终裁判、结果回填）。收尾判断：**不另写实现说明**——「代码看不出来的决策」（mapped 指针生命周期约束、名字来源双腿、Span 不可用的原因）已分别落在 `SymbolTable` 类文档、AGENTS.md「Symbol indexing」段与本提案决策日志，另立一篇只会是复述；**不登记新术语表**——本项目无 `Glossary.md`（项目现状即约定），「offset 化 / 名字来源 / permutation 二分」均在首次出现处展开。 |
| 2026-08-08 | RV 复测闭环 | 落地步骤 8 完成（对面协调，同日）：footprint 稳态 445 → 322 MB（−28%，好于预期）、堆存活 355 → 283.3 MiB（预期带内）、`SymbolIndexStore` 簇 214.6 → 120.9 MiB、StringStorage −42.8 万个/−52.9 MiB，无回归旁证。详数见「落地记录」第 5 条。本提案全部落地步骤就此闭环。 |
