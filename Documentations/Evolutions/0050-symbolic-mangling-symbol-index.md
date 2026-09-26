# 0050 - `_symbolic` 符号索引：被符号引用的对象 → 编译器写下的完整名字

- **状态**: Implemented
- **作者**: JH
- **创建日期**: 2026-09-24
- **最后更新**: 2026-09-26
- **所属愿景**: 无
- **关联提案**: [0018-self-contained-abi-layer](0018-self-contained-abi-layer.md)（符号归属放 SwiftInspection，ABI 模型不碰符号——本提案的解码层沿用这个归宿）、[0001-symbol-name-offsetization](0001-symbol-name-offsetization.md) / [0003-symbol-row-bucket-flattening](0003-symbol-row-bucket-flattening.md)（符号索引的内存纪律：名字不常驻 `String`，按行引用）、[0022-rename-metadata-reader-to-symbolic-demangler](0022-rename-metadata-reader-to-symbolic-demangler.md)（`SymbolicDemangler` 从描述符还原的，正是本提案读出的编译器写法）
- **实现分支 / PR**: `feature/symbolic-mangling-symbol-index`，合入 `next`
- **配套文档**: [`Internal/SymbolicManglingSymbols.md`](../Internal/SymbolicManglingSymbols.md)（实现说明：格式、收集、解码、实测）、[`Internal/Modules/MachOSymbols.md`](../Internal/Modules/MachOSymbols.md)「子系统 5」、术语表「symbolic-mangling symbol」

## 摘要

编译器写进 `__swift5_typeref` 的每条带 symbolic reference 的 mangled name，都有一个供链接器去重的符号，形如
`_symbolic _____Sg 6AppKit24TextShadowViewController33_05EA0EB8E781FFE22747790FC22932B1LLC`：前半截是那条 mangled
name 本身，每个 5 字节的引用写成 `_____`；后面按引用顺序，用空格隔开写出每个引用指向的对象的完整 mangling。二进制里的
引用只是指针，名字只在这里。于是把这些符号扫一遍，就能得到「被引用的对象（主要是 context descriptor）→ 编译器写下的
完整名字」——模块、外层类型、private 鉴别符一个不缺，而 dyld shared cache 保留着它们。

今天库里只有一处用到它：2026-09-24 的私有鉴别符修复（`AnonymousContextPrivateDiscriminatorIndex`，尚未提交）为了给
匿名上下文找鉴别符，自己扫一遍符号表、就地解析。`SymbolIndexStore` 只收带 Swift mangling 前缀的符号，`_symbolic` 被
直接跳过。本提案把这件事做成通用能力：`SymbolIndexStore` 在已有的那一趟扫描里顺带收集 `_symbolic` 符号，
SwiftInspection 新增一个按镜像的解码索引，私有鉴别符改为它的第一个消费者，`SymbolicDemangler` 的对照测试是第二个。

## 方案

### 这些符号是什么（编译器源码与 AppKit 实测）

- **来源**：`IRGenModule::getAddrOfStringForTypeRef`（`lib/IRGen/MetadataRequest.cpp`）为每条类型引用字符串建一个
  全局常量，放进 typeref 段，链接属性 `InternalLinkOnceODR`；符号名由
  `IRGenMangler::mangleSymbolNameForSymbolicMangling`（`lib/IRGen/IRGenMangler.cpp`）生成，注释写明它是
  「uniquing key both for ODR coalescing and within this TU」。运行时从不读它，它只给链接器用。
- **格式**：`<角色前缀><mangled name，每个引用写成 _____>` 之后，每个引用追加 `" " + <被引用者的 mangling>`。角色前缀
  三种：`symbolic `（元数据 / 反射 / 字段元数据）、`default assoc type `（默认关联类型 witness）、`flat unique `（断言不含
  引用）。被引用者按种类写：名义类型写 `appendContext`（声明本身，不带泛型实参），opaque 类型写 opaque 声明名，存在类型
  形状写形状符号。
- **字节布局**（同一函数）：一个紧凑结构体——`default assoc type` 先放一个 `0xFF` 角色标记（符号名里对应的是文字前缀），
  然后是字面量与「控制字节 + 4 字节相对偏移」交替，最后一个 NUL；符号名在同样的位置把这 5 字节写成 `_____`。
  `docs/ABI/Mangling.rst` 允许 mangled name 里夹 `0xFF` 对齐填充，这一路不插。
- **引用种类**（同一函数决定控制字节）：名义类型 `0x01`（直接）/ `0x02`（经 GOT 间接）指向类型或协议描述符，但
  `@objc` 协议——包括 Swift 里声明的 `@objc protocol`——是 `0x0C`，指向 Objective-C 协议引用；opaque 类型 `0x01` /
  `0x02` 指向 opaque 类型描述符；存在类型形状 `0x0A`（唯一）/ `0x0B`（非唯一）。`0x09`（元数据访问函数）与绝对引用
  （`0x18`–`0x1F`）这一路不产生。**占位与被引用者按顺序配对**：第 i 个被引用者就是字节里的第 i 个引用。
- **被引用者不是各自独立的 mangling**：同一个 mangler 依次写出一个符号的全部被引用者，substitution 表与单词表一路
  累积，所以靠后的被引用者会借用前面的——AppKit 里 `7SwiftUI19_ConditionalContentV` 之后紧跟 `AA08ModifiedD0V`，`AA`
  是 `SwiftUI`，`0`/`D` 是指回前一个名字里单词的单词替换。单独 demangle 会失败或得到别的东西；把它们接在同一个 `$s`
  后面一起 demangle，demangler 按同样的顺序重建两张表，每个被引用者得到一个顶层节点。
- **实测**：macOS 26.7 的 shared cache 里 AppKit 保留着这类符号，而匿名上下文描述符上查不到符号（为什么前者留下、后者没有，未核实）。同一个源文件的三个例子：
  `_symbolic _____ …24FontPanelBIUSPopUpButton…LLC`（字段描述符记的本类型名）、`_symbolic _____ …24TextShadowViewController…LLC`、
  `_symbolic ______pSgXw …32TextShadowViewControllerDelegate…LLP`（`weak var delegate` 的类型；第 6 个下划线属于 `_p`；这是
  Swift 里声明的 `@objc` 协议，引用种类实测为 `0x0C`）。草稿还列过一个 `_symbolic _____Sg …`，实现时核实并不存在，已删。

### 第一层：收集（MachOSymbols，`SymbolIndexStore`）

- `buildStorageSweep` 的两条 symtab 采集腿各加一个前缀判断：名字以 `_symbolic ` 或 `_default assoc type ` 开头的，收进
  一张**独立的**表（沿用 `SymbolTable`，`MachOImage` 的行直接指向映射的字符串表，不拷贝）。
- 这张表**不进** `symbolRowsByOffset`，所以 `symbols(offset:)` 与 `Symbol.resolve(from:in:)` 的结果不变——它们的调用方默认
  拿到的都是能 demangle 的 Swift 符号；不 demangle；不进导出事实（这类符号从不导出）。
- 新增 `package` 查询，按行给出 `(偏移, 名字)`；偏移换算与 Swift 符号相同（cache 里的 `MachOFile` 减 `sharedRegionStart`）。
- `Storage` 多一个字段，按 AGENTS.md 要先 `swift package clean`。

### 第二层：解码（SwiftInspection，新增 `SymbolicManglingIndex`）

- 每个收集到的符号：用 `MangledName.resolve(from:in:)` 解析它标的那条 mangled name（沿用现成的字节解析：识别
  `0x01`–`0x17` / `0x18`–`0x1F`、跳过 `0xFF`），与符号名里的被引用者按顺序配对，数量不等或出现绝对引用则跳过该符号、
  计数并记日志。没有被引用者的符号（如 `_symbolic Si`）不读字节。
- 每个引用记下：种类字节；被引用的位置（相对引用 = 引用字段地址 + 偏移，与 `SymbolicDemangler` 同一算法；间接引用给出
  指针槽的位置）；对应第一层的哪一行、第几个被引用者。一条 24 字节，另按被引用位置排好一份 4 字节的下标供二分。
  **不驻留 `String` / `Node`**：被引用者在查询时连同它前面的被引用者一起 transient demangle（见上文「被引用者不是各自
  独立的 mangling」）。
- 查询（`package`）：全部引用；某个位置被哪些引用指向；某个引用的被引用者节点；便捷版「这个 context descriptor 的
  编译器写法」（只看 `0x01`，取第一个解得出的）；某个符号的全部被引用者节点；配不上的符号数。不提供被引用者的原始文本
  （单独拿去 demangle 就会踩上面的坑），也不提供「把占位换掉之后的完整 mangled name」（见决策日志）。
- 按镜像惰性构建，随符号库一起驱逐（它由第一层的行导出，放在索引器 `claims.symbolStore` 那一支）。
- 为什么放 SwiftInspection：要复用 `MangledName` 的字节解析，它在 ABI 模型里，而 `MachOSymbols` 的依赖够不到 ABI 模型；
  0018 已把符号归属放在这一层。

### 第三层：私有鉴别符改为消费者

`AnonymousContextPrivateDiscriminatorIndex` 不再自己扫符号表：遍历第二层里种类为 `0x01` 的引用，读被引用描述符的父级
（每个描述符只读一次），父级是匿名上下文就从第二层解好的被引用者节点里取鉴别符（名字须与描述符一致，这条校验不变）；
某个引用的被引用者解不出来，就接着试指向同一描述符的下一个引用。`SymbolicDemangler` 的 `.anonymous` 分支与
`RuntimeTypeNameDemangling` 的调用方式都不变。

### 第二个消费者：`SymbolicDemangler` 的对照测试

每条 `_symbolic` 符号都是编译器预先写好的标准答案。对 AppKit（macOS 26 cache）里每个种类为 `0x01`、指向类型或协议描述符
的引用，比较 `SymbolicDemangler.demangleContext` 从描述符还原的名字与被引用者名字（都以显示私有鉴别符的选项打印）。预期
零差异；实现时若出现私有鉴别符之外的差异，逐类登记进决策日志再裁决，不在本提案里顺手修。

### 明确不动的地方

- 公开 API 不变，新接口一律 `package`；等下游（如 RuntimeViewer）要用时再提升，并按库的规矩评估源码兼容性。
- `symbols(offset:)` / `Symbol.resolve` 的结果不变。
- `flat unique ` 不收：它不含引用，名字里没有被引用者。
- 其它种类（opaque 类型、存在类型形状、ObjC 协议引用）只进索引，本提案不消费。
- `dump` / `interface` 输出不变：本提案是重构加新能力，私有鉴别符那批带来的输出变化已在流水账 2026-09-24 一节记录。

### 验证

- 第一层：AppKit 收集到 `_symbolic` 符号；在 typeref 偏移处 `symbols(offset:)` 的结果与改动前相同；`MachOImage` 与
  `MachOFile`（cache 镜像）两条腿都覆盖。
- 第二层：上面三个 AppKit 例子逐个钉住种类（前两个 `0x01`、第三个 `0x0C`）、被引用位置（前两个指向对应类的描述符）与
  被引用者节点打印出的名字；每个符号的被引用者都能一起 demangle，且确有单独 demangle 会失败的（钉住「为什么要一起」）；
  AppKit（文件与进程内）与 SwiftUICore 配不上的符号为 0，SwiftUICore 覆盖 `default assoc type` 角色。
- 对照测试如上。
- 已有的 5 条私有鉴别符回归测试不改，保持绿。
- 全量 `swift test --skip IntegrationTests`；AppKit `dump` / `interface` 与私有鉴别符修复后的输出逐字节相同。
- 测量 AppKit、SwiftUI 的 `_symbolic` 符号数，以及第一、二层的内存增量，写进决策日志。

### 未经确认的假设

1. 解码层放 SwiftInspection（理由见上）；备选是放 MachOSymbols，自带一个小的字节解析器。
2. 新接口一律 `package`。
3. 收 `_symbolic ` 与 `_default assoc type ` 两种角色。
4. 与尚未提交的私有鉴别符修复合为一批落地，流水账 2026-09-24 那一节随之补记。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-09-24 | Created as Draft | 私有鉴别符修复之后用户接连提出：「SymbolIndexStore 可以加入这种 `_symbolic` 符号么？」「解 `_symbolic` 的逻辑应该要和 AnonymousContextPrivateDiscriminatorIndex 分开来吧，这个别的地方可能也用的到」「那继续写提案，现在只做了收集私有鉴别器，反正都要扫一遍，弄得通用一点」 |
| 2026-09-24 | `_symbolic` 表与 `symbols(offset:)` 的表分开 | 按偏移查询的调用方默认拿到能 demangle 的 Swift 符号；混进去，查到 typeref 偏移的调用会开始拿到 demangle 不了的名字 |
| 2026-09-24 | 占位与被引用者按顺序配对 | 编译器按引用顺序追加被引用者，顺序本身就是配对关系；不去符号名里数下划线找占位，因为 mangled name 本体会在占位旁边带下划线（`______pSgXw` 的第 6 个属于 `_p`）。按字节位置换算也行（这一路不插填充），但 ABI 允许填充，按顺序对两种情况都成立 |
| 2026-09-24 | 更正「引用种类」与字节布局两条事实 | 草稿写过「字节里可能夹着对齐用的 `0xFF`，符号名里没有」并把 `0x09` 列为可能的种类。对照 `getAddrOfStringForTypeRef` 后：这一路是紧凑结构体、不插填充，唯一的 `0xFF` 是默认关联类型的角色标记；被引用者只有名义类型、opaque 类型、存在类型形状三类，控制字节只会是 `0x01` / `0x02` / `0x0A` / `0x0B` / `0x0C`，`@objc` 协议走 `0x0C` |
| 2026-09-24 | Accepted | 用户：「开始实现」。「未经确认的假设」四条未提异议，按原文采纳 |
| 2026-09-24 | In Progress | 开始实现第一层 |
| 2026-09-24 | 被引用者一起 demangle；第二层不提供被引用者的原始文本，改给节点 | 对照测试把被引用者单独 demangle 时报 `.unexpected(at: 2)`：同一个 mangler 依次写出一个符号的全部被引用者，后面的借用前面的 substitution 与单词（AppKit：`7SwiftUI19_ConditionalContentV AA08ModifiedD0V`）。私有鉴别符那边原来也是单独 demangle，靠「每个引用都试一遍」碰巧避开；重构加上「每个描述符只读一次」后覆盖测试多出 2 个不一致（`NSScrollPocket.ElementContainerModel` 等嵌套 private 类），据此定位。接在同一个 `$s` 后面一起 demangle 即可，每个被引用者一个顶层节点 |
| 2026-09-24 | 撤掉「逐条列出并给出把占位换掉之后的完整 mangled name」这项查询 | 同一原因：typeref 本体里的 substitution 把 symbolic reference 算作一格，被引用者里的 substitution 指向符号名里前面的被引用者，文字拼接让两边的编号同时错位；AppKit 实测拼出来的名字 demangle 失败 |
| 2026-09-24 | 函数体里的局部类型：对照测试登记为已知问题，本提案不修 | AppKit 880 个被直接引用的类型与协议描述符里，878 个「从描述符还原」与「编译器写的」逐字一致；剩下 2 个都是局部类型（`DeferralState #1 in …deferCompletionUntil()`），`SymbolicDemangler` 丢了函数那一层。与私有鉴别符同属「匿名上下文没有名字」一类，按上文「第二个消费者」一节的约定先登记，是否修另议 |
| 2026-09-24 | 实测：两种角色都收得到，内存增量可接受 | macOS 26.7 cache 的 `MachOFile`：AppKit 3028 个符号 / 4826 个引用，表 307 KB、索引 135 KB；SwiftUICore 7531 / 8827，657 KB / 247 KB，其中 9 个 `default assoc type`；SwiftUI 12348 个符号，表 1.28 MB（名字占 1.03 MB）。`MachOImage` 的名字不拷贝，表只剩每行 20 字节。AppKit 没有 `default assoc type`，SwiftUICore 覆盖这个角色 |
| 2026-09-24 | 输出不变、耗时测不出差别 | 与私有鉴别符修复那一版的 debug CLI 对比（同一 cache）：AppKit `dump` 与 `interface` 逐字节相同，`dump` 也与该版早上的输出相同。耗时在系统负载 25–30 下交替各跑 3 次：`interface` 墙钟 28.7 / 30.2 / 32.1 秒 vs 32.6 / 28.2 / 29.8 秒，区间重叠；`dump` 10.6 vs 10.5 秒 |
| 2026-09-24 | 全量测试通过（除既有不稳定项） | `swift test --skip IntegrationTests`：2086 个测试 / 391 个 suite，5 个失败全是既有的不稳定测试——`SharedCacheTests` 的 3 条墙钟断言、`argumentCandidatePathSpecializesNonGenericCandidate`、以及满载时的 arm64e 探针（子进程没启用 PAC），后者单独重跑 3 条全过；另有局部类型那 1 个已知问题 |
| 2026-09-24 | Implemented：合入 `next`，与私有鉴别符修复分两个提交 | 用户：「都提交推送一下」。先提交私有鉴别符修复本身（它自己扫符号表的那一版），再提交本提案，历史里两件事各自可读。配套文档：实现说明 `Internal/SymbolicManglingSymbols.md` 已写并登记进 `Documentations/README.md` 与本文头部；新术语「symbolic-mangling symbol / 被引用者」已进术语表；AGENTS.md 的模块清单与「demangler / 符号索引」陷阱清单各补一条。编号按本仓库惯例在进入 `main` 时再取 |
| 2026-09-24 | 接受：进程内第一次查私有鉴别符改为先建该镜像的 `SymbolIndexStore` | 离线路径找符号本来就经符号库，不多花；进程内路径找符号走 MachOKit，不建符号库，原先查鉴别符只扫一遍符号表。改为经本索引后第一次查询要建全量符号库。RuntimeViewer 这类宿主通常早已为正在看的镜像建好，未单独测量 |
| 2026-09-26 | 落地编号 0050 | 已于 2026-09-24 随 合并提交 `5cbf0378` 合入 `next` 并标为 Implemented，但当时没有取号；0.20.0 发版收尾时按合入顺序补取 |
