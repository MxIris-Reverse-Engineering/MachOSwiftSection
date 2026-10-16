# CrossReferenceAnalysis

从 arm64 机器码里读出一个镜像的函数表，以及每个函数引用了什么：直接调用与尾调用、ObjC 消息发送、`super` 发送、经桩的跨库调用、间接调用。只在进程内读 `MachOImage`，只支持 arm64 / arm64e。RuntimeViewer 的交叉引用功能（调用者、被调、类型引用）建在它上面。

- 提案：[draft-cross-reference-analysis](../../Evolutions/draft-cross-reference-analysis.md)（本库这一层）；整体设计、实测数据在 RuntimeViewer 的 [draft-cross-references](https://github.com/MxIris-Reverse-Engineering/RuntimeViewer/blob/feature/cross-references/Documentations/Evolutions/draft-cross-references.md)。
- 依赖：MachOKit 与 `ARM64InstructionDecoding`。不依赖 Capstone、符号索引或 Swift 元数据层（第二批起会用到 ObjC 方法表与 Swift 方法描述符来给无符号函数起名）。

## 子系统

| 子系统 | 文件 | 分工 |
|---|---|---|
| 1. 指令字与跳板 | `ARM64InstructionDecoding` 模块的 `ARM64InstructionWord`、`ARM64Trampoline` | 手写读取少数几类 A64 编码；按形状认 GOT 桩、stub island 与全缓存共用的 selector 桩。与 SwiftThunkAnalysis 共用 |
| 2. 地址空间 | `CrossReferenceAnalyzer` | 进程里全部镜像（整个共享缓存加缓存外已加载的镜像）、各镜像 `__TEXT` 的内存区间、缓存的可执行与可读映射、`objc_msgSend` 与运行时辅助函数的位置；给函数起名要用的函数表按需建一次并记住 |
| 3. 函数表 | `Scanning/ImageFunctionTable` | 函数起点（`LC_FUNCTION_STARTS` 与 `__text` 里的符号取并集）、主名与代码合并留下的别名、辅助函数、镜像自带的 `__objc_stubs` / `__stubs` / `__auth_stubs`、`__objc_selrefs` |
| 4. 扫描 | `Scanning/ReferenceScanner`、`Scanning/RegisterFile`、`Scanning/RuntimeHelperNames` | 逐条解码、跟踪寄存器、解析调用目标 |
| 5. 结果 | `Models/*` | `CodeLocation`、`CodeFunction`、`CodeReference`、`CodeReferenceTarget`、按目标分组的 `CodeReferenceTable` |
| 6. 预筛与过滤 | `CrossReferenceAnalyzer+Prefiltering`、`references(to:inImageAt:)` | 按未定义符号、`__objc_selrefs` 筛出可能引用某个符号或 selector 的镜像；扫描时只留命中的引用 |

## 关键契约

### 地址

`CodeLocation` 是（镜像在 `images` 里的位置，镜像自己的未滑动地址）。缓存外两个镜像的未滑动地址可能重合，所以位置必须带镜像。跨镜像的查找一律换成运行时地址（未滑动地址加该镜像的 slide）再查 `__TEXT` 区间表，算完再换回 `CodeLocation`。

MachOKit 在内存镜像上给出的 `FunctionStart.offset` 已经是未滑动的绝对地址（迭代器以 `__TEXT` 的 vmaddr 起算），与它的文档注释「相对 mach header 的偏移」不符；当成偏移再加一次基址，会得到范围外的地址、整张表被滤空。

### 两种桩布局

macOS 27 / iOS 27 起的那种见术语表 [cache-shared stub（全缓存共用桩）](../../Glossary.md)。

| 缓存 | ObjC 消息 | 跨库调用 |
|---|---|---|
| macOS 15 至 26、iOS 26 及更早的真机，以及 Simulator | 镜像自己的 `__objc_stubs`（经 MachOKit `objcStubs(in:)` 读 selector 引用） | 镜像自己的 `__stubs` / `__auth_stubs`（MachOKit `stubs(in:)` 给出槽位） |
| macOS 27、iOS 27 真机 | 镜像里的段大小为 0；`bl` 落到全缓存共用的 selector 桩：`adrp x1; add x1; b <objc_msgSend 副本>`，`x1` 就是 selector 字符串 | 全缓存共用的 GOT 桩：`adrp x17; add x17; ldr x16, [x17]; braa x16, x17` |

同一个 selector 在不同子缓存里各有一份共用桩（macOS 27.2：被调用的 155 万个桩只对应 104 万个字符串），所以 selector 以字符串为键，不以桩地址为键。GOT 槽在进程内已经绑定，读出指针、去掉指针认证位就是目标；读之前先确认槽位落在缓存的映射里。

### 读任何目标之前先确认它可读

`__text` 里夹着数据（跳转表之类，缓存镜像的 `LC_DATA_IN_CODE` 是空的），按指令解码会得到指向任意地址的「跳转」。扫描只在目标落在某个镜像的 `__TEXT`、或缓存的可执行映射里时才去读那里的指令；读槽位前确认它在缓存或镜像的映射里。探针第一次全量扫描就崩在没做这一步上。

### 寄存器跟踪只记确定的事

`RegisterFile` 只记录 `adrp` / `adr` / `add` 算出的地址、从已知地址加载的槽位、ObjC 方法入口时 `x0` 里的接收者、指针认证常量，以及「这个寄存器的值是从内存读来的」和读取时的偏移。不建模的指令一律作废它写的寄存器（宁可多忘，不留陈旧的值）；调用作废 `x0`–`x18` 与 `x30`。PAC / AUT / XPAC 保留寄存器的值。

### 尾调用与跳转表

`b` / 条件跳转的目标在本函数之外就是尾调用。经寄存器的 `br`：带认证的（`braa` 等）一律算尾调用；不带认证的，只有寄存器的值是从内存读来的（函数指针）才算——跳转表的目标是 `add` 算出来的，不算。

### 运行时辅助调用

`RuntimeHelperNames` 维护名单：libobjc 的 retain / release / autorelease / weak 系列，Swift 运行时的 retain / release / bridgeObject / unknownObject / unowned / weak / beginAccess / endAccess，编译器写进每个镜像的 `___swift_*_boxed_opaque_existential*` / `___swift_memcpy*`，以及以 `WO` 加小写字母结尾的 outlined 值操作。跨镜像的辅助函数只在 libobjc、libswiftCore、libswift_Concurrency 里找；镜像内的在该镜像的函数表里标出。结果只打标记，过滤交给宿主。

### 缓存外镜像的 GOT 槽

缓存外的镜像（第三方 App 自己的二进制）经自己的 `__stubs` / `__auth_stubs` 调别的镜像，槽位由 dyld 在加载时绑定，按 macOS 11 部署目标、不用 chained fixups 编出来的懒绑定二进制也一样：macOS 27.2 上以 `RTLD_LAZY` 加载，函数第一次被调用之前槽里已经是目标地址。所以扫描直接读槽。`LazyBindingTests` 是这件事的哨兵：哪天 dyld 不再在加载时绑定，槽会指回镜像自己的 `__stub_helper`，测试变红，那时再退回桩上的导入名。

### 缓存、内存与生命周期

库里没有全局的按镜像缓存（因此不需要 `SharedCache`）。`CrossReferenceAnalyzer` 只记住宿主让它起过名的镜像的函数表（`functions(inImageAt:)`、`function(containing:)`、`references(madeBy:)`）；整镜像扫描（`referenceTable(ofImageAt:)`、`references(to:inImageAt:)`）临时建表、用完即丢；给一批结果起名用 `functions(containing:)`，同样临时建表——查 `init` 的调用者会碰到 2,759 个镜像，逐个记住又是上 GB——早先扫描也记表，扫完一遍 macOS 27.2 缓存后常驻 1.5 GB（`wholeImageScansKeepNoFunctionTable` 钉住）。

`CodeReferenceTable` 是值，宿主想留多久就留多久，按 `approximateByteCount` 计预算。大镜像的整表很大（GeoServices 约 121 MiB，全缓存合计约 9 GB），28 个线程同时建整表时峰值约 1.5 GB，分配器之后还留着 1.2 GB 脏页不还。**查调用者用 `references(to:inImageAt:)`**：扫描时只留命中的引用，同样扫完全缓存后常驻约 170 MB（4 线程约 106 MB）。

分析器是一个快照：之后才加载的镜像需要新的分析器。

## 吞吐（macOS 27.2，28 核的 Mac Studio）

| 操作 | 28 核 | 8 线程 | 4 线程 |
|---|---|---|---|
| 建分析器（4,114 个镜像） | 0.02 秒 | | |
| 每个镜像都建整表（1.16 亿条引用） | 1.6–1.8 秒 | 3.5 秒 | 5.9 秒 |
| `init` 的调用者：预筛出 2,759 个镜像再过滤扫描 | 0.05 + 1.5 秒 | | 6.1 秒 |
| `makeKeyAndOrderFront:` 的调用者：105 个镜像 | 0.06 + 0.26 秒 | | |
| 过滤着扫完每个镜像 | 1.7 秒 | | 6.3 秒 |

单线程解码 AppKit 约 187 MiB/s，比 Capstone 快 25–50 倍（RuntimeViewer 提案落地第一步的探针）。库比探针慢一些（4 线程扫完整个缓存，探针 4.1 秒，库 5.9–6.3 秒），多出来的是起名、建 `CodeReference` 与 selector 字符串；过滤扫描也是先建好每条引用再丢弃，按键提前跳过是能做的优化。

## 测试锚点

- `ARM64InstructionWordTests` / `ARM64TrampolineTests`：手写编码器造指令字；`capstoneAgreesWithTheEncoders` 让 Capstone 反汇编同一批字，编码器写错也藏不住。
- `CrossReferenceAnalyzerTests`（只在 arm64 进程里跑）：`-[NSWindow makeKeyAndOrderFront:]` 发出的三条消息及接收者；SwiftUICore 经桩调用 `swift_beginAccess` 落到 libswiftCore；按键过滤与整表一致；整镜像扫描不留函数表；给一批结果起名也不留；预筛；`callSitesMatchCapstone` 抽样 400 个 AppKit 函数，Capstone 找到的每一处调用与跳出函数的跳转，扫描都找到了（Capstone 不开 detail 模式就不给操作数，那半边比对曾因此什么都没比，测试现在断言比对过）。
- `StandaloneImageTests`：SymbolTestsCore fixture 经自己的桩调用 libswiftCore，没有一条停在只有名字的导入上。
- `LazyBindingTests`：现编一个懒绑定的 dylib，见上文「缓存外镜像的 GOT 槽」。
