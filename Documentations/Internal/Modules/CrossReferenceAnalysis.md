# CrossReferenceAnalysis

从 arm64 机器码里读出一个镜像的函数表，以及每个函数引用了什么：直接调用与尾调用、ObjC 消息发送、`super` 发送、经桩的跨库调用、间接调用、ObjC 类引用。只在进程内读 `MachOImage`，只支持 arm64 / arm64e。RuntimeViewer 的交叉引用功能（调用者、被调、类型引用）建在它上面。

- 提案：[draft-cross-reference-analysis](../../Evolutions/draft-cross-reference-analysis.md)（本库这一层）；整体设计、实测数据在 RuntimeViewer 的 [draft-cross-references](https://github.com/MxIris-Reverse-Engineering/RuntimeViewer/blob/feature/cross-references/Documentations/Evolutions/draft-cross-references.md)。
- 依赖：MachOKit、`ARM64InstructionDecoding`；第二批起还有 `MachOObjCSection`（方法表）、`MachOSwiftSection` 与 `SwiftInspection`（Swift 元数据与 `SymbolicDemangler`）、`Demangling`——只用来给符号表没有名字的函数起名，扫描本身仍然只读机器码与符号表。不依赖 Capstone。

## 子系统

| 子系统 | 文件 | 分工 |
|---|---|---|
| 1. 指令字与跳板 | `ARM64InstructionDecoding` 模块的 `ARM64InstructionWord`、`ARM64Trampoline` | 手写读取少数几类 A64 编码；按形状认 GOT 桩、stub island 与全缓存共用的 selector 桩。与 SwiftThunkAnalysis 共用 |
| 2. 地址空间 | `CrossReferenceAnalyzer` | 进程里全部镜像（整个共享缓存加缓存外已加载的镜像）、各镜像 `__TEXT` 的内存区间、缓存的可执行与可读映射、`objc_msgSend` 与运行时辅助函数的位置；给函数起名要用的函数表按需建一次并记住 |
| 3. 函数表 | `Scanning/ImageFunctionTable` | 函数起点（`LC_FUNCTION_STARTS` 与 `__text` 里的符号取并集）、主名与代码合并留下的别名、辅助函数、镜像自带的 `__objc_stubs` / `__stubs` / `__auth_stubs`、`__objc_selrefs`、放类引用的槽（`__got`、`__auth_got`、`__objc_classrefs`）与 `__objc_superrefs`、各段的地址区间 |
| 3a. 补充名字 | `Scanning/ImageFallbackNames` | 符号表没有名字的函数，依次从导出表、ObjC 方法表、Swift 元数据起名；起名时按镜像按需读，扫描不读 |
| 3b. 类索引 | `Scanning/ObjectiveCClassIndex` | 一个镜像定义的类与元类，按地址；直接读 `__objc_classlist` 与各类的 `isa`。扫描时按需建、分析器记住；类名只在报出引用时读 |
| 4. 扫描 | `Scanning/ReferenceScanner`、`Scanning/RegisterFile`、`Scanning/RuntimeHelperNames` | 逐条解码、跟踪寄存器、解析调用目标 |
| 5. 结果 | `Models/*` | `CodeLocation`、`CodeFunction`、`CodeReference`、`CodeReferenceTarget`、按目标分组的 `CodeReferenceTable` |
| 6. 预筛与过滤 | `CrossReferenceAnalyzer+Prefiltering`、`references(to:inImageAt:)` | 按未定义符号、`__objc_selrefs`、类对象上的符号筛出可能引用某个符号、selector 或类的镜像；扫描时只留命中的引用 |

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

不经桩、直接 `bl` / `b` 到 `objc_msgSend` 的传统写法还有第三种形态：缓存构建器把读 selector 引用的 `adrp` / `ldr` 改写成了 `adrp` / `add` 出字符串本身的地址，指令里只剩字符串地址。macOS 27.2 的 `-[NSObject debugDescription]` 就是 `adrp x8; add x1, x8, #…; b _objc_msgSend`（`objc_msgSend` 在 `/usr/lib/objc/libobjcMsgSend.dylib` 里）。所以传统发送的 selector 两处都要认：`x1` 从本镜像的 `__objc_selrefs` 读来，或 `x1` 是 `adrp` / `add` 算出的地址；后者要确认它落在映射里、到结尾为止是不含空格的可打印字符（最长 1,024 字节），不满足就不当作发送。第一批漏了后一种，这些发送全被当成对 `objc_msgSend` 的普通调用；RuntimeViewer 第 3 步查 `-[NSObject description]` 的调用者时发现。

### 读任何目标之前先确认它可读

`__text` 里夹着数据（跳转表之类，缓存镜像的 `LC_DATA_IN_CODE` 是空的），按指令解码会得到指向任意地址的「跳转」。扫描只在目标落在某个镜像的 `__TEXT`、或缓存的可执行映射里时才去读那里的指令；读槽位前确认它在缓存或镜像的映射里。探针第一次全量扫描就崩在没做这一步上。

### 寄存器跟踪只记确定的事

`RegisterFile` 只记录 `adrp` / `adr` / `add` 算出的地址、从已知地址加载的槽位、ObjC 方法入口时 `x0` 里的接收者、指针认证常量，以及「这个寄存器的值是从内存读来的」和读取时的偏移。不建模的指令一律作废它写的寄存器（宁可多忘，不留陈旧的值）；调用作废 `x0`–`x18` 与 `x30`——原样返回所传类的三个函数例外，`x0` 留着（见「类引用」）。PAC / AUT / XPAC 保留寄存器的值。

**寄存器状态沿着分支走（第二批）。** 一个函数内：向前的分支（条件跳转与 `b`）把当时的寄存器状态带到目标处；目标处若前一条是无条件转移（`b`、`br`、`ret`），就以带来的状态为准，否则与顺序走下来的状态取交集——同一个寄存器两条路径放的东西一致才保留。无条件转移之后没有分支指向的指令（跳转表的落点之类）、以及向后分支的目标（循环头，回边的状态此时还不知道）忘掉调用方保存的寄存器。第一批只按指令顺序往下读，汇合处会沿用最后一条路径的值：`-[NSString stringByAppendingString:]` 里一个块把参数放进 `x0`、下一个块放 `self`，两者跳到同一处发送 `copyWithZone:`，顺序读法把接收者说成 `self`。这一改动让 AppKit 80 万处引用里 9,699 处发送多认出了 `self`（前一条路径的调用冲掉了 `x0`，而实际到达的路径没有），78 处不再说 `self`，selector 几乎不受影响；release 下全缓存整表扫描由 1.6–1.8 s 变为 2.0 s。快照是定长值（`SIMD32`），不分配内存；待到的目标与循环头按地址排序、随扫描游标前进。只记「无条件转移后忘掉」的简化版试过，会丢掉 `+[NSObject instanceMethodForSelector:]` 这类早退之后的正确接收者，弃用。

### 尾调用与跳转表

`b` / 条件跳转的目标在本函数之外就是尾调用。经寄存器的 `br`：带认证的（`braa` 等）一律算尾调用；不带认证的，只有寄存器的值是从内存读来的（函数指针）才算——跳转表的目标是 `add` 算出来的，不算。

### 运行时辅助调用

`RuntimeHelperNames` 维护名单：libobjc 的 retain / release / autorelease / weak 系列，Swift 运行时的 retain / release / bridgeObject / unknownObject / unowned / weak / beginAccess / endAccess，编译器写进每个镜像的 `___swift_*_boxed_opaque_existential*` / `___swift_memcpy*`，以及以 `WO` 加小写字母结尾的 outlined 值操作。跨镜像的辅助函数只在 libobjc、libswiftCore、libswift_Concurrency 里找；镜像内的在该镜像的函数表里标出。结果只打标记，过滤交给宿主。

### 类引用（第二批）

一条指令取了某个类对象的地址、但不跳转，就是一处类引用：`CodeReference.Kind.reference`，目标 `.objectiveCClass(name:location:)`。macOS 27.2 的缓存里几乎没有 `__objc_classrefs` 了，类有三种取法：`adrp` / `add` 出本镜像的类对象（AppKit 3,319 处）；从本镜像的 `__got` / `__auth_got` 载入；从缓存放在所有镜像之外的共用 GOT 池载入别的镜像的类（AppKit 后两种合计 53,026 处）。缓存外的二进制还经 `__objc_classrefs`。别的槽里即使放着类指针也不算：常量字符串的 `isa`（`__cfstring`）、缓存某个类的全局变量都不是对类的静态引用。`adr` 与字面量 `ldr` 两种形态在 AppKit、SwiftUI、Foundation 与几个缓存外的系统 App 里一处都没有，不解码。元类的引用按它的类报。

**一个值是不是类对象，看它所在的镜像列没列它。** 不能按所在的节判断：缓存里 9.2 万个 Swift 类与元类放在 `__data` 而不是 `__objc_data`。`ObjectiveCClassIndex` 直接读 `__objc_classlist` 与每个类的 `isa`（即元类），不经 `MachOImage.objc.classes64`——后者对每个类都重新查一遍 load command，扫描全缓存时让整表扫描慢了一倍。类名只在要报出引用时经 `MachOObjCSection` 读 `class_ro_t`（类已被运行时实现时经 `class_rw_t`）。

**类的身份带位置。** 全缓存 203,621 个类名里有 18,906 个不止一个镜像定义——多是 `/System/iOSSupport` 下的 Mac Catalyst 变体，两个 SwiftUI 都定义 `_TtC7SwiftUI13PinnedBarView`。引用表的键是类名（`CodeReferenceTable.Key.objectiveCClass`，预筛与过滤都按它），引用目标另带类对象的 `CodeLocation`，宿主按位置区分。`objectiveCClassLocations(named:inImageAt:)` 把宿主手里的（镜像，类名）换成位置。

**类字面量接收者。** 发送时 `x0` 里是这样取来的类，接收者记为 `.classLiteral(名字)`（AppKit 35,175 处，发送的 11%）。`objc_opt_self`、`objc_opt_class`、`swift_getInitializedObjCClass` 原样返回传入的类，调用之后 `x0` 不作废：Swift 调 ObjC 类方法先过 `objc_opt_self`，SwiftUI 665 处类字面量接收者里 478 处经它。

**super 发送的类**取同一函数里从 `__objc_superrefs` 载入的类：分类方法（`-[NSDictionary(NSKeyValueCoding) valueForKey:]` 得到 `NSDictionary`）、类方法（槽里是元类，按类报）、没有符号的方法都对；没见到这种载入就退回方法符号里的类。这一载入本身不算类引用——它是编译器实现 `super` 的方式，报出来只会让每个调 `super` 的方法都「引用」了自己的类。Swift 代码的 super 发送不经 `__objc_superrefs`，类来自 `self` 的运行时类或元数据访问器的返回值，扫描不知道，类记为空：Foundation 1,803 处 super 发送里有 374 处、AppKit 8,336 处里有 1,133 处是这种，其余都有类。

**预筛**（`imageIndices(referencingObjectiveCClassAt:among:)`）：定义这个类的镜像，加上导入了类或元类地址上任一符号的镜像——定义镜像的符号表与导出表里落在这两个地址上的全部名字都算。抽样实测，别的镜像引用某个类时 96% 导入 `_OBJC_CLASS_$_<名字>`，其余走别名：Block 字面量的 `isa` 是 `__NSConcreteStackBlock`，XPC 类型是 `__xpc_type_dictionary` 之类。只认 `_OBJC_CLASS_$_` 会漏掉它们。

按字符串取类（`objc_getClass("NSFoo")`，AppKit 183 处）不算类引用。

**代价**（release，28 核，与只有分支跟踪的那次提交交替跑三轮取最好）：全缓存整表 2.03 → 2.40 秒（引用多了 326 万条，+17%），查 `init` 的调用者 1.54 → 1.70 秒，`makeKeyAndOrderFront:` 0.29 → 0.33 秒。扫描器自己缓存类索引，查类不抢分析器的锁；地址落在本镜像 `__TEXT`、或载入的槽是本镜像的非类槽时，在任何查表之前就排除。

### 名字从哪来（第二批）

`CodeFunction.name` 依次取：符号表（`<redacted>` 当没有）；导出表（一个缓存镜像的符号表不一定带导出的符号——SiriAppIntents 的只有两条，导出表却给它的 76,318 个函数起了名；iOS 真机的缓存抹掉本地符号，导出表还在）；ObjC 方法表（类、元类、本镜像的分类；列表的列表里属于别的镜像的条目跳过，它们一定也在那个镜像自己的 `__objc_catlist` 里；元数据不记分类名，读出来是 `-[NSTextView draggingUpdated:]`）；Swift 元数据（类型的元数据访问器 `…Ma` 与 singleton 完成函数 `…Mr`，名字取描述符的 `…Mn` 符号，没有就经 `SymbolicDemangler` 从描述符重建；虚表实现取方法描述符的 `…Tq` 符号，没有就不起；async 实现先跟一步 `{rel32 函数, u32 大小}` 记录）。Swift 元数据给的名字是不带 C 前缀下划线的完整 mangled 名字（`.swiftMetadata(mangledName:)`），可以直接 demangle。

这些名字只在起名时（`codeFunction(at:)`，即 `functions(inImageAt:)`、`function(containing:)`、`functions(containing:)`、`symbolName(at:)`）按镜像读一次、记在函数表上；三个来源各自按需读，前面的来源已经起了名，后面的就不读。扫描不读它们：扫描只需要知道一个函数是不是 ObjC 方法（决定 `x0` 是不是接收者），这一点仍只看符号名。

代价（release，28 核）：给一个镜像的全部函数起名，AppKit 0.24 s（方法表补了 3,961 个、Swift 元数据补了 1,147 个），SiriAppIntents 1.5 s，Matter 0.04 s（方法表补了 30,863 个）。每个镜像起 32 个函数的名字、走遍整个缓存要 6.9 s，4 线程 6.1 s——并发几乎不变快：时间耗在 Swift 运行时的泛型元数据缓存（查找与锁等待）和加载命令的动态转换上，来自 `MachOObjCSection` 与元数据读取代码的泛型实现。宿主给大批结果起名时应只给要保留的那些起。

分析器自己找 `objc_msgSend`、`objc_msgSendSuper2` 与运行时辅助函数的位置时，也读运行时库的导出表，不只读符号表。

### 缓存外镜像的 GOT 槽

缓存外的镜像（第三方 App 自己的二进制）经自己的 `__stubs` / `__auth_stubs` 调别的镜像，槽位由 dyld 在加载时绑定，按 macOS 11 部署目标、不用 chained fixups 编出来的懒绑定二进制也一样：macOS 27.2 上以 `RTLD_LAZY` 加载，函数第一次被调用之前槽里已经是目标地址。所以扫描直接读槽。`LazyBindingTests` 是这件事的哨兵：哪天 dyld 不再在加载时绑定，槽会指回镜像自己的 `__stub_helper`，测试变红，那时再退回桩上的导入名。

### 缓存、内存与生命周期

库里没有全局的按镜像缓存（因此不需要 `SharedCache`）。`CrossReferenceAnalyzer` 只记住宿主让它起过名的镜像的函数表（`functions(inImageAt:)`、`function(containing:)`、`references(madeBy:)`）；整镜像扫描（`referenceTable(ofImageAt:)`、`references(to:inImageAt:)`）临时建表、用完即丢；给一批结果起名用 `functions(containing:)`，同样临时建表——查 `init` 的调用者会碰到 2,759 个镜像，逐个记住又是上 GB——早先扫描也记表，扫完一遍 macOS 27.2 缓存后常驻 1.5 GB（`wholeImageScansKeepNoFunctionTable` 钉住）。

`CodeReferenceTable` 是值，宿主想留多久就留多久，按 `approximateByteCount` 计预算。大镜像的整表很大（GeoServices 约 121 MiB，全缓存合计约 9 GB），28 个线程同时建整表时峰值约 1.5 GB，分配器之后还留着 1.2 GB 脏页不还。**查调用者用 `references(to:inImageAt:)`**：扫描时只留命中的引用，同样扫完全缓存后常驻约 170 MB（4 线程约 106 MB）。

分析器是一个快照：之后才加载的镜像需要新的分析器。

## 吞吐（macOS 27.2，28 核的 Mac Studio）

| 操作 | 现在（28 核） | 第一批：28 核 / 8 线程 / 4 线程 |
|---|---|---|
| 建分析器（4,114 个镜像） | 0.06 秒 | 0.02 秒 |
| 每个镜像都建整表 | 2.4 秒（1.19 亿条引用） | 1.6–1.8 / 3.5 / 5.9 秒（1.16 亿条） |
| `init` 的调用者：预筛出 2,759 个镜像再过滤扫描 | 0.05 + 1.7 秒 | 0.05 + 1.5 秒 / — / 6.1 秒 |
| `makeKeyAndOrderFront:` 的调用者：105 个镜像 | 0.06 + 0.33 秒 | 0.06 + 0.26 秒 |
| 过滤着扫完每个镜像 | 2.0 秒 | 1.7 / — / 6.3 秒 |

比第一批多出来的是寄存器状态沿着分支走（约 +10–20%）与类引用（约 +17%）。「现在」一列是在别的会话同时编译、负载较高的机器上交替跑多轮取的最好值。

单线程解码 AppKit 约 187 MiB/s，比 Capstone 快 25–50 倍（RuntimeViewer 提案落地第一步的探针）。库比探针慢一些（4 线程扫完整个缓存，探针 4.1 秒，库 5.9–6.3 秒），多出来的是起名、建 `CodeReference` 与 selector 字符串；过滤扫描也是先建好每条引用再丢弃，按键提前跳过是能做的优化。

## 测试锚点

- `ARM64InstructionWordTests` / `ARM64TrampolineTests`：手写编码器造指令字；`capstoneAgreesWithTheEncoders` 让 Capstone 反汇编同一批字，编码器写错也藏不住。
- `CrossReferenceAnalyzerTests`（只在 arm64 进程里跑）：`-[NSWindow makeKeyAndOrderFront:]` 发出的三条消息及接收者；SwiftUICore 经桩调用 `swift_beginAccess` 落到 libswiftCore；按键过滤与整表一致；整镜像扫描不留函数表；给一批结果起名也不留；预筛；`branchesCarryTheirStateToTheirTargets` 与 `pathsThatDisagreeLeaveTheRegisterUnknown`：寄存器状态沿着分支走（见上文），后者在第一批的顺序读法下失败；`classicSendsInsideTheCacheNameTheirSelector`：libobjc 的 `-[NSObject debugDescription]` 认出发给 `self` 的 `description`（上文「两种桩布局」末段的第三种形态）；`selectorPrefilterKeepsEverySender` / `importPrefilterKeepsEveryCaller`：预筛只丢掉引用不到主体的镜像——在它丢掉的镜像里每 16 个抽 1 个扫描，一处引用也不许有（Debug 构建扫完整个缓存要几分钟，所以抽样）；`callSitesMatchCapstone` 抽样 400 个 AppKit 函数，Capstone 找到的每一处调用与跳出函数的跳转，扫描都找到了（Capstone 不开 detail 模式就不给操作数，那半边比对曾因此什么都没比，测试现在断言比对过）。
- `ObjectiveCClassReferenceTests`：AppKit 里三种取法都有（取本镜像类的地址、载入本镜像的类、载入别的镜像的类，`NSString` 在其中）；`+[NSThread currentThread]` 发给类字面量 `NSNotificationCenter`；`_BenchmarkHost._started(test:)` 经 `objc_opt_self` 发给 `NSApplication`；分类方法与类方法的 super 类；Matter 里没有符号的方法，super 类与方法表一致；两个 SwiftUI 的同名类各自指向自己；类预筛（`NSWindow`、`NSUUID`、`__NSStackBlock__`、`OS_xpc_dictionary`）丢掉的镜像里抽样一处引用也没有。其中三个在去掉对应做法时变红过：经 `objc_opt_self` 不保留 `x0`、不读 `__objc_superrefs`、预筛只认 `_OBJC_CLASS_$_`。
- `FallbackNamingTests`：导出表给的名字落在导出的地址上（SiriAppIntents）；AppKit 里方法表给的名字与 `-[C sel]` 符号一致（去掉分类名后 99.9% 以上）；SwiftUICore 里从元数据重建的名字与真实的 `…Ma`、`…Mr`、方法符号一致（99% 以上）；Matter 的方法在没有符号时由方法表起名；SiriAppIntents 几乎每个类型的访问器都有名字，重建的名字 demangle 出来是元数据访问器。
- `StandaloneImageTests`：SymbolTestsCore fixture 经自己的桩调用 libswiftCore，没有一条停在只有名字的导入上。
- `LazyBindingTests`：现编一个懒绑定的 dylib，见上文「缓存外镜像的 GOT 槽」。
