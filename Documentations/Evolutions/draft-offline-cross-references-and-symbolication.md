# Draft - 交叉引用与地址符号化扩展到磁盘文件和归档 dyld cache

- **状态**: Draft
- **作者**: JH
- **创建日期**: 2026-11-18
- **最后更新**: 2026-11-18
- **所属愿景**: [不依赖 IDA 的逆向](../Visions/ReverseEngineeringWithoutIDA.md)（第 1 阶段）
- **关联提案**:
  - [0072 cross-reference-analysis](0072-cross-reference-analysis.md)：进程内的交叉引用分析，本提案在它上面扩展。
  - [0076 objc-runtime-send-entry-points](0076-objc-runtime-send-entry-points.md)：libobjc 的专用发送入口。
  - [0053](0053-shared-cache-infrastructure.md) `SharedCache`：本提案不新增 `SharedCache`，理由同 0072。
  - RuntimeViewer [0056 cross-references](https://github.com/MxIris-Reverse-Engineering/RuntimeViewer/blob/next/Documentations/Evolutions/0056-cross-references.md)：界面里的交叉引用；它暂缓的第 4 步「CLI 与 MCP」由本提案接手。
  - MachOKitExtensions [draft-move-reading-and-resolving-modules](https://github.com/MxIris-Reverse-Engineering/MachOKitExtensions/blob/feature/move-reading-and-resolving-modules/Documentations/Evolutions/draft-move-reading-and-resolving-modules.md)：把本库的 `MachOReading` / `MachOResolving` 迁进 MachOKitExtensions，本提案的新模块照同一条路将来迁过去。
- **实现分支 / PR**: 待定
- **配套文档**: 待定 —— 落地时登记实现说明 / 使用指南的链接
- **网页版**: 同目录同名的 `.html`

## 摘要

`CrossReferenceAnalysis` 今天只能分析**当前进程**映射进来的镜像，读不了磁盘上的 app、也读不了
`/Volumes/DyldSharedCaches` 下归档的各版本 cache，而且没有命令行入口。本提案做五件事：

1. 把分析器里「直接读进程内存」的地方收进一个读取抽象，新增从 `FullDyldCache` 和一组 `MachOFile` 构造
   分析器的入口，槽里的值改由 fixup 解码得到；
2. 把 `SwiftThunkAnalysis` 里已经写好的离线桩链与槽解析抽成独立的 `MachOAddressResolution` 模块，两边共用；
3. 补三类引用：经 ivar 偏移变量读写 ObjC ivar、C 字符串字面量、CFString 常量，并给每条引用标上它是怎么到达
   目标的（直接调用、本镜像桩、stub island、cache 共用桩、GOT 槽……）；
4. 新增地址符号化：任意一个地址，说出它在哪个镜像的哪个函数加多少偏移，或者它是桩、最终跳到谁，或者它是槽、
   里面装着谁；
5. 新增 `swift-section refs` 与 `swift-section symbolicate` 两个子命令（文本与 JSON 输出），并在 RuntimeViewer
   的 CLI 与 MCP 上接出 `callers` / `callees` / `references` / `symbolicate`。

## 动机

完整动机见愿景《[不依赖 IDA 的逆向](../Visions/ReverseEngineeringWithoutIDA.md)》的「现状与代价」。这一步特有的部分：

- **最常卡住的就是这一块。** 逆向 agent 的笔记里约 15 条用「扫 selref / GOT 字节 → 换算子 cache 偏移 →
  反汇编 stub island → `a2s` 起名」这条手工链路回答「谁调用了它」，13 条涉及 selref，12 条涉及 GOT
  （`~/.claude/agent-memory/reverse-explorer/cross-cache-caller-search.md`、全局 `reverse-engineering` skill
  的 `references/ipsw-cache-recipes.md`）。现成工具都会静默漏：`ipsw dyld xref` 不跟进 stub island，
  `dyld_info -imports` 漏掉大部分 bind。2026-10-29 有一次因此判错：`UINSPasteboardWritingItemProvider` 在
  27.0 和 27.2 上都有两个调用者，它们经 `__DATA_CONST.__got` 读**本镜像自己**的类对象，`ipsw dyld disass`
  只显示 `ldr x0, [x23, #0x590]`，没有类名。
- **分析器已经有了，只是够不着这些目标。** `CrossReferenceAnalyzer` 在进程内 1.6–3.0 秒扫完 macOS 27.2
  的整个 cache，认得 27 的 cache 共用 selector 桩与 GOT 桩、stub island 多跳（`Internal/Modules/CrossReferenceAnalysis.md`
  「吞吐」节）。但它的构造器用 `DyldCacheLoaded.current` 与 `_dyld_get_image_header`，只看得到正在运行的
  系统；卷上归档的 7 个 macOS 版本（15.5 到 27.2）和 `/Volumes/RE` 下的 app 都够不着。0072 把 `MachOFile`
  与 `swift-section` 子命令明确留给了后续提案。
- **RuntimeViewer 只在界面里给出交叉引用。** RuntimeViewer 0056 的第 4 步（CLI 与 MCP）在 2026-10-26 经用户
  批准拆成暂缓项，说明以后另起提案。全部对话记录里 RuntimeViewer 的 MCP 一次也没被调用过；agent 要查调用者，
  只能退回 IDA 或 `ipsw`。
- **地址起名是同一个问题的另一面。** `dyld_info -disassemble` 把 macOS 26.7 SwiftUICore 的 2,195 个
  `__auth_stubs` 桩标成同一个错名，15.3 万条 `bl` 的目标因此标错（RuntimeViewer 记忆
  `dyld-info-mislabels-cache-stubs.md`）；`ipsw dyld a2s` 对 27 的 cache 共用 `objc_msgSend$…` 桩只回 `?`，
  agent 只能先反汇编桩的前三条，自己算 `adrp x1` 的页加 `add x1` 的偏移，再去读字符串。分析器在扫描时本来
  就要把每个桩解析到底，把这一步单独开放出来就是符号化。

## 前期调研

### 现状代码怎么走的

以下路径相对于本仓库，读自 `next`（`6e73eeaa`）。

**`CrossReferenceAnalysis` 的公开入口**（`Sources/Analysis/CrossReferenceAnalysis/CrossReferenceAnalyzer.swift`）：

- `public init?()`（`:85`）只扫当前进程，非 arm64 时返回 `nil`；`public let images: [MachOImage]`（`:23`）、
  `imagePaths`（`:30`）、`imageIndex(forPath:)`、`location(ofRuntimeAddress:)`（`:250`）。
- 函数表：`functions(inImageAt:)`、`function(containing:)`、`functions(containing:)`、`symbolName(at:)`。
- 引用：`references(madeBy:)`、`referenceTable(ofImageAt:)`、`referenceIndex(ofImageAt:)`、
  `references(to:inImageAt:)`（`:449`，键是 `CodeReferenceTable.Key`）。
- 预筛（`+Prefiltering.swift`、`+Linkage.swift`、`+SwiftTypes.swift`）：`imageIndices(importing:among:)`、
  `imageIndices(referencingSelector:among:)`、`imageIndices(referencingObjectiveCClassAt:among:)`、
  `imageIndices(linkingImageAt:among:)`、`imageIndices(referencingSwiftType:among:)` 等。
- 宿主内存管理：`prepareNames(inImageAt:)`、`preparePrefilters()`、`releaseImageData(exceptForImagesAt:)`、
  `approximateByteCount(ofImageDataAt:)`。

**模型**（`Models/`）：`CodeLocation`（镜像下标 + 未滑动地址）；`CodeReference`（`function`、
`instructionAddress`、`kind: call | tailCall | reference`、`target`、`isRuntimeHelperCall`，公开
memberwise 初始化方法在 `CodeReference.swift:104`）；`CodeReferenceTarget` 有 `function`、`importedSymbol`、
`messageSend(selector:receiver:)`、`superMessageSend`、`swiftType`、`swiftTypeName`、`objectiveCClass`、
`indirect`、`unrecognized` 九种；`CodeReferenceTable.Key` 有 `function`、`selector`、`importedSymbol`、
`objectiveCClass`、`swiftTypeDescriptor` 等。

**分析器只能在进程内成立的依赖**——本提案要拆掉的就是这些：

1. 构造器用 `DyldCacheLoaded.current` + `cache.slide`、`_dyld_image_count`、`_dyld_get_image_header`、
   `dladdr`（`CrossReferenceAnalyzer.swift:89-120`）。
2. 未滑动地址靠 `image.vmaddrSlide` 换成运行时地址。
3. 直接按地址读进程内存：`UnsafeRawPointer(bitPattern:)` 在 `ReferenceScanner.swift` 7 处、
   `ObjectiveCClassIndex.swift` 5 处、`SwiftTypeIndex.swift` 4 处、`ImageFunctionTable.swift` 2 处、
   `+SwiftTypes.swift` 2 处、`+Prefiltering.swift` 1 处、`ImageFallbackNames.swift` 1 处，共 22 处。
4. **GOT 槽依赖 dyld 已经绑定好的值**：模块文档写明「GOT 槽在进程内已经绑定，读出指针、去掉指针认证位就是
   目标」，懒绑定场景由 `LazyBindingTests` 守着。
5. 去掉指针认证位用 `StoredPointer` 里的 `InProcessContext.addressMask`。
6. 函数起点依赖 `MachOImage.FunctionStarts` 的偏移语义（模块文档说进程内给的已是绝对地址，与 MachOKit 的
   注释不符）。
7. 类名经 MachOObjCSection 读 `class_rw_t`（类已被运行时实现时）。

**已能认出的引用形态**（`Scanning/ReferenceScanner.swift`、`Scanning/RegisterFile.swift`，解码器是
`Sources/Support/ARM64InstructionDecoding/ARM64InstructionWord.swift`）：直接 `bl` / `b` 与尾调用、跳转表；
镜像自带的 `__objc_stubs` 与 `__stubs` / `__auth_stubs`（读不出时由 `ARM64Trampoline` 补读 ld64 改写过的
`nop; ldr x16, <slot>; br x16`）；27 的 cache 共用 selector 桩（`adrp x1; add x1; b <objc_msgSend 副本>`）
与 GOT 桩（`adrp x17; add x17; ldr x16, [x17]; braa`）；stub island 多跳；cache 内经典发送（`x1` 由
`adrp` / `add` 算出可打印的字符串地址）；GOT / selref / classref / superref 的 `adrp` + `ldr` 与字面量 `ldr`；
`adrp` + `add` / `adr` 算出类对象、元数据或访问器；Swift 类型访问器与 `__swift_instantiateConcreteTypeFromMangledName*`；
按 `autda` / `movk` 鉴别常量区分 vtable、PWT、VWT 的间接调用。

**解码器的覆盖**：`ARM64InstructionWord.load(_:)`（`:88`）只认 64 位的 `ldr` / `ldur` / 前变址 `ldr!` /
`ldraa` / `ldrab`；**不认 `ldrsw` 与 32 位 `ldr w`**，而 arm64 上读 ObjC ivar 偏移变量正是
`adrp x8, _OBJC_IVAR_$_C.ivar@PAGE; ldrsw x8, [x8, …@PAGEOFF]`。

**性能**（模块文档「吞吐」节，macOS 27.2，28 核）：建分析器 0.06 秒（4,114 个镜像）；每个镜像都建整表 3.0 秒、
1.26 亿条引用；查 `init` 的调用者预筛出 2,759 个镜像，0.05 + 1.8 秒；查 `makeKeyAndOrderFront:` 0.06 +
0.33 秒；手写解码器单线程解码 AppKit 约 187 MiB/s，比 Capstone 快 25–50 倍。

**本库已有的离线解析**（`Sources/Analysis/SwiftThunkAnalysis/Resolution/`）：

- `MachOThunkEnvironment`（`package final class`，551 行）已经在 `MachOFile` 上做了这几件事：
  `callee(at:)` 解析桩、ld64 跳板与 stub island（可多跳，`hopping(from:to:islandHops:)`）；
  `callee(boundInSlotAt:)` 解析 GOT 槽——独立文件经 `resolveBind(fileOffset:)` 得 bind 名，cache 里是
  rebase 到别的镜像，再按地址找符号；`pointer(at:)`、`slotSymbolName(at:)`；`foreignCallee` 与
  `dependencyCallee` 跨镜像找导出。
- `CacheImageResolver`（同文件 `:466`）用 `imageInfos` 按加载地址二分，回答「这个地址在 cache 的哪个镜像」，
  并按路径懒打开 `MachOFile`。
- `ThunkAddressSpace`（`ThunkAddressSpace.swift`）定下 cache 镜像的偏移约定：**未滑动地址 − `sharedRegionStart`**，
  并实测记下三种看似可用、实际静默出错的换算（`segment.fileOffset`、`MachOFile.fileOffset(of:)`、
  `FullDyldCache.address(of:)`，在 macOS 26 的 SwiftUI 上分别偏 0x88000、另一套记账、再偏 16384）。

**读取层**：`Sources/MachO/MachOReading` 已有 `ReadingContext` 协议（`associatedtype Runtime`、
`associatedtype Address`、`readElement(at:)`、`readElements(at:numberOfElements:)`、
`readWrapperElement(at:)`）及 `MachOContext` / `InProcessContext` 两种实现。MachOKitExtensions 的草案
`move-reading-and-resolving-modules`（In Progress，四个仓库同名分支）正把它原名迁进 MachOKitExtensions 2.0.0，
随本库 0.25.0 一起发。

**`swift-section` CLI**：根命令 `Sources/Executables/swift-section/SwiftSectionCommand.swift`；输入选项组
`Models/MachOOptionGroup.swift`（`filePath`、`-p/--cache-image-path`、`-n/--cache-image-name`、
`--dyld-shared-cache`、`--uses-system-dyld-shared-cache`、`-a/--architecture`、`--dependency-search-path`），
经 `Sources/Commands/SwiftSectionKit/Inputs/MachOSource.swift` 只产出**单个** `MachOFile`。`AGENTS.md` 的
CLI 一节规定：子命令逻辑写进 `SwiftSectionKit` 的 Request 类型，可执行层只管 flag、`validate()`、
`makeRequest()` 与错误翻译；输出一律经 `StandardStreamOutput`；CLI 改动要同批更新
`AgentPlugins/swift-section/skills/swift-section-cli/`。目前只有 `evolution --json` 与 snapshot 有 JSON，
没有统一约定。`swift-section` target 现在不依赖 `CrossReferenceAnalysis`（`Package.swift:920-941`）。

### 上游或依赖是否已具备能力

- **MachOKit**（fork，本库要求 `from: "0.55.102"`）：`stubs(in:)` / `objcStubs(in:)`
  （`LoadCommand/Model/Section+Stubs.swift`，`Stub.Branch` 为 `.viaSlot` / `.direct` / `.unknown`，带
  `indirectSymbolIndex`）；`MachOFile.resolveBind(at:)`（`MachOFile.swift:927`）、`resolveRebase(at:)`
  （`:879`）、`DyldCache.resolveRebase(at:)`；`MachOFile.functionStarts`（`:481`）；`closestSymbol(at:…)`
  （`MachORepresentable.swift:396-745`）；`DyldCache.symbolCache` 读 `.symbols` 文件。**没有** stub island
  或 cache 共用桩的 API，**没有**「地址 → 所属镜像」的 API，**没有**共享 selector 哈希表的解析；selref /
  classref / protoref 没有专门的访问器。读文件经 p-x9 的 `swift-fileio`（内存映射）。
- **MachOKitExtensions**（`from: "1.3.2"`）：`MachOFile.resolveBind(fileOffset:)` 覆盖 chained fixup 与旧式
  dyld info，但 **`isLoadedFromDyldCache` 时直接返回 `nil`**；`resolveSelfBind(fileOffset:)` 处理
  `BIND_SPECIAL_DYLIB_SELF`；`resolveRebase(fileOffset:)` 对 cache 镜像走 cache；`MachOFile.cached`
  的 `fixupPointer(at:)`；`DyldCacheSubCacheTable` 子 cache 地址二分表。

### 前人怎么做的

- **ipsw**：`dyld xref` 不跟进 stub island；`dyld a2s` 对 27 的 cache 共用 `objc_msgSend$` 桩只回 `?`；
  没有 `.a2s` 符号缓存时 `disass` 会卡在解析符号上 12 分钟、占 23 GB 内存（逆向 agent 笔记）。
- **Apple `dyld_info`**：只读本机正在运行的 cache；`-disassemble` 给 cache 桩标错名；`-imports` 漏 bind；
  `-objc` 对 cache 镜像静默无输出、退出码 0。
- **IDA**：一个库只装得下几个镜像，跨镜像看不到；单镜像库的导入桩借用别的局部符号名；查调用者要两跳
  （槽 → `j__<符号>` 桩 → 调用者）。
- **Binary Ninja**（开源部分取自 `Vector35/binaryninja-api` 的 `dev` 分支；用户装的是 6.0.10601 Personal）：
  - 整个 cache 放进一个地址空间，跨镜像引用就是普通地址；全 cache 的符号单独存成 `CacheSymbol`，打开 cache
    时读每个镜像的导出 trie 建「地址 → 符号」表，LC_SYMTAB 与 `.symbols` 本地符号等镜像被加载时才读
    （`view/sharedcache/core/SharedCache.cpp:305`、`core/MachOProcessor.cpp:88-134`）。
  - stub island 当作单独的区域；桩的判定看节名后缀（`__stubs`、`__auth_stubs`、`__objc_stubs`、
    `_branch_islands`）；解析时在 MLIL 的 SSA 形式上沿跳转目标往回找 `LOAD(CONST_PTR)`，命名为
    `j_<目标符号>`（`view/sharedcache/workflow/SharedCacheWorkflow.cpp`）。
  - ObjC 调用点的 selector 取 `x1` 的 SSA 常量值；`objc_msgSend$sel` 桩不靠符号表，「不超过 32 字节、一个
    基本块、尾调用 msgSend」就当它是，并用同样的 `x1` 追踪取 selector（`plugins/workflow_objc/src/activities/`
    下的 `objc_msg_send_calls.rs`、`name_stubs.rs`）。
  - selector 到实现不改写调用，而是从 selector 字符串和 selref 槽各加一条**数据引用**指向 IMP，查询时两跳；
    改写成直接调用的选项默认关，源码 TODO 承认它总取第一个实现、需要接收者类型才做得好
    （`objectivec/objc.cpp:1182-1184`、`rewrite_to_direct_call.rs`）。
  - 引用分代码、数据、类型、变量四类，另有类型字段引用（`get_code_refs_for_type_field`）；6.0 新增
    `get_derived_string_code_refs`（派生字符串，例如 CFString 的代码引用）。数据流只在函数内做
    （`docs/dev/concepts.md:160`）。
  - 界面里引用列表有上限（`ui.maxXrefItems = 1000`），超出时计数后面带 `+`；可按方向、种类过滤。
  - 6.0 自带 MCP 服务器：GUI 内的 HTTP 版随所有 GUI 版本提供（含 Personal），能查交叉引用、调用者、反汇编、
    IL 与伪代码；无界面的 `binaryninja_mcp` 只随 Commercial / Ultimate。地址在输出里一律写成十六进制字符串，
    「so clients do not lose precision when handling 64-bit addresses」；列表结果带 `count`、`total`、
    `nextOffset`、`truncated`（应用内 `docs/guide/mcp.html`）。

### 验证过什么

- 已验证（引自现有文档与记忆）：进程内分析器的吞吐数字；`ThunkAddressSpace` 的地址约定与三种错误换算
  （macOS 26 SwiftUI）；`UINSPasteboardWritingItemProvider` 的两个经 GOT 的调用者（27.0、27.2）；
  `dyld_info` 的 2,195 个错名桩（26.7 SwiftUICore）。
- IDA 与 Binary Ninja 的交叉引用实测（2026-11-18，Finder 26.5.2 与 ControlCenter 26.7，详见愿景「我们选的
  方向」第 1 条）：代码引用召回 IDA 一次查询 97.0%、两跳 99.4%，Binary Ninja 经 MCP 67.6%。三处双方的盲点
  直接变成本提案的测试用例：恰好页对齐的类对象（`adrp; add #0`，IDA 漏）、Swift 大字符串的
  `adrp; add; sub #0x20`（Binary Ninja 漏）、`retab` 之后没建函数的异常清理代码（Binary Ninja 漏）。
- 卷上有 cache 文件的版本：macOS 15.5、26.0（单文件）；26.5.2、26.6.2、26.7（12 个子文件）；27.0（79 个）、
  27.2（81 个）。本机运行 27.2。
- **推测，第 1、3 步先实测**：
  - 离线模式的吞吐。cache 在外置卷上、冷读几个 GB 的映射文件，预计比进程内慢，慢多少不知道。
  - 文件模式下能否拿到 `__text` 的连续只读字节（`swift-fileio` 的映射能否按区间给出指针），拿不到就按镜像
    把 `__text` 读进一块缓冲区。
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
- `FileCrossReferenceMemory`：基于 `FullDyldCache` 或一组 `MachOFile`。代码字节来自映射的文件；槽的内容由
  fixup 解码得到——cache 镜像里 GOT 是 rebase（指向别的镜像或本镜像的类对象），独立文件里是 bind、self-bind
  或 rebase。地址约定沿用 `ThunkAddressSpace`：未滑动地址 − `sharedRegionStart`。

协议选「分析器专用的小协议」而不是直接用 `ReadingContext`：`ReadingContext` 回答「按类型读一个元素」，
分析器要的是「槽里装着谁」——在进程内是读已绑定的值，在文件里是解 fixup，这层差别正是两种模式唯一的本质
区别。`FileCrossReferenceMemory` 内部仍用 `ReadingContext` 读元素。

### 2. 抽出 `MachOAddressResolution`

把 `SwiftThunkAnalysis` 里与 Swift thunk 无关的离线解析抽成新的 package 模块
`Sources/MachO/MachOAddressResolution`，`SwiftThunkAnalysis` 与 `CrossReferenceAnalysis` 共用：

- `ImageAddressSpace`：原 `ThunkAddressSpace`，地址约定与它的长注释一起搬。
- `CacheImageLocator`：原 `CacheImageResolver`，「地址 → cache 镜像」与按路径懒打开。
- `StubChainResolver`：桩、ld64 跳板、stub island 多跳、27 的 cache 共用 selector 桩与 GOT 桩 → 最终目标
  （函数地址、导入符号名或 selector），并记下经过的每一跳。
- `SlotResolver`：GOT / auth GOT / selref / classref / superref / protoref / ivar 偏移变量的槽 → 目标。

这个模块只依赖 MachOKit、MachOKitExtensions 与 `MachOReading`，不碰 Swift 元数据，将来照
`move-reading-and-resolving-modules` 的走法整体迁进 MachOKitExtensions（愿景「我们选的方向」第 6 条）。

### 3. 文件模式的分析器

```swift
let cache = try FullDyldCache(url: URL(filePath: "/Volumes/DyldSharedCaches/macOS/27.2/dyld_shared_cache_arm64e"))
let analyzer = try CrossReferenceAnalyzer(dyldCache: cache)
```

镜像表来自 cache 头的 `imageInfos`；`imagePaths`、`imageIndex(forPath:)`、函数表、预筛、`referenceTable`
等全部照旧可用。`location(ofRuntimeAddress:)` 在文件模式下接受的就是未滑动地址。`images: [MachOImage]` 在
文件模式下为空，标为 deprecated 并指向 `imagePaths` / `imageCount`。

### 4. 新的引用种类与引用路线

- **ObjC ivar**：`adrp` + `ldrsw`（或 32 位 `ldr`）读 `__objc_ivar` 里的偏移变量 →
  `.objectiveCInstanceVariable(className:name:)`。解码器补 `ldrsw` 与 32 位 `ldr`。名字取自偏移变量的符号
  `_OBJC_IVAR_$_<类>.<ivar>`；没有符号时从类的 ivar 列表反查（ivar 记录里的 `offset` 字段指向这个槽）。
- **C 字符串字面量**：`adrp` + `add` 落进 `__cstring` / `__objc_methname` / `__oslogstring`，且没被当作
  selector 用掉 → `.cString(String)`。覆盖 `objc_getClass("…")`、`sel_registerName`、`dlsym` 一类调用。
  Swift 大字符串字面量的写法是 `adrp; add; sub #0x20`（对象里存的是「地址 − 0x20」），也要认成指向那段字符的
  引用——Binary Ninja 在实测里正是漏在这里。
- **CFString 常量**：`adrp` + `add` 落进 `__cfstring` → 解出字符串指针 → `.constantString(String)`。覆盖
  `NSSelectorFromString(@"…")`、`NSUserDefaults` 键一类用法。
- 两种字符串引用默认**不记录**：它们数量大，RuntimeViewer 常驻的索引不需要。构造分析器时用
  `recordingStringReferences: true` 打开，`swift-section refs --string` 会自动打开。
- **引用路线**：`CodeReference` 新增 `route`，说明引用是怎么到达目标的。照 Binary Ninja 的「引用按来源种类
  建模」，但只在代码引用上加一个字段，不引入数据引用（见非目标）。

### 5. 地址符号化

```swift
let symbolication = analyzer.symbolication(of: 0x1_9012_3450)
// symbolication.meaning == .stub(hops: [0x1_9012_3450], target: .messageSend(selector: "setFrame:", receiver: .unknown))
```

回答「这个地址是什么」，按顺序判断：在某个函数体里（函数起点、名字、偏移；名字来自符号、`ImageFallbackNames`
的回退名）；是桩或 stub island 的跳板（每一跳与最终目标）；是一个槽（槽的种类与里面装的目标）；是 C 字符串
或 CFString（内容）；以上都不是时给最近的前一个符号加偏移；不在任何映射里时如实说没有映射。

### 6. `swift-section refs` 与 `swift-section symbolicate`

```text
swift-section refs --selector makeKeyAndOrderFront: --dyld-shared-cache /Volumes/DyldSharedCaches/macOS/27.2/dyld_shared_cache_arm64e
swift-section refs --class UINSPasteboardWritingItemProvider --uses-system-dyld-shared-cache --json
swift-section refs --function 0x1880a1000 --callees --uses-system-dyld-shared-cache
swift-section refs --string NSWindowDidBecomeKeyNotification --in-image AppKit /path/to/Foo.app/Contents/MacOS/Foo
swift-section symbolicate 0x19012345 0x1e1226590 --dyld-shared-cache /Volumes/DyldSharedCaches/macOS/27.0/dyld_shared_cache_arm64e
```

- 查询（恰好一个）：`--selector`、`--symbol`（C 符号、Swift 修饰名、`_OBJC_CLASS_$_…`）、`--class`、
  `--function <地址>`（以它开头或包含它的函数的调用者；加 `--callees` 改列它引用了什么）、`--ivar <类>.<ivar>`、
  `--string <文本>`。
- 输入：一个或多个独立 Mach-O 文件，或 `--dyld-shared-cache <路径>`，或 `--uses-system-dyld-shared-cache`；
  `-a/--architecture`。`--in-image` 可重复，限定扫描哪些镜像。
- 输出：文本每条引用一行——镜像短名、所在函数名加偏移、调用点地址、引用种类与路线；`--json` 输出一个 JSON
  文档，地址一律写成十六进制字符串（照 Binary Ninja MCP 的理由：避免客户端丢失 64 位精度）。
- `--limit <n>` 截断时如实标出 `isTruncated`。

### 7. RuntimeViewer：CLI 与 MCP

按 0056 §8 原定的设计实现它暂缓的第 4 步，并加上符号化：

- CLI 子命令 `callers`、`callees`、`references`、`symbolicate`；目标写法照 0056：`-[类 sel]`、Swift 名、
  符号名，或 `0x…` 加 `--image`；选项 `--selector`、`--scope image|indexed`、`--receiver`、
  `--include-runtime`、`--limit`。CLI 协议版本 `CommandLineProtocol.version` 由 2 升到 3。
- MCP 工具 `Callers`、`Callees`、`TypeReferences`、`Symbolicate`，`@MCPTool(hints: [.readOnly])`，照现有
  工具带 `windowIdentifier`；每次最多等 30 秒，`isComplete == false` 时返回部分结果。
- 只覆盖活的引擎（本机、Catalyst、注入的进程）；文件引擎见非目标。

### 非目标

- **落盘索引**：沿用 0072 与 RuntimeViewer 0056 的决定。第 3 步实测离线吞吐，结果写进模块文档，是否需要
  持久化由愿景的后续阶段决定。
- **数据引用**（方法表条目 → IMP、CFString → 字符串这类「数据 → 地址」）与其余数据解码（KeyPath、ObjC
  字面量、Swift 字符串）：愿景第 3 阶段。
- **带注解的反汇编、函数清单命令**：愿景第 2 阶段。
- **跨基本块的常量追踪、调用点常量参数普查**：愿景第 4 阶段。
- **接收者类型推断、Swift 字段级引用**。
- **x86_64**。
- 0072「后续」里列的其余项：协议见证与 override 的起名、`objc_getClass("…")` 解析成类引用（本提案只把它记成
  C 字符串引用）、Swift 的 super 发送、协议类型引用。
- **RuntimeViewer**：CLI 直接读文件引擎、文件引擎上的交叉引用（RuntimeViewer「暂缓的后续项」里的另一条）、
  MCP 无头化（RuntimeViewer 愿景《无头 RuntimeViewer》的「之后可以接」）。
- **idax 建库时写入桩名与 Swift 函数名**：IDA 已降为后备。

## 改动地图

步骤号对应「落地步骤」。

| 文件 / 类型 | 动作 | 改什么 | 为什么 | 步骤 |
|---|---|---|---|---|
| `Sources/Analysis/CrossReferenceAnalysis/Memory/CrossReferenceMemory.swift` · `CrossReferenceMemory` | 新增 | package 协议：区间字节、槽内容、C 字符串、指针掩码 | 两种模式唯一的本质差别收在这里 | 1 |
| `…/Memory/InProcessCrossReferenceMemory.swift` · `InProcessCrossReferenceMemory` | 新增 | 搬入现有的直接读指针与 slide 换算 | 进程内行为不变 | 1 |
| `…/CrossReferenceAnalyzer.swift` · `CrossReferenceAnalyzer` | 修改 | 持有 `CrossReferenceMemory`；构造逻辑拆成「进程」与「文件」两条；`images` 标 deprecated | 支持文件模式 | 1、3 |
| `…/Scanning/ReferenceScanner.swift` | 修改 | 7 处直接读内存改走 memory；记录 `route`；识别 ivar 偏移变量与两种字符串 | 读取抽象；新引用种类 | 1、4 |
| `…/Scanning/RegisterFile.swift` | 修改 | 跟踪 `ldrsw` / 32 位 `ldr` 读出的 ivar 偏移来源 | ivar 引用 | 4 |
| `…/Scanning/ImageFunctionTable.swift` | 修改 | selref 读取走 memory；文件模式的函数起点 | 读取抽象；文件模式 | 1、3 |
| `…/Scanning/ObjectiveCClassIndex.swift`、`SwiftTypeIndex.swift`、`ImageFallbackNames.swift` | 修改 | 直接读内存改走 memory；文件模式下类名经 MachOObjCSection 的文件读取 | 读取抽象；文件模式 | 1、3 |
| `…/CrossReferenceAnalyzer+Prefiltering.swift`、`+SwiftTypes.swift` | 修改 | 直接读内存改走 memory；新增 ivar 与字符串的预筛 | 读取抽象；新查询 | 1、4 |
| `…/Scanning/StoredPointer.swift` | 修改 | 掩码由 memory 提供 | 文件模式没有 `InProcessContext` | 1 |
| `…/Memory/FileCrossReferenceMemory.swift` · `FileCrossReferenceMemory` | 新增 | 映射的代码字节；经 `SlotResolver` 解 fixup | 文件模式 | 3 |
| `Sources/MachO/MachOAddressResolution/ImageAddressSpace.swift` · `ImageAddressSpace` | 新增 | 由 `ThunkAddressSpace` 搬来，连同地址约定的注释 | 两个分析模块共用 | 2 |
| `…/MachOAddressResolution/CacheImageLocator.swift` · `CacheImageLocator` | 新增 | 由 `CacheImageResolver` 搬来 | 同上 | 2 |
| `…/MachOAddressResolution/StubChainResolver.swift` · `StubChainResolver` | 新增 | 由 `MachOThunkEnvironment` 的桩链部分抽出，补 27 的 cache 共用桩，记录每一跳 | 同上；符号化要每一跳 | 2 |
| `…/MachOAddressResolution/SlotResolver.swift` · `SlotResolver` | 新增 | 由 `MachOThunkEnvironment` 的槽解析抽出，补 selref / classref / protoref / ivar 偏移槽 | 同上 | 2 |
| `Sources/Analysis/SwiftThunkAnalysis/Resolution/MachOThunkEnvironment.swift` | 修改 | 改用上面四个类型，行为不变 | 去重 | 2 |
| `…/SwiftThunkAnalysis/Resolution/ThunkAddressSpace.swift` · `ThunkAddressSpace` | 删除 | 调用点改用 `ImageAddressSpace` | 已搬走 | 2 |
| `Sources/Support/ARM64InstructionDecoding/ARM64InstructionWord.swift` | 修改 | `load(_:)` 之外新增 32 位 `ldr` 与 `ldrsw` 的解码 | ivar 偏移变量的读法 | 4 |
| `Sources/Analysis/CrossReferenceAnalysis/Models/CodeReference.swift` · `CodeReferenceTarget`、`CodeReference` | 修改 | 新增三个 target case；新增 `Route` 与 `route`；旧初始化方法 deprecated | 新引用种类；引用路线 | 4 |
| `…/Models/CodeReferenceTable.swift` · `CodeReferenceTable.Key` | 修改 | 新增 `instanceVariable`、`cString`、`constantString` 键 | 按新目标查 | 4 |
| `…/Models/CodeReferenceIndex.swift` · `CodeReferenceIndex` | 修改 | 编码新 target 与 `route` | 常驻索引也要带上 | 4 |
| `…/Symbolication/AddressSymbolication.swift` · `AddressSymbolication` | 新增 | 公开的符号化结果模型 | 符号化 | 5 |
| `…/CrossReferenceAnalyzer+Symbolication.swift` · `symbolication(of:)` | 新增 | 按「函数 → 桩 → 槽 → 字符串 → 最近符号 → 未映射」判断 | 符号化 | 5 |
| `Sources/Commands/SwiftSectionKit/CrossReferences/CrossReferenceInput.swift` | 新增 | 由文件、cache 或本机 cache 建分析器 | 两个子命令共用 | 6 |
| `…/SwiftSectionKit/CrossReferences/ReferencesRequest.swift` · `ReferencesRequest` | 新增 | 预筛 → 并发逐镜像查 → 起名 → 文本 / JSON | `refs` 的逻辑 | 6 |
| `…/SwiftSectionKit/CrossReferences/SymbolicateRequest.swift` · `SymbolicateRequest` | 新增 | 批量符号化 → 文本 / JSON | `symbolicate` 的逻辑 | 6 |
| `Sources/Executables/swift-section/Commands/ReferencesCommand.swift`、`SymbolicateCommand.swift` | 新增 | flag、`validate()`、`makeRequest()` | CLI 入口 | 6 |
| `Sources/Executables/swift-section/Models/CrossReferenceInputOptionGroup.swift` | 新增 | 多文件 / cache / 本机 cache、`-a`、`--in-image` | 现有选项组只产出单个 `MachOFile` | 6 |
| `Sources/Executables/swift-section/SwiftSectionCommand.swift` | 修改 | 登记两个子命令 | CLI 入口 | 6 |
| `Package.swift` | 修改 | 新增 `MachOAddressResolution`；`CrossReferenceAnalysis`、`SwiftThunkAnalysis` 依赖它；`SwiftSectionKit` 与 `swift-section` 依赖 `CrossReferenceAnalysis` | 模块图 | 1、2、6 |
| `Tests/CrossReferenceAnalysisTests/…` | 新增 | 对照、文件模式、新种类、符号化测试（见落地步骤） | 验证 | 1–5 |
| `Tests/MachOAddressResolutionTests/…` | 新增 | 桩链、槽解析测试 | 验证 | 2 |
| `Tests/SwiftThunkAnalysisTests/…` | 修改 | 抽取前后结果一致的守护测试 | 去重不改行为 | 2 |
| `Tests/…`（SwiftSectionKit 的命令测试） | 新增 | `refs` / `symbolicate` 的文本与 JSON 输出 | 验证 | 6 |
| `Documentations/Internal/Modules/CrossReferenceAnalysis.md` | 修改 | 文件模式、读取抽象、新种类、路线、符号化、离线吞吐实测 | 模块参考 | 3–5 |
| `Documentations/Internal/Modules/MachOAddressResolution.md` | 新增 | 新模块参考（地址约定、桩链、槽） | 模块参考 | 2 |
| `AgentPlugins/swift-section/skills/swift-section-cli/` | 修改 | 两个新子命令的用法与坑 | `AGENTS.md` 要求 | 6 |
| `README.md`（CLI 一节） | 修改 | 列出两个新子命令 | 面向用户 | 6 |
| `Documentations/Internal/ProjectEvolutionLog.md`、`Documentations/Glossary.md` | 修改 | 追加本批次；登记「符号化」「引用路线」「stub island」等术语 | 文档约定 | 8 |
| RuntimeViewer `RuntimeViewerCore/Sources/RuntimeViewerCrossReferences/Analysis/CrossReferenceQuery.swift` | 修改 | `switch reference.target`（`:92`）补三个新 case | 穷尽 switch 会编译失败 | 4 |
| RuntimeViewer `…/RuntimeViewerCrossReferences/`（新文件）· 符号化引擎命令 | 新增 | 引擎侧 `symbolicate` 命令 | CLI / MCP 的符号化 | 7 |
| RuntimeViewer `RuntimeViewerCommandLine/Sources/RuntimeViewerCommandLineInterface/Model/Command.swift`、`CommandResult.swift` | 修改 | `.callers` / `.callees` / `.references` / `.symbolicate` 与结果 | CLI | 7 |
| RuntimeViewer `…/CommandLine/Subcommands.swift`、`Execution/CommandExecutor.swift`、`Rendering/TextRenderer.swift` | 修改 | 四个子命令的解析、执行与显示 | CLI | 7 |
| RuntimeViewer `…/Protocol/WireMessage.swift` · `CommandLineProtocol.version` | 修改 | 2 → 3 | 新增命令 | 7 |
| RuntimeViewer `RuntimeViewerMCP/Sources/RuntimeViewerMCPBridge/MCPBridgeServer.swift` | 修改 | `Callers`、`Callees`、`TypeReferences`、`Symbolicate` 四个工具 | MCP | 8 |
| RuntimeViewer `AgentPlugins/runtime-viewer/`、`Documentations/Guides/CommandLineInterface.md`、`Documentations/Evolutions/README.md` | 修改 | skill 与两个插件清单的 version；使用指南；`cross-repository draft` 一行 | 文档同批 | 7、8 |

## 架构图

改了什么：

```text
MachOSwiftSection
  Sources/MachO
+   MachOAddressResolution                      package; MachOKit + MachOKitExtensions + MachOReading only
+     ImageAddressSpace        (was ThunkAddressSpace)
+     CacheImageLocator        (was CacheImageResolver)
+     StubChainResolver        stubs, ld64 trampolines, stub islands, cache-shared selector/GOT stubs
+     SlotResolver             GOT, selref, classref, superref, protoref, ivar offset slots
  Sources/Support/ARM64InstructionDecoding
~   ARM64InstructionWord       + 32-bit ldr, ldrsw
  Sources/Analysis
    SwiftThunkAnalysis
~     MachOThunkEnvironment ───────────────> MachOAddressResolution
-     ThunkAddressSpace, CacheImageResolver
    CrossReferenceAnalysis
~     CrossReferenceAnalyzer
+       init(dyldCache:recordingStringReferences:)
+       init(machOFiles:recordingStringReferences:)
+       symbolication(of:) -> AddressSymbolication
+     Memory/CrossReferenceMemory           package protocol
+       InProcessCrossReferenceMemory       today's pointer reads, moved
+       FileCrossReferenceMemory ──────────> MachOAddressResolution
~     ReferenceScanner, RegisterFile       + ivar offset loads, + C string / CFString, + route
~     CodeReferenceTarget                  + objectiveCInstanceVariable, + cString, + constantString
~     CodeReference                        + route
  Sources/Commands/SwiftSectionKit
+   CrossReferences/ReferencesRequest, SymbolicateRequest, CrossReferenceInput
  Sources/Executables/swift-section
+   refs, symbolicate

RuntimeViewer
~ RuntimeViewerCrossReferences   switch over new targets; + symbolicate engine command
~ RuntimeViewerCommandLine       + callers, callees, references, symbolicate (protocol 2 -> 3)
~ RuntimeViewerMCPBridge         + Callers, Callees, TypeReferences, Symbolicate
```

一次 `refs` 查询的数据流：

```text
swift-section refs --selector makeKeyAndOrderFront: --dyld-shared-cache <cache>
  ReferencesCommand.makeRequest()
  -> ReferencesRequest
     -> CrossReferenceInput: FullDyldCache(url:) -> CrossReferenceAnalyzer(dyldCache:)
          image table from cache header imageInfos; FileCrossReferenceMemory over mapped subcache files
     -> imageIndices(referencingSelector:among: all)              prefilter
     -> for each candidate image, concurrently:
          references(to: [.selector("makeKeyAndOrderFront:")], inImageAt:)
            ReferenceScanner over the image's __text bytes
              bl X  -> StubChainResolver(X)  -> cache-shared selector stub -> .messageSend   route .cacheSharedStub
              adrp+ldr slot -> SlotResolver(slot) -> rebase target -> symbol             route .pointerSlot
     -> functions(containing: sites) -> names (symbols, ImageFallbackNames)
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
    public convenience init(dyldCache: FullDyldCache, recordingStringReferences: Bool = false) throws

    /// Analyzes standalone Mach-O files, such as an app's executable and its embedded frameworks.
    public convenience init(machOFiles: [MachOFile], recordingStringReferences: Bool = false) throws

    /// The number of images the analyzer covers, in either mode.
    public var imageCount: Int { get }

    /// What the address is: a place inside a function, a stub, a pointer slot, a string, or nothing mapped.
    public func symbolication(of address: UInt64) -> AddressSymbolication
}

extension CrossReferenceAnalyzer {
    @available(*, deprecated, message: "Empty for analyzers created from files; use imagePaths or imageCount")
    public var images: [MachOImage] { get }
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

extension CodeReference {
    /// How the code reached the target.
    public enum Route: UInt8, Hashable, Sendable {
        /// `bl` / `b` straight to the target.
        case direct
        /// A stub in the referencing image's own `__stubs`, `__auth_stubs` or `__objc_stubs`.
        case imageStub
        /// A trampoline in a dyld shared cache stub island, possibly after several hops.
        case stubIsland
        /// A stub shared by the whole cache: macOS / iOS 27's `objc_msgSend$…` selector stubs and GOT stubs.
        case cacheSharedStub
        /// `adrp` + `ldr` through a GOT or auth GOT slot.
        case pointerSlot
        /// `adrp` + `ldr` through an `__objc_selrefs` slot.
        case selectorReference
        /// `adrp` + `ldr` through an `__objc_classrefs` or `__objc_superrefs` slot.
        case classReference
        /// `adrp` + `add`, or `adr`, computing the target's address.
        case addressMaterialization
        /// `ldr` of a literal pool entry.
        case literalLoad
        /// An authenticated indirect call through a vtable, protocol witness table or value witness table.
        case authenticatedIndirect
    }

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

- 用 **symbolication / symbolicate** 而不是 resolve：MachOKit 与 MachOKitExtensions 里 `resolveBind` /
  `resolveRebase` 的 resolve 指「解 fixup」，同一个词不能再指「说出地址是什么」；symbolication 是 Apple 自己的
  说法（`atos`、崩溃报告的 symbolication）。
- 方法用名词短语 `symbolication(of:)`：它没有副作用，按 API Design Guidelines 读成名词短语。
- `route` 不给默认值：它影响结果是否可信，按「影响正确性的参数不给默认值」处理；旧初始化方法保留一个版本并
  标 `renamed:`。

### 读取抽象（package）

```swift
package protocol CrossReferenceMemory: Sendable {
    /// Read-only bytes of an image range, contiguous, for the scanner's decode loop.
    func bytes(inImageAt imageIndex: Int, unslidRange: Range<UInt64>) -> UnsafeRawBufferPointer?
    /// What a pointer slot holds: an address in some image, or an imported symbol name.
    func slotContent(at unslidAddress: UInt64, inImageAt imageIndex: Int) -> SlotContent?
    /// A NUL-terminated C string at the address, if it is printable to the end.
    func cString(at unslidAddress: UInt64) -> String?
    /// Mask that strips pointer-authentication and tag bits.
    var addressMask: UInt64 { get }
}

package enum SlotContent: Hashable, Sendable {
    case address(UInt64)
    case importedSymbol(String)
}
```

并发：分析器今天是 `@unchecked Sendable` 加手写锁（裁决 A62）。`FileCrossReferenceMemory` 的读取是对只读
映射的并发读，fixup 解码的记忆化沿用 MachOKitExtensions `cached` 视图里已有的锁。

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

（示例中的函数名与地址是示意，不是实测值。）`symbolicate --json` 输出 `{"symbolications": [ … ]}`，每项的字段
对应 `AddressSymbolication`。字段名定下后即是契约，改名按 CLI 的破坏性变更处理。

### 地址的约定

CLI 与 API 进出的地址一律是**未滑动的虚拟地址**，也就是 IDA、`ipsw`、`dyld_info` 显示的那种。进程内模式在
内部换算，调用方不需要知道 slide。

### 性能预算

第 3 步实测并写进模块文档：在 Ultra 上对 `/Volumes/DyldSharedCaches/macOS/27.2` 冷启动、热启动各跑
`--selector makeKeyAndOrderFront:` 与 `--selector init`。若冷启动的整 cache 查询超过 60 秒，在愿景里把
「落盘」阶段提前。

## 替代方案考量

- **另写一个离线分析器，不动现有的。** 否：扫描、寄存器跟踪、命名合计约 5,200 行，复制一份就会和进程内版本
  漂移；`SwiftThunkAnalysis` 里已经有一份重复的离线解析，正是本提案要合并的。
- **把分析器改成对 `MachO: MachORepresentable` 泛型**（本库其它模块的惯用写法）。否：两种模式的差别不在
  「哪种 Mach-O 类型」，而在「槽里的值怎么得到」——进程内读已绑定的值，文件里解 fixup。泛型会一路传染到
  RuntimeViewer 持有分析器的会话类型，而一个小协议正好只隔离这一点。
- **直接用 `ReadingContext` 当读取抽象。** 否，理由见「提议方案」第 1 节；`FileCrossReferenceMemory` 内部仍用它。
- **后端用 `ipsw` 或 `dyld_info`。** 否：「前人怎么做的」里列的几类静默漏报、错名都会原样带进来。
- **直接用 Binary Ninja。** 否：用户的 Personal 许可没有无界面 API，无界面的 `binaryninja_mcp` 也只随
  Commercial / Ultimate；GUI 的 MCP 要求界面开着、当前视图跟随界面，多个 agent 会互相抢；整 cache 查询要把
  几千个镜像装进一个视图。2026-11-18 的实测里，它经 MCP 的代码引用召回只有 67.6%（IDA 两跳 99.4%），
  所以连核对也只作补充。
- **现在就做落盘索引。** 否：0072 与 RuntimeViewer 0056 都定过不做；先量离线吞吐再说。
- **地址符号化放进 MachOKit fork。** 否：fork 已落后上游 33 个提交，再加新能力只会更难合。
- **放进 MachOKitExtensions。** 现在不放：它正在为 2.0.0 接收读取层，同时动两件事风险大；新模块按可迁移的
  依赖写，等那次迁移落定后照同样的路搬过去。
- **CLI 子命令叫 `resolve`。** 否：与 `resolveBind` / `resolveRebase` 撞义，见「详细设计」的命名取舍。
- **照 Binary Ninja 建统一地址空间、换掉 `CodeLocation`。** 否：`CodeLocation` 是公开模型，RuntimeViewer 的
  查询层建在它上面；统一地址空间里最有用的「任何地址都说得出是什么」由符号化单独提供。
- **照 Binary Ninja 加「selref / selector → IMP」的数据引用。** 本提案不做，归入愿景第 3 阶段的数据引用；
  现在按 selector 查发送者已经可以，从调用点到实现的两跳留给数据引用一起做。

## 影响

### 源码兼容性（source compatibility）

**有破坏**，逐条：

- `CodeReferenceTarget` 新增三个 case，`CodeReferenceTable.Key` 新增三个 case：对它们做穷尽 `switch` 的代码
  编译失败。已知下游只有 RuntimeViewer 的 `CrossReferenceQuery.swift:92`（`switch reference.target`），在
  第 4 步同一时间窗里补上：

  ```swift
  // Before: nine cases.
  // After: add
  case .objectiveCInstanceVariable, .cString, .constantString:
      return nil   // not surfaced in the GUI yet
  ```

  RuntimeViewer 本地按「本地路径优先」依赖本库（`../../MachOSwiftSection`），所以本库 `next` 一合进新 case，
  RuntimeViewer 的 `next` 就要跟着改，两边要同批合入。
- `CodeReference` 的旧初始化方法标 deprecated（`renamed:` 到新签名），仍可用一个版本。
- `images` 标 deprecated；进程内模式行为不变。

其余全是新增。

### ABI 兼容性

不适用 —— 本库以 SPM 源码分发，使用方每次重新编译。

### 下游影响

- 本仓库内：`SwiftThunkAnalysis` 改用抽出的模块（行为不变，由守护测试保证）；`SwiftSectionKit` 与
  `swift-section` 新增对 `CrossReferenceAnalysis` 的依赖。
- RuntimeViewer：见上；另有第 7、8 步的 CLI 与 MCP。它的常驻索引（`CodeReferenceIndex`）多出 `route`，第 4 步
  量出 `approximateByteCount` 的增量写进模块文档。
- swift-decompiler：依赖本库的 `SwiftThunkAnalysis` 时只经它的公开接口，抽取不改公开接口；第 2 步核对一次。
- MachOKitExtensions 的读取层迁移：新模块依赖 `MachOReading`，迁移是原名迁入，import 不变；若迁移先合进
  `next`，第 2 步照新的包依赖写 `Package.swift`。

### 文档与示例

README 的 CLI 一节、`swift-section-cli` skill、两个模块参考文档、RuntimeViewer 的 CLI 使用指南与
`runtime-viewer` skill。

## API 演进与废弃策略

- `CodeReference.init(function:instructionAddress:kind:target:isRuntimeHelperCall:)` 与
  `CrossReferenceAnalyzer.images`：标 `@available(*, deprecated, …)` 保留一个次版本，下一个次版本删除。
- `ThunkAddressSpace`、`CacheImageResolver` 是 package 级，直接搬走，不留旧名。
- 本库仍在 0.x，随下一个次版本发布，不需要大版本。

## 落地步骤

1. **读取抽象，行为不变** —— 改动地图里的 `CrossReferenceMemory`、`InProcessCrossReferenceMemory`、分析器与
   各扫描文件的读取改造、`StoredPointer`、`Package.swift`。
   - 行为：`inProcessReferenceTablesAreUnchangedForAppKitSwiftUICoreAndFoundation`（改造前后逐条比对整表）
   - 行为：`crossReferenceAnalysisReadsMemoryOnlyThroughCrossReferenceMemory`（源码扫描：分析模块里不再有
     `UnsafeRawPointer(bitPattern:)`）
2. **抽出 `MachOAddressResolution`** —— 四个新类型、`MachOThunkEnvironment` 改用它们、删 `ThunkAddressSpace`、
   模块文档。
   - 行为：`thunkAnalysisResultsAreUnchangedAfterExtraction`
   - 行为：`stubChainResolvesCacheSharedSelectorStubToItsSelector`
   - 行为：`stubChainRecordsEveryStubIslandHop`
   - 行为：`slotResolverNamesTheOwnImageClassHeldInAGlobalOffsetTableSlot`
   - 行为：`slotResolverResolvesStandaloneBindsAndSelfBinds`
3. **文件模式的分析器** —— `FileCrossReferenceMemory`、两个新构造器、函数起点与类名的文件模式。
   - 行为：`fileModeMatchesInProcessReferencesOnTheRunningSystemCache`（同一个 cache 两种模式逐条比对，
     镜像取 AppKit、SwiftUICore、Foundation）
   - 行为：`archivedCacheFindsBothCallersOfPasteboardWritingItemProvider`（27.0 与 27.2；卷不在时跳过）
   - 行为：`archivedCacheFollowsStubIslandsForSelectorSends`
   - 行为：`standaloneAppResolvesImportedAndSelfBoundSymbols`
   - 行为：`offlineThroughputIsRecordedInTheModuleDocument`（不是断言，是把实测写进文档）
   - 行为：`fileModeScansExceptionCleanupCodeAfterReturn`（`retab` 之后、没有函数起点的异常清理代码也要被扫到）
   - 核对：在 Finder 26.5.2 与 ControlCenter 26.7（卷上有现成 `.i64`）上，用 2026-11-18 那次实测的做法——
     `otool -tV` 加独立寄存器跟踪生成标准答案——比对本库文件模式的结果，并与 IDA 查到两跳的结果对照，差异
     逐条归因后写进模块文档。Binary Ninja 经 MCP 只作补充：它没有「代码 → 数据地址」的反查，dyld cache 的
     镜像也要先在界面里加载。
4. **新引用种类与路线** —— 解码器的 `ldrsw` / 32 位 `ldr`、`RegisterFile`、三个 target、`Route`、表键、
   常驻索引编码、RuntimeViewer 的穷尽 switch。
   - 行为：`instanceVariableOffsetLoadsBecomeInstanceVariableReferences`
   - 行为：`stringReferencesAreRecordedOnlyWhenRequested`
   - 行为：`constantStringReferencesCarryTheirCharacters`
   - 行为：`everyReferenceCarriesTheRouteItTook`
   - 行为：`referenceIndexRoundTripsNewTargetsAndRoutes`
   - 行为：`decoderDecodesThirtyTwoBitLoadAndLoadSignedWord`
   - 行为：`pageAlignedClassObjectMaterializationIsAReference`（`adrp; add #0`）
   - 行为：`swiftLargeStringLiteralPointsAtItsCharacters`（`adrp; add; sub #0x20`）
5. **地址符号化** —— `AddressSymbolication` 与 `symbolication(of:)`。
   - 行为：`symbolicatesEverySwiftUICoreAuthStubToItsIndirectSymbol`（对照 MachOKit 的
     `Stub.indirectSymbolIndex`，正是 `dyld_info` 标错的那批）
   - 行为：`symbolicatesCacheSharedMessageSendStubToItsSelector`
   - 行为：`symbolicatesGlobalOffsetTableSlotToItsBoundSymbol`
   - 行为：`symbolicatesAnAddressInsideAnUnnamedFunctionWithItsFallbackName`
   - 行为：`symbolicatesAnUnmappedAddressAsUnmapped`
6. **`swift-section refs` 与 `symbolicate`** —— SwiftSectionKit 的三个类型、两个命令、选项组、登记、README、
   skill。
   - 行为：`refsListsCallerRowsForASelectorInAnArchivedCache`
   - 行为：`refsJSONUsesHexadecimalStringAddresses`
   - 行为：`refsMarksTruncatedResultsWhenLimited`
   - 行为：`refsRequiresExactlyOneQuery`
   - 行为：`symbolicateAcceptsSeveralAddresses`
   - 行为：`crossReferenceCommandsWriteOnlyThroughStandardStreamOutput`（沿用仓库已有的输出扫描测试）
7. **RuntimeViewer CLI** —— 引擎侧符号化命令、四个子命令、协议版本、文本显示、使用指南、skill。
   - 行为：`callersCommandJSONMatchesTheMCPResponseFields`
   - 行为：`commandLineProtocolVersionIsThree`
   - 行为：`symbolicateCommandWorksOnTheLocalSource`
8. **RuntimeViewer MCP 与收尾** —— 四个 MCP 工具；本库的 `ProjectEvolutionLog.md`、`Glossary.md`；
   RuntimeViewer 的 `Evolutions/README.md` 加 `cross-repository draft` 一行，0056 的暂缓表里把第 4 步那一行
   指向本提案。
   - 行为：`callersToolReturnsAPartialResultAfterThirtySeconds`
   - 行为：`symbolicateToolRequiresAWindowIdentifier`

**收尾时必须判断两件事**（判断结果写进决策日志，不允许沉默跳过）：

- **要不要配套专题文章** —— 预判要写一份 CLI 使用指南：「地址一律未滑动」「字符串引用要打开才记录」「截断
  标记」这几条契约在签名里看不出来。模块参考文档本身按约定更新。
- **有没有引入新术语** —— 预计有「地址符号化（symbolication）」「引用路线（route）」，以及 stub island、
  cache 共用桩若术语表里还没有。

## 决策日志

| 日期 | 变更 | 说明 |
|------|------|------|
| 2026-11-18 | Created as Draft | 调研了过去逆向卡住最久的地方，「跨镜像查谁用了它」与「地址起名」排在最前；用户选定先做这一块，并把它定为愿景《不依赖 IDA 的逆向》的第一步，伪代码不再是默认读物，IDA 退为后备 |
| 2026-11-18 | 参照 Binary Ninja | 用户指出 IDA 的交叉引用弱、Binary Ninja 强。调研了它开源的 shared cache 视图与 ObjC 插件：采纳桩按节名判定与 `j_` 式命名、引用按来源种类标注（本提案的 `route`）、地址写成十六进制字符串、结果带截断标记；selector → IMP 的数据引用留给愿景第 3 阶段 |
| 2026-11-18 | Binary Ninja 6 的 MCP | 用户升级到 Binary Ninja 6.0。它的 GUI 内 MCP 服务器 Personal 版也有，可作第 3 步的结果核对；无界面版仍要 Commercial / Ultimate，所以不作后端 |
| 2026-11-18 | 实测后改用 IDA 核对 | 在 Finder 与 ControlCenter 上实测：代码引用召回 IDA 两跳 99.4%、Binary Ninja 经 MCP 67.6%。第 3 步的核对改以独立生成的标准答案为准、IDA 对照、Binary Ninja 补充；双方的三处盲点（页对齐类对象、Swift 大字符串、`retab` 后的清理代码）加成测试 |
