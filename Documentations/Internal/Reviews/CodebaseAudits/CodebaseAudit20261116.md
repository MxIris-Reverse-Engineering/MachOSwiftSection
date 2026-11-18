# 代码库体检 2026-11-16

- **分支与提交**: `next` @ `1ba927ad`（工作树干净）
- **范围**: 首次体检。改动集取近 30 天：`42cbf5d4`（2026-10-17）到 HEAD，`Sources/` 下 443 个文件、+25,658 −3,228 行，分四块派 finder 深审严重 bug，另各派一个 finder 看结构与冗余。改动集的量已经达到一轮的深审上限、覆盖了大半模块，本轮不轮转。全仓机械扫描照常跑。
- **降级**: 本机没有 `jscpd` / `pmd`，重复代码全靠人工判断；仓库没有 `.swiftlint.yml`，没跑 lint；`Tests/` 不在审查范围（见账本「不审」）。
- **对照已裁决清单**: 跳过 4 条（A62 交叉引用的手写锁、A82 存量单字母泛型参数，以及复核时引用的两条有文档的有意设计：`OSLogEventHandler` 的 `os.Logger` 豁免、`ImageReference` 读失败当空表）。没有推翻任何已裁决条目。
- **子 agent**: 6 个 finder + 2 个复核；补漏在主线程做。

## 总评

近 30 天新增的代码以 ObjC 互操作（`SwiftObjCInterop`，把 ObjC 类、category、协议按 ClangImporter 的规则导入成 Swift 声明）和交叉引用分析为主，严重 bug 也集中在这两块：确认 7 条、待确认 2 条，没有丢数据或安全问题，崩溃类的都要畸形或少见的输入才触发。最该先处理的是两条常见路径上的错误输出：`[self class]` 之后的类方法发送被交叉引用记到实例上，以及所有 `const char *` 成员被印成可变指针。`@BitField` 迁移（125 个 ABI 文件）逐条核过位置与宽度，没有问题。结构上的主要代价是 ObjC 互操作这批新代码里有四处成对的重复，和三份同构的 dyld cache 共享登记表。

## 严重 bug

### 1. 交叉引用把 `[self class]` 之后的类方法发送记成发给实例

- **位置**: `Sources/Analysis/CrossReferenceAnalysis/CrossReferenceAnalyzer.swift:211-215`、`Sources/Analysis/CrossReferenceAnalysis/Scanning/ReferenceScanner.swift:142-143`、`:358`
- **判定**: CONFIRMED
- **状态**: 已修（同日），回归测试 `ClassOfReceiverSendTests`。
- **失败场景**: ObjC 实例方法里写 `[[self class] baz]`，编出来是 `objc_opt_class(self)` 再 `objc_msgSend`。扫描把 `objc_opt_class` 当成「原样返回参数」，调用后 `x0` 仍记作 `.methodReceiver`（实例），`receiverHint` 于是把对 `+baz` 的发送记成发给方法自己的接收者。宿主按接收者区分实例方法与类方法时，`+[Foo baz]` 的真实调用者被漏掉或算到 `-baz` 头上。`objc_opt_class` 只对类字面量是原样返回，对实例返回的是它的类。
- **能复现吗**: 能。任何 `[self class]`、`[[self class] alloc]` 的写法都会触发，ObjC 代码里很常见。
- **新的还是旧的**: `59631757`（2026-10-17，report Objective-C class references）把 `objc_opt_class` 归进「返回传入的类」，和 `0c0ebce3`（2026-10-16）起就有的方法接收者跟踪叠在一起出错；`e64b1085`（2026-10-27）最后改过这段。首次体检，`main` 上也有。
- **值不值得修**: 静默错误输出，RuntimeViewer 的「谁调用了这个方法」直接受影响。建议修：`objc_opt_class` 只在 `x0` 持有类字面量时保留状态，持有方法接收者时改记为「接收者的类」或清空。
- **以前修过吗**: 没有。模块文档 `Modules/CrossReferenceAnalysis.md` 与提案 0072、0076 只讨论了类字面量接收者，当初的设计没考虑方法接收者经过 `objc_opt_class` 的情况，那个前提对这种情况不成立。
- **同类实例**: 无。同一处并列的 `objc_opt_self` 与 `swift_getInitializedObjCClass` 对参数确实原样返回。

### 2. ObjC 协议要求：编码里的参数比 selector 的冒号少时数组越界崩溃

- **位置**: `Sources/Analysis/SwiftObjCInterop/ObjCProtocolRequirements.swift:184-186` → `Sources/Analysis/SwiftObjCInterop/ObjCImporterNaming.swift:174`
- **判定**: CONFIRMED
- **状态**: 已修（同日），回归测试 `ObjCProtocolRequirementBuilderTests.anEncodingThatDoesNotFitTheSelectorIsNotImported`。
- **失败场景**: `methodRequirement` 不核对编码的参数个数与 selector 的冒号数是否一致，就交给 `ObjCImporterNaming.importedName`；后者按冒号数建 `parameterIndices`，再用 `parameterTypes[$0]` 取类型。协议方法 `takeOne:andAnother:` 配上只有一个参数的编码（`v24@0:8@16`）就越界 trap。`dump` 与 `interface` 都走得到。
- **能复现吗**: 机制确认。编译器正常产出的记录不会不一致，触发要靠第 8 条（待确认）的编码错位，或畸形二进制。
- **新的还是旧的**: `e56ad3ff` / `ae6b78f0`（2026-10-28，@objc 协议要求的导入与命名），窗口内新出现，`main` 上没有。
- **值不值得修**: 崩溃，修法便宜。建议修：在 `importedName` 入口统一校验参数个数，两条调用路径一起受益。
- **以前修过吗**: 同类问题只修了一半。`b44b3391`（2026-11-10，never pair a selector with a short encoding）给类成员路径加了 `argumentMatchedMethodType`（`ObjCImportedMemberBuilder.swift:225-240`），提交说明写的正是 "trapped on the missing argument"；协议要求这条路径没跟着改。
- **同类实例**: `ObjCImporterNaming.swift:432` 的 `parameterTypes[0]`，在有冒号而编码没有参数时同样越界（未复核）。

### 3. `const char *` 成员被印成 `UnsafeMutablePointer<Int8>`

- **位置**: `Sources/Analysis/SwiftObjCInterop/ObjCTypeEncoding.swift:181`、`Sources/Analysis/SwiftObjCInterop/ObjCImportedTypes.swift:76`
- **判定**: CONFIRMED
- **状态**: 已修（同日），回归测试 `ObjCImportedMemberBuilderTests.aConstantCStringImportsAsAnImmutablePointer`。
- **失败场景**: 解析器读到 `r` 时记下了 `isConst`，但 `case "*"` 直接返回 `.characterString`，把 const 丢了；导入映射对 `.characterString` 一律给 `UnsafeMutablePointer<Int8>`。`- (const char *)UTF8String`（编码 `r*16@0:8`）于是印成可变指针，ClangImporter 给的是 `UnsafePointer<CChar>`。
- **能复现吗**: 能，所有 `const char *` 的属性、参数和返回值都会这样。
- **新的还是旧的**: 解析在 `ae6b78f0`（2026-10-28），映射在 `9dca5805`（2026-11-10），窗口内新出现，`main` 上没有。
- **值不值得修**: interface 里的类型错误，很常见。建议修：让 `.characterString` 带上 const，映射成 `UnsafePointer<CChar>`。
- **以前修过吗**: 没有。
- **同类实例**: 无。其它指针的 const 在 `ObjCTypeEncoding.swift:188` 保留了，只有 `r*` 丢。

### 4. 另一模块的 Swift 类经 category 遵循本镜像的 `@objc` 协议时，witness 全部找不到

- **位置**: `Sources/Analysis/SwiftThunkAnalysis/ObjCMembers/ObjCProtocolWitnesses.swift:96-101`
- **判定**: CONFIRMED
- **状态**: 已修（同日），回归测试 `ObjCProtocolDefinitionIndexingTests`（文件、进程内、strip 三个读法）；修的时候发现文件里的同类问题，见文末「修复」。
- **失败场景**: `memberTable` 对任何 `_TtC` 名字都先按 Swift 类查表，查不到直接 `return nil`，不回退 `table(forObjCClassNamed:)`；而按 Swift 名查表只认本镜像 classlist 里的类。本镜像写 `extension OtherModule.Foo: MyObjCProtocol`（`Foo` 是另一模块的 `NSObject` 子类）时，这个 conformance 的 witness 一律丢失。这与 `:92-95` 的注释（另一镜像的类按 runtime name 查）相反。
- **能复现吗**: 能，条件是跨模块的 category 遵循，常见于 app 给框架类加协议。
- **新的还是旧的**: `bf1e6d0a`（2026-10-28，tie stripped conformers and keep imported protocol names），窗口内新出现，`main` 上没有。
- **值不值得修**: 静默丢失 witness 与成员归属。建议修：按 Swift 名查不到时回退按 runtime name 查。
- **以前修过吗**: 没有。
- **同类实例**: `Sources/Output/SwiftDump/Dumpable/ObjCCategoryProtocolAdoption+Dumpable.swift:56` 同样按 `_Tt` 前缀分流（见「规则」一节）。

### 5. 同名的 private 泛型类：第二个被去重丢掉，第一个的 ObjC 成员表套到两个定义上

- **位置**: `Sources/Analysis/SwiftObjCInterop/SwiftClassWithoutClassObjectIndex.swift:168`（名字的生成在 `:345-346`）
- **判定**: CONFIRMED
- **状态**: 已修（同日），回归测试 `SwiftClassWithoutClassObjectIndexTests.sameNamedPrivateGenericClassesAreBothListed`。
- **失败场景**: 两个文件各有一个 `private class Foo<T>: NSObject`，它们的 `name` 都是不带私有鉴别符的 `Mod.Foo<A>`，`Storage` 按 `name` 去重时丢掉第二个，`namesBySwiftQualifiedName["Mod.Foo"]` 只剩一项。`ObjCMembers.table(forSwiftClassQualifiedName:)`（`ObjCMembers.swift:57-59`）本该在多于一项时拒绝猜，现在会把第一个类的成员表（`override`、selector 判定）同时安到两个 Swift 定义上。`:163-164` 的注释说多条目表示同名 private 类，对泛型类不成立。
- **能复现吗**: 能，需要同模块里两个同名的 private 泛型 `NSObject` 子类，少见。
- **新的还是旧的**: `c11e3a06`（2026-10-27，read the ObjC class data of Swift classes without a class object），窗口内新出现，`main` 上没有。
- **值不值得修**: 少见，但结果是错的 `override` 与 `@objc(selector)`，不是漏印。建议修：去重键带上私有鉴别符或描述符偏移。
- **以前修过吗**: 没有。同名私有类型的成员归属问题以前在 issue #115（`PrivateTypeMemberAttribution.md`）修过，那次修的是成员索引，不是这张表。

### 6. `@Observable` 类里手写的同名方法被当成宏生成的而藏掉

- **位置**: `Sources/Declaration/SwiftDeclaration/Indexing/Building/ObservableMacroExpansionRecovery.swift:161-174`
- **判定**: CONFIRMED
- **状态**: 已修（同日），回归测试 `ObservableMacroInterfaceTests.methodsNamedLikeTheGeneratedOnesArePrinted`、`ObservableMacroExpansionRecoveryTests.theGeneratedMethodsAreToldByTheirShape`。
- **失败场景**: `isGeneratedFunction` 只比方法名与参数标签，不比参数类型；无参函数没有标签列表，`argumentLabels.isEmpty` 也算命中。用户在 `@Observable` 类里手写 `func shouldNotifyObservers()`，或写一个 `access(keyPath: String)` 重载，都会被计入 `generatedFunctions`（`TypeDefinition+ObservableMacro.swift:66-73`），interface 默认的折叠形态不印它。
- **能复现吗**: 能，需要手写与宏生成成员同名的方法，少见。
- **新的还是旧的**: `f423e26c`（2026-11-11，recover what the @Observable macro generated），窗口内新出现，`main` 上没有。
- **值不值得修**: 静默丢成员。建议修：连参数类型一起比。
- **以前修过吗**: 没有。提案 0093 只说宏生成的不印，没讨论手写同名的情况。

### 7. 畸形 export trie 让 `cursor + Int.max` 溢出，崩掉宿主进程

- **位置**: `Sources/Analysis/CrossReferenceAnalysis/Scanning/RenamedReexportIndex.swift:91`
- **判定**: CONFIRMED
- **状态**: 已修（同日），回归测试 `MalformedExportTrieTests`。
- **失败场景**: `readULEB128` 能读出 0 到 2^64−1 的任意值。export trie 里终端大小 ≥ 2^63 时，`Int(clamping:)` 得 `Int.max`，`cursor + …` 溢出 trap。第一次跨镜像查调用者、或宿主调 `preparePrefilters()` 时走到。
- **能复现吗**: 机制确认，只有畸形或人为构造的缓存外 dylib 会触发，编译器产出的不会。
- **新的还是旧的**: `0bb8f963`（2026-10-17，look for the names other images re-export a function under），`main` 上也有。
- **值不值得修**: 罕见，但崩的是宿主进程（RuntimeViewer 注入时是被查看的 App），修法一行。建议修：越界或溢出时把这个节点当畸形跳过。
- **以前修过吗**: 没有。`:82-83` 的注释声明要容忍畸形 trie，这一处漏了。
- **同类实例**: 无，全仓只有这一处 `Int(clamping:)` 后接加法。

### 8. 待确认：协议的某个方法列表读不出时，extended 类型编码整体错位

- **位置**: `Sources/Analysis/SwiftObjCInterop/ObjCProtocolRecord.swift:149`（`MachOImage` 版在 `:189`），对齐逻辑在 `:82-88`
- **判定**: PLAUSIBLE
- **状态**: 已修（同日，随第 2 条），回归测试 `ObjCProtocolRequirementBuilderTests.extendedTypesThatDoNotFitTheirMethodsAreNotPaired`。
- **失败场景**: 某个方法列表读不出或是 list-of-lists 时按 `[]` 处理，但 extended method types 仍按剩余方法的总数逐槽对齐，后面每个方法拿到的是别的方法的编码：协议要求静默印错参数与返回类型；参数个数对不上时，接着触发第 2 条的崩溃。`:108-111` 的注释防了「数组读一半」，没防「列表缺失」。
- **能复现吗**: 缺证据：要找到一个 `methods(in:)` 对 `protocol_t` 的某个列表返回 nil 的真实二进制。`protocol_t` 正常不会是 list-of-lists。
- **新的还是旧的**: `02b3d5f5`（2026-10-28，find the @objc protocols an image declares in Swift），`main` 上没有。
- **值不值得修**: 待确认；建议和第 2 条一起修，读不出的列表按原位置占位，不压缩。
- **以前修过吗**: 没有。

### 9. 待确认：编码里超大的 C 数组让导入卡死或耗尽内存

- **位置**: `Sources/Analysis/SwiftObjCInterop/ObjCImportedTypes.swift:97-100`
- **判定**: PLAUSIBLE
- **状态**: 已修（同日，用户看过报告后批准），回归测试 `ObjCImportedMemberBuilderTests.aCArrayImportsAsClangImporterImportsIt`。
- **失败场景**: C 数组按编码里的元素个数建等长 tuple，个数没有上限，`readNumber` 能读到接近 `Int.max`。编码 `^[999999999c]` 会让 `map` 分配十亿个节点。正常的方法与属性编码里 C 数组会退化成指针，只有指向数组的指针或畸形编码能走到这里。
- **能复现吗**: 缺证据：要一个真实二进制里出现大数组的 `^[N…]` 编码，或人为构造。
- **新的还是旧的**: `9dca5805`（2026-11-10），`main` 上没有。
- **值不值得修**: 待确认，低优先；加一个上限（超过就印成 `OpaquePointer`）即可。
- **以前修过吗**: 没有。

## 修复验证时发现的严重问题

### 10. 并行建 demangled index 时整个进程卡死

- **位置**: `Sources/MachO/MachOSymbols/SymbolIndexStore.swift:2019-2040`（`DemanglingWave.start` / `waitUntilDemangled`），调用处 `:1018-1022`，加锁处 `:297-303`
- **判定**: CONFIRMED（本机两次复现）
- **状态**: 已修（同日，用户看过报告后批准「先缩小复现再修」），回归测试 `SymbolIndexDemangledIndexTests.firstReadersOnEveryCooperativeThreadAllFinish`。
- **失败场景**: 建 demangled index 的线程持着构建锁，把下一批名字交给 `DispatchQueue.global()` 去还原，再同步等这批做完（`group.wait()`）。同时别的读者在协作线程上调 `demangledIndex`，经 `withLargeStack` 同步阻塞，等大栈线程，而大栈线程要么持锁等这一批、要么等这把锁。协作线程池被占满后，那批任务一直没有被调度起来，整个测试进程停住，CPU 为 0。
- **能复现吗**: 能。在公司那台 10 核 Mac Studio（macOS 27.2，Xcode 26.6）上，修复分支的并行全量测试两次都卡死，一次在约 9 分钟处，一次在约 2 分钟处。`sample` 显示 10 个协作线程全在 `demangledIndex(reportingProgressTo:)` → `StackSafeExecutor.runOnLargeStack` 的信号量上；几个大栈线程在 `DemanglingWave.waitUntilDemangled()`，其余在构建锁上；没有一个线程在执行 `DemanglingWave.start` 交出去的那批任务。卡住时在跑的是 `DumpAndInterfaceRequestTests`、`ConstructedThunkOracleTests`、`SymbolIndexDemangledIndexTests.concurrentFirstReadersShareOneBuild` 等与本次修复无关的套件。还缺一条单独就能变红的命令：在 `LIBDISPATCH_COOPERATIVE_POOL_STRICT=1`（单线程协作池）下单跑 `SymbolIndexDemangledIndexTests` 不卡，4 个测试 2 秒跑完；28 核的 Ultra 上并行全量也不卡。之后缩小成了一条命令：在子进程里同时起「核数 × 2」个任务，各自在协作线程上同步读一个新建 storage 的 demangled index，28 核的 Ultra 上也稳定卡住（两次都卡满 60 秒看门狗），采样形态与 10 核那台一致。
- **根因**: 协作线程全部同步阻塞时，它们仍占着同一 QoS 的并发额度，交给 `DispatchQueue.global()` 的任务分不到线程。只用 GCD 的探针证实了这一点：把协作线程全部阻塞后，全局队列和私有并发队列的任务 5 秒内都没执行，私有串行队列（挂在 overcommit 根队列上）0.07 秒就执行了。建索引的线程同步等这一批，于是整个进程停住。
- **修法**: `DemanglingWave` 改从私有串行队列起头，里面的 `concurrentPerform` 照常用满所有核（探针实测 28 个线程），没有别的线程加入时由调用线程自己做完。`AGENTS.md` 的异步一节加了「同步等待的工作只交给私有串行队列」这条规则；回归测试所在的套件加进了 CI 的名单。
- **新的还是旧的**: `b4f80bf9`（2026-11-06，demangle a symbol table's names on several threads ahead of the interning sweep，提案 0088 第 5 项）引入，`main` 上没有。11-12 两批的全量测试在 28 核的 Ultra 上跑过，协作线程池有 28 个线程，没有撞上。体检时第 D 单元的 finder 判断「靠大栈线程池的溢出放行不会死锁」，但那个放行只管大栈线程，管不到 GCD 全局队列给不给线程。
- **值不值得修**: 卡死。宿主在 Swift 并发里同时给几个镜像建索引（RuntimeViewer、多版本 evolution），核数少的机器上就可能撞上。建议修：那批任务改交给不和协作线程池共用额度的地方执行（私有串行队列，或自己起线程；私有并发队列不行，见下文根因），并把回归测试所在的套件加进 CI。
- **以前修过吗**: 同一类问题出过：项目 `CLAUDE.md` 写着「不要在协作线程上无时限地等一个需要线程池线程的任务，比如 `DispatchQueue.global()` 的 block」，2026-09-29 有三个测试因此在 3 核的 CI 上冻住整个进程，CI 为此加了 `LIBDISPATCH_COOPERATIVE_POOL_STRICT=1` 的步骤。这次是同一类等待出现在库代码里，而且等待的一方在大栈线程上，那一步的套件名单没收它。

## 规则

### 新增违规（窗口内，2026-10-17 起）

| 规则 | 位置 | 说明 |
|------|------|------|
| 项目 `CLAUDE.md` SwiftObjCInterop 一段："every name-keyed ObjC-side lookup of a Swift class falls back to it [`SwiftClassObjectIndex`] on a miss" | `Sources/Output/SwiftDump/Dumpable/ObjCCategoryProtocolAdoption+Dumpable.swift:54-60` | 私有 `classNode()` 自己 demangle `_Tt` / `$s` 名字，没用会回退查索引的 `ObjCRuntimeNames.classNode(forRuntimeName:in:)`；interface 那条路（`ObjCCategoryConformance.swift:35`）用的是后者。可能的后果是同一镜像里改过运行时名的类，它的 category 在 dump 里印成 `__C.Name`、interface 里印成 Swift 名，但同镜像的 category 一般已被链接器合并进类里，这个后果没有证实。引入于 `07c6153f`（2026-10-28）。可能的原因：这里只拿得到 `ReadingContext`，共享函数要 `machO`。 |
| 全局指令「编码风格」："更不要用 print" | `Sources/Executables/reader-benchmark/ReaderBenchmark.swift:221-232` | 基准可执行文件用 `print` 输出测量结果，是产品输出而不是日志；`swift-section` 的 `StandardStreamOutput` 规定不管它。建议不修，见文末。引入于 `b28d8887`（2026-11-06）。 |

窗口内新增的其余命中都不是违规：`InitAccessorFixture.swift:80-81` 的 `var b` / `var a` 是写在字符串里、测试时现场编译的 fixture 源码；`SwiftPrinting` 新增的 `var x: T` 在文档注释里；新增的 `NSLock`（`MachODependencies` 三份登记表、`SwiftLayout/LazilyBuiltIndex.swift`）是按文件或按 cache 的打开登记、以及 `SharedCache` 条目内部的槽位，不是按镜像的缓存；`GenericArgumentEnvironment.swift:215` 的 `"Swift.AnyObject"` 只用作查找 key。

### 存量计数

首次体检，没有上轮。只列计数不为 0 的规则；检查式见账本。

| 规则 | 模块分布 | 本轮 | 上轮 | 变化 |
|------|---------|------|------|------|
| 不用 `print` | SwiftInspection 12（`SpareBitAnalyzer.printAnalysis`，在 `PrintFailureEventTests` 允许名单里）、MachOTestingSupport 4、MachOFixtureSupport 4、reader-benchmark 4、SwiftDeclarationRendering 2 与 MachOReading 1（都是文档注释） | 27 | — | — |
| 不直接用 `os.Logger` | SwiftIndexing 1（`OSLogEventHandler`，`PrintFailureEventTests` 登记的豁免） | 1 | — | — |
| 不用 `FileHandle.standard*.write` | RegenerateBaselinesPlugin 2、SwiftIndexing 1（注释） | 3 | — | — |
| 节点工厂调用（信号） | SwiftThunkAnalysis 10、SwiftLayout 8、SwiftSpecialization 6、SwiftPrinting 4、SwiftDeclarationRendering 4、MachOSymbols 2、SwiftDeclaration 1、SwiftDump 1（全是 `Node.create`，只对无子节点的叶子做驻留） | 36 | — | — |
| 裸 `NodeReference(interning:)`（信号） | MachOSymbols 5、SwiftInspection 1、SwiftPrinting 1 | 7 | — | — |
| 单字母泛型参数（存量，A82） | MachOPointers 21、MachOReading 17、MachOTestingSupport 16、MachOSwiftSection 7、MachOFixtureSupport 6、Utilities 5、SwiftDeclaration 3、MachOResolving 3、SwiftLayout 2、SwiftSpecialization 2、其余四个模块各 1 | 86 | — | — |
| 单字母局部变量 | SwiftInspection 14、SwiftPrinting 7（5 处在文档注释）、SwiftLayout 2、SwiftDeclaration 2、MachOTestingSupport 2、SwiftInterface 1、MachOFixtureSupport 1 | 29 | — | — |
| 裸 `_mangledTypeName` | SwiftDeclarationRendering 1（`RuntimeTypeNameDemangling` 自己，合规） | 1 | — | — |
| `first(of: .privateDeclName)`（信号） | SwiftPrinting 2（`FunctionNodePrinter.swift:58`、`VariableNodePrinter.swift:56`，作用在 `children` 数组上只查直接子节点，合规） | 2 | — | — |
| `NodeReference` 作键（信号） | SwiftIndexing 1（`SwiftDeclarationIndexer.swift:1091`） | 1 | — | — |
| `Task {}` | MachOSymbols 1（文档注释） | 1 | — | — |
| 手写锁（信号） | MachODependencies 10、CrossReferenceAnalysis 7（A62）、SwiftDeclarationRendering 5、SwiftThunkAnalysis 5、MachOTestingSupport 4、SwiftObjCInterop 3、MachOSymbols 2、MachOCaches 2、其余五个模块各 1 | 43 | — | — |
| 废弃转发器 | MachOSwiftSection 252、MachOPointers 45、MachOResolving 29、SwiftInspection 15、SwiftDeclaration 8、SwiftDump 3、SwiftInterface 2、其余三个模块各 1 | 356 | — | — |
| 模块限定名字符串（信号） | SwiftLayout 34、SwiftInterface 31、SwiftInspection 18 | 83 | — | — |

## 代码异味与层次

### 成员排序逻辑有三份

- **位置**: `Sources/Output/SwiftPrinting/SwiftDeclarationPrinter+ObservableMacro.swift:418-426`，对照 `Sources/Output/SwiftPrinting/SwiftDeclarationPrinter.swift:800`、`:842-852`
- **问题与代价**: `.byOffset` / `.byCategory`（`vtableOrdered`、按类别、滤掉 `minVTableOffset == nil`）的排序在 `@Observable` 展开里抄了第三份；排序规则改一处，展开里的成员顺序就和类型体不一致。finder 担心的「漏了 property wrapper 合成成员的过滤」复核后不影响输出（这份只留宏生成的函数）。
- **更简单的形状**: 抽一个 `orderedMembersForPrinting(of:)` 给三处共用。
- **四问**: 确认存在；`f0fd4447`（2026-11-11）引入，`main` 上没有；代价中等、收益明确，建议修；没修过。

### `SwiftDeclarationIndexer` 的几个阶段函数过长

- **位置**: `Sources/Declaration/SwiftIndexing/SwiftDeclarationIndexer.swift:913-1249`（`indexExtensions`，约 337 行）、`:723-860`（`indexConformances`，约 138 行）、`:503-634`（`indexTypes`，约 130 行）、`:281-400`（`prepareIndexes`，约 120 行）
- **问题与代价**: 每个新识别能力（这一窗口的「其它镜像类型的成员」、`@Observable`、ObjC 协议）都往这几个函数里加步骤，全文 1,606 行，近 30 天又涨了 240 行。
- **更简单的形状**: 每个阶段拆成具名步骤，`indexExtensions` 先拆。
- **四问**: 确认存在；起源于 `e2759bb6`（2025-11-18，Split SwiftInterfaceBuilder Class）之后逐步加长，`main` 上也有；建议在下次动这些函数时顺手拆，不单独排期；没处理过。

### `SymbolIndexStore` 一个文件管太多事

- **位置**: `Sources/MachO/MachOSymbols/SymbolIndexStore.swift`（2,046 行）
- **问题与代价**: 符号表行、`ExportFacts`、`_symbolic` 表、晚到名字的 side store、`DemangledIndex` 的懒构建与锁、按 owner 分组都在一个类型下。内部已按嵌套类型分块，代价主要是一个文件过大、锁与栈的不变量要在大文件里推理（裁决 A61 的「持锁时 demangle」就出在这里）。
- **更简单的形状**: 把 `DemangledIndex` 的构建与 owner 分组搬到各自的文件或类型。
- **四问**: 确认存在；始于 `406d2187`（2025-06-26），逐步长大，`main` 上也有；收益中等，可排低优先；没处理过。

### `SwiftDeclaredObjCProtocolIndex` 同一映射一半存、一半现算

- **位置**: `Sources/Analysis/SwiftObjCInterop/SwiftDeclaredObjCProtocolIndex.swift:94-97`、`:135-137`
- **问题与代价**: `Storage` 存了 `qualifiedNamesByRuntimeName`，查找时先拿它判断有没有，再对 `protocols` 线性 `first`。建字典时同名的后者覆盖前者，`first` 取的却是前者，同一镜像两个协议用同一运行时名时两边会分叉（现实中几乎不会）。
- **更简单的形状**: 直接存 `[String: SwiftDeclaredObjCProtocol]`。
- **四问**: 确认存在；`02b3d5f5` 与 `e56ad3ff`（2026-10-28），`main` 上没有；代价小，顺手修；没修过。

## 重复代码

### `MachODependencies` 里三份同构的共享登记表

- **位置**: `Sources/MachO/MachODependencies/SharedDyldCacheOpenings.swift:33`、`SharedMachOFileOpenings.swift:68`、`DyldCacheImageDirectory.swift:136`
- **重复了什么**: 外层锁加 `[Key: Slot]`、每个 slot 自带 `NSLock` 先查后建，各约 30 行；`SharedDyldCacheOpenings.swift:36-38` 自己注明照抄了 `DyldCacheImageDirectory`。两个弱引用版本的 slot 从不从字典删除，条目数随进程里见过的文件数增长，每条约两三百字节，量级可以忽略。
- **该合并到哪里**: `MachODependencies`（或 `MachOCaches`）里一个泛型 slot 登记表，参数化强 / 弱持有与建好后的预热。
- **四问**: 确认；`ab0fc5cd`（2026-11-03）、`accdec47` 与 `6fe12bf7`（2026-11-06），`main` 上没有；并发策略改一处要改三处，建议合并；没处理过。

### ObjC 属性的 getter / setter selector 推导写了两份

- **位置**: `Sources/Analysis/SwiftObjCInterop/ObjCImportedMemberBuilder.swift:177-185` 与 `Sources/Analysis/SwiftObjCInterop/ObjCProtocolRequirements.swift:155-163`（`PropertyAccessors` 与 `propertyAccessors(of:)`）；attribute string 的手工 `split` 另有三处（`ObjCProtocolRequirements.swift:157`、`ObjCImportedMemberBuilder.swift:179,205`、`ObjCImporterNaming.swift:218`）
- **该合并到哪里**: 一个只要求 `name` 与 `attributes` 的小协议加共享实现，放在 `ObjCImporterNaming` 旁边。
- **四问**: 确认逐字相同、合并后行为不变；`e56ad3ff`（2026-10-28）与副本 `97741012`（2026-11-10），`main` 上没有；改 selector 推导时两条路径会不一致，建议合并；提案 0090 决策日志说过协议要求复用已有 builder，类成员这边却另抄了一份。

### ObjC 协议要求的打印写了两份

- **位置**: `Sources/Output/SwiftPrinting/SwiftDeclarationPrinter+ObjCImportedDefinitions.swift:231-237` 与 `Sources/Output/SwiftPrinting/SwiftDeclarationPrinter+ObjCProtocols.swift:126-132`；`printingKind(of: ObjCProtocolRequirementDefinition)` 在两文件 `:294-300` 与 `:177-183` 逐字相同
- **重复了什么**: 两个函数只差 `@objc` 是总写还是只在显式 selector 时写。
- **该合并到哪里**: 合成一个函数，用参数控制 `@objc` 的写法。
- **四问**: 确认；`bfecf4bf`（2026-10-28）与副本 `ed72c915`（2026-11-10），`main` 上没有；建议合并；没处理过。

### 「已 realize 的类先经 `class_rw_t` 再取 `class_ro_t`」写了四份

- **位置**: `Sources/Analysis/SwiftLayout/ObjCClassIndex.swift:124`、`Sources/Analysis/CrossReferenceAnalysis/Scanning/ObjectiveCClassIndex.swift:155`、`Sources/Analysis/SwiftObjCInterop/ObjCImplementationClassIndex.swift:609`、`Sources/Declaration/SwiftPrivateDiscriminators/PrivateDiscriminatorSourceFileIndex.swift:236`
- **重复了什么**: 同一段 runtime 规则（ro → rw.ro → rw.ext.ro），四份写法等价，还没有分叉。
- **该合并到哪里**: 下沉到四个模块共同依赖的一层（`SwiftObjCInterop`，或上游 `MachOObjCSection` 的 `ObjCClass64` 扩展）。
- **四问**: 确认；`5a9971d6`（2026-06-22）、`584f1ff7`（2026-09-20）、`1292cda2`（2026-10-11）、`59631757`（2026-10-17），前两份 `main` 上也有；每份不到 20 行，收益中等，可排低优先；没处理过。

## 死代码

| 位置 | 判定依据 | 引入 | 建议 |
|------|---------|------|------|
| `Sources/Output/SwiftPrinting/NodePrinter/FunctionNodePrinter.swift:105` `isReturnOptional`（internal） | `rg isReturnOptional` 在 `Sources`、`Tests`、`Plugins` 与上游 swift-demangling 都只有声明；不是协议要求 | `9fdb1a5a`（2025-09-28），`main` 上也有 | 删 |
| `Sources/Analysis/SwiftLayout/ImageReference.swift:200` `protocolClassConstraint(forQualifiedTypeName:)`（internal） | 唯一使用方直接读底层字典（`ImageUniverse.swift:250`），测试也读字典 | `a5fe6743`（2026-06-21），`main` 上也有 | 删 |
| `Sources/ABI/MachOSwiftSection/Models/Mangling/MangledName.swift:116` `isContentsEqual(to:)`（package） | `package` 在包外不可见，`Sources`、`Tests` 都没有引用 | `f67b11cc`（2025-10-13），`main` 上也有 | 删 |
| `Sources/Output/SwiftDeclarationRendering/Extensions/MetadataWrapper+Dump.swift:68` `TypeLayout.dumpDebugDescription`（fileprivate） | 本文件内无使用，fileprivate 不可能被动态引用 | `560b683c`（2025-12-24），`main` 上也有 | 删 |

都不涉及动态引用（selector、类名字符串、KVC、插件注册）。

## 复核为 PLAUSIBLE、未达门槛的线索

后果不是崩溃、丢数据或安全问题，按门槛不列为发现；记在这里，供以后有证据时重新判断。

| 位置 | 机制 | 什么能证实它 |
|------|------|-------------|
| `Sources/Support/ARM64InstructionDecoding/ARM64Trampoline.swift:64-67` | GOT 桩识别一见 `ldr` 就判为桩，不核对后面的 `br` / `braa`；`SwiftThunkAnalysis` 的 `resolveCallee`（`MachOThunkEnvironment.swift:278`）对未认出的被调函数都先试它 | 一个以 `adrp; ldr` 开头的普通函数被 thunk 调用，thunk 读取器把它跟到 GOT 槽 |
| `Sources/Analysis/SwiftObjCInterop/SwiftDeclaredObjCProtocolIndex.swift:226` | 字段描述符的名字用 `.symbolString` 拼成文本再 demangle，没走 `SymbolicDemangler`；名字里有 symbolic reference 时该 `@objc` 协议整个消失 | 编一个 `struct Outer { @objc protocol P {} }`（SE-0404 嵌套协议），看名字里有没有 symbolic reference |
| `Sources/Declaration/SwiftIndexing/ObjCSuppliedClass+SwiftClassesWithoutClassObjects.swift:30`、`ObjCInterfaceIndexerClassHierarchyProvider.swift:118` | 父类读不出时空名被转成 `nil`，宿主 provider 路径判定祖先链完整，可能下出错误的 `@objc(selector)`；库自己的路径判为不完整 | `superclassTypeMangledName` 或 demangle 抛错的真实镜像，走 RuntimeViewer 的 provider 路径 |
| `Sources/Declaration/SwiftIndexing/SwiftDeclarationIndexer.swift:973`、`:1091` | 两个成员批次合并后用裸 `NodeReference` 键分组，违反只在单批次内用裸键的规则 | 在 SwiftUI / SwiftUICore 的 interface 里找重复的 `extension … where` 头 |
| `Sources/Output/SwiftPrinting/SwiftDeclarationPrinter.swift:1250-1253` | 废弃转发 `opaqueType(forNode:index:usesModuleSelectors:)` 不带 `useExistentialAny`，仍调它的宿主拿到不带 `any` 的拼写 | 下游（RuntimeViewer、MachOKitUI）是否还调这个废弃接口 |
| `Sources/Output/SwiftPrinting/SwiftDeclarationPrinter.swift:554` | 折叠形态无条件藏起 `Observable` conformance extension；类型自身打印失败时这个 conformance 彻底消失（失败本身已有 `definitionPrintFailed` 事件） | 一个打印会抛错的 `@Observable` 类 |
| `Sources/Analysis/SwiftLayout/ImageReference.swift:51-52` | 依赖镜像的 `ImageReference`（强引用 `MachOFile` 与七个索引）进进程级 `SharedCache`，没有 owner 认领，CLI 从不调 `evictImagesWithoutLiveOwners()`，多版本运行时可能随版本数增长 | 确认 `evolution` 是否经 `ImageUniverse` 带依赖闭包；若是，对几个归档 cache 跑它，看 `lsof` 计数和 footprint |
| `Sources/Commands/SwiftSectionKit/ObjC/ObjCAPIRequests.swift:234-238` | `objc evolution --interface` 先把所有版本的 `MachOFile` 装进数组，映射整个运行期都开着（先全部加载是为了推断平台） | 几十个 dyld cache 跑一次，量文件描述符与 footprint |

## 建议不修（用户确认后登记进已裁决清单）

用户已确认，三条依次登记为 [ReviewAdjudications](../../ReviewAdjudications.md) 的 A83、A84、A85。

| 发现 | 理由 | 重新判断的条件 |
|------|------|---------------|
| `@Observable` 的折叠特例叠在共享的字段渲染上（`SwiftDeclarationPrinter+Headers.swift:523-560`，`ModelMembersSelection` 三种模式） | 提案 0093 有意把折叠接进字段块与成员块，为的是展开形态与折叠形态用同一套打印代码，注释逐字节一致；理由仍成立 | 出现第二个要折叠的宏时，再考虑改成由各个宏的折叠规则产出字段列表 |
| `CodeReferenceIndex` 查询结果里同一条指令上多条引用的顺序每个进程不同（`Models/CodeReferenceIndex.swift:117`、`:291`），与扫描路径的顺序不一致 | 内容一致，只差同一指令上 `alloc` / `init` 这类并列引用的先后；现有测试不比这种组合。可以只把类型文档里「答案完全一致」改成「集合一致」 | 宿主或测试开始逐数组比较两条路径的结果 |
| `reader-benchmark` 用 `print` 输出测量结果 | 基准可执行文件，输出是产品结果不是日志，不随库发布 | 它被并进 `swift-section` 或开始输出诊断信息 |

## 修复（2026-11-16 同日）

体检报告写完后，用户批准修第 1–7 条，第 8 条随第 2 条一起修；前八条验证完之后又批准修第 9 条；三条「建议不修」登记为已裁决清单的 A83–A85。分支 `fix/codebase-audit-2026-11-16`，每条都先写复现测试、确认它在修复前失败（第 2、7 条是子进程 SIGTRAP，其余是错误输出），修复后转绿。

- **第 1 条**：`CrossReferenceAnalyzer.ClassArgumentReturn` 把 `objc_opt_class`（返回参数的类）与 `objc_opt_self`、`swift_getInitializedObjCClass`（原样返回参数）分开；`objc_opt_class` 之后，`x0` 只在类方法里或不是方法接收者时保留。函数表新增 `isObjectiveCClassMethod(at:)`。
- **第 2 条**：参数个数守卫收成 `ObjCTypeEncodingParser.methodType(from:matchingArgumentsOf:)`，类成员（`ObjCImportedMemberBuilder`）与协议要求（`ObjCProtocolRequirements`）共用；协议要求也照类成员的做法，扩展编码不合时退回方法表的编码，再不合就不导入。顺带修了原来扩展编码解析失败、退回方法表编码时 `typeEncoding` 仍记扩展编码的不一致。
- **第 3 条**：`ObjCEncodedType.characterString` 带上 `isConst`，`r*` 导入成 `UnsafePointer<Int8>`。
- **第 4 条**：`ObjCProtocolWitnesses` 对本镜像之外的 Swift 类按运行时名取 category 的成员表；`ObjCMembers.table(forObjCClassNamed:)` 的所属名对 Swift 类取 Swift 限定名，strip 过的镜像里 thunk 代码那一档才认得这些成员。**同类问题**：修的时候发现，从文件读时这种 category 指向的是类元数据符号 `_$s…CN` 而不是 `_TtC…`，`ObjCRuntimeNames` 不认，interface 把扩展印成 `extension __C._$s36…`，dump 那份自己的实现只认 `$s` 不认 `_$s`。改为由新的 `NodeTypeNaming.swiftClassNode(fromRuntimeName:)` 统一认 `_TtC`、`$s`、`_$s` 三种写法，`ObjCRuntimeNames`、dump 的 category 行、`swiftClassQualifiedName(fromRuntimeName:)` 都经它。
- **第 5 条**：`SwiftClassWithoutClassObjectIndex.Storage` 把同名的类都登记进限定名表，按名字查遇到同名时返回空。
- **第 6 条**：`ObservableMacroExpansionRecovery.isGeneratedFunction(name:node:)` 连形状一起比：`access`、`withMutation` 要求泛型、第一个参数是 `KeyPath`，`shouldNotifyObservers` 要求泛型、两个参数。
- **第 7 条**：终端大小超出表尾时不再与游标相加，按「没有子节点」处理。
- **第 8 条**：`ObjCProtocolRecord.make` 逐个核对扩展编码与方法表编码是否同一签名（擦掉类名、协议名与 block 签名后比较），有一个对不上就整组不用。
- **第 9 条**（在 Ultra 上验证完前八条之后，用户批准一并修）：C 数组照 ClangImporter 的 `VisitConstantArrayType` 导入——超过 4,096 个元素的不导入（指针指向它时导入成 `OpaquePointer`），只有一个元素的导入成元素本身；嵌套数组展开后超过 65,536 个元素的同样当作导入不了，免得构造出来的编码让构建与打印没有尽头。顺带修了单元素数组印成一元元组的偏差。
- **fixture 的扩充**：`SwiftDeclaredObjCProtocolsFixture` 的 kit 加 `KitWidget`、客户端加 `KitWidgetAdopted` 与对它的 extension；`ClassesWithoutClassObjectsFixture` 的客户端加第二个源文件与两个同名 private 泛型类；`ObservableMacroFixture` 加 `HandwrittenNamesModel`。列举协议、category 与被识别类的既有断言随之补上新成员。
- **验证**：JHs-Mac-Studio-Ultra（macOS 27.2，Xcode 26.6，本地兄弟依赖）上全量 2,916 个测试只红 3 条，都是满负载下的既有偶发（`FileMappingTests`、`SharedCacheTests` 的重叠测试、`BoundedConcurrentMapTests` 的时限），单独重跑全过。JHs-Mac-Studio（10 核）上受影响的 22 个套件 118 个测试全过，并行全量两次卡死在第 10 条。没跑渲染 A/B：改动只影响上面几种具体形态的输出，不是大重构。

## 下一轮

- **轮转候选**（从未深审、按行数与近期改动排）：`SwiftInspection`（6,316）、`SwiftSpecialization`（4,883）、`SwiftLayout`（4,704）、`TypeIndexing`（1,311）、`MachOCaches`（675）、`MachOPointers`（809），合计约 1.9 万行；`MachOSwiftSection`（10,453）这轮只看了 `@BitField` 迁移，留给再下一轮。
- **本轮没覆盖到的**：单元 C 的 finder 没读 `StructuredComment*`、`DeclarationRenderConfiguration`、`InterfaceVersionRendering`、`EvolutionMarking`、`SwiftDeclaredObjCProtocolDumper` 等文件；单元 B 的 `ObjCImporterNaming.swift`（1,030 行）只读了约四分之三；单元 D 没读 `ObjCInterfaceRequest`。下一轮的改动集若碰到它们，优先读。
- 补漏（主线程）重看了 `ObjCImporterNaming` 的下标运算、ObjC interface 会话、符号表并行 demangle 的等待、窗口内新增的布尔配置默认值，没有新发现。
