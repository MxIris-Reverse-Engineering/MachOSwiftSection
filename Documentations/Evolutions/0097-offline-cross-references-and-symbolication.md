# 0097 - 交叉引用与地址符号化扩展到磁盘文件和归档 dyld cache

- **状态**: Implemented
- **作者**: JH
- **创建日期**: 2026-11-18
- **最后更新**: 2026-11-19
- **所属愿景**: [不依赖 IDA 的逆向](../Visions/ReverseEngineeringWithoutIDA.md)（第 1 阶段）
- **关联提案**:
  - [0072 cross-reference-analysis](0072-cross-reference-analysis.md)：进程内的交叉引用分析，本提案在它上面扩展。
  - [0076 objc-runtime-send-entry-points](0076-objc-runtime-send-entry-points.md)：libobjc 的专用发送入口。
  - [0053](0053-shared-cache-infrastructure.md) `SharedCache`：本提案不新增 `SharedCache`，理由同 0072。
  - RuntimeViewer [0056 cross-references](https://github.com/MxIris-Reverse-Engineering/RuntimeViewer/blob/next/Documentations/Evolutions/0056-cross-references.md)：界面里的交叉引用；它暂缓的第 4 步「CLI 与 MCP」由本提案接手。
  - MachOKitExtensions [0002 move-reading-and-resolving-modules](https://github.com/MxIris-Reverse-Engineering/MachOKitExtensions/blob/main/Documentations/Evolutions/0002-move-reading-and-resolving-modules.md) 与 [0003 move-macho-infrastructure-modules](https://github.com/MxIris-Reverse-Engineering/MachOKitExtensions/blob/main/Documentations/Evolutions/0003-move-macho-infrastructure-modules.md)（两份都已 Accepted）：把本库的读取层、`MachOPointers` / `MachOCaches` / `MachODependencies` 与语言无关的 `MachOSymbols` 迁进 MachOKitExtensions 2.0.0。本提案拆出的核心层与 ObjC 层照同样的走法，**之后另写一份迁移提案**搬到 MachOKitExtensions 与 MachOObjCSection（见「提议方案」第 2 节）。
- **实现分支 / PR**: 本库与 RuntimeViewer 都是 `feature/offline-cross-references-and-symbolication`（从各自的 `next` 切出），本地合进各自的 `next`，没开 PR
- **配套文档**: 用法与契约在 [README](../../README.md) 的 `refs` / `symbolicate` 两节、`swift-section` 插件的 [references/cross-references.md](../../AgentPlugins/swift-section/skills/swift-section-cli/references/cross-references.md) 与 RuntimeViewer 的 `Documentations/Guides/CommandLineInterface.md`；实现说明在模块文档 [CrossReferenceAnalysis](../Internal/Modules/CrossReferenceAnalysis.md)、[CrossReferenceCore](../Internal/Modules/CrossReferenceCore.md)、[CrossReferenceObjC](../Internal/Modules/CrossReferenceObjC.md)、[CodeAddressResolution](../Internal/Modules/CodeAddressResolution.md)
- **网页版**: [0097-offline-cross-references-and-symbolication.html](0097-offline-cross-references-and-symbolication.html)

## 摘要

`CrossReferenceAnalysis` 今天只能分析**当前进程**映射进来的镜像，读不了磁盘上的 app、也读不了 `/Volumes/DyldSharedCaches` 下归档的各版本 cache，而且没有命令行入口。本提案做六件事：

1. 把分析器里「直接读进程内存」的地方收进一个读取抽象，新增从 `FullDyldCache` 和一组 `MachOFile` 构造分析器的入口，槽里的值改由 fixup 解码得到；
2. **把交叉引用按层拆成三个模块**：与语言无关的核心 `CrossReferenceCore`（指令扫描、函数表、桩与槽、字符串、符号化）、ObjC 层 `CrossReferenceObjC`（消息发送、类引用、ivar、ObjC 方法名）、Swift 层 `CrossReferenceAnalysis`（Swift 类型、对外的公开 API）。层与层之间经「识别器」扩展点相接，核心不认识任何一种语言；各层能 import 什么由源码扫描测试守住，只许 import 它们将来的落脚处也有的模块。真正搬到 MachOKitExtensions（核心）与 MachOObjCSection（ObjC 层）**另写迁移提案**，在本提案量完吞吐、跑稳之后做；
3. 把 `SwiftThunkAnalysis` 里已经写好的离线桩链与槽解析抽成独立的 `CodeAddressResolution` 模块，两边共用；
4. 补三类引用：经 ivar 偏移变量读写 ObjC ivar、C 字符串字面量、CFString 常量，并给每条引用标上它是怎么到达目标的（直接调用、本镜像桩、stub island、cache 共用桩、GOT 槽……）；
5. 新增地址符号化：任意一个地址，说出它在哪个镜像的哪个函数加多少偏移，或者它是桩、最终跳到谁，或者它是槽、里面装着谁；
6. 新增 `swift-section refs` 与 `swift-section symbolicate` 两个子命令（文本与 JSON 输出），并在 RuntimeViewer 的 CLI 与 MCP 上接出 `callers` / `callees` / `references` / `symbolicate`。

## 动机

完整动机见愿景《[不依赖 IDA 的逆向](../Visions/ReverseEngineeringWithoutIDA.md)》的「现状与代价」。这一步特有的部分：

- **最常卡住的就是这一块。** 逆向 agent 的笔记里约 15 条用「扫 selref / GOT 字节 → 换算子 cache 偏移 → 反汇编 stub island → `a2s` 起名」这条手工链路回答「谁调用了它」，13 条涉及 selref，12 条涉及 GOT（`~/.claude/agent-memory/reverse-explorer/cross-cache-caller-search.md`、全局 `reverse-engineering` skill 的 `references/ipsw-cache-recipes.md`）。现成工具都会静默漏：`ipsw dyld xref` 不跟进 stub island，`dyld_info -imports` 漏掉大部分 bind。2026-10-29 有一次因此判错：`UINSPasteboardWritingItemProvider` 在 27.0 和 27.2 上都有两个调用者，它们经 `__DATA_CONST.__got` 读**本镜像自己**的类对象，`ipsw dyld disass` 只显示 `ldr x0, [x23, #0x590]`，没有类名。
- **分析器已经有了，只是够不着这些目标。** `CrossReferenceAnalyzer` 在进程内 1.6–3.0 秒扫完 macOS 27.2 的整个 cache，认得 27 的 cache 共用 selector 桩与 GOT 桩、stub island 多跳（`Internal/Modules/CrossReferenceAnalysis.md`「吞吐」节）。但它的构造器用 `DyldCacheLoaded.current` 与 `_dyld_get_image_header`，只看得到正在运行的系统；卷上归档的 7 个 macOS 版本（15.5 到 27.2）和 `/Volumes/RE` 下的 app 都够不着。0072 把 `MachOFile` 与 `swift-section` 子命令明确留给了后续提案。
- **RuntimeViewer 只在界面里给出交叉引用。** RuntimeViewer 0056 的第 4 步（CLI 与 MCP）在 2026-10-26 经用户批准拆成暂缓项，说明以后另起提案。全部对话记录里 RuntimeViewer 的 MCP 一次也没被调用过；agent 要查调用者，只能退回 IDA 或 `ipsw`。
- **地址起名是同一个问题的另一面。** `dyld_info -disassemble` 把 macOS 26.7 SwiftUICore 的 2,195 个 `__auth_stubs` 桩标成同一个错名，15.3 万条 `bl` 的目标因此标错（RuntimeViewer 记忆 `dyld-info-mislabels-cache-stubs.md`）；`ipsw dyld a2s` 对 27 的 cache 共用 `objc_msgSend$…` 桩只回 `?`，agent 只能先反汇编桩的前三条，自己算 `adrp x1` 的页加 `add x1` 的偏移，再去读字符串。分析器在扫描时本来就要把每个桩解析到底，把这一步单独开放出来就是符号化。

## 前期调研

### 现状代码怎么走的

以下路径相对于本仓库，读自 `next`（`6e73eeaa`）。

**`CrossReferenceAnalysis` 的公开入口**（`Sources/Analysis/CrossReferenceAnalysis/CrossReferenceAnalyzer.swift`）：

- `public init?()`（`:85`）只扫当前进程，非 arm64 时返回 `nil`；`public let images: [MachOImage]`（`:23`）、`imagePaths`（`:30`）、`imageIndex(forPath:)`、`location(ofRuntimeAddress:)`（`:250`）。
- 函数表：`functions(inImageAt:)`、`function(containing:)`、`functions(containing:)`、`symbolName(at:)`。
- 引用：`references(madeBy:)`、`referenceTable(ofImageAt:)`、`referenceIndex(ofImageAt:)`、`references(to:inImageAt:)`（`:449`，键是 `CodeReferenceTable.Key`）。
- 预筛（`+Prefiltering.swift`、`+Linkage.swift`、`+SwiftTypes.swift`）：`imageIndices(importing:among:)`、`imageIndices(referencingSelector:among:)`、`imageIndices(referencingObjectiveCClassAt:among:)`、`imageIndices(linkingImageAt:among:)`、`imageIndices(referencingSwiftType:among:)` 等。
- 宿主内存管理：`prepareNames(inImageAt:)`、`preparePrefilters()`、`releaseImageData(exceptForImagesAt:)`、`approximateByteCount(ofImageDataAt:)`。

**模型**（`Models/`）：`CodeLocation`（镜像下标 + 未滑动地址）；`CodeReference`（`function`、`instructionAddress`、`kind: call | tailCall | reference`、`target`、`isRuntimeHelperCall`，公开 memberwise 初始化方法在 `CodeReference.swift:104`）；`CodeReferenceTarget` 有 `function`、`importedSymbol`、`messageSend(selector:receiver:)`、`superMessageSend`、`swiftType`、`swiftTypeName`、`objectiveCClass`、`indirect`、`unrecognized` 九种；`CodeReferenceTable.Key` 有 `function`、`selector`、`importedSymbol`、`objectiveCClass`、`swiftTypeDescriptor` 等。

**分析器只能在进程内成立的依赖**——本提案要拆掉的就是这些：

1. 构造器用 `DyldCacheLoaded.current` + `cache.slide`、`_dyld_image_count`、`_dyld_get_image_header`、`dladdr`（`CrossReferenceAnalyzer.swift:89-120`）。
2. 未滑动地址靠 `image.vmaddrSlide` 换成运行时地址。
3. 直接按地址读进程内存：`UnsafeRawPointer(bitPattern:)` 在 `ReferenceScanner.swift` 7 处、`ObjectiveCClassIndex.swift` 5 处、`SwiftTypeIndex.swift` 4 处、`ImageFunctionTable.swift` 2 处、`+SwiftTypes.swift` 2 处、`+Prefiltering.swift` 1 处、`ImageFallbackNames.swift` 1 处，共 22 处。
4. **GOT 槽依赖 dyld 已经绑定好的值**：模块文档写明「GOT 槽在进程内已经绑定，读出指针、去掉指针认证位就是目标」，懒绑定场景由 `LazyBindingTests` 守着。
5. 去掉指针认证位用 `StoredPointer` 里的 `InProcessContext.addressMask`。
6. 函数起点依赖 `MachOImage.FunctionStarts` 的偏移语义（模块文档说进程内给的已是绝对地址，与 MachOKit 的注释不符）。
7. 类名经 MachOObjCSection 读 `class_rw_t`（类已被运行时实现时）。

**已能认出的引用形态**（`Scanning/ReferenceScanner.swift`、`Scanning/RegisterFile.swift`，解码器是 `Sources/Support/ARM64InstructionDecoding/ARM64InstructionWord.swift`）：直接 `bl` / `b` 与尾调用、跳转表；镜像自带的 `__objc_stubs` 与 `__stubs` / `__auth_stubs`（读不出时由 `ARM64Trampoline` 补读 ld64 改写过的 `nop; ldr x16, <slot>; br x16`）；27 的 cache 共用 selector 桩（`adrp x1; add x1; b <objc_msgSend 副本>`）与 GOT 桩（`adrp x17; add x17; ldr x16, [x17]; braa`）；stub island 多跳；cache 内经典发送（`x1` 由 `adrp` / `add` 算出可打印的字符串地址）；GOT / selref / classref / superref 的 `adrp` + `ldr` 与字面量 `ldr`；`adrp` + `add` / `adr` 算出类对象、元数据或访问器；Swift 类型访问器与 `__swift_instantiateConcreteTypeFromMangledName*`；按 `autda` / `movk` 鉴别常量区分 vtable、PWT、VWT 的间接调用。

**解码器的覆盖**：`ARM64InstructionWord.load(_:)`（`:88`）只认 64 位的 `ldr` / `ldur` / 前变址 `ldr!` / `ldraa` / `ldrab`；**不认 `ldrsw` 与 32 位 `ldr w`**，而 arm64 上读 ObjC ivar 偏移变量正是 `adrp x8, _OBJC_IVAR_$_C.ivar@PAGE; ldrsw x8, [x8, …@PAGEOFF]`。

**性能**（模块文档「吞吐」节，macOS 27.2，28 核）：建分析器 0.06 秒（4,114 个镜像）；每个镜像都建整表 3.0 秒、1.26 亿条引用；查 `init` 的调用者预筛出 2,759 个镜像，0.05 + 1.8 秒；查 `makeKeyAndOrderFront:` 0.06 + 0.33 秒；手写解码器单线程解码 AppKit 约 187 MiB/s，比 Capstone 快 25–50 倍。

**本库已有的离线解析**（`Sources/Analysis/SwiftThunkAnalysis/Resolution/`）：

- `MachOThunkEnvironment`（`package final class`，551 行）已经在 `MachOFile` 上做了这几件事：`callee(at:)` 解析桩、ld64 跳板与 stub island（可多跳，`hopping(from:to:islandHops:)`）；`callee(boundInSlotAt:)` 解析 GOT 槽——独立文件经 `resolveBind(fileOffset:)` 得 bind 名，cache 里是 rebase 到别的镜像，再按地址找符号；`pointer(at:)`、`slotSymbolName(at:)`；`foreignCallee` 与 `dependencyCallee` 跨镜像找导出。
- `CacheImageResolver`（同文件 `:466`）用 `imageInfos` 按加载地址二分，回答「这个地址在 cache 的哪个镜像」，并按路径懒打开 `MachOFile`。
- `ThunkAddressSpace`（`ThunkAddressSpace.swift`）定下 cache 镜像的偏移约定：**未滑动地址 − `sharedRegionStart`**，并实测记下三种看似可用、实际静默出错的换算（`segment.fileOffset`、`MachOFile.fileOffset(of:)`、`FullDyldCache.address(of:)`，在 macOS 26 的 SwiftUI 上分别偏 0x88000、另一套记账、再偏 16384）。

**读取层**：`Sources/MachO/MachOReading` 已有 `ReadingContext` 协议（`associatedtype Runtime`、`associatedtype Address`、`readElement(at:)`、`readElements(at:numberOfElements:)`、`readWrapperElement(at:)`）及 `MachOContext` / `InProcessContext` 两种实现。MachOKitExtensions 的草案 `move-reading-and-resolving-modules`（In Progress，四个仓库同名分支）正把它原名迁进 MachOKitExtensions 2.0.0，随本库 0.25.0 一起发。

**`swift-section` CLI**：根命令 `Sources/Executables/swift-section/SwiftSectionCommand.swift`；输入选项组 `Models/MachOOptionGroup.swift`（`filePath`、`-p/--cache-image-path`、`-n/--cache-image-name`、`--dyld-shared-cache`、`--uses-system-dyld-shared-cache`、`-a/--architecture`、`--dependency-search-path`），经 `Sources/Commands/SwiftSectionKit/Inputs/MachOSource.swift` 只产出**单个** `MachOFile`。`AGENTS.md` 的 CLI 一节规定：子命令逻辑写进 `SwiftSectionKit` 的 Request 类型，可执行层只管 flag、`validate()`、`makeRequest()` 与错误翻译；输出一律经 `StandardStreamOutput`；CLI 改动要同批更新 `AgentPlugins/swift-section/skills/swift-section-cli/`。目前只有 `evolution --json` 与 snapshot 有 JSON，没有统一约定。`swift-section` target 现在不依赖 `CrossReferenceAnalysis`（`Package.swift:920-941`）。

### 按层拆分的依据

**今天的模块把三种语言层的逻辑混在一起。** `CrossReferenceAnalysis` 有 21 个文件、4,511 行，依赖 MachOKit、MachOObjCSection、Demangling、`ARM64InstructionDecoding`、`MachOFoundation`、`MachOSwiftSection`、`SwiftInspection`（`Package.swift:640-655`）。按 import 看，ObjC 与 Swift 的部分集中在几个文件：`ObjectiveCClassIndex.swift`（`@_spi(Core) import MachOObjCSection`，读 `ObjCClass64`）、`ImageFallbackNames.swift`（ObjC 方法列表 + `SymbolicDemangler`）、`SwiftTypeIndex.swift` 与 `CrossReferenceAnalyzer+SwiftTypes.swift`（Swift 描述符、`SymbolicDemangler`、Demangling）。但扫描器本身不分层，ObjC 与 Swift 的识别在五个地方插进同一趟循环（`Scanning/ReferenceScanner.swift`）：

1. **进入函数**：ObjC 方法在 `x0` 上打「方法接收者」标记（`:117-121`），这是 `RegisterFile` 里唯一与语言有关的状态（`RegisterFile.swift:17` 的 `methodReceiver`）。
2. **解析调用目标**（`computeResolution`，`:690-715`；`functionTarget`，`:751-769`）：`__objc_stubs` 的 selector、libobjc 专用入口（`objc_alloc_init` 等）、`objc_msgSend` / `objc_msgSendSuper2` 的位置、Swift 元数据访问器与 mangled name 实例化辅助函数。这些位置表建在分析器上（`CrossReferenceAnalyzer.swift:51-66`）。
3. **调用点**（`reference(to:at:in:kind:isObjectiveCMethod:)`，`:303-345`）：读 `x1` 的 selector（`:585`）、`x0` 的接收者（`:363`）、`__objc_superrefs` 给出的父类（`:235`、`:564`）；调用之后 `x0` 是否保留由 `objc_opt_self` / `objc_opt_class` / `swift_getInitializedObjCClass` 决定（`:143-152`，名单在 `CrossReferenceAnalyzer.swift:224-226`）。
4. **算出地址**与 5. **读槽**（`:401-473`）：认 ObjC 类对象、Swift 值类型元数据（kind 0x200–0x204）与元数据访问器。

其余是通用的：指令解码、寄存器跟踪、分支间状态的传递、本镜像桩与 GOT、stub island、跨镜像函数、间接调用的指针认证常量。还有几处混用：`RuntimeHelperNames` 同时列 `_swift_retain…` 与 `_objc_retain…`；`ImageFunctionTable`（`:35-46`）同时存 `__objc_stubs`、`__objc_selrefs`、`__objc_superrefs`、classref 与 GOT 的范围；cache 共用 selector 桩由 `ARM64Trampoline.selectorStub` 认出（`:728`），形状是通用的（`adrp x1; add x1; b <目标>`），含义（selector）是 ObjC 的。`IndirectCallEvidence.Table` 列着 vtable / PWT / VWT，但扫描器只写过 `.none`（`:355`），没有别处赋值。

公开模型也把语言写死在封闭枚举里：`CodeReferenceTarget` 九个 case 里五个属于 ObjC 或 Swift；`CodeReferenceTable.Key` 有 `selector`、`objectiveCClass`、`swiftTypeDescriptor`；`CodeFunction.Name` 有 `objectiveCMethod`、`swiftMetadata`；另有 `ReceiverClassHint`、`SwiftTypeName`。

**三层将来的落脚处。**

- **MachOKitExtensions**：两份迁移提案都已 Accepted。落地后它有读取层、`MachOPointers`、`MachOCaches`、`MachODependencies`、`MachOBase` / `MachOFoundation`，以及语言无关的 `MachOSymbols`（带只收 C、C++、ObjC 名字的 `SymbolIndexStore`）——核心层要的依赖届时都在那里。它的 README 承诺支持 Linux，并因此去掉了 FrameworkToolbox；核心层的锁都是 `NSLock`，不用 FrameworkToolbox，但进程内构造器用的 `_dyld_*`、`dladdr`、`DyldCacheLoaded.current`（`CrossReferenceAnalyzer.swift:90-117`）只在 Darwin 上有。
- **MachOObjCSection**：已依赖 MachOKitExtensions；模块按 `ObjC` 前缀命名（`ObjCMetadataSource`、`ObjCIndexing`、`ObjCInterface` 等）。ObjC 层现在经 `@_spi(Core)` 读的类结构，搬进去后就是包内访问。
- **本库**：Swift 层与 `swift-section` 的两个子命令。

**模块名与版本。** SwiftPM 不允许依赖图里出现同名模块，不论那个模块是不是 product、有没有被用到（MachOKitExtensions 迁移提案的调研）。本库对 MachOKitExtensions 的要求是 `from: "1.3.2"`（`Package.swift:174`，2.0.0 之后改成 `from: "2.0.0"`，即 `< 3.0.0`），对 MachOObjCSection 是 `"0.8.206" ..< "0.9.0"`（`Package.swift:217`）。所以本库发布过的版本里只要有一个模块，和 MachOKitExtensions 2.x 之后新增的模块同名，旧版本本库与新版本 MachOKitExtensions 就解析不到一起。另外，基础模块迁移提案定下：迁完之后本库里带 `MachO` 前缀的只剩 ABI 模型。本提案原先把抽出的模块叫 `MachOAddressResolution`、放在 `Sources/MachO/`，两条都会撞上。

**目前没有第二个使用方。** 在 REAgent、MachOKitUI、swift-decompiler 的源码里不分大小写搜 `crossreference`、`xref`，没有结果（REAgent 查调用者走 IDA）；需要交叉引用而又不想带上 Swift 栈的使用方，现在还只是预期。

### 上游或依赖是否已具备能力

- **MachOKit**（fork，本库要求 `from: "0.55.102"`）：`stubs(in:)` / `objcStubs(in:)`（`LoadCommand/Model/Section+Stubs.swift`，`Stub.Branch` 为 `.viaSlot` / `.direct` / `.unknown`，带 `indirectSymbolIndex`）；`MachOFile.resolveBind(at:)`（`MachOFile.swift:927`）、`resolveRebase(at:)`（`:879`）、`DyldCache.resolveRebase(at:)`；`MachOFile.functionStarts`（`:481`）；`closestSymbol(at:…)`（`MachORepresentable.swift:396-745`）；`DyldCache.symbolCache` 读 `.symbols` 文件。**没有** stub island 或 cache 共用桩的 API，**没有**「地址 → 所属镜像」的 API，**没有**共享 selector 哈希表的解析；selref / classref / protoref 没有专门的访问器。读文件经 p-x9 的 `swift-fileio`（内存映射）。
- **MachOKitExtensions**（`from: "1.3.2"`）：`MachOFile.resolveBind(fileOffset:)` 覆盖 chained fixup 与旧式 dyld info，但 **`isLoadedFromDyldCache` 时直接返回 `nil`**；`resolveSelfBind(fileOffset:)` 处理 `BIND_SPECIAL_DYLIB_SELF`；`resolveRebase(fileOffset:)` 对 cache 镜像走 cache；`MachOFile.cached` 的 `fixupPointer(at:)`；`DyldCacheSubCacheTable` 子 cache 地址二分表。

### 前人怎么做的

- **ipsw**：`dyld xref` 不跟进 stub island；`dyld a2s` 对 27 的 cache 共用 `objc_msgSend$` 桩只回 `?`；没有 `.a2s` 符号缓存时 `disass` 会卡在解析符号上 12 分钟、占 23 GB 内存（逆向 agent 笔记）。
- **Apple `dyld_info`**：只读本机正在运行的 cache；`-disassemble` 给 cache 桩标错名；`-imports` 漏 bind；`-objc` 对 cache 镜像静默无输出、退出码 0。
- **IDA**：一个库只装得下几个镜像，跨镜像看不到；单镜像库的导入桩借用别的局部符号名；查调用者要两跳（槽 → `j__<符号>` 桩 → 调用者）。
- **Binary Ninja**（开源部分取自 `Vector35/binaryninja-api` 的 `dev` 分支；用户装的是 6.0.10601 Personal）：
  - 整个 cache 放进一个地址空间，跨镜像引用就是普通地址；全 cache 的符号单独存成 `CacheSymbol`，打开 cache 时读每个镜像的导出 trie 建「地址 → 符号」表，LC_SYMTAB 与 `.symbols` 本地符号等镜像被加载时才读（`view/sharedcache/core/SharedCache.cpp:305`、`core/MachOProcessor.cpp:88-134`）。
  - stub island 当作单独的区域；桩的判定看节名后缀（`__stubs`、`__auth_stubs`、`__objc_stubs`、`_branch_islands`）；解析时在 MLIL 的 SSA 形式上沿跳转目标往回找 `LOAD(CONST_PTR)`，命名为 `j_<目标符号>`（`view/sharedcache/workflow/SharedCacheWorkflow.cpp`）。
  - ObjC 调用点的 selector 取 `x1` 的 SSA 常量值；`objc_msgSend$sel` 桩不靠符号表，「不超过 32 字节、一个基本块、尾调用 msgSend」就当它是，并用同样的 `x1` 追踪取 selector（`plugins/workflow_objc/src/activities/` 下的 `objc_msg_send_calls.rs`、`name_stubs.rs`）。
  - selector 到实现不改写调用，而是从 selector 字符串和 selref 槽各加一条**数据引用**指向 IMP，查询时两跳；改写成直接调用的选项默认关，源码 TODO 承认它总取第一个实现、需要接收者类型才做得好（`objectivec/objc.cpp:1182-1184`、`rewrite_to_direct_call.rs`）。
  - 引用分代码、数据、类型、变量四类，另有类型字段引用（`get_code_refs_for_type_field`）；6.0 新增 `get_derived_string_code_refs`（派生字符串，例如 CFString 的代码引用）。数据流只在函数内做（`docs/dev/concepts.md:160`）。
  - 界面里引用列表有上限（`ui.maxXrefItems = 1000`），超出时计数后面带 `+`；可按方向、种类过滤。
  - 6.0 自带 MCP 服务器：GUI 内的 HTTP 版随所有 GUI 版本提供（含 Personal），能查交叉引用、调用者、反汇编、IL 与伪代码；无界面的 `binaryninja_mcp` 只随 Commercial / Ultimate。地址在输出里一律写成十六进制字符串，「so clients do not lose precision when handling 64-bit addresses」；列表结果带 `count`、`total`、`nextOffset`、`truncated`（应用内 `docs/guide/mcp.html`）。

### 验证过什么

- 已验证（引自现有文档与记忆）：进程内分析器的吞吐数字；`ThunkAddressSpace` 的地址约定与三种错误换算（macOS 26 SwiftUI）；`UINSPasteboardWritingItemProvider` 的两个经 GOT 的调用者（27.0、27.2）；`dyld_info` 的 2,195 个错名桩（26.7 SwiftUICore）。
- IDA 与 Binary Ninja 的交叉引用实测（2026-11-18，Finder 26.5.2 与 ControlCenter 26.7，详见愿景「我们选的方向」第 1 条）：代码引用召回 IDA 一次查询 97.0%、两跳 99.4%，Binary Ninja 经 MCP 67.6%。三处双方的盲点直接变成本提案的测试用例：恰好页对齐的类对象（`adrp; add #0`，IDA 漏）、Swift 大字符串的 `adrp; add; sub #0x20`（Binary Ninja 漏）、`retab` 之后没建函数的异常清理代码（Binary Ninja 漏）。
- 卷上有 cache 文件的版本：macOS 15.5、26.0（单文件）；26.5.2、26.6.2、26.7（12 个子文件）；27.0（79 个）、27.2（81 个）。本机运行 27.2。
- **推测，第 1、4 步先实测**：
  - 离线模式的吞吐。cache 在外置卷上、冷读几个 GB 的映射文件，预计比进程内慢，慢多少不知道。
  - 文件模式下能否拿到 `__text` 的连续只读字节（`swift-fileio` 的映射能否按区间给出指针），拿不到就按镜像把 `__text` 读进一块缓冲区。
  - `MachOFile.functionStarts` 在 cache 镜像上的偏移语义。
  - macOS 27 的 cache **文件**里各镜像的 `__objc_stubs` 是否也是 0 大小（文档只说进程内为 0）。

## 提议方案

### 1. 读取抽象：`CrossReferenceMemory`

分析器里所有「按地址读」都改走一个 package 级协议 `CrossReferenceMemory`，它只回答分析器真正问的几个问题：

- 某个镜像某个区间的**连续只读字节**（扫描热循环用，循环本身不变，仍对一段缓冲区逐条解码）；
- 某个**槽**里装的是什么（目标地址，或导入符号名）；
- 某个地址处的 C 字符串；
- 去掉指针认证位的掩码。

两种实现：

- `InProcessCrossReferenceMemory`：今天的行为原样搬进来——读 dyld 已绑定的值、按 `vmaddrSlide` 换算。
- `FileCrossReferenceMemory`：基于 `FullDyldCache` 或一组 `MachOFile`。代码字节来自映射的文件；槽的内容由 fixup 解码得到——cache 镜像里 GOT 是 rebase（指向别的镜像或本镜像的类对象），独立文件里是 bind、self-bind 或 rebase。地址约定沿用 `ThunkAddressSpace`：未滑动地址 − `sharedRegionStart`。

协议选「分析器专用的小协议」而不是直接用 `ReadingContext`：`ReadingContext` 回答「按类型读一个元素」，分析器要的是「槽里装着谁」——在进程内是读已绑定的值，在文件里是解 fixup，这层差别正是两种模式唯一的本质区别。`FileCrossReferenceMemory` 内部仍用 `ReadingContext` 读元素。

### 2. 按层拆成三个模块

交叉引用拆成三个模块，依赖从上到下：

| 模块（本库里的名字） | 管什么 | 将来的落脚处与名字 |
|---|---|---|
| `CrossReferenceCore` | 镜像表与读取抽象（进程内、文件两种）、函数表（起点、符号与导出名、data in code）、本镜像桩与 GOT、stub island、指令扫描与寄存器跟踪、跳板设定的寄存器常量、间接调用的指针认证常量、C 字符串与 CFString、链接关系与导入名预筛、符号化的通用部分、识别器扩展点 | MachOKitExtensions，`MachOCodeReferences` |
| `CrossReferenceObjC` | `objc_msgSend` 系列与 libobjc 专用入口、`__objc_stubs` 与 cache 共用 selector 桩的含义、`x1` 的 selector 与 `x0` 的接收者、classref / superref / 类对象、ivar 偏移变量、ObjC 方法列表给出的回退名、selector 与类的预筛、`objc_*` 运行时辅助函数 | MachOObjCSection，`ObjCCodeReferences` |
| `CrossReferenceAnalysis`（原模块） | Swift 元数据访问器、值类型元数据、mangled name 实例化、`SymbolicDemangler` 起名、Swift 类型预筛、`swift_*` 运行时辅助函数；把三层拼成对外的 `CrossReferenceAnalyzer`，持有全部公开模型 | 留在本库 |

`CodeAddressResolution`（第 3 节）在核心层之下，将来随核心一起迁到 MachOKitExtensions，改名 `MachOAddressResolution`。

**扩展点：识别器。** 每个语言层有一个识别器（每个分析器一个，建分析器时读一次自己要的运行时符号，按镜像记住自己的索引），它为每次扫描造一个会话；核心层定义会话协议 `CodeReferenceRecognitionSession`（单线程，持有这次扫描的记忆化与当前函数的状态）。核心的扫描循环只在「前期调研 · 按层拆分的依据」列出的五个时机问识别器：进入函数、解析不认识的调用目标、调用点、算出地址、读槽。识别器按顺序排成一列，核心逐个问，第一个认领的为准；新增一种语言的识别只是多一个识别器，核心不改。识别器产出的引用不经核心转手：各层定义自己的记录协议（`CodeReferenceRecording`、`ObjCCodeReferenceRecording`、`SwiftCodeReferenceRecording`），顶层实现全部三个，直接造出公开的 `CodeReference`。细节见「详细设计」。

**公开模型第一步全部留在顶层。** `CodeReferenceTarget`、`CodeReferenceTable`、`CodeReferenceIndex`、`CodeFunction` 都还在 `CrossReferenceAnalysis`；纯数据、不含语言的 `CodeLocation` 下移到核心层，`ReceiverClassHint` 下移到 ObjC 层，顶层 `@_exported import` 两个下层模块，RuntimeViewer 的 `import CrossReferenceAnalysis` 照旧看得到它们。两个下层模块这一步不做 library product，不对外承诺 API。下层模块对外该长什么样（例如没有 Swift 层时目标用什么类型表示），等迁移提案时有了具体的使用方再定。

**边界由测试守住。** 源码扫描测试逐层检查 import：核心层只许 import 将来 MachOKitExtensions 里也有的模块（MachOKit、MachOKitExtensions、读取层与基础模块迁移提案搬过去的那些、`CodeAddressResolution`、`ARM64InstructionDecoding`、Foundation）；ObjC 层在此之上多一个 MachOObjCSection；两层都不许出现 `MachOSwiftSection`、`SwiftInspection`、Demangling。核心层的源码里还不许出现 `objc_` 与 `swift_` 开头的符号名字面量——运行时的名单属于各自的层。

**本库里的名字刻意不同于落脚处的名字。** 理由见「前期调研 · 按层拆分的依据」的「模块名与版本」：本库只要发布过一个与 MachOKitExtensions 2.x 新模块同名的模块，旧版本本库与新版本 MachOKitExtensions 就解析不到一起；而且基础模块迁移之后，本库带 `MachO` 前缀的模块只留 ABI 模型。搬的时候改名，只动本库内部的 import——两个下层模块不是 product，没有外部使用方。

**为什么分两步。** 本提案还有四项「先实测」的未知（离线吞吐、`__text` 能否连续读、`functionStarts` 在 cache 镜像上的语义、27 的 cache 文件里 `__objc_stubs` 的大小）；识别器的接口也要在扫描热路径上量过才算定下来。在一个仓库里改这些只要改一处；跨三个仓库时核心每改一次都要按 MachOKitExtensions → MachOObjCSection → 本库的顺序发版。拆分在本库里做完、量过、跑稳，迁移就只剩机械地搬文件。

### 3. 抽出 `CodeAddressResolution`

把 `SwiftThunkAnalysis` 里与 Swift thunk 无关的离线解析抽成新的 package 模块 `Sources/Analysis/CodeAddressResolution`，`SwiftThunkAnalysis` 与 `CrossReferenceCore` 共用：

- `ImageAddressSpace`：原 `ThunkAddressSpace`，地址约定与它的长注释一起搬。
- `CacheImageLocator`：原 `CacheImageResolver`，「地址 → cache 镜像」与按路径懒打开。
- `StubChainResolver`：桩、ld64 跳板、stub island 多跳、27 的 cache 共用 selector 桩与 GOT 桩 → 最终目标（函数地址或导入符号名），连同跳板一路设定的寄存器常量（cache 共用 selector 桩在 `x1` 里放的地址），并记下经过的每一跳。常量是什么意思（selector）由 ObjC 层解释，这个模块不认识 selector。
- `SlotResolver`：任意指针槽 → 里面装着谁（rebase 的目标地址，或 bind 的符号名）。GOT、auth GOT 与 ObjC 的 selref / classref / superref / protoref、ivar 偏移变量共用它；哪个节算哪种槽由上层说。

这个模块只依赖 MachOKit、MachOKitExtensions 与读取层，不碰 Swift 与 ObjC 元数据，将来随核心层一起迁进 MachOKitExtensions（见第 2 节）。

### 4. 文件模式的分析器

```swift
let cache = try FullDyldCache(url: URL(filePath: "/Volumes/DyldSharedCaches/macOS/27.2/dyld_shared_cache_arm64e"))
let analyzer = try CrossReferenceAnalyzer(dyldCache: cache)
```

镜像表来自 cache 头的 `imageInfos`；`imagePaths`、`imageIndex(forPath:)`、函数表、预筛、`referenceTable` 等全部照旧可用。`location(ofRuntimeAddress:)` 在 cache 文件模式下接受的就是未滑动地址；一组独立文件里各文件按 dyld 的做法错开（与已放下的重叠就滑到其后的下一个 MB 边界），那时它接受的是错开后的地址。`images: [MachOImage]` 在文件模式下为空，只在文档注释里写明，不标 deprecated（见决策日志）；`imageCount` 在两种模式下都给镜像数。

实现（第 4 步）：每个镜像由核心层的 `CodeImage` 描述——`reader` 是 `MachOImage` 或 `MachOFile`，两种读取器的差别（slide、读取器 API 给出的 offset 落在哪个地址）只在构造它的地方定一次；`__LINKEDIT` 里的表（符号表、间接符号、函数起点、data in code、导出树）一律按「`__LINKEDIT` 的地址 + 表的偏移 − 段的文件偏移」经读取层读（`ImageLinkEdit`），进程内与文件里是同一个算法。ObjC 层与 Swift 层用到 MachOObjCSection / MachOSwiftSection 各读取器一套的 API 时，经 `asMachOImage` / `asMachOFile` 或 `MachOSwiftSectionRepresentableWithCache` 打开。文件读取层 `FileCrossReferenceMemory` 是个值，以 `unowned(unsafe)` 引用由镜像集持有的存储：经 existential 的每次读都复制一次读取层，类或持有引用的值每次复制都要计数，整 cache 建表因此慢过 6 倍。cache 的槽按 mapping 预取的 slide info 解：v5（macOS 14 / iOS 17 起的 arm64e cache）在读取层里直接解，其余交给 MachOKit。

### 5. 新的引用种类与引用路线

各种引用落在哪一层写在每条末尾。

- **ObjC ivar**：`adrp` + `ldrsw`（或 32 位 `ldr`）读 `__objc_ivar` 里的偏移变量 → `.objectiveCInstanceVariable(className:name:)`。解码器补 `ldrsw` 与 32 位 `ldr`。名字取自偏移变量的符号 `_OBJC_IVAR_$_<类>.<ivar>`；没有符号时从类的 ivar 列表反查（ivar 记录里的 `offset` 字段指向这个槽）。ObjC 层，经「读槽」时机。
- **C 字符串字面量**：`adrp` + `add` 落进 `__cstring` / `__objc_methname` / `__oslogstring`，且没被当作 selector 用掉 → `.cString(String)`。覆盖 `objc_getClass("…")`、`sel_registerName`、`dlsym` 一类调用。核心层；识别器按顺序问，ObjC 层先认领当作 selector 的那些。Swift 大字符串字面量的写法是 `adrp; add; sub #0x20`（对象里存的是「地址 − 0x20」），也要认成指向那段字符的引用——Binary Ninja 在实测里正是漏在这里。这个写法是 Swift 的约定，由 Swift 层的识别器认出，记成同一种 C 字符串引用。
- **CFString 常量**：`adrp` + `add` 落进 `__cfstring` → 解出字符串指针 → `.constantString(String)`。覆盖 `NSSelectorFromString(@"…")`、`NSUserDefaults` 键一类用法。核心层：`__cfstring` 的结构是 CoreFoundation 的链接约定，不依赖 ObjC 运行时。
- 两种字符串引用默认**不记录**：它们数量大，RuntimeViewer 常驻的索引不需要。构造分析器时用 `recordingStringReferences: true` 打开，`swift-section refs --string` 会自动打开。
- **对其他镜像符号的数据引用**（第 4 步核对时补进来）：只分析一个 app 而不带它链接的库时，经 GOT 槽读别的镜像的类（`adrp; ldr x0, [_OBJC_CLASS_$_CALayer@GOT]`）、ivar 或数据，槽里是 bind，读出的是导入名而不是地址，现在什么都不记——进程内槽里是地址，会记成类引用。改为记一条指向导入符号的 `.reference`，ObjC 层再把 `_OBJC_CLASS_$_<类>` 认成按名字的类引用。核心层（读槽时机拿到导入名）加 ObjC 层。
- **引用路线**：`CodeReference` 新增 `route`，说明引用是怎么到达目标的。照 Binary Ninja 的「引用按来源种类建模」，但只在代码引用上加一个字段，不引入数据引用（见非目标）。

### 6. 地址符号化

```swift
let symbolication = analyzer.symbolication(of: 0x1_9012_3450)
// symbolication.meaning == .stub(hops: [0x1_9012_3450], target: .messageSend(selector: "setFrame:", receiver: .unknown))
```

回答「这个地址是什么」，按顺序判断：在某个函数体里（函数起点、名字、偏移；名字来自符号、`ImageFallbackNames` 的回退名）；是桩或 stub island 的跳板（每一跳与最终目标）；是一个槽（槽的种类与里面装的目标）；是 C 字符串或 CFString（内容）；以上都不是时给最近的前一个符号加偏移；不在任何映射里时如实说没有映射。判断顺序与函数、桩、槽、字符串的结构由核心层给出；桩的最终目标与槽里的东西是什么（selector、类、Swift 类型）、没有符号的函数叫什么，由 ObjC 层与 Swift 层经同一列识别器补上。

### 7. `swift-section refs` 与 `swift-section symbolicate`

```text
swift-section refs --selector makeKeyAndOrderFront: --dyld-shared-cache /Volumes/DyldSharedCaches/macOS/27.2/dyld_shared_cache_arm64e
swift-section refs --class UINSPasteboardWritingItemProvider --uses-system-dyld-shared-cache --json
swift-section refs --function 0x1880a1000 --callees --uses-system-dyld-shared-cache
swift-section refs --string NSWindowDidBecomeKeyNotification --in-image AppKit /path/to/Foo.app/Contents/MacOS/Foo
swift-section symbolicate 0x19012345 0x1e1226590 --dyld-shared-cache /Volumes/DyldSharedCaches/macOS/27.0/dyld_shared_cache_arm64e
```

- 查询（恰好一个）：`--selector`、`--symbol`（C 符号、Swift 修饰名、`_OBJC_CLASS_$_…`）、`--class`、`--function <地址>`（以它开头或包含它的函数的调用者；加 `--callees` 改列它引用了什么）、`--ivar <类>.<ivar>`、`--string <文本>`。
- 输入：一个或多个独立 Mach-O 文件，或 `--dyld-shared-cache <路径>`，或 `--uses-system-dyld-shared-cache`；`-a/--architecture`。`--in-image` 可重复，限定扫描哪些镜像。
- 输出：文本每条引用一行——镜像短名、所在函数名加偏移、调用点地址、引用种类与路线；`--json` 输出一个 JSON 文档，地址一律写成十六进制字符串（照 Binary Ninja MCP 的理由：避免客户端丢失 64 位精度）。
- `--limit <n>` 截断时如实标出 `isTruncated`。

### 8. RuntimeViewer：CLI 与 MCP

按 0056 §8 原定的设计实现它暂缓的第 4 步，并加上符号化：

- CLI 子命令 `callers`、`callees`、`references`、`symbolicate`；目标写法照 0056：`-[类 sel]`、Swift 名、符号名，或 `0x…` 加 `--image`；选项 `--selector`、`--scope image|indexed`、`--receiver`、`--include-runtime`、`--limit`。CLI 协议版本 `CommandLineProtocol.version` 由 2 升到 3。
- MCP 工具 `Callers`、`Callees`、`TypeReferences`、`Symbolicate`，`@MCPTool(hints: [.readOnly])`，照现有工具带 `windowIdentifier`；每次最多等 30 秒，`isComplete == false` 时返回部分结果。
- 只覆盖活的引擎（本机、Catalyst、注入的进程）；文件引擎见非目标。

### 非目标

- **把核心层与 ObjC 层真正迁出本库**，以及迁出后两个下层模块对外的公开模型：另写迁移提案（见第 2 节）。那份提案要定的事先记在这里——下层的引用目标在没有 Swift 层时用什么类型表示；`ARM64InstructionDecoding` 是否一起迁、迁过去叫什么；`IndirectCallEvidence.Table` 里 vtable / PWT / VWT 这些 Swift 的叫法留在核心还是改由 Swift 层分类；进程内构造器在 MachOKitExtensions 承诺的 Linux 上怎么条件编译；MachOObjCSection 发 0.9.0 时怎样与本库的版本要求衔接。
- **落盘索引**：沿用 0072 与 RuntimeViewer 0056 的决定。第 4 步实测离线吞吐，结果写进模块文档，是否需要持久化由愿景的后续阶段决定。
- **数据引用**（方法表条目 → IMP、CFString → 字符串这类「数据 → 地址」）与其余数据解码（KeyPath、ObjC 字面量、Swift 字符串）：愿景第 3 阶段。
- **带注解的反汇编、函数清单命令**：愿景第 2 阶段。
- **跨基本块的常量追踪、调用点常量参数普查**：愿景第 4 阶段。
- **接收者类型推断、Swift 字段级引用**。
- **x86_64**。
- 0072「后续」里列的其余项：协议见证与 override 的起名、`objc_getClass("…")` 解析成类引用（本提案只把它记成 C 字符串引用）、Swift 的 super 发送、协议类型引用。
- **RuntimeViewer**：CLI 直接读文件引擎、文件引擎上的交叉引用（RuntimeViewer「暂缓的后续项」里的另一条）、MCP 无头化（RuntimeViewer 愿景《无头 RuntimeViewer》的「之后可以接」）。
- **idax 建库时写入桩名与 Swift 函数名**：IDA 已降为后备。

## 改动地图

步骤号对应「落地步骤」。第 2 步把文件按层搬家；之后各行的路径写的是搬家后的位置（核心层 `Sources/Analysis/CrossReferenceCore/`，ObjC 层 `Sources/Analysis/CrossReferenceObjC/`，Swift 层仍是 `Sources/Analysis/CrossReferenceAnalysis/`）。

| 文件 / 类型 | 动作 | 改什么 | 为什么 | 步骤 |
|---|---|---|---|---|
| `Sources/Analysis/CrossReferenceAnalysis/Memory/CrossReferenceMemory.swift` · `CrossReferenceMemory` | 新增 | package 协议：区间字节、槽内容、C 字符串、指针掩码；第 2 步随核心层搬到 `CrossReferenceCore/Memory/` | 两种模式唯一的本质差别收在这里 | 1、2 |
| `…/Memory/InProcessCrossReferenceMemory.swift` · `InProcessCrossReferenceMemory` | 新增 | 搬入现有的直接读指针与 slide 换算 | 进程内行为不变 | 1、2 |
| 现有 22 处 `UnsafeRawPointer(bitPattern:)`（`ReferenceScanner`、`ObjectiveCClassIndex`、`SwiftTypeIndex`、`ImageFunctionTable`、`+SwiftTypes`、`+Prefiltering`、`ImageFallbackNames`）、`StoredPointer` | 修改 | 改走 `CrossReferenceMemory`；掩码由 memory 提供 | 读取抽象；文件模式没有 `InProcessContext` | 1 |
| `Sources/Analysis/CrossReferenceCore/` | 新增 | 核心层模块：`CodeLocation`、`CodeReferenceRoute`、`IndirectCallEvidence`（由顶层下移），镜像表、函数表、扫描循环、寄存器跟踪、链接关系与导入名预筛、`RenamedReexportIndex` | 按层拆分 | 2 |
| `…/CrossReferenceCore/Recognition/CodeReferenceRecognition.swift` · `CodeReferenceRecognitionSession`、`CodeReferenceRecording`、`ResolvedCallTarget`、`ScanSite` | 新增 | package 协议：会话在五个时机（进入函数、解析只有它认得的调用目标、调用点、算出地址、读槽）被问；核心层产出的引用交给谁 | 扩展点；核心不认识任何语言；引用不经核心转手 | 2 |
| `…/CrossReferenceCore/Images/CodeImageSet.swift`、`CodeImageSet+Linkage.swift` · `CodeImageSet`、`RuntimeLibraryRules` | 新增 | 由 `CrossReferenceAnalyzer` 里与语言无关的部分拆出：镜像与映射、按镜像缓存的函数表、锁、`releaseImageData` 的核心部分 | 顶层门面之下的核心状态 | 2 |
| `…/CrossReferenceCore/Scanning/ReferenceScanner.swift` | 修改（搬家） | 只留通用识别；ObjC 与 Swift 的分支改成在五个时机问识别器；`findsTypeReferences` 一类的跳过改成每个识别器按这次查询要的种类决定 | 按层拆分 | 2 |
| `…/CrossReferenceCore/Scanning/RegisterFile.swift` | 修改（搬家） | `methodReceiver` 状态换成识别器可用的寄存器标记位（随 `mov` 复制、写入即清除、调用后按识别器给的保留集合保留） | 去掉核心里唯一的 ObjC 状态 | 2 |
| `…/CrossReferenceCore/Scanning/ImageFunctionTable.swift` | 修改（搬家） | ObjC 节的范围（`__objc_stubs`、selref、superref、classref）移出，只留函数起点、名字、data in code、本镜像桩、GOT、段范围 | 按层拆分 | 2 |
| `Sources/Analysis/CrossReferenceObjC/` · `ObjCCodeReferenceRecognizer`、`ObjCCodeReferenceRecording` | 新增 | ObjC 层模块：发送与 super 发送、libobjc 专用入口、`__objc_stubs` 与跳板常量里的 selector、接收者、classref / superref / 类对象、`objc_*` 运行时辅助函数、`ReceiverClassHint`（由顶层下移） | 按层拆分 | 2 |
| `…/CrossReferenceObjC/ObjectiveCClassIndex.swift`、`MessageSendEntryPoints.swift` | 修改（搬家） | 原样搬入 | 属于 ObjC 层 | 2 |
| `…/CrossReferenceObjC/ObjCImageSections.swift`、`ObjCMethodNames.swift` | 新增 | 由 `ImageFunctionTable` 拆出的 ObjC 节范围与方法标记；由 `ImageFallbackNames` 拆出的 ObjC 方法列表回退名 | 按层拆分 | 2 |
| `…/CrossReferenceObjC/` 预筛 | 修改（搬家） | `imageIndices(referencingSelector:)`、`imageIndices(referencingObjectiveCClassAt:)`、`objectiveCClassLocations(named:)` 的实现由 `+Prefiltering` 搬来，顶层门面转发 | 按层拆分 | 2 |
| `Sources/Analysis/CrossReferenceAnalysis/Scanning/SwiftCodeReferenceRecognizer.swift` · `SwiftCodeReferenceRecognizer` | 新增 | 由扫描器拆出的 Swift 部分：元数据访问器、值类型元数据、mangled name 实例化辅助函数与运行时入口、`swift_*` 运行时辅助函数、`swift_getInitializedObjCClass` 的 `x0` 保留 | 按层拆分 | 2 |
| `…/CrossReferenceAnalysis/Scanning/SwiftMetadataNames.swift`、`…/CrossReferenceCore/Scanning/ExportedFunctionNames.swift` | 新增 | 由 `ImageFallbackNames` 拆出：Swift 元数据回退名（Swift 层）、导出 trie 的名字（核心层），都是函数表附件 | 按层拆分 | 2 |
| `…/CrossReferenceAnalysis/CrossReferenceAnalyzer.swift` · `CrossReferenceAnalyzer` | 修改 | 变成门面：持有 `CodeImageSet` 与两个识别器，实现三个记录协议造出公开的 `CodeReference`；公开方法签名不变；`@_exported import` 两个下层模块；之后持有 `CrossReferenceMemory`、拆出「进程」与「文件」两条构造、`images` 标 deprecated | 公开 API 不变；支持文件模式 | 2、4 |
| `…/CrossReferenceAnalysis/Scanning/RuntimeHelperNames.swift` | 改名 | 改名 `SwiftRuntimeHelperNames`，只留 Swift 的名单；libobjc 的名单移到 ObjC 层的 `ObjCRuntimeHelperNames` | 核心不许出现运行时名字 | 2 |
| `…/CrossReferenceAnalysis/Scanning/ImageFallbackNames.swift` | 删除 | 三种来源拆成三层各自的函数表附件，起名顺序留在门面的 `codeFunction(at:in:)` | 按层拆分 | 2 |
| `Sources/Analysis/CrossReferenceAnalysis/Exports.swift`、`CrossReferenceAnalyzer+Linkage.swift`、`+Prefiltering.swift` | 新增 / 修改 | `@_exported import` 两个下层模块；公开预筛与链接方法转发到各层 | 公开 API 不变 | 2 |
| `Sources/Analysis/CodeAddressResolution/ImageAddressSpace.swift` · `ImageAddressSpace` | 新增 | 由 `ThunkAddressSpace` 搬来，连同地址约定的注释 | 两个分析模块共用 | 3 |
| `…/CodeAddressResolution/CacheImageLocator.swift` · `CacheImageLocator` | 新增 | 由 `CacheImageResolver` 搬来 | 同上 | 3 |
| `…/CodeAddressResolution/StubChainResolver.swift` · `StubChainResolver` | 新增 | 由 `MachOThunkEnvironment` 的桩链部分抽出，补 27 的 cache 共用桩，记录每一跳与跳板设定的寄存器常量 | 同上；符号化要每一跳 | 3 |
| `…/CodeAddressResolution/SlotResolver.swift` · `SlotResolver` | 新增 | 由 `MachOThunkEnvironment` 的槽解析抽出，泛化到任意指针槽 | 同上 | 3 |
| `Sources/Support/ARM64InstructionDecoding/ARM64Trampoline.swift` | 修改 | GOT 桩的载入之后必须紧跟经同一寄存器的跳转 | 开头是 `adrp; ldr` 的普通函数被误认成桩 | 3 |
| `Sources/Analysis/SwiftThunkAnalysis/Resolution/MachOThunkEnvironment.swift` | 修改 | 改用上面四个类型，行为不变 | 去重 | 3 |
| `…/SwiftThunkAnalysis/Resolution/ThunkAddressSpace.swift` · `ThunkAddressSpace` | 删除 | 调用点改用 `ImageAddressSpace` | 已搬走 | 3 |
| `…/CrossReferenceCore/Memory/FileCrossReferenceMemory.swift` · `FileCrossReferenceMemory` | 新增 | 值，`unowned(unsafe)` 引用镜像集持有的 `Storage`：MachOKit 映射的文件字节；cache 的槽按 mapping 预取的 slide info 解（v5 自己解，其余交给 MachOKit），独立文件的槽经 `SlotResolver`，bind 落到所覆盖文件的导出上 | 文件模式 | 4 |
| `…/CrossReferenceCore/Images/CodeImage.swift` · `CodeImage`、`ImageLinkEdit` | 新增 | 与读取器无关的镜像描述（slide、读取器 offset 与地址的换算只在构造处定一次）；`__LINKEDIT` 的各表按地址经读取层读 | 两种模式共用一套读法 | 4 |
| `…/CrossReferenceCore/Images/CodeImageSet.swift` | 修改 | `images: [CodeImage]`；新增 `dyldCache(_:…)` 与 `files(_:…)` 两个构造器（独立文件按 dyld 的做法错开）；持有文件读取层的存储 | 文件模式 | 4 |
| `…/CrossReferenceCore/Scanning/ImageFunctionTable.swift`、`ExportedFunctionNames`、`RenamedReexportIndex`、`CodeImageSet+Linkage` | 修改 | 符号、间接符号、桩、函数起点、data in code、导出树、依赖都改走 `CodeImage` / `ImageLinkEdit` | 文件模式 | 4 |
| `…/CrossReferenceObjC/ObjectiveCClassIndex.swift`、`ObjCMethodNames.swift`、`ObjCImageSections.swift`、`+Prefiltering` | 修改 | 类名、方法表、objc 桩按读取器分两条路读（MachOObjCSection 的 API 各一套，文件里 `imp` 是读取器 offset）；按名字导入的 `_objc_msgSend` 认成发送 | 文件模式 | 4 |
| `…/CrossReferenceAnalysis/Scanning/SwiftTypeIndex.swift`、`SwiftMetadataNames.swift`、`CrossReferenceAnalyzer+SwiftTypes.swift` | 修改 | 经 `MachOSwiftSectionRepresentableWithCache` 泛型读描述符；文件里的 mangled name 经文件的读取上下文解 | 文件模式 | 4 |
| `…/CrossReferenceAnalysis/CrossReferenceAnalyzer.swift`、`FileAnalysisError.swift` | 修改 / 新增 | `init(dyldCache:)`、`init(machOFiles:)`、`imageCount`、`FileAnalysisError` | 公开入口 | 4 |
| `…/CodeAddressResolution/SlotResolver.swift`、`ImageAddressSpace.swift` | 修改 | 独立文件的链式 fixup 目标按 `__TEXT` 加偏移换算（`address(forHeaderOffset:)`） | 修 bug：可执行文件的槽解错 4 GiB | 4 |
| `Tests/CrossReferenceAnalysisTests/FileModeTests.swift`、`StandaloneFileReferenceDumpTests.swift` | 新增 | 文件模式的行为测试；独立文件引用导出（按环境变量启用，供与反汇编器对照） | 验证 | 4 |
| `Sources/Support/ARM64InstructionDecoding/ARM64InstructionWord.swift` | 修改 | `load(_:)` 之外新增 32 位 `ldr` 与 `ldrsw` 的解码 | ivar 偏移变量的读法 | 5 |
| `…/CrossReferenceCore/Scanning/ReferenceScanner.swift`、`RegisterFile.swift` | 修改 | 记录 `route`；C 字符串与 CFString；跟踪 `ldrsw` / 32 位 `ldr` 读出的来源，交给识别器 | 引用路线；新引用种类 | 5 |
| `…/CrossReferenceObjC/ObjCCodeReferenceRecognizer.swift` | 修改 | ivar 偏移变量 → ivar 引用；selector 优先于 C 字符串认领 | 新引用种类 | 5 |
| `…/CrossReferenceAnalysis/SwiftCodeReferenceRecognizer.swift` | 修改 | Swift 大字符串字面量（`adrp; add; sub #0x20`）记成 C 字符串引用 | 新引用种类 | 5 |
| `…/CrossReferenceAnalysis/Models/CodeReference.swift` · `CodeReferenceTarget`、`CodeReference` | 修改 | 新增三个 target case；新增 `route`（类型是核心层的 `CodeReferenceRoute`，以 `CodeReference.Route` 暴露）；旧初始化方法 deprecated | 新引用种类；引用路线 | 5 |
| `…/Models/CodeReferenceTable.swift` · `CodeReferenceTable.Key` | 修改 | 新增 `instanceVariable`、`cString`、`constantString` 键 | 按新目标查 | 5 |
| `…/Models/CodeReferenceIndex.swift` · `CodeReferenceIndex` | 修改 | 编码新 target 与 `route` | 常驻索引也要带上 | 5 |
| `…/CrossReferenceAnalyzer+Prefiltering.swift` 及两层的预筛 | 修改 | 新增 ivar（ObjC 层）与字符串（核心层）的预筛 | 新查询 | 5 |
| `…/CrossReferenceAnalysis/Symbolication/AddressSymbolication.swift` · `AddressSymbolication` | 新增 | 公开的符号化结果模型（顶层，因为它带 `CodeReferenceTarget`） | 符号化 | 6 |
| `…/CrossReferenceCore/Symbolication/`、`…/CrossReferenceAnalysis/CrossReferenceAnalyzer+Symbolication.swift` · `symbolication(of:)` | 新增 | 核心按「函数 → 桩 → 槽 → 字符串 → 最近符号 → 未映射」判断结构，识别器补含义与名字，门面组装 | 符号化 | 6 |
| `Sources/Commands/SwiftSectionKit/CrossReferences/CrossReferenceInput.swift` | 新增 | 由文件、cache 或本机 cache 建分析器 | 两个子命令共用 | 7 |
| `…/SwiftSectionKit/CrossReferences/ReferencesRequest.swift` · `ReferencesRequest` | 新增 | 预筛 → 并发逐镜像查 → 起名 → 文本 / JSON | `refs` 的逻辑 | 7 |
| `…/SwiftSectionKit/CrossReferences/SymbolicateRequest.swift` · `SymbolicateRequest` | 新增 | 批量符号化 → 文本 / JSON | `symbolicate` 的逻辑 | 7 |
| `…/SwiftSectionKit/CrossReferences/CrossReferenceFormatting.swift` | 新增 | 文本与 JSON 的拼写（`CrossReferenceJSONValue`、目标起名） | 两个子命令共用，JSON 名字即契约 | 7 |
| `Sources/Analysis/CrossReferenceCore/Images/CodeImageSet+SymbolLookup.swift`；门面 `locations(ofSymbolNamed:among:)` | 新增 | 按名字在导出表与符号表里找定义 | `refs --symbol` / `--class` | 7 |
| `Sources/Analysis/CrossReferenceAnalysis/CrossReferenceAnalyzer.swift` · `ReferenceCollector` | 修改 | 键集合拷一份自己的 | 并发共用键集合时的引用计数争抢 | 7 |
| `Sources/Executables/swift-section/Commands/ReferencesCommand.swift`、`SymbolicateCommand.swift` | 新增 | flag、`validate()`、`makeRequest()` | CLI 入口 | 7 |
| `Sources/Executables/swift-section/Models/CrossReferenceInputOptionGroup.swift` | 新增 | 多文件 / cache / 本机 cache、`-a`、`--in-image` | 现有选项组只产出单个 `MachOFile` | 7 |
| `Sources/Executables/swift-section/SwiftSectionCommand.swift` | 修改 | 登记两个子命令 | CLI 入口 | 7 |
| `Sources/Executables/swift-section/Models/CommandLineSupport.swift` | 修改 | `--in-image` / `--function-image` 的错误译成退出码 64 | 用法错误按惯例 | 7 |
| `Package.swift` | 修改 | 新增 `CrossReferenceCore`、`CrossReferenceObjC`、`CodeAddressResolution` 三个 target（不做 product）；`CrossReferenceAnalysis` 依赖前两个，`CrossReferenceCore` 与 `SwiftThunkAnalysis` 依赖第三个；`SwiftSectionKit` 与 `swift-section` 依赖 `CrossReferenceAnalysis` | 模块图 | 2、3、7 |
| `Tests/CrossReferenceAnalysisTests/CrossReferenceLayerBoundaryTests.swift` | 新增 | 源码扫描：每层只 import 允许的模块；核心层没有 `objc_` / `swift_` 字面量 | 守住拆分的边界 | 2 |
| `Tests/CrossReferenceAnalysisTests/…` | 新增 | 对照、按层拆分、文件模式、新种类、符号化测试（见落地步骤） | 验证 | 1–6 |
| `Tests/CodeAddressResolutionTests/…` | 新增 | 桩链、槽解析测试 | 验证 | 3 |
| `Tests/SwiftThunkAnalysisTests/…` | 修改 | 抽取前后结果一致的守护测试 | 去重不改行为 | 3 |
| `Tests/SwiftSectionKitTests/CrossReferenceRequestTests.swift`、`Tests/SwiftSectionCommandTests/CrossReferenceCommandTests.swift` | 新增 | `refs` / `symbolicate` 的文本与 JSON 输出、flag 映射与拒绝的组合 | 验证 | 7 |
| `Documentations/Internal/Modules/CrossReferenceAnalysis.md` | 修改 | 三层的分工与识别器；文件模式、读取抽象、新种类、路线、符号化、拆分前后与离线吞吐实测 | 模块参考 | 2、4–6 |
| `Documentations/Internal/Modules/CrossReferenceCore.md`、`CrossReferenceObjC.md`、`CodeAddressResolution.md` | 新增 | 三个新模块的参考；各写明将来的落脚处与名字 | 模块参考 | 2、3 |
| `AGENTS.md`（模块层级图与各模块说明）、`Documentations/README.md` | 修改 | 登记三个新模块与它们的去向 | 项目约定 | 2、3 |
| `Documentations/Visions/ReverseEngineeringWithoutIDA.md` | 修改 | 「我们选的方向」第 6 条：语言无关的分析核心也归 MachOKitExtensions，ObjC 专属归 MachOObjCSection | 愿景与提案一致 | 2 |
| `AgentPlugins/swift-section/skills/swift-section-cli/` | 修改 | 两个新子命令的用法与坑 | `AGENTS.md` 要求 | 7 |
| `README.md`（CLI 一节） | 修改 | 列出两个新子命令 | 面向用户 | 7 |
| `Documentations/Internal/ProjectEvolutionLog.md`、`Documentations/Glossary.md` | 修改 | 追加本批次；登记「符号化」「引用路线」「识别器」「stub island」等术语 | 文档约定 | 9 |
| RuntimeViewer `RuntimeViewerCore/Sources/RuntimeViewerCrossReferences/Analysis/CrossReferenceQuery.swift` | 修改 | `switch reference.target`（`:92`）补三个新 case | 穷尽 switch 会编译失败 | 5 |
| RuntimeViewer `…/RuntimeViewerCrossReferences/`（新文件）· 符号化引擎命令 | 新增 | 引擎侧 `crossReferenceSymbolicate` 与 `crossReferenceLocateSymbol` 两个命令，`RuntimeEngine.symbolicate(_:inImageAt:)`、`locations(ofSymbolNamed:)`，线上类型 `RuntimeAddressSymbolication`、`RuntimeSymbolLocation` | CLI / MCP 的符号化与按名字找函数 | 8 |
| RuntimeViewer `…/RuntimeViewerCrossReferences/RuntimeCrossReferenceTargetResolution.swift` | 新增 | 目标写法（方法、Swift 成员、符号、地址、selector）→ 查询主体，CLI 与 MCP 共用 | 两个前端一套写法 | 8 |
| RuntimeViewer `…/RuntimeViewerCrossReferences/Models/RuntimeCrossReferenceRow.swift`、`RuntimeAddressSymbolicationRow.swift` | 新增 | CLI `--json` 与 MCP 每行字段的唯一来源，地址一律十六进制字符串 | 字段名一致 | 8 |
| RuntimeViewer `…/RuntimeViewerCrossReferences/Analysis/CrossReferenceQuery.swift`、`Models/RuntimeCrossReferenceError.swift` | 修改 | 两处穷尽 switch 补三个新目标（不显示）；符号化与按名定位的实现；错误加 `addressNeedsImage`、`targetNotFound`、`ambiguousTarget` | 源码兼容；新命令 | 8 |
| RuntimeViewer `…/Model/CommandFailure.swift` | 修改 | 失败代码加 `targetNotFound`、`crossReferencesUnavailable` | CLI | 8 |
| RuntimeViewer `Documentations/Guides/CommandLineInterface.md`、`AgentPlugins/runtime-viewer/`（skill 与两个清单 1.3.0）、`README.md` | 修改 | 四个子命令与目标写法 | RuntimeViewer 的 AGENTS.md 要求 | 8 |
| RuntimeViewer `RuntimeViewerCommandLine/Sources/RuntimeViewerCommandLineInterface/Model/Command.swift`、`CommandResult.swift` | 修改 | `.callers` / `.callees` / `.references` / `.symbolicate` 与结果 | CLI | 8 |
| RuntimeViewer `…/CommandLine/Subcommands.swift`、`Execution/CommandExecutor.swift`、`Rendering/TextRenderer.swift` | 修改 | 四个子命令的解析、执行与显示 | CLI | 8 |
| RuntimeViewer `…/Protocol/WireMessage.swift` · `CommandLineProtocol.version` | 修改 | 2 → 3 | 新增命令 | 8 |
| RuntimeViewer `RuntimeViewerMCP/Sources/RuntimeViewerMCPBridge/MCPBridgeServer.swift`、`MCPBridgeProtocol.swift` | 修改 | `Callers`、`Callees`、`TypeReferences`、`Symbolicate` 四个工具，30 秒等待 `references(within:_:)`，响应类型 `MCPCrossReferencesResponse` 等 | MCP | 9 |
| RuntimeViewer `Documentations/Evolutions/README.md`、`0056-cross-references.md` | 修改 | cross-repository draft 一行；暂缓表第 4 步指向本提案 | 提案索引 | 9 |
| RuntimeViewer `AgentPlugins/runtime-viewer/`、`Documentations/Guides/CommandLineInterface.md`、`Documentations/Evolutions/README.md` | 修改 | skill 与两个插件清单的 version；使用指南；`cross-repository draft` 一行 | 文档同批 | 8、9 |

## 架构图

改了什么——模块与依赖（箭头指向被依赖的一方；方括号里是将来的落脚处）：

```text
MachOSwiftSection
  Sources/Executables/swift-section
+   refs, symbolicate ───────────────────────────────┐
  Sources/Commands/SwiftSectionKit                    │
+   CrossReferences/ReferencesRequest, SymbolicateRequest, CrossReferenceInput
                                                      v
  Sources/Analysis
~   CrossReferenceAnalysis          Swift layer + public facade            [stays]
~     CrossReferenceAnalyzer        facade: CodeImageSet + recognizers; implements the three recordings
+     SwiftCodeReferenceRecognizer  accessors, value metadata, mangled names, swift_* helpers
+     SwiftMetadataNames            (split from ImageFallbackNames)
~     CodeReferenceTarget, CodeReferenceTable, CodeReferenceIndex, CodeFunction   public model stays here
+     AddressSymbolication
        |  @_exported import
        v
+   CrossReferenceObjC              package, not a product               [MachOObjCSection: ObjCCodeReferences]
+     ObjCCodeReferenceRecognizer   sends, entry points, selector stubs, receivers, class/super refs, ivars
+     ObjCCodeReferenceRecording
~     ObjectiveCClassIndex, MessageSendEntryPoints   (moved)
+     ObjCImageSections, ObjCMethodNames             (split from ImageFunctionTable, ImageFallbackNames)
        |                     \
        v                      -> MachOObjCSection (package)
+   CrossReferenceCore              package, not a product               [MachOKitExtensions: MachOCodeReferences]
+     CodeReferenceRecognitionSession, CodeReferenceRecording, ResolvedCallTarget
+     CodeImageSet                  images, mappings, function tables (split from CrossReferenceAnalyzer)
~     ReferenceScanner, RegisterFile, ImageFunctionTable   (moved; language-free)
+     CrossReferenceMemory: InProcessCrossReferenceMemory, FileCrossReferenceMemory
~     CodeLocation, CodeReferenceRoute, IndirectCallEvidence   (moved down)
        |
        v
+   CodeAddressResolution           package, not a product               [MachOKitExtensions: MachOAddressResolution]
+     ImageAddressSpace, CacheImageLocator, StubChainResolver, SlotResolver
        ^
~   SwiftThunkAnalysis / MachOThunkEnvironment ─┘
-     ThunkAddressSpace, CacheImageResolver

  Sources/Support/ARM64InstructionDecoding
~   ARM64InstructionWord            + 32-bit ldr, ldrsw

RuntimeViewer
~ RuntimeViewerCrossReferences   switch over new targets; + symbolicate engine command
~ RuntimeViewerCommandLine       + callers, callees, references, symbolicate (protocol 2 -> 3)
~ RuntimeViewerMCPBridge         + Callers, Callees, TypeReferences, Symbolicate
```

扫描一个函数时，核心层在哪里问识别器：

```text
ReferenceScanner.scanFunction(at:)                           CrossReferenceCore
  for session in sessions: session.enterFunction(...)        ObjC: tag x0 as the method receiver
  for each instruction:
    bl / b out of the function
      core: resolve target  (own stubs, GOT, stub islands, other images via StubChainResolver)
        not recognized? -> sessions: resolveCallTarget(...)  ObjC: __objc_stubs selector
      sessions: noteCall(callee, registers)                  ObjC: x1 selector, x0 receiver -> recordMessageSend
                                                             Swift: metadata accessor, mangled name -> recordSwiftType
        no session claimed the call -> core: recordCall(.function / .importedSymbol / .unrecognized)
        registers kept across the call = union of what the sessions return (objc_opt_self keeps x0)
    adrp+add / adr built an address
      core: C string, CFString                               (string references, when requested)
      sessions: noteAddress(...)                             ObjC: class object; Swift: metadata, accessor, large string
    ldr from a slot
      sessions: noteSlotLoad(...)                            ObjC: classref, superref, ivar offset; Swift: GOT -> type
    blr / braa
      core: recordIndirectCall(pointer-authentication constant, displacement)
  CrossReferenceAnalyzer (facade) implements every recording -> public CodeReference
```

一次 `refs` 查询的数据流：

```text
swift-section refs --selector makeKeyAndOrderFront: --dyld-shared-cache <cache>
  ReferencesCommand.makeRequest()
  -> ReferencesRequest
     -> CrossReferenceInput: FullDyldCache(url:) -> CrossReferenceAnalyzer(dyldCache:)
          CodeImageSet from cache header imageInfos; FileCrossReferenceMemory over mapped subcache files
     -> imageIndices(referencingSelector:among: all)              prefilter (ObjC layer)
     -> for each candidate image, concurrently:
          references(to: [.selector("makeKeyAndOrderFront:")], inImageAt:)
            ReferenceScanner over the image's __text bytes
              bl X  -> StubChainResolver(X) -> trampoline sets x1, ends at objc_msgSend
                    -> ObjC session: x1 constant is a selector -> .messageSend    route .cacheSharedStub
              adrp+ldr slot -> SlotResolver(slot) -> rebase target -> ObjC session: class object  route .pointerSlot
     -> functions(containing: sites) -> names (symbols, export trie, ObjC method lists, Swift metadata)
  -> StandardStreamOutput: text rows | one JSON document
```
## 详细设计

### 公开 API（`CrossReferenceAnalysis`）

按全局 `apple-style-api-design` skill 的顺序，先写调用点：

```swift
// Simplest: what is this address?
let analyzer = try CrossReferenceAnalyzer(dyldCache: FullDyldCache(url: cacheURL))
print(analyzer.symbolication(of: 0x1_9012_3450))

// Most common: who sends a selector, across an archived cache.
let selectorKey = CodeReferenceTable.Key.selector("makeKeyAndOrderFront:")
for imageIndex in analyzer.imageIndices(referencingSelector: "makeKeyAndOrderFront:", among: analyzer.imagePaths.indices) {
    for reference in analyzer.references(to: [selectorKey], inImageAt: imageIndex) {
        print(analyzer.imagePaths[imageIndex], reference.instructionAddress, reference.route)
    }
}

// Most complex: an app and its frameworks, string references included.
let files = try appBundle.machOFileURLs.map { try MachOFile(url: $0) }
let appAnalyzer = try CrossReferenceAnalyzer(machOFiles: files, recordingStringReferences: true)
```

声明：

```swift
extension CrossReferenceAnalyzer {
    /// Analyzes every image of a dyld shared cache read from disk, such as an archived one.
    /// `recordingStringReferences` arrives with step 5.
    public convenience init(dyldCache: FullDyldCache, recordingStringReferences: Bool = false) throws

    /// Analyzes standalone Mach-O files, such as an app's executable and its embedded frameworks.
    public convenience init(machOFiles: [MachOFile], recordingStringReferences: Bool = false) throws

    /// Why an analyzer could not be made from files: `Code.unsupportedArchitecture` for a cache or
    /// a file holding no arm64 code. A struct with codes, since more may come.
    public struct FileAnalysisError: Error, Hashable, Sendable { public let code: Code; public let path: String }

    /// The number of images the analyzer covers, in either mode.
    public var imageCount: Int { get }

    /// What the address is: a place inside a function, a stub, a pointer slot, a string, or nothing mapped.
    public func symbolication(of address: UInt64) -> AddressSymbolication
}

extension CrossReferenceAnalyzer {
    /// The in-process analyzer's images; empty for one made from files. Not deprecated: in-process
    /// hosts read what only a `MachOImage` tells (its slide, its header).
    public let images: [MachOImage]
}

public enum CodeReferenceTarget: Hashable, Sendable {
    // … the nine existing cases …
    /// A load of an Objective-C instance variable's offset variable (`_OBJC_IVAR_$_Class.ivar`).
    case objectiveCInstanceVariable(className: String, name: String)
    /// A C string literal whose address the code materializes. Recorded only when string references are recorded.
    case cString(String)
    /// A constant `CFString` / `NSString` literal. Recorded only when string references are recorded.
    case constantString(String)
}

// CrossReferenceCore — re-exported by CrossReferenceAnalysis.
/// How the code reached what it references: the instructions and trampolines on the way, not what the target is.
public enum CodeReferenceRoute: UInt8, Hashable, Sendable {
    /// `bl` / `b` straight to the target.
    case direct
    /// A stub in the referencing image's own stub sections (`__stubs`, `__auth_stubs`, `__objc_stubs`).
    case imageStub
    /// A trampoline in a dyld shared cache stub island, possibly after several hops.
    case stubIsland
    /// A stub shared by the whole cache: macOS / iOS 27's `objc_msgSend$…` selector stubs and GOT stubs.
    case cacheSharedStub
    /// `adrp` + `ldr` through a pointer slot: a GOT or auth GOT slot, or a slot of an Objective-C reference section.
    case pointerSlot
    /// `adrp` + `add`, or `adr`, computing the target's address.
    case addressMaterialization
    /// `ldr` of a literal pool entry.
    case literalLoad
    /// A call or a jump through a register — `blr`, `br` and their authenticating forms; the
    /// evidence says what is known. (Was `authenticatedIndirect`; see the decision log.)
    case indirect
}

/// Whether the referencing instruction calls, leaves the function, or only takes an address.
public enum CodeReferenceKind: Hashable, Sendable {
    case call
    case tailCall
    case reference
}

// CrossReferenceAnalysis
extension CodeReference {
    public typealias Route = CodeReferenceRoute
    /// Was a nested enum; the cases are unchanged.
    public typealias Kind = CodeReferenceKind

    public let route: Route

    public init(function: CodeLocation, instructionAddress: UInt64, kind: Kind, target: CodeReferenceTarget, route: Route, isRuntimeHelperCall: Bool)

    @available(*, deprecated, renamed: "init(function:instructionAddress:kind:target:route:isRuntimeHelperCall:)")
    public init(function: CodeLocation, instructionAddress: UInt64, kind: Kind, target: CodeReferenceTarget, isRuntimeHelperCall: Bool)
}

extension CodeReferenceTable.Key {
    // new cases
    case instanceVariable(className: String, name: String)
    case cString(String)
    case constantString(String)
}

public struct AddressSymbolication: Hashable, Sendable {
    public let address: UInt64
    public let imagePath: String?
    public let segmentName: String?
    public let sectionName: String?
    public let meaning: Meaning

    public enum Meaning: Hashable, Sendable {
        /// Inside a function's body.
        case function(start: CodeLocation, name: String?, offset: UInt64)
        /// A stub or stub-island trampoline; `hops` lists every trampoline passed through, starting with the address asked about.
        case stub(hops: [UInt64], target: CodeReferenceTarget)
        /// A pointer slot and what it holds.
        case pointerSlot(PointerSlotKind, target: CodeReferenceTarget)
        case cString(String)
        case constantString(String)
        /// None of the above: the nearest preceding symbol.
        case symbol(name: String, offset: UInt64)
        /// Mapped by an image, but none of the above and no symbol at or below it.
        case data
        /// Not inside any mapped image.
        case unmapped
    }

    public enum PointerSlotKind: Hashable, Sendable {
        case globalOffsetTable
        case selectorReference
        case classReference
        case superclassReference
        case protocolReference
        case instanceVariableOffset
    }
}
```

（`CodeReferenceTable.Key` 的新 case 在实现里直接写进原 enum；上面用 extension 的写法只为标出新增部分。）

命名取舍：

- 用 **symbolication / symbolicate** 而不是 resolve：MachOKit 与 MachOKitExtensions 里 `resolveBind` / `resolveRebase` 的 resolve 指「解 fixup」，同一个词不能再指「说出地址是什么」；symbolication 是 Apple 自己的说法（`atos`、崩溃报告的 symbolication）。
- 方法用名词短语 `symbolication(of:)`：它没有副作用，按 API Design Guidelines 读成名词短语。
- `route` 不给默认值：它影响结果是否可信，按「影响正确性的参数不给默认值」处理；旧初始化方法保留一个版本并标 `renamed:`。
- 路线只描述「代码怎么到达」，不描述「槽在哪个节」：原先列的 `selectorReference`（selref）与 `classReference`（classref / superref）并进 `pointerSlot`。路线由核心层产出，核心不认识 ObjC 的节；槽是哪一种，看引用的目标（selector 还是类）或对槽地址做符号化（`PointerSlotKind`）即可得知。
- `Route` 与 `Kind` 定义在核心层、以 `CodeReference` 的 typealias 暴露：核心层要产出这两个值，而 `CodeReference` 本身留在顶层。`CodeReference.Kind.call` 一类写法照旧可用。

### 按层拆分与识别器（package）

三层之间的接口全部是 `package` 级：两个下层模块这一步不做 product，接口还可以按实测改。下面是第 2 步实际做成的样子。

核心层的扩展点（`CrossReferenceCore/Recognition/CodeReferenceRecognition.swift`）：

```swift
/// One scan of one image by one language layer, on one thread.
package protocol CodeReferenceRecognitionSession: AnyObject {
    /// Slots, unslid, holding references the session reads besides the core's GOT: `__objc_classrefs`.
    var referenceSlotRanges: [Range<UInt64>] { get }
    /// Slots a load from which the session watches on every load: `__objc_superrefs`.
    var watchedSlotRanges: [Range<UInt64>] { get }
    /// Whether the session looks at addresses built and slots loaded at all.
    var looksForAddressReferences: Bool { get }

    /// A function starts; may tag registers (an Objective-C method's receiver in `x0`).
    func enterFunction(at functionIndex: Int, registers: RegisterFile)
    /// A target only this session can read (`__objc_stubs`); asked before the core resolves it.
    func claimCallTarget(at target: UInt64) -> CallTargetClaim?
    /// The session's role for a target the core resolved; asked once per distinct target of a scan.
    func role(of target: ResolvedCallTarget) -> CalleeRole?
    /// Records what the call stands for in place of the plain call reference — a message send.
    func recordCallStandIn(_ call: ScannedCall, registers: RegisterFile) -> Bool
    /// After the call's reference: records what it references besides (a Swift type); returns
    /// the caller-saved registers, by bit, that keep their contents across it.
    func noteCallMade(_ call: ScannedCall, registers: RegisterFile) -> UInt32
    /// An address an instruction built, at its runtime address; `isCode` when in the image's `__text`.
    func recordAddressReference(toRuntimeAddress address: UInt, isCode: Bool, at site: ScanSite) -> Bool
    /// A load from a reference slot that holds the runtime address `value`.
    func recordSlotReference(holding value: UInt, at site: ScanSite) -> Bool
    /// A load from one of `watchedSlotRanges`.
    func noteWatchedSlotLoad(from slot: UInt64)
}

/// Where the references a scan finds go; each language layer refines it.
package protocol CodeReferenceRecording: AnyObject {
    func recordCall(to target: ResolvedCallTarget, targetAddress: UInt64, at site: ScanSite, isRuntimeHelperCall: Bool)
    func recordIndirectCall(_ evidence: IndirectCallEvidence, at site: ScanSite)
}

/// What the core resolves a call target to, knowing no language.
package enum ResolvedCallTarget: Hashable {
    case function(CodeLocation)
    case importedSymbol(UnsafePointer<CChar>)
    /// macOS / iOS 27's cache-shared selector stub: `x1` = the selector string, then a branch.
    case registerSettingTrampoline(register: Int, value: UInt64)
    case unrecognized
}
```

ObjC 层（`CrossReferenceObjC`）与 Swift 层各自细化记录协议：

```swift
package protocol ObjCCodeReferenceRecording: CodeReferenceRecording {
    func recordMessageSend(selector: String, receiver: ReceiverClassHint, at site: ScanSite)
    func recordSuperMessageSend(selector: String, className: String?, at site: ScanSite)
    func recordClassReference(_ classObject: ObjectiveCClassObject, at site: ScanSite)
}

protocol SwiftCodeReferenceRecording: CodeReferenceRecording {
    func recordSwiftType(descriptor: CodeLocation, at site: ScanSite)
    func recordSwiftTypeName(_ name: SwiftTypeName, at site: ScanSite)
}
```

规则：

- **识别器是各层的具体类型，没有共同协议**：`ObjCCodeReferenceRecognizer`、`SwiftCodeReferenceRecognizer` 各自按镜像记住类索引与 Swift 类型索引，各有 `makeSession(table:recording:…)`。门面是组合根，本来就认识两个具体的层，再抽一个识别器协议说不出能带来什么。核心只认会话协议。
- **会话排成一列，顺序就是优先级**：门面按 ObjC、Swift 的顺序建会话；同一个时机第一个认领的为准。核心只在没有会话代替时记录普通调用。
- **调用不拖慢扫描**：每个不同的调用目标只问一次各会话的角色，结果连同核心的解析一起记在扫描器的调用计划里；没有角色的调用——绝大多数——不经过任何会话。地址与槽按地址记住是哪个会话认领的（或谁都没认领），下次只问那一个或直接跳过。
- **门面是组合根**：`CrossReferenceAnalyzer` 里的 `ReferenceCollector` 实现全部三个记录协议，直接造公开的 `CodeReference` 并按查询的键过滤（原 `ReferenceScanner.keep`）。下层不认识 `CodeReferenceTarget`，所以加一种目标不碰下层。
- **查询只给一个开关**：两层的会话收到同一个「找不找类与类型引用」的开关（原 `findsTypeReferences`），与拆分前一致；只查 selector 或函数时两层都跳过地址与槽，ObjC 层在发送处照旧认类字面量接收者。
- **寄存器标记**：`RegisterFile` 的「方法接收者」状态换成通用的标记（`setTag(_:of:)` / `tag(of:)`），随 `mov` 复制、写入即清除；ObjC 会话用标记 1。调用后保留哪些寄存器由会话按位返回（`clobberCallerSavedRegisters(keepingMask:)`）。
- **跳板常量**：cache 共用 selector 桩由核心解析成 `.registerSettingTrampoline(register: 1, value:)`，核心不解释；ObjC 会话把它读成发送。
- **运行时库与辅助函数**：核心不认识运行时库。门面把两层的规则（`RuntimeLibraryRules`：哪些路径是运行时库、哪些符号是辅助函数）交给 `CodeImageSet`；建镜像集时核心扫一遍运行时库的符号，记下辅助函数位置，并把每个符号交给门面，门面分发给两层各自记下 `objc_msgSend`、专用入口、`swift_getTypeByMangledName…` 这些位置。
- **按镜像的缓存挂在函数表上**：`ImageFunctionTable.attachment(_:makingIt:)`，核心的 `ExportedFunctionNames`、ObjC 层的 `ObjCImageSections` 与 `ObjCMethodNames`、Swift 层的 `SwiftMetadataNames`。无名函数的起名不在扫描热路径上，由门面依次问这三个附件。
- **预筛**各归各层：导入名与链接关系在核心层（`CodeImageSet+Linkage`），selector 与类在 ObjC 层，Swift 类型在 Swift 层；门面上的公开预筛方法签名不变，只是转发。
- **性能**：会话只在事件上经 existential 调用。验收：在 Ultra 上 release 构建，拆分后整 cache 建表与 `init`、`makeKeyAndOrderFront:` 两条查询的耗时，相对拆分前的增幅都不超过 5%（`ScanThroughputBenchmarkTests`，按环境变量启用，两边各跑三轮取最好）。超出时先把会话列表改成具体类型的泛型参数、扫描入口标 `@inline(always)` 让门面特化，再量；数字写进模块文档。

### 读取抽象（package）

```swift
package protocol CrossReferenceMemory: Sendable {
    /// The `length` bytes from `address` on — an address in the analyzer's own
    /// address space — contiguous and read-only, or nil when they cannot be read.
    func bytes(at address: UInt, length: Int) -> UnsafeRawBufferPointer?
    /// What the pointer slot at `address` holds, its signature and tag bits stripped.
    func slotContent(at address: UInt) -> SlotContent?
    /// The bits of a stored pointer that are its address.
    var addressMask: UInt { get }
    /// Bulk forms for a pass over a whole section of slots (the selector prefilter):
    /// one call rather than one call a slot. Default implementations go slot by slot.
    func pointers(inSlotsAt address: UInt, count: Int) -> [UInt]
    func readablePointers(at addresses: [UInt]) -> [UnsafeRawPointer?]
}

package enum SlotContent: Hashable, Sendable {
    case address(UInt)
    case importedSymbol(String)
}

// load(_:at:), pointer(at:), typedPointer(to:at:length:) are extension helpers.
```

并发：分析器今天是 `@unchecked Sendable` 加手写锁（裁决 A62）。`FileCrossReferenceMemory` 的读取是对只读映射的并发读，fixup 解码的记忆化沿用 MachOKitExtensions `cached` 视图里已有的锁。

### `swift-section` 的 JSON

```json
{
  "query": { "selector": "makeKeyAndOrderFront:" },
  "input": { "dyldSharedCache": "/Volumes/DyldSharedCaches/macOS/27.2/dyld_shared_cache_arm64e", "imageCount": 4114 },
  "scannedImageCount": 2759,
  "isTruncated": false,
  "references": [
    {
      "image": "/System/Library/Frameworks/AppKit.framework/Versions/C/AppKit",
      "function": { "address": "0x18801a000", "name": "-[NSApplication _showWindow:]" },
      "site": "0x18801a040",
      "kind": "call",
      "route": "cacheSharedStub",
      "target": { "messageSend": { "selector": "makeKeyAndOrderFront:", "receiver": "unknown" } }
    }
  ]
}
```

（示例中的函数名与地址是示意，不是实测值。）`symbolicate --json` 输出 `{"symbolications": [ … ]}`，每项的字段对应 `AddressSymbolication`。字段名定下后即是契约，改名按 CLI 的破坏性变更处理。

### 地址的约定

CLI 与 API 进出的地址一律是**未滑动的虚拟地址**，也就是 IDA、`ipsw`、`dyld_info` 显示的那种。进程内模式在内部换算，调用方不需要知道 slide。

### 性能预算

拆分本身的验收见上文「按层拆分与识别器」。离线吞吐在第 4 步实测并写进模块文档：在 Ultra 上对 `/Volumes/DyldSharedCaches/macOS/27.2` 冷启动、热启动各跑 `--selector makeKeyAndOrderFront:` 与 `--selector init`。若冷启动的整 cache 查询超过 60 秒，在愿景里把「落盘」阶段提前。

## 替代方案考量

- **另写一个离线分析器，不动现有的。** 否：扫描、寄存器跟踪、命名合计约 5,200 行，复制一份就会和进程内版本漂移；`SwiftThunkAnalysis` 里已经有一份重复的离线解析，正是本提案要合并的。
- **把分析器改成对 `MachO: MachORepresentable` 泛型**（本库其它模块的惯用写法）。否：两种模式的差别不在「哪种 Mach-O 类型」，而在「槽里的值怎么得到」——进程内读已绑定的值，文件里解 fixup。泛型会一路传染到 RuntimeViewer 持有分析器的会话类型，而一个小协议正好只隔离这一点。
- **直接用 `ReadingContext` 当读取抽象。** 否，理由见「提议方案」第 1 节；`FileCrossReferenceMemory` 内部仍用它。
- **后端用 `ipsw` 或 `dyld_info`。** 否：「前人怎么做的」里列的几类静默漏报、错名都会原样带进来。
- **直接用 Binary Ninja。** 否：用户的 Personal 许可没有无界面 API，无界面的 `binaryninja_mcp` 也只随 Commercial / Ultimate；GUI 的 MCP 要求界面开着、当前视图跟随界面，多个 agent 会互相抢；整 cache 查询要把几千个镜像装进一个视图。2026-11-18 的实测里，它经 MCP 的代码引用召回只有 67.6%（IDA 两跳 99.4%），所以连核对也只作补充。
- **现在就做落盘索引。** 否：0072 与 RuntimeViewer 0056 都定过不做；先量离线吞吐再说。
- **地址符号化放进 MachOKit fork。** 否：fork 已落后上游 33 个提交，再加新能力只会更难合。
- **一步到位：本提案直接把核心写进 MachOKitExtensions、ObjC 层写进 MachOObjCSection。** 否，改为分两步：本提案还有四项要先实测的未知，识别器接口也要在热路径上量过才定得下来；跨三个仓库时核心每改一次都要按序发版，而 MachOKitExtensions 此刻正在为 2.0.0 接收读取层与基础模块。用户在两种走法之间选了分两步。
- **只抽桩链与槽解析，扫描器整体留在本库**（本提案原先的方案）。否：ObjC 与 Swift 的识别仍和通用扫描混在一个依赖 Swift 栈的模块里，不带 Swift 的使用方（关掉 SwiftSection trait 的 MachOKitUI、MachOObjCSection 自己的 `objc-section`）永远拿不到交叉引用；越往上加功能，日后越难拆。
- **核心层直接定义列着 ObjC 与 Swift case 的目标枚举，不开扩展点。** 否：这样也能做到核心不 import 上层，但每加一种语言层的目标都要改核心、在 MachOKitExtensions 发版，而且把 Swift 的词汇带进一个语言无关的包——违反开闭原则。识别器加记录协议让核心对新语言封闭、对扩展开放。
- **核心层对目标类型泛型（`CodeReference<Target>`），各层用 SE-0280 的「enum case 当协议要求的实现」构造目标。**否（这一步）：泛型会扩散到 `CodeReferenceTable`、`CodeReferenceIndex` 和 RuntimeViewer 用到的每个名字；跨模块的泛型在 release 下不特化（`package` 函数不参与默认跨模块优化），扫描热路径上逐条引用的拷贝会走值见证调用。记录协议只在事件上做一次动态派发。下层将来要不要有自己的目标类型，留给迁移提案。
- **本库里的模块直接用落脚处的名字（`MachOCodeReferences`、`ObjCCodeReferences`、`MachOAddressResolution`）。**否：本库发布过的版本只要带着与 MachOKitExtensions 2.x 新模块同名的模块，两边就解析不到一起，迁移时就得让 MachOKitExtensions 再升一个大版本；基础模块迁移提案也定了迁完后本库带 `MachO` 前缀的只有 ABI 模型。两个下层模块不是 product，搬的时候改名只动本库内部的 import。
- **CLI 子命令叫 `resolve`。** 否：与 `resolveBind` / `resolveRebase` 撞义，见「详细设计」的命名取舍。
- **照 Binary Ninja 建统一地址空间、换掉 `CodeLocation`。** 否：`CodeLocation` 是公开模型，RuntimeViewer 的查询层建在它上面；统一地址空间里最有用的「任何地址都说得出是什么」由符号化单独提供。
- **照 Binary Ninja 加「selref / selector → IMP」的数据引用。** 本提案不做，归入愿景第 3 阶段的数据引用；现在按 selector 查发送者已经可以，从调用点到实现的两跳留给数据引用一起做。

## 影响

### 源码兼容性（source compatibility）

**有破坏**，逐条：

- `CodeReferenceTarget` 新增三个 case，`CodeReferenceTable.Key` 新增三个 case：对它们做穷尽 `switch` 的代码编译失败。已知下游只有 RuntimeViewer 的 `CrossReferenceQuery.swift:92`（`switch reference.target`），在第 5 步同一时间窗里补上：

  ```swift
  // Before: nine cases.
  // After: add
  case .objectiveCInstanceVariable, .cString, .constantString:
      return nil   // not surfaced in the GUI yet
  ```

  RuntimeViewer 本地按「本地路径优先」依赖本库（`../../MachOSwiftSection`），所以本库 `next` 一合进新 case，RuntimeViewer 的 `next` 就要跟着改，两边要同批合入。
- `CodeReference` 的旧初始化方法标 deprecated（`renamed:` 到新签名），仍可用一个版本。
- `images` 标 deprecated；进程内模式行为不变。
- `CodeReference.Route` 去掉了原设计里的 `selectorReference` 与 `classReference`（并进 `pointerSlot`）。`Route` 是本提案新增的，没有已发布的使用方。

**按层拆分不破坏源码**：`CodeLocation`、`IndirectCallEvidence`、`ReceiverClassHint` 搬到下层模块，`CodeReference.Kind` 从嵌套 enum 改成指向核心层 `CodeReferenceKind` 的 typealias；顶层 `@_exported import` 两个下层模块，`import CrossReferenceAnalysis` 的代码照旧看得到同样的名字、同样的 case。类型的完整名字（模块前缀）变了，只影响按类型名做序列化的代码；RuntimeViewer 在第 2 步核对一次它跨进程传交叉引用结果时怎么编码。

其余全是新增。

### ABI 兼容性

不适用 —— 本库以 SPM 源码分发，使用方每次重新编译。

### 下游影响

- 本仓库内：`SwiftThunkAnalysis` 改用抽出的模块（行为不变，由守护测试保证）；`SwiftSectionKit` 与 `swift-section` 新增对 `CrossReferenceAnalysis` 的依赖。
- RuntimeViewer：见上；另有第 8、9 步的 CLI 与 MCP。它的常驻索引（`CodeReferenceIndex`）多出 `route`，第 5 步量出 `approximateByteCount` 的增量写进模块文档。
- swift-decompiler：依赖本库的 `SwiftThunkAnalysis` 时只经它的公开接口，抽取不改公开接口；第 3 步核对一次。
- MachOKitExtensions 的两次迁移（读取层、基础模块）：都是原名迁入，import 不变；核心层与 ObjC 层只许 import 将来 MachOKitExtensions / MachOObjCSection 里也有的模块，正是以这两次迁移之后的样子为准。若迁移先合进 `next`，第 2、3 步照新的包依赖写 `Package.swift`。
- 之后的迁移提案：本提案落地后，核心层、`CodeAddressResolution` 与 ObjC 层的文件应能原样搬走、只改 import 与模块名；做不到的地方（例如进程内构造器的 Darwin 条件编译）记进那份提案的调研。

### 文档与示例

README 的 CLI 一节、`swift-section-cli` skill、四个模块参考文档（`CrossReferenceAnalysis` 更新，`CrossReferenceCore`、`CrossReferenceObjC`、`CodeAddressResolution` 新增）、`AGENTS.md` 的模块层级图、愿景第 6 条、RuntimeViewer 的 CLI 使用指南与 `runtime-viewer` skill。

## API 演进与废弃策略

- `CodeReference.init(function:instructionAddress:kind:target:isRuntimeHelperCall:)` 与 `CrossReferenceAnalyzer.images`：标 `@available(*, deprecated, …)` 保留一个次版本，下一个次版本删除。
- `ThunkAddressSpace`、`CacheImageResolver` 是 package 级，直接搬走，不留旧名。
- 搬到下层模块的公开类型不改名、不留转发：经 `@_exported import` 原名可见。
- 三层之间的识别器与记录协议是 package 级，这一步不承诺稳定；迁移提案把它们变成公开 API 时再按 `apple-style-api-design` 定形。
- 本库仍在 0.x，随下一个次版本发布，不需要大版本。

## 落地步骤

1. **读取抽象，行为不变**（已完成） —— 改动地图里的 `CrossReferenceMemory`、`InProcessCrossReferenceMemory`、分析器与各扫描文件的读取改造、`StoredPointer`、`Package.swift`。
   - 行为：`inProcessReferenceTablesAreUnchangedForAppKitSwiftUICoreAndFoundation`（改造前后逐条比对整表）
   - 行为：`crossReferenceAnalysisReadsMemoryOnlyThroughCrossReferenceMemory`（源码扫描：分析模块里不再有 `UnsafeRawPointer(bitPattern:)`）
2. **按层拆分，行为不变**（已完成） —— 改动地图里步骤列为 2 的各行：建 `CrossReferenceCore` 与 `CrossReferenceObjC`，识别器、会话与三个记录协议，寄存器标记，`CodeImageSet`，函数表与回退名按层拆开，运行时名单分到两层，门面改为组合两个识别器，`@_exported import`，边界测试，三份模块文档、`AGENTS.md`、愿景第 6 条。先量拆分前的基准，拆完在同一台机器上再量。
   - 行为：`inProcessReferenceTablesAreUnchangedForAppKitSwiftUICoreAndFoundation`（沿用第 1 步的整表比对，AppKit、SwiftUICore、Foundation 逐条相同；比较前去掉类型搬家带来的拼写差异）
   - 行为：`aFunctionStartingOutsideTextScansWhereItLies`（第 1 步引入、吞吐基准发现的下溢陷入的复现）
   - 行为：`crossReferenceLayersImportOnlyWhatTheirFutureHomesProvide`（源码扫描：核心层、ObjC 层的 import 都在白名单里）
   - 行为：`crossReferenceCoreSpellsNoRuntimeSymbolName`（源码扫描：核心层没有 `objc_` / `swift_` 开头的字面量）
   - 行为：`aRecognizerDefinedInTestsPlugsInWithoutChangingTheCore`（测试里定义一个只认某个 C 函数的识别器，它的引用出现在结果里——扩展点确实开放）
   - 行为：`selectorQueriesLookUpNoSwiftType`（只查 selector 时 Swift 会话不建任何镜像的类型索引；ObjC 会话照旧为发送的类字面量接收者读类对象，与拆分前一致）
   - 行为：`scanThroughputAfterTheLayerSplitIsRecordedInTheModuleDocument`（不是断言：拆分前后整 cache 建表与两条查询的耗时写进模块文档，增幅超过 5% 时按「详细设计」的退路处理后再量）
   - 行为：`publicNamesStillResolveThroughCrossReferenceAnalysis`（只 `import CrossReferenceAnalysis` 的测试文件能用 `CodeLocation`、`CodeReference.Kind.call`、`ReceiverClassHint.methodReceiver`）
3. **抽出 `CodeAddressResolution`**（已完成） —— 四个新类型、`MachOThunkEnvironment` 改用它们、删 `ThunkAddressSpace`、模块文档。
   - 行为：线程读取的结果不变——由 `SwiftThunkAnalysisTests` 全套守着（归档 iOS 设备 cache 的 stub island、归档 macOS cache 的合并 accessor、模拟器运行时、独立文件），不另写测试
   - 行为：`stubChainCarriesTheSelectorRegisterConstantOfACacheSharedSelectorStub`（`x1` 的常量与最终的 `objc_msgSend` 副本；模块本身不认识 selector）
   - 行为：`stubChainRecordsEveryStubIslandHop`
   - 行为：`slotResolverMatchesTheProcessForEveryGlobalOffsetTableSlotOfAppKit`（含指向 AppKit 自己的类对象的槽）
   - 行为：`slotResolverResolvesStandaloneBinds`
   - 行为：`cacheImageLocatorFindsTheImageAnAddressLiesIn`
   - 行为：`aFunctionLoadingAGlobalIsNoSlotStub`（`ARM64Trampoline` 的修复，见决策日志）
4. **文件模式的分析器**（已完成） —— `CodeImage` 与 `ImageLinkEdit`、`FileCrossReferenceMemory`、两个新构造器、各层按镜像读取的文件模式。
   - 行为：`fileModeMatchesInProcessReferencesOnTheRunningSystemCache`（同一个 cache 两种模式逐条比对，镜像取 AppKit、SwiftUICore、Foundation）
   - 行为：`fileModeNamesFunctionsAsTheProcessDoes`、`fileModeReadsTheFallbackNameSourcesAsTheProcessDoes`（函数名与 ObjC 方法表、Swift 元数据两种后备来源两种模式逐条一致）
   - 行为：`fileModePrefiltersSelectorsAsTheProcessDoes`
   - 行为：`fileMemoryDecodesSlotsAsMachOKitDoes`（v5 与没有 slide info 的模拟器 cache，逐槽与 MachOKit 一致）
   - 行为：`archivedCacheFindsBothCallersOfPasteboardWritingItemProvider`（27.0 与 27.2；卷不在时跳过）
   - 行为：`archivedCacheFollowsStubIslandsForSelectorSends`
   - 行为：`standaloneAppResolvesImportedAndSelfBoundSymbols`
   - 行为：`standaloneExecutableResolvesRebasesAndObjectiveCStubs`（`SlotResolver` 的修复，见决策日志）
   - 行为：`fileModeScansExceptionCleanupCodeAfterReturn`（`retab` 之后、没有函数起点的异常清理代码也要被扫到）
   - 吞吐：`ScanThroughputBenchmarkTests` 加 `CROSS_REFERENCE_BENCHMARK_DYLD_CACHE`，实测写进模块文档
   - 核对：卷上没有 Finder 26.5.2，也没有 2026-11-18 那次的标准答案与生成脚本；按原法重做要新写 `otool -tV` 加寄存器跟踪的脚本，留给用户看过之后再跑。改做抽样：ControlCenter 26.7 的文件模式结果（`StandaloneFileReferenceDumpTests` 导出）与 IDA 逐函数对照，见决策日志。
5. **新引用种类与路线**（已完成） —— 解码器的 `ldrsw` / 32 位 `ldr`（含字面量形式）、核心层的字符串、路线与对导入符号的数据引用、ObjC 层的 ivar、三个 target、`Route`、表键、常驻索引编码。RuntimeViewer 的穷尽 switch 挪到第 8 步，与 RuntimeViewer 的其余改动一起做。
   - 行为：`instanceVariableOffsetLoadsBecomeInstanceVariableReferences`（带符号与剥了符号两种）
   - 行为：`stringReferencesAreRecordedOnlyWhenRequested`
   - 行为：`constantStringReferencesCarryTheirCharacters`（8 位与 UTF-16 两种）
   - 行为：`everyReferenceCarriesTheRouteItTook`、`inProcessReferencesCarryTheirRoutes`；iOS 设备 cache 经 stub island 的发送路线是 `stubIsland`（`archivedCacheFollowsStubIslandsForSelectorSends`）
   - 行为：`referenceIndexRoundTripsNewTargetsAndRoutes`
   - 行为：`decoderDecodesThirtyTwoBitLoadAndLoadSignedWord`
   - 行为：`pageAlignedClassObjectMaterializationIsAReference`（`adrp; add #0`，在运行中的 cache 里找）
   - 行为：`swiftLargeStringLiteralPointsAtItsCharacters`（`adrp; add; sub #0x20`）
   - 对导入符号的数据引用由 ControlCenter 的导出核对（`_OBJC_CLASS_$_CALayer` 一类）
6. **地址符号化**（已完成） —— `AddressSymbolication` 与 `symbolication(of:)`、`symbolication(of:inImageAt:)`；核心层的 `AddressPlace` 判断结构，门面补含义。
   - 行为：`symbolicatesSwiftUICoreAuthStubsByTheirSlotsNotTheirIndirectSymbols`（26.7 SwiftUICore 的全部 `__auth_stubs` 都解到函数或导入名；其中 5 个经 `ipsw dyld macho --stubs` 独立核对的桩，间接符号表给的是错名，正是 `dyld_info` 标错的那批）
   - 行为：`symbolicatesCacheSharedMessageSendStubToItsSelector`
   - 行为：`symbolicatesGlobalOffsetTableSlotToItsBoundSymbol`
   - 行为：`symbolicatesAnAddressInsideAnUnnamedFunctionWithItsFallbackName`
   - 行为：`symbolicatesAnUnmappedAddressAsUnmapped`
   - 行为：`symbolicatesStringsAndObjectiveCSlots`（C 字符串、`CFString`、`__objc_ivar` 的偏移变量）
7. **`swift-section refs` 与 `symbolicate`**（已完成） —— SwiftSectionKit 的三个类型、两个命令、选项组、登记、README、skill。
   - 行为：`refsListsCallerRowsForASelectorInAnArchivedCache`
   - 行为：`refsJSONUsesHexadecimalStringAddresses`
   - 行为：`refsMarksTruncatedResultsWhenLimited`
   - 行为：`refsRequiresExactlyOneQuery`
   - 行为：`symbolicateAcceptsSeveralAddresses`
   - 行为：`refsListsTheCalleesOfAFunction`、`refsListsTheCallersOfASymbol`、`refsListsTheReferencesToAClass`、`refsReadsAStandaloneFatExecutable`、`symbolicateJSONUsesHexadecimalStringAddresses`
   - 行为：`crossReferenceCommandsWriteOnlyThroughStandardStreamOutput`（沿用仓库已有的输出扫描测试）
8. **RuntimeViewer CLI**（已完成） —— 引擎侧符号化命令、四个子命令、协议版本、文本显示、使用指南、skill。
   - 行为：`callersCommandJSONMatchesTheMCPResponseFields`
   - 行为：`commandLineProtocolVersionIsThree`
   - 行为：`symbolicateCommandWorksOnTheLocalSource`
9. **RuntimeViewer MCP 与收尾**（已完成） —— 四个 MCP 工具；本库的 `ProjectEvolutionLog.md`、`Glossary.md`；RuntimeViewer 的 `Evolutions/README.md` 加 `cross-repository draft` 一行，0056 的暂缓表里把第 4 步那一行指向本提案。
   - 行为：`callersToolReturnsAPartialResultAfterThirtySeconds`
   - 行为：`symbolicateToolRequiresAWindowIdentifier`

**收尾时必须判断两件事**（判断结果写进决策日志，不允许沉默跳过）：

- **要不要配套专题文章** —— 预判要写一份 CLI 使用指南：「地址一律未滑动」「字符串引用要打开才记录」「截断标记」这几条契约在签名里看不出来。模块参考文档本身按约定更新。
- **有没有引入新术语** —— 预计有「地址符号化（symbolication）」「引用路线（route）」「识别器（recognizer）」，以及 stub island、cache 共用桩若术语表里还没有。

## 后续项

- **全面核对没有重做**：2026-11-18 那次用 `otool -tV` 加寄存器跟踪独立生成标准答案、再对照 IDA 的做法，生成脚本与 Finder 26.5.2 都已不在卷上。第 4 步改为 ControlCenter 26.7 三个函数的抽样核对。重做要新写生成标准答案的脚本，先给用户看过再跑。
- **Swift 类经 ObjC ivar 列表登记的偏移变量没有收**：它们是 `__data` 里的 Swift 字段偏移全局量，不在 `__objc_ivar`（ControlCenter 的 `BentoBackdrop.maskLayer` 就是这样）。
- **ivar 名字的两个来源有 23 条之差**（共约 182 万条 ivar 引用），没有逐条追。
- **RuntimeViewer**：三种新目标（ivar、C 字符串、常量字符串）在界面里先不显示；App 工程本身没有构建过，只在沙盒里编过 Core、CLI 与 MCP 三个包；它跟的是本库的 `next` 分支，提交的 `Package.resolved` 已同日抬到本库的 `a98cbc15`。交叉引用测试模块整体并发跑时「分析器换新后要重新读名字」那组会超时，是基线就有的问题。
- **核心层与 ObjC 层迁出本库**：另写迁移提案，要定的事见「非目标」第一条。

## 决策日志

| 日期 | 变更 | 说明 |
|------|------|------|
| 2026-11-18 | Created as Draft | 调研了过去逆向卡住最久的地方，「跨镜像查谁用了它」与「地址起名」排在最前；用户选定先做这一块，并把它定为愿景《不依赖 IDA 的逆向》的第一步，伪代码不再是默认读物，IDA 退为后备 |
| 2026-11-18 | 参照 Binary Ninja | 用户指出 IDA 的交叉引用弱、Binary Ninja 强。调研了它开源的 shared cache 视图与 ObjC 插件：采纳桩按节名判定与 `j_` 式命名、引用按来源种类标注（本提案的 `route`）、地址写成十六进制字符串、结果带截断标记；selector → IMP 的数据引用留给愿景第 3 阶段 |
| 2026-11-18 | Binary Ninja 6 的 MCP | 用户升级到 Binary Ninja 6.0。它的 GUI 内 MCP 服务器 Personal 版也有，可作第 3 步的结果核对；无界面版仍要 Commercial / Ultimate，所以不作后端 |
| 2026-11-18 | 实测后改用 IDA 核对 | 在 Finder 与 ControlCenter 上实测：代码引用召回 IDA 两跳 99.4%、Binary Ninja 经 MCP 67.6%。第 3 步的核对改以独立生成的标准答案为准、IDA 对照、Binary Ninja 补充；双方的三处盲点（页对齐类对象、Swift 大字符串、`retab` 后的清理代码）加成测试 |
| 2026-11-18 | 改为按层拆分、分两步迁移 | 用户提出把核心放进 MachOKitExtensions、ObjC 与 Swift 各管自己的部分。核实了两份 MachOKitExtensions 迁移提案都已 Accepted，核心层要的依赖届时都在那里；难点在扫描器里 ObjC 与 Swift 的识别穿插在五个时机。用户在「一步到位写进三个仓库」与「先在本库拆层、量完再迁」之间选了后者。本提案因此新增第 2 步：拆成 `CrossReferenceCore`、`CrossReferenceObjC`、`CrossReferenceAnalysis` 三个模块，经识别器与记录协议相接，核心不认识任何语言，源码扫描守住 import 边界，公开模型与 API 留在顶层不变；`MachOAddressResolution` 改名 `CodeAddressResolution`，下层模块在本库里的名字刻意不同于落脚处，避开同名模块与 `MachO` 前缀两条约束；`Route` 去掉按节区分的两个 case。原第 2–8 步顺延为第 3–9 步（上面几行里的「第 3 步」指现在的第 4 步）。真正的搬迁另写迁移提案 |
| 2026-11-18 | Accepted | 用户批准，开始实现 |
| 2026-11-19 | 第 1 步完成 | 读取协议按分析器地址空间里的地址读（进程内就是运行时地址），而不是原设计的「未滑动地址 + 镜像下标」：现有代码处处用运行时地址，这样改动最小，文件模式给每个镜像定一个滑动量即可。进程内实现不检查映射，信任调用方——此前的直接读也不检查，可能读到未映射地址的地方本来就先问 `isMapped`。「整表不变」做成靠环境变量驱动的 A/B 测试（`ReferenceTableDigestTests`）：基线用 `git archive` 导出、拷入同一个测试文件生成摘要，候选与之比对；两边都要带 `USING_LOCAL_DEPENDENCIES=1`，因为 `next` 已用到 swift-demangling 未发版的 API。2026-11-19 在 Ultra 上 AppKit、SwiftUICore、Foundation 三个镜像逐条一致 |
| 2026-11-19 | 第 2 步完成 | 按层拆分落地，与原设计的出入：识别器没有共同协议，两层各是具体类型，核心只认会话与记录协议（门面本来就认识两个具体的层）；角色声明自己会不会代替调用、要不要事后记录，扫描器只调用需要的那个方法，调用计划里的角色用 `SIMD4` 存，一次扫描最多四个会话；运行时库的规则（`RuntimeLibraryRules`）由门面交给核心，建镜像集时只扫一遍运行时库的符号；各层按镜像的缓存挂在函数表上作附件，函数表在它那一遍里记下各节供 ObjC 层用；`CodeReference.Kind` 改成核心层 `CodeReferenceKind` 的 typealias。测试 `selectorQueriesSkipClassAndTypeLookups` 改为 `selectorQueriesLookUpNoSwiftType`：ObjC 会话为发送的类字面量接收者照旧读类对象，与拆分前一致。整表对照：`String(describing:)` 给枚举负载里的类型加模块前缀，`Kind` 的拼法也变了，摘要在比较前去掉这两处；归一化后 AppKit、SwiftUICore、Foundation 逐行一致，整 cache 4,116 个系统镜像的引用数逐个一致 |
| 2026-11-19 | 修掉第 1 步引入的陷入 | 吞吐基准扫整个 cache 时触发：第 1 步把读指令改成以 `__text` 起点为基的偏移，有些镜像的符号表把 `__text` 的函数起点放在节起点之下，减法下溢陷入。改回按地址经读取层读，`instructionPointer(at:count:)` 由调用方给条数。复现测试 `FunctionStartOutsideTextTests` 修复前陷入、修复后通过。同类排查：`CodeReferenceIndex` 的编码本就先比较再用 `&-`，没有别处 |
| 2026-11-19 | 吞吐优化 | 第一次量（Ultra，release，对 `next`）超了 5%：整 cache 建表 +8%、`init` 调用者 +8%、`makeKeyAndOrderFront:` +11%、建分析器 +24%。逐项采样后改了四处：读槽先做区间排除再查认领表（原来就是这个顺序）；运行时库的符号只扫一遍；调用计划不再持有数组（复制计划时的引用计数）、只调用角色需要的方法；会话与收集器里热路径上的可变属性标 `@exclusivity(unchecked)`（它们只在一个线程上用）；函数表记下各节，ObjC 层不再为每次扫描遍历一遍 load command。另给读取层加了两个批量读接口（`pointers(inSlotsAt:count:)`、`readablePointers(at:)`），selector 预筛按 256 个槽一块读，不再每个槽一次 existential 调用 |
| 2026-11-19 | 吞吐验收 | 同一台 Ultra、release、三方交替各三轮取最好：整 cache 建表 `next` 2.42 / 第 1 步 2.54 / 第 2 步 2.52 秒，`init` 调用者 1.70 / 1.71 / 1.74 秒，`makeKeyAndOrderFront:` 调用者 0.36 / 0.37 / 0.38 秒。第 2 步相对拆分前（第 1 步）在 −0.5% 到 +3% 之间，满足 5% 的验收线，不必退到泛型特化；整表多出的约 5% 来自第 1 步的读取层，记进模块文档。debug 下交叉引用全套 99 个测试通过 |
| 2026-11-19 | 第 3 步完成 | `CodeAddressResolution` 按设计抽出，另有两处细节：它依赖 `MachOReading`（`MachOFile.readElements`，设计里说的读取层）；`CacheImageLocator` 不自带 `SharedCache`，按镜像共用一个 locator 由线程读取器在 `thunkResolution` 组里做，本模块因此不依赖 `MachOCaches`，将来能原样搬走。`SwiftThunkAnalysis` 不再直接依赖 `ARM64InstructionDecoding`。行为清单对齐实际测试：抽取前后结果不变由 `SwiftThunkAnalysisTests` 全套守着；「本镜像类对象在 GOT 里」并进 AppKit 全部 GOT 槽与进程逐个比对的测试；独立文件的 self-bind 在 `SlotResolver` 里只是名字，换成地址是第 4 步文件模式的事，那条行为由第 4 步的 `standaloneAppResolvesImportedAndSelfBoundSymbols` 覆盖 |
| 2026-11-19 | 修掉跳板把普通函数认成 GOT 桩 | 写 `stubChainRecordsEveryStubIslandHop` 时发现：iOS 26.3.1 设备 cache 里 SwiftUI 经 stub island 调到 UIKitCore 的 `UIHostingViewBase.viewGraph` getter，它开头是 `adrp x8; ldr x8, [x8, #0xb10]; ldr x0, [x20, x8]`（读一个字段偏移），`ARM64Trampoline` 读到 `ldr` 就认定是从槽里取目标的桩，链落到 `sharedRegionStart + 0x38`。这是 `next` 上就有的旧 bug。改成载入之后必须紧跟一条经同一寄存器的非调用跳转（三种 GOT 桩都是这个形状），复现测试 `aFunctionLoadingAGlobalIsNoSlotStub` 修复前四处断言全红、修复后通过。影响面：进程内扫描器只对不落在任何镜像里的地址认跳板，结果不变；线程读取器只在调用目标落在别的镜像、又不是 accessor 或运行时入口时才走到它，原来得出 `unknown`，现在也是。真正会受影响的是第 4 步的文件模式，它经同一个解析器一跳一跳地跟，所以在这一步修掉 |
| 2026-11-19 | 第 4 步：镜像抽象 | 每个镜像改由核心层的 `CodeImage` 描述，`__LINKEDIT` 的表经读取层按地址读（`ImageLinkEdit`），桩按 `S_SYMBOL_STUBS` 的 `reserved1/2` 与 `ARM64Trampoline` 自己读，不再经 MachOKit 各读取器一套的 `symbols64`、`stubs(in:)`、`functionStarts`。读取器专属的 API 只在 ObjC 层（MachOObjCSection）与 Swift 层（MachOSwiftSection）里经 `asMachOImage` / `asMachOFile` / `MachOSwiftSectionRepresentableWithCache` 打开。进程内结果不变：交叉引用全套 100 个测试与整表摘要照旧，吞吐与第 1 步相比 −3% 到 +3% |
| 2026-11-19 | 第 4 步：文件读取层的形状 | `FileCrossReferenceMemory` 是值，以 `unowned(unsafe)` 引用镜像集持有的存储，区间表放在手动分配的缓冲区。第一版是类，整 cache 建表 37 秒（进程内 2.5 秒）：每次经 existential 读都复制读取层、计一次数，`FullDyldCache.cacheAndFileOffset(for:)` 每次还新建子 cache 对象、重读 slide info。按 mapping 预取 slide info、v5 在读取层里直接解之后 16.5 秒，改成值之后 2.6 秒，与进程内持平。v2、v3 的快速路径写过又删了：卷上没有能验证它们的 arm64 cache（模拟器 cache 没有 slide info），只留 v5，其余交给 MachOKit |
| 2026-11-19 | 第 4 步：API 与设计的出入 | 两个构造器先不带 `recordingStringReferences`，第 5 步加字符串引用时一起加。失败时抛 `FileAnalysisError`（带 `Code` 的结构体，眼下只有 `unsupportedArchitecture`）。`images` 不标 deprecated：进程内的宿主与测试读的是只有 `MachOImage` 给得出的东西（slide、header），`imagePaths` / `imageCount` 替代不了，标了只会把它们推向无处可去；文件模式下它为空写在文档注释里。一组独立文件按 dyld 的做法错开地址。ObjC 层把按名字导入的 `_objc_msgSend` / `_objc_msgSendSuper2` 认成发送：不带 libobjc 分析一个 app 时它们就是这样到达的 |
| 2026-11-19 | 修掉 `SlotResolver` 把 rebase 偏移当地址 | 抽样核对 ControlCenter 时发现：几乎所有 objc 桩都没认出 selector。MachOKitExtensions 对独立文件的链式 fixup 给的是「相对首选加载地址的偏移」，`SlotResolver`（承自线程读取器的 `rebaseTargetAddress`，注释写着「独立文件给的是目标地址」）直接当地址用——dylib 的 `__TEXT` 在 0，两者相同，夹具都是 dylib，所以没被测到；可执行文件的 `__TEXT` 在 0x100000000，槽解出 0x798 而函数在 0x100000798。改为按 `__TEXT` 加偏移（`ImageAddressSpace.address(forHeaderOffset:)`）；没有链式 fixup、靠 opcode rebase 的旧文件，MachOKitExtensions 不解，文件读取层直接用槽里的值。复现测试 `standaloneExecutableResolvesRebasesAndObjectiveCStubs` 修复前四处断言全红、修复后通过。同类排查：别处（`MachOPointers`、线程读取器的描述符读取）都把这个结果当 MachOSwiftSection 自己口径的 offset 用，是一致的。修复后 ControlCenter 的发送从 967 条到 4,909 条，无法识别的调用从 3,933 条到 1 条 |
| 2026-11-19 | 第 4 步完成 | 吞吐（Ultra，release，归档 macOS 27.2 cache，三轮最好）：建分析器 0.14 秒，整 cache 建表 2.58 秒（1.263 亿条），`init` 调用者预筛 0.04 + 扫描 1.74 秒，`makeKeyAndOrderFront:` 0.11 + 0.34 秒；进程里第一次查询 0.5 秒与 1.9 秒。读运行中的 cache 文件与外置卷上的归档一样快，远低于愿景里「冷启动整 cache 查询超过 60 秒就提前落盘」的线。核对改为抽样：ControlCenter 26.7 的三个函数（ObjC 发送与 super 发送、Swift 元数据访问器与类型引用、`objc_allocWithZone` 与 `init`），IDA 反汇编里的直接调用与发送本库逐一都有；差异两类——经 GOT 槽读别的镜像的类（槽里是 bind）不记，补进第 5 步；直接经 GOT 槽的 `blraa` 记成间接调用，进程内同样如此。按 2026-11-18 的做法重做全面核对，需要新写生成标准答案的脚本，留给用户 |
| 2026-11-19 | 文件读取层不掩地址 | `AddressMaskScanTests` 不许库里出现自定义的地址掩码常量。文件读取层的 `addressMask` 改为不掩（解出的槽本来就是干净地址）；slide info v5 的 34 位 `runtimeOffset` 是格式字段不是掩码，在扫描用例里加了一条只减不增、写明是哪个字段的白名单 |
| 2026-11-19 | 第 5 步完成 | 与设计的出入：路线的最后一种叫 `indirect`，不叫 `authenticatedIndirect`——不带认证的 `blr` / `br` 也得有路线，认证与否已在 `IndirectCallEvidence` 里。Swift 大字符串不需要 Swift 层专门认：`add` 算出的正是字符串起点，核心在那里记下；只是「减法算出的地址」从不当作字符串，否则 `sub #0x20` 之后的地址会落进前一个字符串中间。ivar 只认 `__objc_ivar` 里的偏移变量，即父类不在本镜像的 ObjC 类（父类是 `NSObject` 时 clang 用常量偏移、根本不载入）；Swift 类经 ObjC ivar 列表登记的偏移变量是 `__data` 里的 Swift 字段偏移全局量，不在 `__objc_ivar`，没有收（ControlCenter 的 `BentoBackdrop.maskLayer` 就是这样），留作后续。对导入符号的数据引用记成 `.importedSymbol(name:)`、`kind == .reference`，不另外按名字认成 ObjC 类引用：类引用的 target 要带位置，导入的类没有；查一个类的全部引用时，调用方同时查 `_OBJC_CLASS_$_<类>`。查询里含字符串键时，那次扫描照样找字符串，不受分析器开关限制。32 位载入另认 ld64 改写出的字面量形式（`ldrsw xt, label`）。RuntimeViewer 的穷尽 switch 挪到第 8 步：它经远端版本依赖本库，本库发版之前不受影响 |
| 2026-11-19 | 第 6 步完成 | 与设计的出入：另有 `symbolication(of:inImageAt:)`——一组独立文件各留自己的地址，两个文件可能都有同一个未滑动地址（进程内，链接在 0 的测试 bundle 就占着 0x10），不指定镜像时取第一个有它的镜像，cache 优先。`Meaning` 多一个 `.data`：映射着、但不是函数、桩、槽、字符串，其下也没有符号，不能说成未映射。槽里的东西按节说：selector 引用给 `.messageSend(selector:receiver: .unknown)`（目标类型里没有单独的 selector），protocol 引用给协议名 `.cString`，GOT 给函数、类、Swift 类型或导入名，`__objc_ivar` 给 ivar。结构由核心层的 `AddressPlace` 判断（函数体、本镜像的桩、镜像之间的跳板链、槽、字符串、最近的符号），ObjC 层的 selector 桩、类与 ivar、Swift 类型与无符号函数的名字在门面补上。符号化用留存的函数表（第一版用不留存的，问 26.7 SwiftUICore 的全部桩花了 207 秒，改后 0.9 秒）。原计划的「对照 MachOKit 的 `Stub.indirectSymbolIndex`」不成立：那批桩上 MachOKit 读间接符号表与 `dyld_info` 一样标错，改为用 `ipsw` 独立核对的 5 个桩钉住、其余全部桩都要解出目标 |
| 2026-11-19 | ivar 名字改经读取层读 | 第 5 步的 ivar 名字第二来源经 MachOObjCSection 遍历类，每个类都重走一遍加载命令，整 cache 建表因此慢了 30%（3.25 秒）。改为从 `__objc_classlist` 起经读取层读 `class_ro_t` 与 ivar 列表（已 realize 的类经 `class_rw_t` 的第二个字，指针剥签名），两种读取器一套代码；整表回到 2.57–2.66 秒，比第 4 步多约 4%，多出的正是 182 万条 ivar 引用。两条路给的名字有 23 条之差（共约 182 万条），没有逐条追 |
| 2026-11-19 | 第 7 步完成 | 与设计的出入：`refs --function` 多一个 `--function-image`——一组文件各有各的地址，两个链接在 0 的 dylib 会在同一地址都有函数，此时报错要求指名；`symbolicate` 的文件输入是可重复的 `--file`（位置参数是地址），`--in-image` 指地址属于哪个镜像。胖文件必须给 `-a`，沿用 README 自 0.10.0 起「不默默挑切片」的约定（实现时一度自动挑 arm64e，发现与约定相悖后改回）。`--string` 不需要打开 `recordingStringReferences`：按键查询本来就找字符串。`--class` 先找 `_OBJC_CLASS_$_` 符号，找不到（cache 里多数私有类）再读各镜像的类表，并按类对象位置过滤同名类。`--symbol` 要求名字是函数的起点，变量报错；没有任何镜像定义时按导入名找（一组文件里调用外部库的情形）。为此门面加了 `locations(ofSymbolNamed:among:)`（导出表加符号表），`CodeFunction.Name` 加了 `spelling`。JSON 键排序、地址一律十六进制字符串，每条引用多一个 `isRuntimeHelperCall`。请求的 `run(output:)` 不收环境：不往产物里盖任何东西 |
| 2026-11-19 | 修共用键集合的争抢 | 写 `refs` 时发现：多个线程并发扫描、共用同一个键集合时，`ReferenceCollector.keep` 每检查一条引用都对该集合 retain/release 一次（`tableKey.map(keptKeys.contains)` 把集合捕获进闭包），28 个核争一个引用计数，整 cache 查 `init` 的调用者用了 152 秒、查 `makeKeyAndOrderFront:` 11.6 秒。`next` 上的 `ReferenceScanner.keep` 是同一写法，RuntimeViewer 并发查调用者时也共用一个键集合，是基线就有的问题；基准每个镜像现建一个集合，所以没暴露。改为收集器各留一份自己的拷贝、去掉闭包捕获：两条查询降到 2.2 秒与 1.05 秒（release CLI，含建分析器与起名）。基准的调用者查询改成共用一个键集合，与真实调用方一致，今后回归能在数字上看出；改后 `init` 的扫描 1.69 秒，与原来每镜像一个集合时相同 |
| 2026-11-19 | 第 8 步完成 | 与设计的出入：引擎侧加两个命令而不是一个——符号化之外还有「按名字定位符号」（`crossReferenceLocateSymbol`，用本库新加的 `locations(ofSymbolNamed:among:)`），因为查询主体没有「符号」这一种，符号名要先在引擎进程里换成函数地址。目标写法的解析放进 `RuntimeViewerCrossReferences` 的 `RuntimeCrossReferenceTargetResolution`，CLI 与 MCP 共用；按名字找类型由调用方传入，各前端沿用自己的查找规则。CLI 的 `--json` 与 MCP 的每行字段同出 Core 的 `RuntimeCrossReferenceRow` / `RuntimeAddressSymbolicationRow`（MCP 的响应类型要用 SwiftMCP 的 `@Schema`，Core 里不能用，所以 MCP 一侧逐字段照抄、测试钉住键名一致）。三种新目标（ivar、C 字符串、常量字符串）在 RuntimeViewer 里先不显示，照源码兼容性一节的约定返回空。失败代码新增 `targetNotFound` 与 `crossReferencesUnavailable`。RuntimeViewer 分支从远端 `next` 切出：本地 `next` 当时有十几个别的会话未推送的提交，从它切会在推送功能分支时把那些工作一并公开 |
| 2026-11-19 | 第 9 步完成 | MCP 四个工具照现有工具带 `windowIdentifier`；30 秒的等待做成可单测的 `MCPBridgeServer.references(within:_:)`：边查边收进度里的引用，到时取消查询、带着已有结果返回 `isComplete: false` 与说明（已扫完的镜像有缓存，再调一次接着扫）。RuntimeViewer 的提案索引加了 cross-repository draft 一行，暂缓表里第 4 步那一行指向本提案，0056 的决策日志记了一行 |
| 2026-11-19 | 渲染 A/B 验证全部一致 | 桩与槽的解析从 `SwiftThunkAnalysis` 抽成共用模块，动到了读取层，按 AGENTS.md 跑系统框架渲染 A/B：基线是开工时的 `next`（f8b25d2a），三条读取路径共 84 对 dump 与 interface 逐字节一致（归档 cache 15.5 与 26.6、iOS 15.5 至 26.5 模拟器、进程内） |
| 2026-11-19 | RuntimeViewer 交叉引用模块的并发超时是基线就有的 | 在沙盒里对本分支跑 RuntimeViewer 整个交叉引用测试模块（82 条并发），「分析器换新后要重新读名字」的两条等了 60 秒没等到；基线（RuntimeViewer 远端 `next` 加本库 `next`）整模块跑同样有其中一条在同一行失败，两边单跑这一组（18 条）都在 41 秒内全过。是会话队列在整模块并发时被前面的准备工作占满，与本次改动无关，没有修 |
| 2026-11-19 | 实现完成，待用户看过后收尾 | 九个落地步骤都已完成。本库全量测试（跳过 IntegrationTests）2,993 个零失败；渲染 A/B 84 对一致；RuntimeViewer 一侧在沙盒里对本分支编过 Core、CLI 与 MCP 三个包，新测试全过，App 工程本身没有构建。文档判断：配套使用指南不另写——CLI 的用法与契约写在 README、`swift-section` 插件的 `references/cross-references.md` 与 RuntimeViewer 的 `Guides/CommandLineInterface.md`，实现细节在三份模块文档；新术语「地址符号化」「识别器」「引用路线」「stub island」已登记进术语表。两个仓库的功能分支已在本地合进各自常驻的 `next` 检出，没有推送 |
| 2026-11-19 | Implemented，取号 0097，两个仓库合进各自的 `next` 并推送 | 用户验收后批准收尾。验收在 JHs-Mac-Studio-Ultra 上用功能分支的 release 版 CLI 做（Xcode 27.2，本地兄弟依赖）：运行中系统 cache 里 `makeKeyAndOrderFront:` 的 439 处发送，0.7 秒；归档 27.0 与 27.2 cache 里 `UINSPasteboardWritingItemProvider` 的两个调用者；cache 共用 `objc_msgSend` 桩解成 selector（`ipsw dyld a2s` 对同一地址只回 `?`），GOT 槽、类对象与未映射地址的符号化；TextEdit 胖文件带 `-a arm64e` 找到 4 处发送，不带时按约定报错。落地前验证沿用「实现完成」一行的结果，之后只改了文档。文档判断不变：不另写使用指南，配套文档登记在头部，新术语已登记。正文去掉了段内硬换行，内容不变。没做完的列在「后续项」 |
| 2026-11-26 | 补做全面核对 | 按 2026-11-18 的方法复测 0.25.0：标准答案与选目标的代码从当次对话记录原样取回，复现出同一批 120 个目标。代码引用召回 90.3%，IDA 一次查询 97.0%、两跳 99.4%。数字与漏报原因写进愿景「我们选的方向」第 1 条的复测段，修复另起提案 [draft-cross-reference-recall-gaps](draft-cross-reference-recall-gaps.md)。上文「全面核对没有重做」一段留下的缺口至此补上 |
