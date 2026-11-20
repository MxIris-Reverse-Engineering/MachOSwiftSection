# SwiftSymbols 模块

> 模块参考文档（module reference），随代码维护。读者：维护者。
> 细节文档见文末[「相关文档」](#相关文档)；本文负责全貌与分工，不复述细节。
> 2026-11 之前本模块叫 `MachOSymbols`，符号表与采集也在这里；与语言无关的那一半已迁到 MachOKitExtensions 的同名模块 `MachOSymbols`，本模块只留 Swift 部分（MachOKitExtensions 提案 move-macho-infrastructure-modules）。

## 模块定位

SwiftSymbols 是 **Swift 符号索引**层：在 MachOKitExtensions `MachOSymbols` 的一趟采集上取出一个镜像的 Swift 符号，把每个 Swift 符号 demangle 成节点树存起来，按成员、类型、witness、thunk 归类，供上层按偏移、按名字、按类型成员反查。入口类型是 `SwiftSymbolIndexStore`。

与语言无关的底层——16 字节的紧凑符号表、按偏移分桶、符号值到偏移的换算、对符号表与导出表的单趟采集（`SymbolSweep`）、语言判断与注册（`SymbolLanguage`、`SymbolLanguageRegistry`）——在 MachOKitExtensions 的 `MachOSymbols` 里，说明见它的 [SymbolIndex.md](https://github.com/MxIris-Reverse-Engineering/MachOKitExtensions/blob/main/Documentations/Internal/SymbolIndex.md)。那边还有一个只收 C 与 C++ 名字的 `SymbolIndexStore`（已注册语言的符号只留偏移作边界）；它与本模块的 `SwiftSymbolIndexStore` 查询方法同名，但互不相干（见「关键契约」）。

它坐在 ABI 模型**上面一层**。`MachOSwiftSection` 够不到它（演进提案 `self-contained-abi-layer` 的边界）：描述符只暴露实现偏移，把偏移归属到符号名是 `SwiftInspection` 的事。符号的**值类型**（`Symbol` / `Symbols` / `SymbolOrElement`）住在 `MachOResolving`（MachOKitExtensions），不在这里——「这个偏移上有哪些符号」是一次针对索引的**查询**，不是一次读取，所以 `Symbols` 故意不是 `Resolvable`。

模块另外托管一个跟符号无关的东西：`LargeStackTaskExecution`，库入口用来把整个调用链搬到大栈执行器上的开关。它放这儿是因为 demangler 是它唯一的服务对象。

## 文件 → 子系统对照

| 子系统 | 文件 |
|---|---|
| 1. 索引本体 | `SwiftSymbolIndexStore`、`SwiftSymbolTableRouting`、`SharedCacheEvictionGroup+SwiftSymbols`（`.swiftSymbolStore`、`.internedNames`） |
| 2. 符号值与查询出口 | `Symbol`、`DemangledSymbol`、`MachO+Symbol` |
| 3. 节点引用的共享与跨 store 对账 | `InternedNodeReferenceCache`、`StructuralNodeReferenceKey` |
| 4. 大栈执行器接入 | `LargeStackTaskExecution` |
| 5. `_symbolic` 符号表 | `SymbolicManglingSymbols` |

## `SymbolLanguage.swift` 与加载时注册

`SymbolLanguage.swift` 定义在本模块（`SymbolLanguage+Swift.swift`），不在 MachOKitExtensions：Swift 名字怎么认归本包管（MachOKitExtensions 提案 [split-symbol-language](https://github.com/MxIris-Reverse-Engineering/MachOKitExtensions/blob/main/Documentations/Evolutions/0004-split-symbol-language.md)）。

- **识别**：`SwiftSymbolNameRecognition.recognizes` 只看名字开头的字节——`$s` `_$s` `$S` `_$S` `$e` `_$e` `_T0` `@__swiftmacro_`，以及链接器去重名 `_symbolic `、`_default assoc type `。前缀集合必须与 swift-demangling 的 `isSwiftSymbol` 一致，`SymbolTableEquivalenceTests.swiftRecognitionMatchesDemanglingIsSwiftSymbol` 在真实符号表上钉住。
- **注册**：C target `SwiftSymbolsRegistration` 里的 `__attribute__((constructor))` 在镜像加载时调用本模块用 `@c` 导出的 `swift_symbols_register_symbol_language`，向 `SymbolLanguageRegistry.shared` 登记 `.swift`。`SwiftSymbols` 依赖这个 C target。SwiftPM 与 Xcode 自带的包集成整块链接每个 target，constructor 总会带上；从静态归档链接时（Tuist 的静态 framework、静态库），链接器只拉被符号引用到的成员，而 constructor 是 `static` 的，所以这个 C 文件另外导出一个什么都不做的锚点 `swift_symbols_registration_anchor`，由 `SymbolLanguage+Swift.swift` 的注册函数调用：用到 Swift 索引、或带 `-ObjC` 的链接会拉进那个 Swift 文件，它对锚点的引用再把 C 文件连同 constructor 拉进来。调用方什么都不用做；`SwiftSymbolLanguageRegistrationTests.languageFileRefersToTheRegistrationAnchor` 钉住引用的两端。Swift 自己没有加载时初始化：SE-0492 的 `@section` 写进 `__mod_init_func` 在 Swift 6.4.2 上链接失败，所以用 C target。
- **效果**：注册之后，MachOKitExtensions 的 C/C++ 索引不再收 Swift 名字，只留它们的偏移，地址落在 Swift 函数里时 `closestSymbols` 答 `nil`。`SwiftSymbolLanguageRegistrationTests` 钉住这三件事。

## 子系统 1：索引本体

**采集交给 MachOKitExtensions**。建索引的第一段（见下文「建索引分两段」）由 `SymbolSweep(sweeping:routing: SwiftSymbolTableRouting())` 一趟扫完符号表与导出表：本模块的 `SwiftSymbolNameRecognition` 认作 Swift 的名字里（routing 直接用它，不看注册表给的语言，Swift 索引不会因为注册没发生而变空），`_symbolic ` / `_default assoc type ` 开头的进 `.symbolicMangling` 表（`.nameOnly`，不建偏移索引），其余进 `.swift` 表（`.byOffset`）；非 Swift 名字不收。routing 声明了 `mayReferenceStringTablesOfLoadedImages`（dyld 不卸载带 Swift 内容的镜像），所以 `MachOImage` 的行直接指进镜像的字符串表。采集的通用规则——每个唯一名字一行 16 字节、名字的两种来源（零拷贝的字符串表或私有缓冲）、规范化偏移的口径与 `SymbolValueOffsetConverter`、STABS 调试条目只占行不定偏移、导出事实与本地符号事实的采集——都写在 MachOKitExtensions 的 [SymbolIndex.md](https://github.com/MxIris-Reverse-Engineering/MachOKitExtensions/blob/main/Documentations/Internal/SymbolIndex.md)，这里不复述。对本模块要记住的只有两条后果：`MachOKit` 给 `MachOFile` 符号的 `offset` 是原始 `n_value`（虚拟地址，不是它文档注释说的文件偏移），进索引一律经换算，主可执行文件（`__TEXT` 在 0x100000000）上弄错会让每个成员地址都高出一个基址（`ExecutableImageSymbolOffsetTests` 钉住）；调试条目保留占位行是为了让行序跟着调试映射走，即源码顺序——打印器按行序列成员，丢掉它们会让 SymbolTestsCore 的 42 个快照变化。

`SwiftSymbolIndexStore.Storage` 里**不驻留 `Node` 类树，也不驻留符号名 `String`**。建索引时每个符号 demangle 到一棵临时树上，分类完就 intern 进这个镜像的 `NodeStoreBuilder`；全局 `NodeCache` 全程不参与，`Storage` 一放，整个镜像的内存占用就跟着走。

**建索引分两段**（演进提案 `machofile-performance`）。`storage(in:)` 建出来的只有第一段：符号表、按偏移的行索引、`_symbolic` 符号表和导出事实，一个名字也不 demangle。第二段 `Storage.DemangledIndex`——每一行的节点树和按树分类的各个索引——在第一次有查询要用到树时才建，建在大栈上、持锁只建一次，并发的第一批读者等同一次构建。`symbols(for:in:)`、`containsSymbol(named:)`、`offset(ofSymbolNamed:)`、导出判定、`hasLocalSwiftSymbols` 与 `symbolicManglingSymbols(in:)` 只读第一段。原因是只为别的镜像而读的镜像：静态布局引擎经匿名上下文描述符上的符号给依赖镜像的私有类型起名，以前这一查就把整个依赖镜像的名字全部 demangle 一遍，生成 SwiftUI 的 interface 27.8 秒里有 7.7 秒花在这上面。`prepare(in:)`、`prepareWithProgress(in:)` 与 `buildStorage(for:)` 照旧把两段都建好，进度只报第二段（第一段太快，不值得报）。字段仍以原名从 `Storage` 上读，第二段的字段经转发属性取；逐行的循环先取一次 `demangledIndex` 再读，不要每行都经转发属性。

**第二段的 demangle 分到多个线程**（同一提案）。建第二段的线程按行号顺序一批一批地驻留、分类，`DemanglingWave` 提前一批把下一批的名字分给机器上同时运行的线程去还原成树（每批最多 16 × 512 行，每 512 行跳一次大栈），两批在内存里交替。驻留和分类仍只在建索引的线程上按行号顺序做，节点池与各个索引因此和单线程建出来的逐位相同；一行的树只由它的名字决定，哪个线程还原的不影响结果（`everyRowHoldsTheTreeOfItsOwnName` 钉住）。不要把驻留挪进线程里，也不要让线程按别的顺序交回结果：节点序号就是驻留顺序，打印与快照都依赖它。每一批由一个私有串行队列起头、在里面 `concurrentPerform`，不交给 `DispatchQueue.global()`：建索引的线程要同步等这一批，而当协作线程池的线程全都同步阻塞在读索引的大栈跳转上时，它们仍占着同一 QoS 的并发额度，全局队列（以及挂在同一根队列上的私有并发队列）分不到线程，整个进程就停住了——2026-11-16 在 10 核机器的并行全量里两次卡死（代码库体检第 10 条）。私有串行队列挂在 overcommit 根队列上，总能拿到线程；`concurrentPerform` 的调用线程自己也执行迭代，没有别的线程加入时照样做完，正常时仍用满所有核（`firstReadersOnEveryCooperativeThreadAllFinish` 钉住）。本机 SwiftUI 的第二段墙钟时间减半；CPU 时间的代价取决于 demangler 自己的引用计数开销——swift-demangling 0.7.2 的 `Demangler` 在 `require(pop())` 这类写法上会整份复制自身，多线程同时复制节点栈时互相抢引用计数，CPU 时间约为单线程的 2.3 倍，修掉这处复制后只多约四分之一。

**interface 的 import 列表从节点池里收**（同一提案）。`moduleNamesInAllSymbols(in:)` 沿每个符号的根节点在节点池里做前序遍历，每个节点只进一次：同样的子树在池里是同一个节点，第二次遇到时它能贡献的模块名第一次都已收过，所以名字和它们第一次出现的顺序都与逐棵树完整遍历相同（`moduleNamesMatchAWalkOfEveryTree` 钉住）。以前 `SwiftInterfaceBuilder.collectModules()` 对 `allSymbols(in:)` 的每棵树做一次泛型的整树遍历，SwiftUI 的 interface 准备阶段因此多出约 450 亿条指令。

成员与全局变量按入口节点归类：getter、setter，SE-0507 的 `borrow` / `mutate` 访问器（`vb` / `vz`），以及 SE-0400 的 init accessor（`vi`）都算属性或下标的成员符号——只声明 `borrow` / `mutate` 的属性没有 getter 符号，漏了它们整个成员就不见了。`_read` / `_modify` 及其新 ABI 版本不收进成员桶。新加一种进成员桶的 accessor 要改两处名单：分桶 switch 之前还有一道 `Node.Kind.isMember`（`SwiftSymbolIndexStore.swift` 末尾），不在名单里的入口节点直接被丢掉，什么错误也不报。按 kind 的索引（`symbols(of:)`）不受这两处影响，每个符号都记一行。

`@objc` thunk（`$s…To`）不是成员符号，成员索引不收它；它照旧进 thunk 属性的标记表（只记成员名，供 `applyThunkAttributes` 打 `@objc`），此外按它进入的成员归进第四个成员索引 `objcThunkMemberSymbolRowsByKind`，与实现符号、`Tq`、protocol witness 三个索引的键相同，存的是 thunk 自己的行（`objcThunkMemberSymbols(of:…)`）。这个索引是给优化构建用的：成员的 Swift 函数体被内联进 thunk、Swift entry point 被删掉之后，thunk 是这个成员仅剩的符号，声明模型从它造替身成员（[ThunkOnlyObjCMembers.md](../ThunkOnlyObjCMembers.md)）。`…ToTm`（合并后的 thunk 函数体）以 `mergedFunction` 开头，不进这个索引。

**成员 / typeInfo / thunk 属性这几个索引的 key 不是单射的**：第一层是打印出来的类型名，用 `.interfaceTypeBuilderOnly` 打印，会剥掉 private discriminator，于是不同文件里同名的 private 类型共用一个名字桶（issue #115：dump 路径按名字查，把两个类型的成员混进了同一个声明）。所以——

> 解析**某一个**类型的成员 / 信息 / 属性，必须用带 node 的重载（`memberSymbols(of:for:node:in:)`、`methodDescriptorMemberSymbols(of:for:node:in:)`、`objcThunkMemberSymbols(of:for:node:in:)`、`typeInfo(for:node:in:)`、`thunkAttributeMembers(of:for:node:in:)`）。只带名字的那几个重载会故意把所有子桶摊平，只用于「所有打印成这个名字的类型」这种聚合查询。

**同一地址上的符号按归属分组**（演进提案 `faster-lazy-definition-indexing`）。identical code folding 会把许多 conformance 内容相同的 witness 实现合并到一个地址上——SwiftUI 里一个 `_destroySelf` 或值 witness 的实现挂着上千个名字。要在这样的地址上找「属于某个 conformance 的那个」或「属于某个协议的那个」，用 `symbols(for:ownedBy:ownerKind:printedWith:in:)`：`SymbolOwnerKind.conformingType` 是符号树里第一个 `protocolConformance` 的第一个子节点，`.protocol` 是第一个 `protocol` 节点，按调用方给的打印预设打印后比较；结果按 `symbols(for:in:)` 的顺序排列，带查询偏移。每个「地址 + 规则 + 预设」第一次被问到时在 `Storage` 上分组一次（锁外计算、锁内先到者胜），之后每次是两次字典查找。以前 `ExtensionDefinition`、`ProtocolDefinition`、`ProtocolConformanceDumper`、`ProtocolDumper` 都是把这个地址的名字逐个 demangle、搜索、打印再比较，每个 conformance 来一次，对别名组大小是平方级：SwiftUI 一个镜像检查 365 万次、只涉及 17,852 个不同的名字。**新的「在别名里找归属」的代码走这个查询，不要再逐个比较。**`ClassDumper.validNode` 与 `OverrideSymbolMatcher` 按声明上下文结构相等来认领，规则不同、实测开销可以忽略，没有改。

`Storage` 同时带着 `.swift` 表的**导出事实**（`SymbolExportFacts`，采集方式见 MachOKitExtensions 的 [SymbolIndex.md](https://github.com/MxIris-Reverse-Engineering/MachOKitExtensions/blob/main/Documentations/Internal/SymbolIndex.md)），撑起三态的 `isExported(name:in:)`（`nil` = 这个镜像没有导出信息，**此时绝不标注**）。注意 `NlistProtocol.isExternal` 只指**未定义的导入**（`N_EXT` 加 `N_UNDF`），导出的定义同样带 `N_EXT`，不要拿它当「是否导出」。成员级的判定走 `isExportedIncludingDerivedSymbols(names:in:)`：成员任一入口（自身或 `Tj` / `Tq` / `Tu` 派生形式）导出即为导出，interface 的 `// not exported` 注释和 ABI 快照的 `MemberRecord.isExported` 都问这一处。

同一趟还记下镜像**有没有 local Swift 符号**（`hasLocalSwiftSymbols(in:)`，取自 `.swift` 表的 `hasLocalSymbols`，演进提案 `evolution-unobservable-presence`）：收到的 Swift 符号里，只要有一个 `N_EXT` 位为 0（`NlistProtocol.isLocal`，调试用的 STABS 条目不算）就是 `true`。被剥掉 local 符号的镜像——macOS 13.0–14.8 dyld shared cache 里的 SwiftUI——只剩导出的 Swift 名字，非导出的声明在这里根本没有名字，evolution 与 diff 据此把它们记为看不见而不是删除。判据不能用 `!isExternal`：导出符号同样过得了那道过滤。

## 子系统 2：查询出口与 detach

查询在出口处构造 `DemangledSymbol` / `NodeReference` 值。这些值共享镜像那张 `SymbolTable`——对于一次查询吐出又丢弃的几十万个值，这是对的交换。

> **但凡要存进声明模型的 `DemangledSymbol`，必须先 `detachedFromSharedTable()`。** 一个存活的值就钉住整张表（镜像表还会把它对 mapped string table 的读连在加载状态上），`removeSubIndexer(_:)` 想回收的按镜像内存就白回收了。查询路径上**不要** detach。

实测（SwiftUI，iOS 18.5）：9872 个被存下来的值只引用 5.1% 的行，detach 是拿约 0.6 MB 的小分配换掉整张表的驻留。存的地方一共六处，`SymbolTableRetentionTests` 会在有人新增第七处却忘了 detach 时立刻变红。

## 子系统 3：跨 store 对账

节点引用的 `Hashable` 是 **store 身份**语义。一个镜像内部同时存在好几个 store——冻结的主符号 store、迟到名字的旁路 store、缓存的各作用域 store，按镜像驱逐还会把某个作用域重建到新 store 上而旧引用仍然钉着旧的（2026-09-28 之前内存压力也会）——所以跨 store 是常态，不是例外。

> **任何 key 与查询可能来自不同 store 的 `Dictionary` / `Set`，必须以 `StructuralNodeReferenceKey` 为 key，不能用裸 `NodeReference`。**

用裸 key 会静默失败，而且各处的失败形态还不一样：override / vtable 查找会丢掉 `override` 关键字和 vtable 偏移注释；下标的 getter 和 setter 分进两个桶，只有 setter 的那个被丢弃；合并的 thunk 会把 `func` / `init` 印两遍；witness 会被认领两次。只有在**一批** `memberSymbols` 内部做分组或去重（单一 hash-consed store，结构相等与索引相等重合）时，裸 key 才是安全的。

`InternedNodeReferenceCache` 管的是 `SharedNodeStore` 里**没有**的那部分职责：按 Mach-O 作用域分区和驱逐。metadata 派生的名字树走它。

> 批量路径上不要裸调 `NodeReference(interning:)`，走缓存。

## 子系统 4：大栈执行器

`LargeStackTaskExecution.run(_:)` 在库入口外面把 swift-demangling 的 16 MB `LargeStackTaskExecutor` 设为 task executor preference。demangler 每次调用会拿**调用线程**的剩余栈跟 2 MB 下限比一下决定要不要跳到自己的 8 MB 池；协作线程和 libdispatch 线程只有 512 KB，于是异步打印循环每打印一个符号就要付一次线程往返加信号量等待（实测 8–21 µs，1.14–2.28 倍）。在执行器线程上这个探测每次都过，整条流水线（含同步被调用方）就地跑完。

几条容易踩的：嵌套调用是 no-op；**非结构化的 `Task {}` 不继承这个偏好**（SE-0417），所以绝不要在被包裹的入口里起一个；main actor 保留自己的执行器；macOS 15 / iOS 18 以下或非 Darwin 平台原样执行 body。进程级关闭开关 `isEnabled`，由环境变量 `MACHO_SWIFT_SECTION_LARGE_STACK_EXECUTOR` 播种。

## 子系统 5：`_symbolic` 符号表

编译器给每条带 symbolic reference 的 mangled name 生成一个链接器去重用的符号（`_symbolic ` / `_default assoc type ` 开头），
名字里按引用顺序写出每个被引用者的完整 mangling。`SwiftSymbolTableRouting` 把它们分进采集的 `.symbolicMangling` 表，存为
`Storage.symbolicManglingSymbolTable`——同一个 `SymbolTable` 结构、同样的名字来源与偏移换算，但**不进任何索引**：
`symbols(for:in:)`、`containsSymbol(named:)`、导出事实都看不到它们，这些名字也从不 demangle。唯一的出口是
`symbolicManglingSymbols(in:)`，解码在 SwiftInspection 的 `SymbolicManglingIndex`（它要读 mangled name 的字节，本模块够不到
ABI 模型）。

> 被引用者不能单独 demangle：同一个 mangler 依次写出它们，后面的会用 substitution 借用前面的。一律经
> `SymbolicManglingIndex.referentNode(of:in:)` 拿节点。

细节与实测：[SymbolicManglingSymbols.md](../SymbolicManglingSymbols.md)。

## 关键契约

- **Swift 层不要写裸的 `SymbolIndexStore`**。那是 MachOKitExtensions 里只收 C/C++/ObjC 名字的 store，查询方法与 `SwiftSymbolIndexStore` 同名，写错会照样编译、却查不到任何 Swift 名字。`SymbolIndexStoreNamingScanTests` 扫 `Sources/` 与 `Tests/` 钉住。对应的名字：驱逐组是 `.swiftSymbolStore`（C/C++ store 用 `.symbolStore`），`DependencyValues` 的键是 `swiftSymbolIndexStore`。
- **不要重新引入带缓存的 demangle**。全模块（以及上层）用 `demangleAsNodeTransient` + `Node.createTransient`；一棵用完即弃的树必须是 transient 的，否则全局 `NodeCache` 会随浏览一路涨。
- **不要在缓存锁里做可能阻塞的大栈跳转**。迟到名字的 demangle 跑在锁外面，竞争的 misser 各自 intern 进同一个 store，靠结构化去重拿到同一个引用。
- **改本模块的结构布局要先 `swift package clean`**。SwiftPM 增量构建被观察到链接了陈旧的下游目标文件，症状是运行时在 `outlined destroy` 里 SIGSEGV。公开类型跨模块搬家或翻转依赖边同样会触发（2026-09-12 有一次实例）——先 clean，再诊断。

## 相关文档

- MachOKitExtensions [SymbolIndex.md](https://github.com/MxIris-Reverse-Engineering/MachOKitExtensions/blob/main/Documentations/Internal/SymbolIndex.md)——符号表、采集（`SymbolSweep` / `SymbolTableRouting`）与 C/C++ 符号索引。
- [NodeStoreMigrationPlan.md](../NodeStoreMigrationPlan.md)——存储形态迁移的完整分阶段计划。
- [NodeStoreMigrationOpenIssues.md](../NodeStoreMigrationOpenIssues.md)——迁移遗留问题。
- [SharedNodeStoreMigration.md](../SharedNodeStoreMigration.md)——声明模型持有 `NodeReference` 的那一步。
- [SymbolIndexStoreMemoryOptimization.md](../SymbolIndexStoreMemoryOptimization.md)——内存优化。
- [PrivateTypeMemberAttribution.md](../PrivateTypeMemberAttribution.md)——同名 private 类型的成员归属（issue #115）。
- [LargeStackTaskExecutorAdoption.md](../LargeStackTaskExecutorAdoption.md)——执行器接入与实测数据。
- [MetadataReaderCacheRetirement.md](../MetadataReaderCacheRetirement.md)——`SymbolicDemangler` 的 demangle memo。
- [SymbolicManglingSymbols.md](../SymbolicManglingSymbols.md)——`_symbolic` 符号的格式、收集与解码。
- 演进提案：[0001](../../Evolutions/0001-symbol-name-offsetization.md) 符号名 offset 化 · [0003](../../Evolutions/0003-symbol-row-bucket-flattening.md) 行号桶扁平化 · [0018](../../Evolutions/0018-self-contained-abi-layer.md) ABI 层自包含 · [0019](../../Evolutions/0019-large-stack-executor-and-cross-version-parallelism.md) 大栈执行器。
