# Draft - 交叉引用分析：从机器码读出每个函数引用了什么

- **状态**: In Progress
- **创建日期**: 2026-10-16
- **最后更新**: 2026-10-17
- **关联**: RuntimeViewer 的 [draft-cross-references](https://github.com/MxIris-Reverse-Engineering/RuntimeViewer/blob/feature/cross-references/Documentations/Evolutions/draft-cross-references.md)。交叉引用的整体设计、前期调研与实测数据都在那里，本提案只定本库这一层。

## 摘要

新增 public target `CrossReferenceAnalysis`（`Sources/Analysis/CrossReferenceAnalysis`）：给出一个镜像的函数表，以及每个函数引用了什么——直接调用与尾调用、ObjC 消息发送、super 发送、跨库调用、类型引用、间接调用及其候选目标。RuntimeViewer 的交叉引用（调用者、被调、类型引用）建在它上面。规则放在本库，沿用「二进制分析的规则放在 MachOSwiftSection，RuntimeViewer 只负责显示」的做法。

## 方案

- **读取**：只读进程内的 `MachOImage`，只支持 arm64 / arm64e。`MachOFile` 与 swift-section 子命令留给以后的提案。
- **函数表**：边界取自 `LC_FUNCTION_STARTS`（MachOKit 在内存镜像上给出的 `FunctionStart.offset` 已经是未滑动的绝对地址，与它的文档注释不符）。名字依次取自符号表、ObjC 方法表（`ObjCClassMethodIndex`）、Swift 方法描述符的实现（`implementationSymbols`）；同一地址上的多个名字（代码合并）归为一个函数；都叫不出名字时 `name` 为 `nil`，照样扫描。
- **解码**：手写，只认调用、尾调用、间接调用、`adrp` / `add` / `ldr` 取地址、`movk` / `mov` 鉴别常量、`autda` / `ldraa` 这几类，其余指令只作废它写的寄存器。实测比 Capstone 快 25–50 倍，Capstone 只在测试里作对照。`__text` 里夹着数据，读任何跳转目标之前先确认它落在缓存的可执行映射或本镜像里。
- **调用目标**：镜像自带的 `__objc_stubs` / `__stubs` / `__auth_stubs`（macOS 26、iOS 26 及更早，以及 Simulator）；macOS 27 / iOS 27 全缓存共用的 selector 桩（`x1` 就是 selector 字符串，以字符串地址为键）与 GOT 桩（进程内读出槽位里已绑定的指针）；stub island。GOT 桩与 island 的形状识别和 `MachOThunkEnvironment` 共用一份：把它的 `stubSlotAddress` / `stubIslandTarget` 抽成两边都能调用的 package 级纯函数。
- **间接调用**：按 `autda` 的常量分出虚表（isa，0x6ae1）、value witness table（0x2e3f）与协议见证表；value witness 调用标为运行时辅助调用。虚表与见证表调用按（鉴别常量、表内偏移）反查本镜像的根声明：常量是带 `$s` 前缀的 `SILDeclRef` mangling 经 `getPointerAuthStableSipHash` 再取 `% 0xFFFF + 1`。闭包调用只给签名形态。
- **类型引用**：`$s…Ma` 元数据访问器、`__swift_instantiateConcreteTypeFromMangledName*` / `swift_getTypeByMangledName*`（名字取自 `x0` 指向的缓存变量）、ObjC 类引用。
- **运行时辅助调用**：名单由本库维护，结果里只打标记，过滤交给宿主。
- **预筛**：按符号表的未定义符号与 `__objc_selrefs`，筛出可能引用某个符号或 selector 的镜像。
- **不缓存**：每次调用都重新读；整镜像扫描返回一个值，留多久由宿主决定（RuntimeViewer 按字节预算做 LRU），所以不新增 `SharedCache`。
- **分三批落地**，每批单独可用：① 函数表（符号表与函数起点）、解码、两种桩布局、selector、辅助调用标记、单函数与整镜像 API、预筛，发一个版本后 RuntimeViewer 就能开始它的第 3 步；② ObjC 方法表与 Swift 元数据命名、类型引用；③ 间接调用的表来源、鉴别常量反查与候选。
- **测试**：解码器用合成的指令字单测；SymbolTestsCore fixture（arm64）测函数表与直接调用；arm64e 才有的形状用自编的 arm64e 目标文件和进程内的系统缓存测，并以 Capstone 的反汇编作对照。

第一批落地的 API。草图原是一组接收 `MachOImage` 的静态函数；实现时发现跨镜像解析目标要用到整个进程的镜像表，改成一个由宿主持有的分析器：

```swift
public final class CrossReferenceAnalyzer: @unchecked Sendable {
    /// The current process's images — the whole shared cache plus the images loaded outside it; nil off arm64.
    public init?()
    public let images: [MachOImage]
    public let imagePaths: [String]
    public func imageIndex(forPath path: String) -> Int?
    public func location(ofRuntimeAddress address: UInt) -> CodeLocation?
    public func functions(inImageAt imageIndex: Int) -> [CodeFunction]
    public func function(containing location: CodeLocation) -> CodeFunction?
    /// Names many results at once without keeping the images' tables.
    public func functions(containing locations: some Sequence<CodeLocation>) -> [CodeLocation: CodeFunction]
    public func symbolName(at location: CodeLocation) -> String?
    public func references(madeBy function: CodeFunction) -> [CodeReference]
    /// Every function's references in one image, grouped by what they reference.
    public func referenceTable(ofImageAt imageIndex: Int) -> CodeReferenceTable
    /// Only the references filed under `keys` — what a callers query needs.
    public func references(to keys: Set<CodeReferenceTable.Key>, inImageAt imageIndex: Int) -> [CodeReference]
    public func imageIndices(importing symbolName: String, among candidates: some Sequence<Int>) -> [Int]
    public func imageIndices(referencingSelector selector: String, among candidates: some Sequence<Int>) -> [Int]
}
```

地址一律是 `CodeLocation`（镜像在 `images` 里的位置，加该镜像的未滑动地址），因为缓存外两个镜像的未滑动地址可能重合。实现细节见 [Modules/CrossReferenceAnalysis.md](../Internal/Modules/CrossReferenceAnalysis.md)。

## 第一批的实现与验证（2026-10-16）

- **落地模块**：新 target `ARM64InstructionDecoding`（`Sources/Support`：`ARM64InstructionWord` 手写读取少数几类编码，`ARM64Trampoline` 按形状认 GOT 桩、stub island 与全缓存共用的 selector 桩）；新 target `CrossReferenceAnalysis`（`Sources/Analysis`）；SwiftThunkAnalysis 的 `MachOThunkEnvironment.stubSlotAddress` / `stubIslandTarget` 改用 `ARM64Trampoline`，此前用 Capstone 加寄存器跟踪认同样的形状。
- **与方案的出入**：①API 改成宿主持有的 `CrossReferenceAnalyzer`（上文）。②分析器只记住宿主让它起过名的镜像的函数表；这不是全局的按镜像缓存，释放分析器即释放，所以仍不需要 `SharedCache`。③ObjC 方法的 `x0` 接收者提示（`methodReceiver`）这批就做了：寄存器跟踪本来就在，代价只是多一个状态。④新增 `references(to:inImageAt:)`（见下「内存」）。
- **内存**（用库写的 release 基准量）：整镜像扫描起初也记住函数表，扫完一遍 macOS 27.2 缓存后常驻 1.5 GB，改为扫描临时建表、用完即丢（`wholeImageScansKeepNoFunctionTable`，改前红、改后绿）。剩下的 1.2 GB 不是活对象（`heap` 只见一两 MB），是 28 个线程同时建整表（大镜像一张 121 MiB）后分配器没还的脏页，由峰值决定；查调用者改用只留命中引用的 `references(to:inImageAt:)` 后，同样扫完全缓存常驻约 170 MB。
- **吞吐**：建分析器 0.02 秒；每个镜像都建整表 28 核 1.6–1.8 秒、4 线程 5.9 秒；`init` 的调用者（预筛出 2,759 个镜像）28 核 1.5 秒、4 线程 6.1 秒；`makeKeyAndOrderFront:`（105 个镜像）0.3 秒。比探针慢的部分是起名与建引用，见模块参考。
- **懒绑定**：曾以为懒绑定的老式二进制在函数第一次调用前槽位指向 `__stub_helper`，加了退回导入名的防护和测试；测试在去掉防护后照样通过。用探针看：macOS 27.2 的 dyld 以 `RTLD_LAZY` 加载时就绑好了槽。防护是死代码，撤掉；测试改成哨兵 `LazyBindingTests`，断言调用直接解析到 `puts`。
- **验证**（JHs-Mac-Studio-Ultra，macOS 27.2，Xcode 27.2，依赖全部走远端发布版本）：`CrossReferenceAnalysisTests` 20 个测试通过，其中 `callSitesMatchCapstone` 抽样 AppKit 的 400 个函数，Capstone 找到的每一处调用与跳出函数的跳转，扫描都找到了；`SwiftThunkAnalysisTests` 82 个测试通过，包括经 stub island 解析的两个离线 iOS 缓存测试；全量 `swift test --skip IntegrationTests` 见演进账本本批一节。
- **第一次测试的教训**：Capstone 不开 detail 模式就不给操作数，按位置取操作数会越界；比对「跳出函数的跳转」那半边因此一度什么都没比。测试现在断言这半边比对过不止一处。
- **第一批之后的修补**（RuntimeViewer 第 3 步接入时发现）：①缓存里的传统 `objc_msgSend` 发送，`x1` 不是从 selector 引用读来，而是缓存构建器改写出的字符串地址（`adrp x8; add x1, x8; b _objc_msgSend`，libobjc 的 `-[NSObject debugDescription]` 就是），第一批把它们当成对 `objc_msgSend` 的普通调用，发送整个看不见。修法是 `x1` 是 `adrp` / `add` 算出的地址时，确认它可读、到结尾是可打印字符，就当作 selector；回归测试 `classicSendsInsideTheCacheNameTheirSelector` 改前红、改后绿。②补上预筛的正确性测试：此前只断言预筛「留下了 AppKit、筛得够狠」，没断言「丢掉的镜像里真没有引用」。现在 3 个 selector 与 2 个导出函数各在被丢掉的镜像里每 16 个抽 1 个扫描，一处引用也没有。③新增 `functions(containing:)`：给一批结果起名，用完不留函数表。
- **留给后续批次**：过滤扫描按键提前跳过（现在先建好每条引用再丢）；`CodeReference` 的紧凑存储。

## 第二批的设计（2026-10-17，实测之后）

方案一节对第二批只有一句「ObjC 方法表与 Swift 元数据命名、类型引用」。动手前用两个只读探针在 macOS 27.2 的缓存上实测（代码在 agent 临时目录 `Probes/CrossReferences/BatchTwo-ObjC`、`BatchTwo-Swift`，不在仓库里），有几条事实改变了做法，按它们定下第二批：

### 起名：三个来源，都在起名时按镜像按需读

| 来源 | 能给多少无名起点起名（全缓存，无名共 822 万） | 代价 |
|---|---|---|
| 导出表（export trie）——第一批没读 | 140 万；iOS 真机上也在 | 每个镜像不到 1 毫秒 |
| ObjC 方法表（类、元类、分类） | 40 万（Matter 53,000 个无名里 30,863 个） | AppKit 42–86 ms；全缓存单线程 14 s，`MachOObjCSection` 内部串行，并发不变快 |
| Swift 元数据 | 146 万处被元数据指到，其中 132 万导出表也没名字 | 全缓存单线程 8.2 s，28 线程 3.3 s |

- 每个方法实现都是 `LC_FUNCTION_STARTS` 里的函数起点。一个镜像只读自己的类列表（列表的列表里属于别的镜像的条目跳过：它们一定也在那个镜像自己的分类列表里）和自己的分类列表。元数据里没有分类名，`-[NSTextView(NSDragging) draggingUpdated:]` 读出来是 `-[NSTextView draggingUpdated:]`；有符号的照用符号（Swift 的 `@objc` 桥接函数 `…To` 与方法表名字不同，符号是对的）。
- Swift 元数据里，名字一定能还原的：类型元数据访问器（`…Ma`）与 singleton 完成函数（`…Mr`），类型名取自描述符的上下文。虚表实现要靠方法描述符导出的 `…Tq`（去掉 `Tq` 就是方法本身的 mangled 名字），16 万处里 8.4 万有。协议见证可以由 conformance 加 requirement 重新 mangle 出 `…TW`，留到下一步。虚表里有大量空实现；指向 `__swift5_typeref` 的见证是关联类型，不是代码；async 函数指向 `{rel32 函数, u32 大小}` 记录，要再跟一步。
- 扫描时用不到这些名字（判断一个函数是不是 ObjC 方法除外，见下），所以不在建函数表时读，只在给函数起名时（`functions(inImageAt:)`、`function(containing:)`、`functions(containing:)`）按镜像读一次、记在函数表上。
- `CodeFunction.Name` 变成三种：`.symbol`（符号表与导出表）、`.objectiveCMethod`、`.swiftMetadata(mangledName:)`（从元数据重建的完整 mangled 名字，可以直接 demangle）。第一批占位的 `.swiftMethod(descriptorAddress:)` 去掉。

### ObjC：类字面量接收者、super 的类、类引用

- 27.2 的缓存里几乎没有 `__objc_classrefs` 了（全缓存只剩 53 个镜像、1,023 个槽）。类经 GOT 载入：镜像自己的 `__got`，或全缓存共用的 GOT 池（落在所有镜像的段之外）；或 `adrp`+`add` 直接取类对象地址；super 发送仍经 `__objc_superrefs`。AppKit 里 34,256 处来自共用池、17,450 处来自自己的 `__got`、3,311 处直接取址。
- 槽里的值是不是类对象，用目标镜像按需建的类索引判断（`__objc_classlist` 的类与元类，名字取自 `class_ro_t`）；其他槽（`__cfstring` 的 isa 之类）一律不算。类对象不能只按所在段认：9.2 万个 Swift 类与元类在 `__data` 里。
- 发送的接收者来自类引用时记为 `classLiteral`（AppKit 11% 的发送）。`objc_opt_self`、`objc_opt_class`、`swift_getInitializedObjCClass` 视为原样返回实参（SwiftUI 的类接收者几乎都经 `objc_opt_self`）。
- super 发送的类取发送方法自己的类（名字 `-[C sel]` 里的 `C`，或方法表给的类）。用栈槽跟踪能还原 88%，与方法自己的类对照，7,106 处一致、2 处不同，所以不做栈槽跟踪。
- 扫描时判断一个函数是不是 ObjC 方法（`x0` 是不是接收者）仍只看名字。把无名的方法实现也算上能让 AppKit 的 self 发送从 67,848 处升到 77,696 处，但要在每次扫描时读方法表，代价与扫描本身相当；iOS 真机上符号全被抹掉，这一项影响更大，留到有更快的方法表读法时再做。

### 类型引用

- **键**：名义类型的 mangling，不带 `$s`，不带后缀：`7SwiftUI4TextV`、`Sa`、`So8NSWindowC`。泛型实例里出现的每个名义类型各算一处引用（`Array<Text>` 引用 `Sa` 和 `7SwiftUI4TextV`）。ObjC 类写成 `So<长度><名字>C`；有 ObjC 元数据的 Swift 类经元数据 +0x40 的描述符得到它自己的 mangling。不用描述符地址作键：导入的 `So…` 类型在每个用到它的镜像里各有一份描述符，标准库类型在 mangled 名字里写成文本。键一律经重新 mangle 得到——直接从 `…Mn` 符号截取，与重新 mangle 的结果在受约束扩展里的嵌套类型上不一致（SwiftUICore 4,778 个里 36 个）。
- **来源**（括号里是 SwiftUICore 的数量）：
  1. 元数据访问器调用（本镜像 15,042，跨镜像 5,649）：目标属于访问器集合（各镜像 `__swift5_types` 描述符的 `accessFunction`，全缓存 34 万个，并发 0.13 s 建完）。泛型实例、存在类型、导入类型的访问器（`$sSNy10Foundation4DateVGMa`、`…_pMa`、`$sSo…Ma`）没有描述符，只能按符号名认。
  2. 取址：`adrp`+`add` 或 GOT 载入得到访问器地址（8,060 / 6,332）、值类型元数据地址（27,057 / 4,106）或类元数据（266）。SwiftUICore 里取址比访问器调用还多。
  3. 按 mangled 名字实例化：调用本镜像的 `__swift_instantiateConcreteTypeFromMangledName*` helper（全缓存 1,771 个 Swift 镜像有，147 万处调用，一律调本镜像的那份；没有符号时按形态认：不超过 0x90 字节、调用 `swift_getTypeByMangledNameInContext*`）。27.2 上几乎都是 V2：名字不在 `x0` 的缓存变量里，而在 `x1` 指向的 `{int32 到 __swift5_typeref 的偏移, int32 长度}` 记录里。名字里的 `\x01` / `\x02` 符号引用指向描述符，用 `SymbolicDemangler` 解开（每个约 60 µs，平均含 2.5 个名义类型）。SwiftUI 与 SwiftUICore 不用这个 helper。
  4. ObjC 类引用，见上一节。
- **查询**：「哪些函数引用了类型 T」不能只按键等值过滤：mangled 名字要解开才知道引用了谁，全缓存 147 万处逐个解开太慢。扫描先拿 T 的全部身份（访问器位置、元数据与类对象地址、描述符地址、mangling 文本）做结构比对——符号引用比地址、文本比子串——命中了才解开确认。
- **预筛**：定义 T 的镜像，加上导入了 T 的 `…Mn`、`…Ma`、`…N`、`_OBJC_CLASS_$_…` 的镜像；标准库与导入的 C 类型只以文本出现在 mangled 名字里，按各镜像 `__swift5_typeref` 的字节预筛。

### 寄存器跟踪在汇合点的问题（第一批的缺陷，已修）

扫描原先按指令顺序跟踪寄存器，没有处理汇合，汇合处沿用最后一条路径的值。核实结果：`-[NSString stringByAppendingString:]` 里一个块把参数放进 `x0`、下一个块放 `self`，两者跳到同一处发送 `copyWithZone:`，顺序读法把接收者说成 `self`——确实会错。先试了「无条件转移后忘掉调用方保存的寄存器」：AppKit 80 万处引用改了 1,237 处，selector 一处没变，但它把 `+[NSObject instanceMethodForSelector:]` 这类早退之后本来正确的 `self` 也丢了，弃用。最后的修法是让状态沿着分支走：向前的分支带着快照到目标处，目标处以带来的状态为准（前一条是无条件转移）或与顺序状态取交集；循环头与无人指向的落点忘掉调用方保存的寄存器。AppKit 因此多认出 9,699 处 `self` 发送、少说 78 处；release 下全缓存整表扫描 1.6–1.8 s → 2.0 s，查 `init` 的调用者 1.5 s 不变。

### 第二批 ①：起名的实现与验证（2026-10-17）

- **落地**：新文件 `Scanning/ImageFallbackNames.swift`（三个来源各自按需读、记在函数表上）；`ImageFunctionTable.codeFunction(at:)` 在符号表没有名字时问它；`CodeFunction.Name.swiftMethod(descriptorAddress:)` 换成 `.swiftMetadata(mangledName:)`；分析器找运行时函数时也读运行时库的导出表。target 依赖加了 `MachOObjCSection`、`MachOFoundation`、`MachOSwiftSection`、`SwiftInspection`、`Demangling`（只用于起名）。
- **这一步没做的**：协议见证（全缓存 78 万处，最大的一类）、override 实现、witness table pattern 条目的名字；扫描时用方法表判断无名的 ObjC 方法。
- **实测**（release，28 核）：给全部函数起名，AppKit 0.24 s（方法表补 3,961、元数据补 1,147，仍无名 15,884），SwiftUICore 0.06 s（不需要补），SiriAppIntents 1.5 s（导出表 76,318、元数据 2,820），Matter 0.04 s（方法表 30,863）。每个镜像起 32 个名字、走遍整个缓存 6.9 s（4 线程 6.1 s，并发几乎不变快：耗在 Swift 运行时的泛型元数据缓存）。
- **验证**：`FallbackNamingTests` 5 个测试（各来源与真实符号互相印证，见模块参考）；`CrossReferenceAnalysisTests` 共 29 个、`SwiftThunkAnalysisTests` 82 个通过。
- **第一次跑测试的教训**：导出表与实现的偏移可以是负的（缓存里落在本镜像头部之下），`UInt64(offset)` 当场崩溃；全部改成带环绕的加法。

### 第二批 ②：ObjC 类的实现与验证（2026-10-17）

- **落地**：新文件 `Scanning/ObjectiveCClassIndex.swift`（每个镜像按需建的类索引）；新的引用种类 `CodeReference.Kind.reference`（取类地址但不跳转的指令）；目标 `.objectiveCClass(name:location:)`；`superMessageSend` 多了 `className`；`ReceiverClassHint.classLiteral` 有了来源；表键 `CodeReferenceTable.Key.objectiveCClass`；公开 API `objectiveCClassLocations(named:inImageAt:)`、`imageIndices(referencingObjectiveCClassAt:among:)`、`imageIndices(importingAnyOf:among:)`。
- **与设计不同之处**：
  - super 的类不取方法名或方法表，取同一函数里从 `__objc_superrefs` 载入的类，没见到时才退回方法符号。槽里就是编译器给的类，分类方法、类方法（槽里是元类）、没有符号的方法都对，扫描也不必读方法表。这一载入本身不报成类引用。Swift 代码的 super 发送不经这个槽（类来自 `self` 的运行时类或元数据访问器），类记为空：Foundation 1,803 处里 374 处、AppKit 8,336 处里 1,133 处，其余全有类。
  - 引用目标除了类名还带类对象的位置：全缓存 203,621 个类名里 18,906 个不止一个镜像定义，多是 `/System/iOSSupport` 下的 Mac Catalyst 变体。表键仍是类名。
  - 类预筛不只认 `_OBJC_CLASS_$_<名字>`：抽样里别的镜像引用某个类，6,921 对中 251 对走别名（Block 的 `isa` 是 `__NSConcreteStackBlock`，XPC 类型是 `__xpc_type_dictionary`）。预筛取定义镜像的符号表与导出表里落在类或元类地址上的全部名字。
- **实测**：AppKit 取本镜像类的地址 3,319 处、载入类 53,026 处（与探针的 3,318 / 52,668 一致），类字面量接收者 35,175 处（发送的 11%）；SwiftUI 665 处类字面量接收者里 478 处经 `objc_opt_self`。`adr` 与字面量 `ldr` 两种形态在缓存与几个缓存外的系统 App 里都没有，不解码。
- **性能**：类索引起初经 `MachOImage.objc.classes64` 建——它对每个类都重新查一遍 load command，撞上 Swift 运行时的泛型元数据锁——加上扫描每次查类都抢分析器的锁，全缓存整表扫描从 2.0 秒变成 4.9 秒。改为直接读 `__objc_classlist` 与 `isa`、扫描器自己缓存索引、本镜像 `__TEXT` 与非类槽在查表前排除之后，与只有分支跟踪的那次提交交替跑三轮取最好：整表 2.03 → 2.40 秒（引用多 326 万条，+17%），查 `init` 的调用者 1.54 → 1.70 秒。
- **验证**：`ObjectiveCClassReferenceTests` 7 个测试（11 个用例），其中经 `objc_opt_self` 保留 `x0`、读 `__objc_superrefs`、预筛认别名三项在去掉做法时变红过；`CrossReferenceAnalysisTests` 共 38 个、`SwiftThunkAnalysisTests` 82 个通过。
- **没做的**：按字符串取类（`objc_getClass("…")`，AppKit 183 处）；扫描时用方法表判断无名的 ObjC 方法（见设计）；Swift 的 super 发送的类。

### 第二批 ③：Swift 类型引用的实现与验证（2026-10-17）

- **落地**：`Scanning/SwiftTypeIndex.swift`（每个镜像按需建：`__swift5_types` 的描述符、各自的访问器、按需算的 key）；`CrossReferenceAnalyzer+SwiftTypes.swift`（`SwiftTypeIdentity`、`swiftTypeIdentity(ofDescriptorAt:)`、`swiftTypeDescriptorLocations(withKey:inImageAt:)`、`references(toSwiftType:inImageAt:)`、`imageIndices(referencingSwiftType:among:)`、`swiftTypeKeys(in:)`，以及比对器 `SwiftTypeQuery`）；目标 `.swiftType(descriptor:)` 与 `.swiftTypeName(SwiftTypeName)` 换掉第一批声明了、没人产出的 `.typeMetadataAccessor` 与 `.mangledTypeName`；表键 `.swiftTypeDescriptor(CodeLocation)`；分析器认出运行时的 `swift_getTypeByMangledName…` 入口。
- **与设计不同之处**：
  - 表按描述符位置归档，不按 key（设计里说「不用描述符地址作键」）。扫描时算 key 要为每个被引用的描述符 demangle，而 key 的拼法随 demangle 的路径变：受约束扩展里的嵌套类型、其他模块类型的扩展里的 private 类型都会拼偏。位置精确、不花时间，也天然分开 Mac Catalyst 变体。设计里不用位置的两条理由由查询解决：导入的类型每个镜像一份描述符，查询按 key 比；标准库类型在名字里拼出来，查询解开名字。key 改为取自描述符的 `…Mn` 符号。
  - 查询不做文本子串比对（设计里「文本比子串」）：mangling 会把同一名字里重复出现的单词换成替身，子串会漏。只有名字可能拼出来的类型才解开名字，其余只比符号引用。这条前提逐个解开 Foundation、SwiftData、libswift_Concurrency、SwiftUI 的全部名字核对过，没有例外。
  - 预筛对名字可能拼出来的类型，不按 `__swift5_typeref` 的字节筛（同一原因），凡有这一节的镜像都算。
- **实测**（扫一遍）：SwiftUICore 调用描述符可知的访问器 15,432 处、取元数据或访问器地址 35,140 处、经 GOT 载入 10,438 处、调用只有符号的访问器 5,259 处，不用按名字实例化；Foundation 按名字实例化 6,280 处、934 个不同名字；SwiftUI 访问器调用 63,487 处。访问器调用报出的类型与访问器符号全部一致。
- **性能**：全缓存整表 2.1 → 3.0 秒（引用 1.16 亿 → 1.26 亿条），查 `init` 的调用者 1.6 → 1.8 秒（只查 selector 或函数时不找类与类型引用）。途中两次退化：`keep(reference(to: …))` 这种参数里修改扫描器的写法让 Swift 每次复制整个扫描器，整表一度 95 秒；类型索引每次去分析器的锁里取，等锁占掉大半时间。两处的修法见模块参考。
- **第一批的预筛缺陷（已修）**：写类型预筛的正确性测试时发现，macOS 27.2 的缓存镜像一个 Swift 的未定义符号都不留（SharedWithYou 照样调用 `URL` 的访问器，却没有任何导入记录）。第一批的函数预筛按导入符号筛，只拿 C 函数测过，对 Swift 函数一直会丢掉其他镜像里的全部调用者——RuntimeViewer 第 3 步查 Swift 方法的跨库调用者受影响。Swift 符号改按链接关系筛（直接链接，或经再导出链接到定义镜像），新增 `imageIndices(linkingImageAt:among:)` 与 `imageIndices(callingFunctionAt:symbolNames:among:)`；Swift 类的类预筛同样补上链接关系。回归测试 `swiftFunctionPrefilterKeepsEveryCaller` 在旧做法下变红。
- **没做的**：协议的类型引用（协议描述符、存在类型、泛型约束都要另算）；旧形态（V1）已经实例化的缓存变量；直接调用 `swift_getTypeByMangledName…` 时只认 `adrp` / `add` 出的名字地址。

### 落地顺序

①起名（导出表、ObjC 方法表、Swift 元数据）；②ObjC 的类字面量、super 的类与类引用，以及汇合点的核实与修正；③Swift 类型引用、类型查询与预筛。每一步单独测试、单独提交。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-10-16 | Created as Draft | RuntimeViewer 提案落地第二步要求先写本库的提案；整体方向用户已在那份提案里确认 |
| 2026-10-16 | 采用的假设 | 只读 `MachOImage`；target 名 `CrossReferenceAnalysis`；不新增缓存；分三批落地；GOT 桩与 island 的识别与 SwiftThunkAnalysis 共用 |
| 2026-10-16 | 状态 → Accepted → In Progress | 用户批准按本方案动手（「可以，开始第一批」），跳板识别从 SwiftThunkAnalysis 抽出共用；开始第一批 |
| 2026-10-16 | API 改为宿主持有的 `CrossReferenceAnalyzer`，位置用 `CodeLocation` | 跨镜像解析目标要整张进程镜像表；缓存外两个镜像的未滑动地址可能重合 |
| 2026-10-16 | 整镜像扫描不记函数表；新增只留命中引用的 `references(to:inImageAt:)` | 实测：记表时扫完全缓存常驻 1.5 GB；整表并发扫描的峰值让分配器留下 1.2 GB；过滤扫描后约 170 MB |
| 2026-10-16 | 不做懒绑定退回，留哨兵测试 | 探针实测 dyld 加载时就绑好懒绑定槽，防护是死代码 |
| 2026-10-16 | 补认缓存内传统发送的 selector 字符串地址；补预筛正确性测试 | RuntimeViewer 第 3 步查 `-[NSObject description]` 的调用者一条都没有，追到第一批漏认了这种形态；同时发现预筛从未被断言过「不漏」 |
| 2026-10-17 | 第二批按实测重定：加导出表起名；名字在起名时按镜像按需读；类型键用名义类型的 mangling；类型查询先结构比对再解开 | 两个只读探针实测：导出表能给 140 万个无名起点起名而第一批没读；方法表与元数据每次扫描都读，代价与扫描本身相当；27.2 上实例化的名字在 `x1` 的记录里、类引用几乎不经 `__objc_classrefs`。用户要求「继续第二批」 |
| 2026-10-17 | 寄存器状态沿着分支走（快照随前向分支到目标处，汇合取交集），不用「转移后一律忘掉」 | 核实了第一批的汇合点缺陷：`-[NSString stringByAppendingString:]` 的 `copyWithZone:` 接收者被错说成 `self`；简化版会丢掉早退之后正确的 `self`；完整版 release 开销约 10–20% |
| 2026-10-17 | 类引用的目标带类对象的位置，表键仍是类名 | 全缓存 18,906 个类名不止一个镜像定义（多是 Mac Catalyst 变体），只按名字会把两个 SwiftUI 的同名类混在一起 |
| 2026-10-17 | super 的类取 `__objc_superrefs` 的载入，退回方法符号；Swift 的不记 | 槽里就是编译器给的类，分类方法、无符号的方法都对，不必在扫描时读方法表；Swift 的类到运行时才知道 |
| 2026-10-17 | 类预筛认定义镜像在类与元类地址上的全部符号 | 抽样 4% 的跨镜像类引用走别名（`__NSConcreteStackBlock`、`__xpc_type_dictionary`），只认 `_OBJC_CLASS_$_` 会漏 |
| 2026-10-17 | 类索引直接读 `__objc_classlist` 与 `isa`，不经 `MachOImage.objc.classes64` | 后者让全缓存整表扫描从 2.0 秒变成 4.9 秒；直接读之后为 2.4 秒 |
| 2026-10-17 | Swift 类型引用的表按描述符位置归档，key 取自描述符的 `…Mn` 符号 | 扫描时算 key 要 demangle，且 key 的拼法随 demangle 路径变（受约束扩展、扩展里的 private 类型）；位置精确、不花时间、分得开 Catalyst 变体 |
| 2026-10-17 | 类型查询只比符号引用；名字可能拼出来的类型（标准库、`_Concurrency`、导入）才解开名字；不做文本子串比对 | 逐个解开四个镜像的全部名字核对：其他类型在名字里都是符号引用；mangling 的单词替身会让子串比对漏 |
| 2026-10-17 | 扫描器先把引用算进局部变量再保留；类与类型索引由扫描器持有的引用类型缓存；只查 selector 或函数时不找类与类型引用 | 实测：参数里修改扫描器让整表扫描一度 95 秒；等分析器的锁占掉大半时间；selector 查询本来用不到它们 |
| 2026-10-17 | 跨镜像的 Swift 符号按链接关系预筛，不按导入符号；`imageIndices(importing:)` 只对 C 与 ObjC 符号 | 实测缓存镜像不留任何 Swift 未定义符号；第一批的函数预筛因此对 Swift 函数会丢掉全部跨库调用者（只用 C 函数测过）。链接关系在缓存里完整，粗但不漏 |
