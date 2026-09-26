# `_symbolic` 符号：编译器写下的被引用者

> 提案 [0050-symbolic-mangling-symbol-index](../Evolutions/0050-symbolic-mangling-symbol-index.md) 的实现说明。读者：维护者。
> 格式事实与取舍过程在提案里，本文讲落地后的形状、为什么这样落、边界和实测。

## 一句话

mangled name 里的 symbolic reference 只是 5 个字节（控制字节 + 相对偏移），说得出被引用的东西在哪，说不出它叫什么。
编译器另给每条带引用的 mangled name 生成一个供链接器去重的符号，名字里按引用顺序写出每个被引用者的完整 mangling，
模块、外层类型、private 鉴别符一个不缺，而 dyld shared cache 保留着它们。`SymbolIndexStore` 在已有的符号表扫描里把这类
符号收进一张独立的表；SwiftInspection 的 `SymbolicManglingIndex` 把每个引用和它的被引用者配对，按被引用的位置建索引。
私有鉴别符的还原（`AnonymousContextPrivateDiscriminatorIndex`）是第一个消费者，`SymbolicDemangler` 的对照测试是第二个。

## 这些符号长什么样

来源是 `IRGenModule::getAddrOfStringForTypeRef`（`lib/IRGen/MetadataRequest.cpp`），名字由
`IRGenMangler::mangleSymbolNameForSymbolicMangling`（`lib/IRGen/IRGenMangler.cpp`）生成：

```
_symbolic ______pSgXw 6AppKit32TextShadowViewControllerDelegate33_05EA0EB8E781FFE22747790FC22932B1LLP
└ 角色前缀 ┘└ mangled name，引用写成 _____ ┘ └ 被引用者（每个引用一个，空格分隔）                      ┘
```

- **角色**：`_symbolic `（元数据 / 反射 / 字段元数据）、`_default assoc type `（默认关联类型 witness；字节以 `0xFF` 角色
  标记开头，符号名里写成这个前缀）、`_flat unique `（不含引用，不收）。
- **字节**：紧凑结构体，字面量与「控制字节 + 4 字节相对偏移」交替，末尾一个 NUL；符号名在同样的位置把这 5 字节写成
  `_____`。这一路不插 ABI 允许的 `0xFF` 对齐填充。
- **引用种类**：名义类型 `0x01`（直接）/ `0x02`（经 GOT 间接），`@objc` 协议——Swift 里声明的也算——一律 `0x0C`；
  opaque 类型 `0x01` / `0x02`；存在类型形状 `0x0A` / `0x0B`。`0x09` 与绝对引用这一路不产生。
- **配对靠顺序**：第 i 个被引用者就是字节里的第 i 个引用。不去符号名里数下划线——上面那个名字的第 6 个下划线属于 `_p`。

### 被引用者不是各自独立的 mangling

同一个 mangler 依次写出一个符号的全部被引用者，substitution 表和单词表一路累积，所以靠后的被引用者会借用前面的。AppKit 里
`7SwiftUI19_ConditionalContentV` 之后紧跟 `AA08ModifiedD0V`：`AA` 是前一个名字里的 `SwiftUI`，`0`、`D` 是指回前一个名字
里单词的单词替换。单独 demangle 它会失败，或者得到别的东西。

所以被引用者只能**一起** demangle：接在同一个 `$s` 后面，demangler 按 mangler 填表的顺序重建两张表，每个被引用者得到
一个顶层节点（`SymbolicManglingIndex.demangleTogether(_:)`）。同样的原因，也没有「把占位换成被引用者、拼成完整 mangled
name」这种东西：typeref 本体里的 substitution 把 symbolic reference 当成一格计数，被引用者里的 substitution 引用的是符号名
里前面的被引用者，文字拼接会让两边的编号同时错位。

实现时踩过这个坑：私有鉴别符那边原来把每个被引用者单独 demangle，靠「指向同一描述符的每个引用都试一遍」碰上一个排在
第一位、不借用前文的；重构时加了「每个描述符只读一次」，两个嵌套的 private 类（`NSScrollPocket.ElementContainerModel`
这类）立刻丢了鉴别符，覆盖测试从 0 个不一致变成 2 个。

## 落地形状

| 层 | 文件 | 做什么 |
|---|---|---|
| MachOSymbols | `SymbolicManglingSymbols.swift` | `SymbolicManglingSymbols`：按行、零拷贝的集合（`MachOImage` 的名字留在映射的字符串表里）；`SymbolicManglingSymbolName`：拆出角色、带占位的 mangled name、被引用者；字节级前缀判断 `nameBytesHaveSymbolicManglingSymbolPrefix` |
| MachOSymbols | `SymbolIndexStore.swift` | 两条采集腿各多一个前缀分支，收进 `Storage.symbolicManglingSymbolTable`（沿用 `SymbolTable`）；查询 `symbolicManglingSymbols(in:)` |
| SwiftInspection | `SymbolicManglingIndex.swift` | `SymbolicManglingReference`（种类、引用位置、被引用位置、符号位置、第几个被引用者，24 字节）；按镜像的 `SharedCache`：读每个符号标的 mangled name、按顺序配对、按被引用位置排一份下标；查询 `references(in:)` / `references(to:in:)` / `referentNode(of:in:)` / `referentNode(forContextDescriptorAt:in:)` / `referentNodes(ofSymbolAt:in:)` / `unpairedSymbolCount(in:)` |
| SwiftInspection | `AnonymousContextPrivateDiscriminatorIndex.swift` | 不再自己扫符号表：遍历 `0x01` 引用，每个描述符只读一次父级，父级是匿名上下文就从解好的被引用者节点里取鉴别符；某个引用解不出来就接着试下一个指向同一描述符的引用 |
| SwiftIndexing | `SwiftDeclarationIndexer.deinit` | 符号库那一支（`claims.symbolStore`）一起驱逐 `SymbolicManglingIndex` |

## 为什么这样落

- **独立的一张表**：不进 `symbolRowsByOffset`，所以 `symbols(for:in:)` / `Symbol.resolve` 的结果不变——它们的调用方默认拿到的
  都是能 demangle 的 Swift 符号；也不进 demangle 扫描、不进导出事实。`containsSymbol(named:)` 同样看不到它们。
- **收集在 MachOSymbols、解码在 SwiftInspection**：解码要读 mangled name 的字节，现成的解析是 ABI 模型里的
  `MangledName.resolve(from:in:)`，`MachOSymbols` 的依赖够不到 ABI 模型；提案 0018 也已把符号归属放在 SwiftInspection。
- **不驻留 `String` / `Node`**：引用只记位置与下标，被引用者在查询时连同前面的被引用者一起 transient demangle。
- **驱逐**：索引的存储握着符号库那张表，符号库被回收时它若留着，就钉住那张表，所以放在 `claims.symbolStore` 那一支。
  私有鉴别符索引只存 `[Int: String]`，不握任何表，仍跟着 demangle memo 走。
- **代价**：离线路径（`MachOContext`）找符号本来就经 `SymbolIndexStore`，收集在同一趟扫描里，不多扫一遍。进程内路径
  （`InProcessContext`）找符号走 MachOKit，不建符号库；私有鉴别符改为经本索引之后，进程内第一次遇到没有名字的匿名上下文，
  要先为该镜像建 `SymbolIndexStore`（原先只扫一遍符号表）。RuntimeViewer 这类宿主通常早已为正在看的镜像建好；这笔一次性
  代价没有单独测量。

## 边界

- `_flat unique ` 不收：它不含引用。
- 字节里出现绝对引用、或引用数与被引用者数不等的符号整个跳过、计入 `unpairedSymbolCount`，并记一条日志；AppKit 与
  SwiftUICore 实测为 0。没有被引用者的符号（如 `_symbolic Si`）不读字节。
- 间接引用（`0x02`）只给出指针槽的位置，不解它指向哪个镜像的哪个描述符。
- 不提供被引用者的原始文本：单独拿去 demangle 就会踩上面那个坑。
- 函数体里声明的局部类型：编译器写 `DeferralState #1 in AppKit.NSWMDeferrableWMWindowTransaction.deferCompletionUntil() -> () -> ()`，
  `SymbolicDemangler` 从描述符还原时丢掉函数那一层——和私有鉴别符是同一类问题（匿名上下文没有名字）。对照测试把它登记为
  已知问题（`withKnownIssue`），本提案不修。

## 实测（macOS 26.7 系统 dyld shared cache）

| 镜像 | 符号 | 其中带被引用者 | 被引用者 | `default assoc type` | 表（`MachOFile`，字节） | 其中名字 |
|---|---|---|---|---|---|---|
| AppKit | 3028 | 2489 | 4826 | 0 | 307118 | 246558 |
| SwiftUICore | 7531 | 6855 | 8827 | 9 | 656757 | 506137 |
| SwiftUI | 12348 | 11369 | 20254 | 12 | 1279141 | 1032181 |

`MachOImage` 的名字不拷贝，表只剩每行 16 字节加名字排序下标 4 字节（AppKit 约 60 KB）。

| 镜像 | 引用 | `0x01` | `0x02` | `0x0B` | `0x0C` | 来自 `default assoc type` | 索引（字节） |
|---|---|---|---|---|---|---|---|
| AppKit | 4826 | 1475 | 3291 | 17 | 43 | 0 | 135128 |
| SwiftUICore | 8827 | 5429 | 3384 | 6 | 8 | 7 | 247156 |

对照测试：AppKit 里被直接引用的 880 个类型与协议描述符，878 个「从描述符还原的名字」与「编译器写的名字」逐字一致，
其余 2 个都是上面说的局部类型。AppKit 注册到 ObjC 运行时的 183 个 Swift 类，从描述符解出的名字与 ObjC 运行时名全部一致。

与私有鉴别符修复那一版（它自己扫符号表）相比，AppKit 的 `dump` / `interface` 输出逐字节相同；耗时在系统负载 25–30 下交替
各跑 3 次，`interface` 28.7–32.1 秒对 28.2–32.6 秒，区间重叠，测不出差别。

## 相关文档

- 提案：[0050-symbolic-mangling-symbol-index](../Evolutions/0050-symbolic-mangling-symbol-index.md)；上游
  [0018](../Evolutions/0018-self-contained-abi-layer.md)（符号归属在 SwiftInspection）、[0001](../Evolutions/0001-symbol-name-offsetization.md) /
  [0003](../Evolutions/0003-symbol-row-bucket-flattening.md)（符号表的行与名字来源）。
- [Modules/MachOSymbols.md](Modules/MachOSymbols.md)「子系统 5」。
- [SpecializedInterfaceBoundRenderingRestoration.md](SpecializedInterfaceBoundRenderingRestoration.md)「私有鉴别符（2026-09-24）」：私有鉴别符修复本身。
- 测试：`Tests/MachOSymbolsTests/SymbolicManglingSymbolCollectionTests.swift`、`Tests/SwiftInspectionTests/SymbolicManglingIndexTests.swift`、
  `Tests/SwiftInspectionTests/AnonymousContextPrivateDiscriminatorTests.swift`、`Tests/SwiftIndexingTests/PerImageCacheEvictionTests.swift`。
