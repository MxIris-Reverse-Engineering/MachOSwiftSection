# CrossReferenceAnalysis

从 arm64 机器码里读出一个镜像的函数表，以及每个函数引用了什么：直接调用与尾调用、ObjC 消息发送、`super` 发送、经桩的跨库调用、间接调用、ObjC 类引用、Swift 类型引用。只在进程内读 `MachOImage`，只支持 arm64 / arm64e。RuntimeViewer 的交叉引用功能（调用者、被调、类型引用）建在它上面。

- 提案：[draft-cross-reference-analysis](../../Evolutions/draft-cross-reference-analysis.md)（本库这一层）；整体设计、实测数据在 RuntimeViewer 的 [draft-cross-references](https://github.com/MxIris-Reverse-Engineering/RuntimeViewer/blob/feature/cross-references/Documentations/Evolutions/draft-cross-references.md)。
- 依赖：MachOKit、`ARM64InstructionDecoding`；第二批起还有 `MachOObjCSection`（方法表、类的只读数据）、`MachOSwiftSection` 与 `SwiftInspection`（Swift 元数据与 `SymbolicDemangler`）、`Demangling`——给符号表没有名字的函数起名，以及认出扫描碰到的类与类型（类列表、类型描述符、mangled 名字）。不依赖 Capstone。

## 子系统

| 子系统 | 文件 | 分工 |
|---|---|---|
| 1. 指令字与跳板 | `ARM64InstructionDecoding` 模块的 `ARM64InstructionWord`、`ARM64Trampoline` | 手写读取少数几类 A64 编码；按形状认 GOT 桩、stub island 与全缓存共用的 selector 桩。与 SwiftThunkAnalysis 共用 |
| 2. 地址空间 | `CrossReferenceAnalyzer` | 进程里全部镜像（整个共享缓存加缓存外已加载的镜像）、各镜像的路径与安装名、`__TEXT` 的内存区间、缓存的可执行与可读映射、`objc_msgSend` 与运行时辅助函数的位置；给函数起名要用的函数表按需建一次并记住 |
| 3. 函数表 | `Scanning/ImageFunctionTable` | 函数起点（`LC_FUNCTION_STARTS` 与 `__text` 里的符号取并集）、主名与代码合并留下的别名、辅助函数、镜像自带的 `__objc_stubs` / `__stubs` / `__auth_stubs`、`__objc_selrefs`、放类引用的槽（`__got`、`__auth_got`、`__objc_classrefs`）与 `__objc_superrefs`、各段的地址区间 |
| 3a. 补充名字 | `Scanning/ImageFallbackNames` | 符号表没有名字的函数，依次从导出表、ObjC 方法表、Swift 元数据起名；起名时按镜像按需读，扫描不读 |
| 3b. 类索引 | `Scanning/ObjectiveCClassIndex` | 一个镜像定义的类与元类，按地址；直接读 `__objc_classlist` 与各类的 `isa`。扫描时按需建、分析器记住；类名只在报出引用时读 |
| 3c. 类型索引 | `Scanning/SwiftTypeIndex` | 一个镜像 `__swift5_types` 列出的描述符与各自的元数据访问器；类型的 key 按需算，优先取 `…Mn` 符号 |
| 4. 扫描 | `Scanning/ReferenceScanner`、`Scanning/RegisterFile`、`Scanning/RuntimeHelperNames` | 逐条解码、跟踪寄存器、解析调用目标 |
| 5. 结果 | `Models/*` | `CodeLocation`、`CodeFunction`、`CodeReference`、`CodeReferenceTarget`、按目标分组的 `CodeReferenceTable`，以及给宿主常驻用的紧凑版 `CodeReferenceIndex` |
| 6. 预筛与过滤 | `CrossReferenceAnalyzer+Prefiltering`、`CrossReferenceAnalyzer+Linkage`、`Scanning/RenamedReexportIndex`、`references(to:inImageAt:)` | 按未定义符号（只对 C 与 ObjC 符号，连同别的镜像改名再导出的名字）、链接关系（Swift 符号）、`__objc_selrefs`、类对象上的符号筛出可能引用某个符号、selector 或类的镜像；扫描时只留命中的引用 |
| 7. 类型查询 | `CrossReferenceAnalyzer+SwiftTypes` | Swift 类型的身份、预筛与按类型的扫描；`SwiftTypeQuery` 比对描述符位置与名字里的符号引用 |

## 关键契约

### 地址

`CodeLocation` 是（镜像在 `images` 里的位置，镜像自己的未滑动地址）。缓存外两个镜像的未滑动地址可能重合，所以位置必须带镜像。跨镜像的查找一律换成运行时地址（未滑动地址加该镜像的 slide）再查 `__TEXT` 区间表，算完再换回 `CodeLocation`。

**镜像的路径是 dyld 加载它的路径。** 缓存里的镜像就是安装名；缓存外的取 `dladdr` 按镜像头读到的加载路径——App 的主程序与插件 bundle 没有安装名（`MachOImage.path` 为空），App 自带的框架的安装名是 `@rpath/…`，哪个都对不上宿主手里的路径（交叉引用审查 B3，2026-10-17 之前就是这样，缓存外的镜像查不到）。另有一张「安装名 → 镜像」的表给加载命令解析链接关系用：同一安装名的两份拷贝（两个插件各带一份同一框架）都算；`imageIndex(forPath:)` 先按路径、再按安装名找。用 `-bundle_loader` 链接宿主的插件经 `EXECUTABLE_ORDINAL` 绑定主程序，没有加载命令指向它，所以每个 bundle 都算作主程序的依赖方。

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

`RegisterFile` 只记录 `adrp` / `adr` / `add` 算出的地址、从已知地址加载的槽位、ObjC 方法入口时 `x0` 里的接收者、指针认证常量，以及「这个寄存器的值是从内存读来的」和读取时的偏移。不建模的指令一律作废它写的寄存器（宁可多忘，不留陈旧的值）；调用作废 `x0`–`x18` 与 `x30`——原样返回所传类的三个函数例外，`x0` 留着（见「类引用」）。PAC 与 AUT 原地签名或认证，寄存器的含义不变，保留；XPAC 作废。

一条指令写哪些寄存器由 `RegisterFile.registersWritten(by:)` 按 A64 的编码分组判断，容易漏的几类：前 / 后变址的读写（单寄存器与寄存器对、通用与 SIMD 寄存器都一样）会改掉基址寄存器；原子指令不论内存序都返回旧值，不带内存序的那种（`ldadd`、`swp`）编码像存储；`ldxp` 写第二个寄存器，`casp` 写 `Rs` 与 `Rs+1`；`umov` / `smov`、浮点转整数与转定点写通用寄存器；SVE / SME 里有几条写通用寄存器（`cntd`、`addvl`、`rdsvl`）；`mrs` 与 `sysl`；`svc` 的结果在 `x0`、`x1`。第一批漏了其中大半（交叉引用审查 A1）；`RegisterFileTests` 用汇编器编出的 48 条指令逐条核对，并用 Capstone 的寄存器访问表独立核对那张表没有漏项（Capstone 把 `cas` / `casp` 的基址也算作被写，架构上并不写，测试里列为已知偏差）。SwiftThunkAnalysis 的两个跟踪器同一轮补上了成对回写的基址。

**寄存器状态沿着分支走（第二批）。** 一个函数内：向前的分支（条件跳转与 `b`）把当时的寄存器状态带到目标处；目标处若前一条是无条件转移（`b`、`br`、`ret`），就以带来的状态为准，否则与顺序走下来的状态取交集——同一个寄存器两条路径放的东西一致才保留。无条件转移之后没有分支指向的指令（跳转表的落点之类）、以及向后分支的目标（循环头，回边的状态此时还不知道）忘掉调用方保存的寄存器。第一批只按指令顺序往下读，汇合处会沿用最后一条路径的值：`-[NSString stringByAppendingString:]` 里一个块把参数放进 `x0`、下一个块放 `self`，两者跳到同一处发送 `copyWithZone:`，顺序读法把接收者说成 `self`。这一改动让 AppKit 80 万处引用里 9,699 处发送多认出了 `self`（前一条路径的调用冲掉了 `x0`，而实际到达的路径没有），78 处不再说 `self`，selector 几乎不受影响；release 下全缓存整表扫描由 1.6–1.8 s 变为 2.0 s。快照是定长值（`SIMD32`），不分配内存；待到的目标与循环头按地址排序、随扫描游标前进。只记「无条件转移后忘掉」的简化版试过，会丢掉 `+[NSObject instanceMethodForSelector:]` 这类早退之后的正确接收者，弃用。

**已知局限（审查 A5，2026-10-17）。** 循环头与没人指向的落点只作废 `x0`–`x18`，`x19`–`x28` 可能带着到不了那里的旧值：`-[NSMenuItem _titlePathForUserKeyEquivalents]` 的循环把 `x22` 从 `self` 换成父菜单项再跳回，循环头之后的发送仍被说成发给 `self`。量过（release，六个大镜像 332 万条引用、257 个抽样镜像 711 万条）：对含循环的函数反复扫到回边状态不变的精确做法，与现行做法相差 0.04% / 0.02% 的引用，扫描多花 42% / 61%；循环头一律全部作废则会丢掉约 3.9 万条正确的事实（`self` 发送少 15%）。只作废「循环里写过的寄存器」的近似试了几版，都还会丢掉正确的事实，弃用。数据与抽查见 [2026-10-17 审查记录](../../../Roadmaps/2026-10-17-cross-reference-analysis-review-findings.md) A5。看过数据后决定保持现状，理由与复审条件见 [ReviewAdjudications A68](../ReviewAdjudications.md)。

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

### Swift 类型引用（第二批）

一处 Swift 类型引用有三种来源，都报成 `.reference` 种类：

1. **调用类型的元数据访问器。** 调用照常报一条，另加一条目标为 `.swiftType(descriptor:)` 的引用。访问器靠各镜像 `__swift5_types` 列出的描述符认（描述符 +12 处是访问器的相对指针），`Scanning/SwiftTypeIndex` 按需给每个镜像建一份。
2. **取访问器或元数据的地址。** `adrp` / `add` 出、或从 GOT 槽载入访问器地址，或结构体、枚举、`Optional`、导入类型的元数据——元数据首字是种类（0x200–0x204），次字是描述符。Swift 类的元数据就是它的 ObjC 类对象，按类引用报（见上一节）。
3. **按 mangled 名字实例化。** 调用本镜像的 `__swift_instantiateConcreteTypeFromMangledName…` 辅助函数，或运行时的 `swift_getTypeByMangledName…`。macOS 27.2 上几乎都是 V2：`x1` 指向 `{到名字的 int32 偏移, int32 长度}` 记录；旧形态的名字在 `x0` 的缓存变量里，类型一经实例化缓存里就只剩元数据，名字读不到，不报。没有符号的辅助函数按形态认：不超过 0x90 字节、调用运行时那几个入口；读 `[x1]` 的是 V2。目标是 `.swiftTypeName(.mangledName(location:length:))`：名字里可能夹着符号引用，解开一个要几十微秒，扫描不解开，表也不按类型归档它。没有描述符的访问器——泛型实例（`$sSay7SwiftUI4TextVGMa`）、存在类型、导入类型——按符号名认，报 `.swiftTypeName(.accessorSymbol(…))`。

**表按描述符位置归档**（`CodeReferenceTable.Key.swiftTypeDescriptor`），不按类型的 key。key 是名义类型的 mangling（`7SwiftUI4TextV`、`Sa`），取自描述符的 `…Mn` 符号（demangle 再 mangle，与名字、符号里的拼法一致）；没有符号时才 demangle 描述符的上下文，而那样拼出的 key 会偏：受约束扩展里的嵌套类型带上扩展的要求（SwiftUICore 有 58 处访问器调用拼法不同），其他模块类型的扩展里的 private 类型干脆丢了自己（Foundation 的 `Mutex<…>.LockResult` 成了 `15Synchronization5MutexV`）。位置没有这些问题，扫描时也不必解开任何东西。从名字取 key 时，泛型实参各算一个类型，嵌套在泛型类型（或它的受约束扩展）里的类型去掉父类型的实参：`Regex<AnyRegexOutput>.Match` 是 `17_StringProcessing5RegexV5MatchV` 加上 `AnyRegexOutput`。

**查询**（`references(toSwiftType:inImageAt:)`）带一个比对器：访问器与元数据的引用比描述符位置；名字逐字节走，符号引用（`\x01` 直接、`\x02` 经指针）指向的描述符就是这个类型，就算提到了它。只有名字可能直接拼出来的类型——标准库、`_Concurrency`、从 C / ObjC 导入的，key 以 `s` 或 `S` 开头——才解开名字确认；文本子串比对不可靠，mangling 会把同一名字里重复出现的单词换成替身。前提是其他类型在名字里一定以符号引用出现：在 Foundation、SwiftData、libswift_Concurrency、SwiftUI 里逐个解开全部名字核对过，没有例外（AppIntentsServices 有 56 处 key 对不上，原始字节全是符号引用，是那个镜像没有 `…Mn` 符号造成的拼法差别）。导入的类型每个用到它的镜像各有一份描述符，比的是 key。Swift 类同时比它的 ObjC 类对象的位置。macOS 与 Mac Catalyst 变体里的同一个类型按位置分开。协议没有类型描述符，不在这一批。

宿主的用法：类型对象 → 描述符位置（或经 `swiftTypeDescriptorLocations(withKey:inImageAt:)`，先找 `…Mn` 符号）→ `swiftTypeIdentity(ofDescriptorAt:)` → 预筛 → 每个候选镜像 `references(toSwiftType:inImageAt:)`。`swiftTypeKeys(in:)` 解开一个 `SwiftTypeName`，供显示用。

**预筛**（`imageIndices(referencingSwiftType:among:)`）：定义镜像本身；定义镜像导出了这个类型的符号时（描述符 `…Mn`、元数据访问器 `…Ma`、元数据 `…N` 任何一个），再加上能绑定到它的镜像（按链接关系，见下一节），类再并上类预筛；名字可能拼出来的类型——标准库的、导入的，每个镜像都可能自己命名——凡是 Swift 镜像都算。**一个符号都没导出的类型（内部类型）只可能被定义镜像引用**：别的镜像要引用它，只能经这几个符号绑定，或者在名字里拼出它，而内部类型在别的模块里拼不出来。2026-10-17 之前没有这条，AppKit 的内部结构体 `NSSmartNamingSuggestion` 一次类型引用查询要扫所有链接 AppKit 的镜像——几乎整个缓存，Debug 构建下要好几分钟（用户实测，CPU 占满）；现在只扫 AppKit 一个（测试 `typesNoImageExportsAreLookedForInTheirOwnImage`，并对链接 AppKit 的镜像每 64 个抽 1 个确认确实没有引用）。导出表按镜像在第一次需要时读成集合留着（`exportedSymbolNames(ofImageAt:)`）。Swift 函数不需要同样处理：缓存里没导出的函数在进程内看不到本地符号，没有 `.symbol` 名字，本来就不会按链接关系去扩大候选。

**代价**（release，28 核，与只有分支跟踪的那次提交交替跑）：全缓存整表 2.1 → 3.0 秒（引用 1.16 亿 → 1.26 亿条），查 `init` 的调用者 1.6 → 1.8 秒——只查 selector 或函数时不找类与类型引用，发送处的类字面量接收者照认。踩过两个坑。一是 `keep(reference(to: …))` 这种写法：参数里修改扫描器，外层又在同一个扫描器上调非 mutating 方法，Swift 只好每次把整个扫描器连同它的备忘字典复制一份，整表扫描一度要 95 秒——第一批的 `keep` 是静态方法，没有这个问题。二是类型索引若每次都去分析器的锁里取，等锁占掉大半时间；现在扫描器自己留一份（`ScanIndexes`，引用类型，解析调用目标的非 mutating 路径也用得上）。

### 预筛：缓存几乎不留 Swift 的未定义符号

macOS 27.2 的缓存里，4,113 个镜像只有 245 个在符号表里留着 Swift 的未定义符号（libswift 系列、Foundation、CoreData、AXCoreUtilities 等），其余的绑定 Swift 符号后什么也不留：SharedWithYou 留了 314 个未定义符号，全是 C 函数与 ObjC 类，可它照样经全缓存共用的 GOT 桩调用 `URL` 的元数据访问器；AppKit 的 5,085 个里也没有一个 `$s…`。所以「导入了某个符号的镜像」只对 C 与 ObjC 符号成立。第一批的函数预筛只拿 C 函数（`CFRelease`、`dispatch_async`）测过，对 Swift 函数一直是错的：查 `URL.path` 的调用者时只留下按名字导入它的 44 个镜像，其余调用它的镜像全被丢掉（`swiftFunctionPrefilterKeepsEveryCaller` 在旧做法下变红）。

**改名再导出。** 一个镜像可以把别的镜像的符号换个名字导出：libsystem_c 把 libsystem_platform 的 `__platform_strlen` 导出成 `_strlen`，CoreGraphics 把 SkyLight 的 1,112 个 `_SL…` 函数导出成 `_CG…`，UIFoundation 把 CoreText 的 `CTEmojiImageAsset` 类导出成 `NSEmojiImageAsset`。调用方导入的是新名字——AppKit 按 CoreGraphics 的名字导入了 273 个 SkyLight 函数——所以按导入预筛时这些名字也要比。macOS 27.2 的缓存里 12 个镜像共 1,438 条这样的再导出。`RenamedReexportIndex` 在第一次需要时并发走一遍所有镜像的导出表，只记改名的再导出（名字只在命中时拼出），按「被再导出的镜像与名字」归档，之后留着；`reexportedNames(ofSymbolsNamed:inImageAt:)` 顺着改名再改名、以及经伞形框架整体再导出的情形找全别名（acfsSupport 从 CoreServices 再导出 Metadata 的 `_kMDConfigErase`）。函数预筛与类预筛都把别名一并比对。2026-10-17 之前没有这一步，查 `__platform_strlen`、`_SLSMainConnectionID` 的跨库调用者会漏掉 AppKit（`RenamedReexportTests`）。

Swift 符号改按链接关系预筛（`imageIndices(linkingImageAt:among:)`，`CrossReferenceAnalyzer+Linkage`）：一个镜像只能绑定到它链接的镜像，以及这些镜像（层层）再导出的镜像的符号，这些加载命令在缓存里完整保留——SwiftUI 再导出 SwiftUICore，链接 SwiftUI 的镜像就算能绑定 SwiftUICore。比按导入粗得多（链接 Foundation 的镜像数以千计），但不漏。宿主查函数的调用者用 `imageIndices(callingFunctionAt:symbolNames:among:)`：C 与 ObjC 名字按导入，Swift 名字按链接。Swift 类的类预筛、Swift 类型的类型预筛同理。链接关系第一次用到时读一遍所有镜像的加载命令，之后留着。

### 名字从哪来（第二批）

`CodeFunction.name` 依次取：符号表（`<redacted>` 当没有）；导出表（一个缓存镜像的符号表不一定带导出的符号——SiriAppIntents 的只有两条，导出表却给它的 76,318 个函数起了名；iOS 真机的缓存抹掉本地符号，导出表还在）；ObjC 方法表（类、元类、本镜像的分类；列表的列表里属于别的镜像的条目跳过，它们一定也在那个镜像自己的 `__objc_catlist` 里；元数据不记分类名，读出来是 `-[NSTextView draggingUpdated:]`）；Swift 元数据（类型的元数据访问器 `…Ma` 与 singleton 完成函数 `…Mr`，名字取描述符的 `…Mn` 符号，没有就经 `SymbolicDemangler` 从描述符重建；虚表实现取方法描述符的 `…Tq` 符号，没有就不起；async 实现先跟一步 `{rel32 函数, u32 大小}` 记录）。Swift 元数据给的名字是不带 C 前缀下划线的完整 mangled 名字（`.swiftMetadata(mangledName:)`），可以直接 demangle。

这些名字只在起名时（`codeFunction(at:)`，即 `functions(inImageAt:)`、`function(containing:)`、`functions(containing:)`、`symbolName(at:)`）按镜像读一次、记在函数表上；三个来源各自按需读，前面的来源已经起了名，后面的就不读。扫描不读它们：扫描只需要知道一个函数是不是 ObjC 方法（决定 `x0` 是不是接收者），这一点仍只看符号名。

代价（release，28 核）：给一个镜像的全部函数起名，AppKit 0.24 s（方法表补了 3,961 个、Swift 元数据补了 1,147 个），SiriAppIntents 1.5 s，Matter 0.04 s（方法表补了 30,863 个）。每个镜像起 32 个函数的名字、走遍整个缓存要 6.9 s，4 线程 6.1 s——并发几乎不变快：时间耗在 Swift 运行时的泛型元数据缓存（查找与锁等待）和加载命令的动态转换上，来自 `MachOObjCSection` 与元数据读取代码的泛型实现。宿主给大批结果起名时应只给要保留的那些起。

分析器自己找 `objc_msgSend`、`objc_msgSendSuper2` 与运行时辅助函数的位置时，也读运行时库的导出表，不只读符号表。

### 缓存外镜像的 GOT 槽

缓存外的镜像（第三方 App 自己的二进制）经自己的 `__stubs` / `__auth_stubs` 调别的镜像，槽位由 dyld 在加载时绑定，按 macOS 11 部署目标、不用 chained fixups 编出来的懒绑定二进制也一样：macOS 27.2 上以 `RTLD_LAZY` 加载，函数第一次被调用之前槽里已经是目标地址。所以扫描直接读槽。`LazyBindingTests` 是这件事的哨兵：哪天 dyld 不再在加载时绑定，槽会指回镜像自己的 `__stub_helper`，测试变红，那时再退回桩上的导入名。

### 缓存、内存与生命周期

库里没有全局的按镜像缓存（因此不需要 `SharedCache`，理由见 [ReviewAdjudications](../ReviewAdjudications.md) A62）。`CrossReferenceAnalyzer` 记住宿主让它起过名的镜像的函数表（`functions(inImageAt:)`、`function(containing:)`、`references(madeBy:)`）；整镜像扫描（`referenceTable(ofImageAt:)`、`references(to:inImageAt:)`）临时建表、用完即丢；给一批结果起名用 `functions(containing:)`，同样临时建表——查 `init` 的调用者会碰到 2,759 个镜像，逐个记住又是上 GB——早先扫描也记表，扫完一遍 macOS 27.2 缓存后常驻 1.5 GB（`wholeImageScansKeepNoFunctionTable` 钉住）。

第二批起分析器还在自己的生命期里留着：扫描碰到的每个镜像的类索引（类与元类按地址，类名读过的记住）与类型索引（描述符与访问器，key 算过的记住），链接关系，以及改名再导出表。它们以缓存里的类与类型的总数为上限（macOS 27.2 有 203,621 个类名），没有单独测过占用；下面那个约 170 MB 的数字是第二批之前测的。宿主想放掉就换一个分析器（RuntimeViewer 的会话在缓存外的镜像变化、或起过名的镜像超过 64 个时换）。

分析器存活期间若有缓存外的镜像被卸载，再读它会读到已释放的内存；极少见，没有防（A63）。名字的解开一律是瞬时的：类型查询碰到的访问器符号与 mangled 名字不进全局的 `NodeCache`，也不进进程级的 demangle 记忆（交叉引用审查 B2，`TypeNameRetentionTests`），按镜像的 `demangleContext` 记忆随镜像淘汰。

`CodeReferenceTable` 是值，宿主想留多久就留多久，按 `approximateByteCount` 计预算（不含字符串的堆存储；同一次扫描里重复的名字共用一份）。大镜像的整表很大（GeoServices 约 121 MiB，全缓存合计约 9 GB），28 个线程同时建整表时峰值约 1.5 GB，分配器之后还留着 1.2 GB 脏页不还。**查调用者用 `references(to:inImageAt:)`**：扫描时只留命中的引用，同样扫完全缓存后常驻约 170 MB（4 线程约 106 MB）。

**要为少数几个镜像常驻、反复查，用 `CodeReferenceIndex`**（`referenceIndex(ofImageAt:)`，2026-10-18 为 RuntimeViewer 的预先准备新增）。它按目标分组存放：选择子、导入名、类名每个只存一份，引用所在的函数与指令存成相对 `__text` 起点的 32 位偏移（一条 16 字节），只留查调用者与查类型引用会读的引用，间接调用与落在镜像外的跳转不留。macOS 27.2 实测（`approximateByteCount`，含名字的堆存储）：AppKit 21 MiB（整表 67 MiB，87.5 万条引用里留 85.6 万条），Foundation 9 MiB（34），SwiftUICore 9 MiB（35），libswiftCore 1 MiB（7）。`index.references(to:)` 与 `references(toSwiftType:in:)` 回答的和过滤扫描完全相同，顺序也相同（按指令地址，同一条指令的调用排在它顺带的类型引用前面）。建索引会**留住**镜像的函数表——给结果起名要用；分析器被换掉后，索引照样能读（它不持有分析器），宿主用 `keepFunctionTable(ofImageAt:)` 让新分析器重新留住。`referenceIndex(ofImageAt:reportingProgress:)` 每扫 2,048 个函数报一次进度，回答「停」就不建了。Debug 构建建 AppKit 的索引约 6 秒。

分析器是一个快照：之后才加载的镜像需要新的分析器。

## 吞吐（macOS 27.2，28 核的 Mac Studio）

| 操作 | 现在（28 核） | 第一批：28 核 / 8 线程 / 4 线程 |
|---|---|---|
| 建分析器（4,114 个镜像：缓存的 4,113 个，加基准程序自己） | 0.06 秒 | 0.02 秒 |
| 每个镜像都建整表 | 3.0 秒（1.26 亿条引用） | 1.6–1.8 / 3.5 / 5.9 秒（1.16 亿条） |
| `init` 的调用者：预筛出 2,759 个镜像再过滤扫描 | 0.05 + 1.8 秒 | 0.05 + 1.5 秒 / — / 6.1 秒 |
| `makeKeyAndOrderFront:` 的调用者：105 个镜像 | 0.06 + 0.33 秒 | 0.06 + 0.26 秒 |

比第一批多出来的是寄存器状态沿着分支走（约 +10–20%）、类引用与 Swift 类型引用（整表约 +45%，只查 selector 或函数时约 +10%）。「现在」一列是在别的会话同时编译、负载较高的机器上交替跑多轮取的最好值。

单线程解码 AppKit 约 187 MiB/s，比 Capstone 快 25–50 倍（RuntimeViewer 提案落地第一步的探针）。库比探针慢一些（4 线程扫完整个缓存，探针 4.1 秒，库 5.9–6.3 秒），多出来的是起名、建 `CodeReference` 与 selector 字符串；过滤扫描也是先建好每条引用再丢弃，按键提前跳过是能做的优化。

## 测试锚点

- `ARM64InstructionWordTests` / `ARM64TrampolineTests`：手写编码器造指令字；`capstoneAgreesWithTheEncoders` 让 Capstone 反汇编同一批字，编码器写错也藏不住。
- `CrossReferenceAnalyzerTests`（只在 arm64 进程里跑）：`-[NSWindow makeKeyAndOrderFront:]` 发出的三条消息及接收者；SwiftUICore 经桩调用 `swift_beginAccess` 落到 libswiftCore；按键过滤与整表一致；整镜像扫描不留函数表；给一批结果起名也不留；预筛；`branchesCarryTheirStateToTheirTargets` 与 `pathsThatDisagreeLeaveTheRegisterUnknown`：寄存器状态沿着分支走（见上文），后者在第一批的顺序读法下失败；`classicSendsInsideTheCacheNameTheirSelector`：libobjc 的 `-[NSObject debugDescription]` 认出发给 `self` 的 `description`（上文「两种桩布局」末段的第三种形态）；`selectorPrefilterKeepsEverySender` / `importPrefilterKeepsEveryCaller` / `swiftFunctionPrefilterKeepsEveryCaller`：预筛只丢掉引用不到主体的镜像（最后一个是 Swift 函数，见上文「预筛：缓存几乎不留 Swift 的未定义符号」）——在它丢掉的镜像里每 16 个抽 1 个扫描，一处引用也不许有（Debug 构建扫完整个缓存要几分钟，所以抽样）；`callSitesMatchCapstone` 抽样 400 个 AppKit 函数，双向比对：Capstone 找到的每一处调用与跳出函数的跳转，扫描都找到了；扫描报的每一处也都是 Capstone 眼里的调用或跳转（`br` 除外，Capstone 分不出跳转表与尾调用）。Capstone 不开 detail 模式就不给操作数，那半边比对曾因此什么都没比，测试断言比对过不止一处。
- `ObjectiveCClassReferenceTests`：AppKit 里三种取法都有（取本镜像类的地址、载入本镜像的类、载入别的镜像的类，`NSString` 在其中）；`+[NSThread currentThread]` 发给类字面量 `NSNotificationCenter`；`_BenchmarkHost._started(test:)` 经 `objc_opt_self` 发给 `NSApplication`；分类方法与类方法的 super 类；Block 里的 super 发送按 `__objc_superrefs` 得到所在方法的类（Block 的符号不是方法名，只有槽位能给出类；分类方法那个测试里槽位与符号给出的类相同，分辨不出）；Matter 里没有符号的方法，super 类与方法表一致；两个 SwiftUI 的同名类各自指向自己；类预筛（`NSWindow`、`NSUUID`、`__NSStackBlock__`、`OS_xpc_dictionary`）丢掉的镜像里抽样一处引用也没有。其中三个在去掉对应做法时变红过：经 `objc_opt_self` 不保留 `x0`、不读 `__objc_superrefs`、预筛只认 `_OBJC_CLASS_$_`。
- `SwiftTypeReferenceTests`：SwiftUICore 里访问器调用报出的类型与访问器符号全部一致（一万处以上）；紧邻的 `adrp` / `add` 取出的地址上若有符号，报出的类型与符号一致；Foundation 的名字取自 `x1` 的记录、落在 `__swift5_typeref`、能解开；Foundation 与 SwiftData 里，查询保留的名字恰是解开后提到该类型的名字（40 个最常被符号引用的类型；另四个标准库类型，查询退回的正是同一套解开，所以它们只守着符号引用不指错描述符）；两个 SwiftUI 的同名类型按位置分开；类型预筛（Foundation 的 `URL` 与 `JSONEncoder`、SwiftUICore 的 `Text`）丢掉的镜像里抽样一处引用也没有——按导入符号预筛时三者都漏。
- `FallbackNamingTests`：导出表给的名字落在导出的地址上（SiriAppIntents）；AppKit 里方法表给的名字与 `-[C sel]` 符号一致（去掉分类名后 99.9% 以上）；SwiftUICore 里从元数据重建的名字与真实的 `…Ma`、`…Mr`、方法符号一致（99% 以上）；Matter 的方法在没有符号时由方法表起名；SiriAppIntents 几乎每个类型的访问器都有名字，重建的名字 demangle 出来是元数据访问器。
- `StandaloneImageTests`：SymbolTestsCore fixture 经自己的桩调用 libswiftCore，没有一条停在只有名字的导入上；它的路径是加载路径而不是 `@rpath/…`，安装名也能查回它；测试包（`MH_BUNDLE`，没有安装名）的路径等于 `dladdr` 给的；测试包算作主程序的依赖方。
- `RegisterFileTests`：48 条汇编器编出的指令，每条写的寄存器都被作废，Capstone 的寄存器访问表独立核对这张表；普通读写只作废目标寄存器。
- `RenamedReexportTests`：AppKit 按 `_strlen`、`_CGSMainConnectionID` 调用 `__platform_strlen`、`_SLSMainConnectionID`，CharacterPicker 按 `NSEmojiImageAsset` 引用 CoreText 的类，三者的预筛都留住了它们；别名经伞形框架的那一种（`_xkMDConfigErase`）。
- `TypeNameRetentionTests`：类型查询解开的访问器符号、mangled 名字与描述符符号都不留在全局 `NodeCache` 与进程级 demangle 记忆里（用每次随机的名字，与并行跑的测试互不干扰）。
- `LazyBindingTests`：现编一个懒绑定的 dylib，见上文「缓存外镜像的 GOT 槽」。
- `CodeReferenceIndexTests`：Foundation 整表的每一个键，索引给出的引用与整表逐条相同、顺序相同，条数等于整表里有键的加上 Swift 类型名；AppKit 里一次查几个键（selector、libswiftCore 的函数、`NSWindow`）与过滤扫描逐条相同；Foundation 里 `URL`、`JSONEncoder`（类，经类对象）与标准库的 `Sa`（名字里拼出来，要解开）从索引查与按类型扫描逐条相同；索引不到整表的一半大；建索引留住函数表；进度从 0 报到函数总数，回答「停」就不建。
