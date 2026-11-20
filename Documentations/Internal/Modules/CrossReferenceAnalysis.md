# CrossReferenceAnalysis

从 arm64 机器码里读出一个镜像的函数表，以及每个函数引用了什么：直接调用与尾调用、ObjC 消息发送、`super` 发送、经桩的跨库调用、间接调用、ObjC 类引用、Swift 类型引用。读进程里加载的 `MachOImage`，也读磁盘上的 dyld shared cache 文件与独立 Mach-O 文件（「文件模式」一节），只支持 arm64 / arm64e。RuntimeViewer 的交叉引用功能（调用者、被调、类型引用）建在它上面。

- 提案：[0072-cross-reference-analysis](../../Evolutions/0072-cross-reference-analysis.md)（本库这一层）、[0076-objc-runtime-send-entry-points](../../Evolutions/0076-objc-runtime-send-entry-points.md)（libobjc 的发送入口）；整体设计、实测数据在 RuntimeViewer 的 [0056-cross-references](https://github.com/MxIris-Reverse-Engineering/RuntimeViewer/blob/next/Documentations/Evolutions/0056-cross-references.md)。
- 依赖：MachOKit、MachOKitExtensions 的 `ARM64InstructionDecoding` 与 `MachOCodeReferences`（核心层）、MachOObjCSection 的 `ObjCCodeReferences`（ObjC 层）；第二批起还有 `MachOObjCSection`（方法表、类的只读数据）、`MachOSwiftSection` 与 `SwiftInspection`（Swift 元数据与 `SymbolicDemangler`）、`Demangling`——给符号表没有名字的函数起名，以及认出扫描碰到的类与类型（类列表、类型描述符、mangled 名字）。不依赖 Capstone。

## 三层与识别器

交叉引用分成三个模块，依赖从上到下（提案 [0097-offline-cross-references-and-symbolication](../../Evolutions/0097-offline-cross-references-and-symbolication.md) 第 2 步在本库里拆开，提案 [0098 move-cross-reference-layers](../../Evolutions/0098-move-cross-reference-layers.md) 把下两层搬去各自的落脚处）。三层的代码一起演进，这份文档是它们的总说明；两个下层仓库里的实现说明只讲各自的边界与测试：

- **`MachOCodeReferences`**（核心层，在 MachOKitExtensions，原名 `CrossReferenceCore`，[实现说明](https://github.com/MxIris-Reverse-Engineering/MachOKitExtensions/blob/main/Documentations/Internal/MachOCodeReferences.md)）：读取层、镜像集 `CodeImageSet`（镜像、路径、内存区间、按镜像缓存的函数表、链接关系与改名再导出）、函数表、指令扫描与寄存器跟踪、按导入名与链接关系预筛、导出表起名，以及识别器扩展点。不认识任何一种语言：源码里不许出现 `objc_` / `swift_` 开头的字面量（MachOKitExtensions 的 `SourceScanTests`）。离线的地址空间、桩链与槽解析在同包的 `MachOAddressResolution`（原 `CodeAddressResolution`，[实现说明](https://github.com/MxIris-Reverse-Engineering/MachOKitExtensions/blob/main/Documentations/Internal/MachOAddressResolution.md)），手写的 A64 解码在 `ARM64InstructionDecoding`（[实现说明](https://github.com/MxIris-Reverse-Engineering/MachOKitExtensions/blob/main/Documentations/Internal/ARM64InstructionDecoding.md)）。
- **`ObjCCodeReferences`**（ObjC 层，在 MachOObjCSection，原名 `CrossReferenceObjC`，[实现说明](https://github.com/MxIris-Reverse-Engineering/MachOObjCSection/blob/next/Documentations/Internal/ObjCCodeReferences.md)）：`objc_msgSend` 系列与 libobjc 专用入口、`__objc_stubs` 与 cache 共用 selector 桩的含义、selector 与接收者、classref / superref / 类对象、ObjC 方法列表起名、按 selector 与类预筛、libobjc 的运行时辅助函数名单。
- **`CrossReferenceAnalysis`**（Swift 层兼门面，留在本库）：Swift 元数据访问器、值类型元数据、mangled name、Swift 类型查询与 Swift 元数据起名、Swift 运行时的辅助函数名单；`CrossReferenceAnalyzer` 把三层拼起来，持有全部公开模型，`@_exported import` 两个下层模块，所以 `import CrossReferenceAnalysis` 照旧看得到 `CodeLocation`、`ReceiverClassHint` 这些下移的类型。下层的其余接口都是 `@_spi(Internals) public`，不经 `@_exported` 漏出去，门面与测试按文件 `@_spi(Internals) import`。

**识别器怎么接进扫描。** 核心层定义 `CodeReferenceRecognitionSession` 与 `CodeReferenceRecording` 两个 SPI 协议（`MachOCodeReferences` 的 `Recognition/CodeReferenceRecognition.swift`）。门面每次扫描为 ObjC 层、Swift 层各建一个会话，排成一列交给核心的 `ReferenceScanner`，核心只在五个时机问它们：进入函数（ObjC 会话在 `x0` 打「方法接收者」标记，`RegisterFile` 的标记位是通用的）、解析只有会话认得的调用目标（`__objc_stubs`）、调用点、算出地址、读槽。为了不拖慢扫描：每个不同的调用目标只问一次各会话的角色（`role(of:)`，结果记在扫描器的调用计划里），没有角色的调用——绝大多数——不经过任何会话；地址与槽按地址记住是哪个会话认领的，没人认领的下次直接跳过。会话产出的引用不经核心转手，记到各层的记录协议上，门面里的 `ReferenceCollector` 实现全部三个，造出公开的 `CodeReference` 并按查询的键过滤。

**按镜像的缓存挂在函数表上。** 各层按镜像读的东西作为函数表的「附件」（`ImageFunctionTable.attachment(_:makingIt:)`）：核心层的导出表名字 `ExportedFunctionNames`、ObjC 层的节范围 `ObjCImageSections` 与方法名 `ObjCMethodNames`、Swift 层的元数据名字 `SwiftMetadataNames`，随表一起留下或释放，`approximateByteCount` 把它们算进表里。类索引与 Swift 类型索引仍由各层的识别器按镜像记住。

## 文件模式

`CrossReferenceAnalyzer(dyldCache:)` 读一个 cache 文件里的全部镜像（归档的、别的设备的），`CrossReferenceAnalyzer(machOFiles:)` 读一组独立文件（一个 app 的主程序与它自带的框架），公开 API 与进程内一样（提案 [0097-offline-cross-references-and-symbolication](../../Evolutions/0097-offline-cross-references-and-symbolication.md) 第 4 步）。

- **镜像与 `__LINKEDIT`**：每个镜像是一个 `CodeImage`，`reader` 是 `MachOImage` 或 `MachOFile`；两种读取器的差别——slide（进程内是镜像的 slide，cache 文件里是 0）、MachOSwiftSection / MachOObjCSection 给出的 offset 落在哪个地址——只在构造它的地方定一次。符号表、间接符号、函数起点、data in code、导出树一律由 `ImageLinkEdit` 按「`__LINKEDIT` 的地址 + 表的偏移 − 段的文件偏移」经读取层读，进程内与文件里是同一个算法；镜像自带的桩按 `S_SYMBOL_STUBS` 的 `reserved1/2` 逐个读字节、按形状认。
- **读取器专属的 API**：MachOObjCSection 的类、方法表与 MachOKit 的 objc 桩是各读取器一套，ObjC 层经 `asMachOImage` / `asMachOFile` 分两条路读；文件里方法的 `imp` 是读取器 offset，进程内是运行时地址，类在文件里从不 realize。Swift 层经 `MachOSwiftSectionRepresentableWithCache` 泛型读描述符；文件里的 mangled name 经文件的读取上下文解（进程内照旧经 `InProcessContext`）。
- **地址**：cache 文件里地址就是未滑动地址。一组独立文件按 dyld 的做法错开：与已放下的重叠就滑到其后的下一个 MB 边界（多数框架链接在 0，所以除第一个外都会滑），对外的 `CodeLocation` 仍是各文件自己的地址。
- **`FileCrossReferenceMemory`**：字节取自 MachOKit 打开文件时的映射（`fileBytes`）。cache 的槽按 mapping 预取的 slide info 解，v5（macOS 14 / iOS 17 起的 arm64e cache）在读取层里直接解，没有 slide info 的（模拟器 cache）与其余版本交给 MachOKit。独立文件的槽经 `SlotResolver`：bind 落到所覆盖文件导出的同名符号上（self-bind 即落到自己），没有就是导入名；链式 fixup 的 rebase 是「`__TEXT` 地址 + 偏移」；没有链式 fixup、靠 opcode rebase 的旧文件，槽里本来就是地址。按名字查，不分 bind 指名的是哪个库。
- **读取层是值，不持有存储**：经 `any CrossReferenceMemory` 的每次读都复制一次读取层，类或持有引用的值每次复制都要计一次数——第一版这样写，整 cache 建表比进程内慢 6 倍以上。现在它以 `unowned(unsafe)` 引用存储，存储由镜像集持有，读取层只在镜像集活着时有效。
- **只给一个 app 时的缺口**：经 GOT 槽读别的镜像的类、ivar 或数据，槽里是 bind，眼下不记任何引用（进程内会记成类引用），补在第 5 步；调用照常记成导入符号，`_objc_msgSend` / `_objc_msgSendSuper2` 按名字认成发送。一个 app 连同系统 cache 一起分析还不支持。

## 引用种类与路线

提案 [0097-offline-cross-references-and-symbolication](../../Evolutions/0097-offline-cross-references-and-symbolication.md) 第 5 步加了三种目标、对导入符号的数据引用，以及每条引用的「路线」。

- **ivar**：`.objectiveCInstanceVariable(className:name:)`。代码经 `adrp; ldrsw`（或 ld64 改写出的字面量 `ldrsw`、Swift 的 64 位 `ldr`）读 `__objc_ivar` 里的偏移变量；ObjC 会话把这个节作为「观察的槽」，核心在 32 位与 64 位载入时都问它。名字先取 `_OBJC_IVAR_$_<类>.<变量>` 符号，没有符号再从类的 ivar 列表反查（列表项的第一个字段指向偏移变量，第二个是名字），在 ObjC 层的附件 `ObjCInstanceVariableNames` 里，第一次碰到时读。父类是 `NSObject` 的类，clang 直接用常量偏移，不经偏移变量；Swift 类经 ObjC ivar 列表登记的偏移变量是 `__data` 里的 Swift 字段偏移全局量，不在 `__objc_ivar`，眼下不收。
- **字符串**：`.cString(String)`（`adrp; add` 或 `adr` 落进 C 字符串节——`__cstring`、`__objc_methname`、`__oslogstring` 等 `S_CSTRING_LITERALS` 节）与 `.constantString(String)`（落进 `__cfstring`，按 `{ isa, flags, characters, length }` 读，`flags & 0x10` 是 UTF-16）。核心层认，默认不记：分析器用 `recordingStringReferences: true` 打开（`recordsStringReferences`），查询里含 `.cString` / `.constantString` 键时那次扫描也会找。减法算出的地址从不当作字符串：Swift 的大字符串字面量是 `adrp; add; sub #0x20`，`add` 已经指到字符串起点，`sub` 之后的地址会落进前一个字符串中间。
- **对导入符号的数据引用**：从引用槽（GOT 等）读到一个 bind，而它绑到的符号不在分析器覆盖的镜像里——只给一个 app 时读 `_OBJC_CLASS_$_CALayer`、ivar、全局量都是这样——记成 `.importedSymbol(name:)`、`kind == .reference`。进程内槽里都是地址，不会出现。查一个类的全部引用时，调用方还要查 `_OBJC_CLASS_$_<类>` 这个导入名。
- **路线**：`CodeReference.route`（`CodeReferenceRoute`，核心层定义）说明这条引用是怎么到达目标的，不说明目标是什么。`direct`（`bl` / `b` 直达）、`imageStub`（本镜像的 `__stubs`、`__auth_stubs`、`__objc_stubs`）、`stubIsland`（cache 镜像之间的 stub island，可多跳）、`cacheSharedStub`（macOS / iOS 27 整个 cache 共用的 selector 桩与 GOT 桩）、`pointerSlot`（经指针槽载入：GOT、ObjC 引用节、ivar 偏移变量）、`addressMaterialization`（`adrp; add` 或 `adr` 算地址）、`literalLoad`（字面量 `ldr`）、`indirect`（经寄存器的调用与跳转，认证与否看证据）。调用的路线由 `CallTargetResolver.resolveWithRoute(_:)` 给出，经多跳时取第一种跳板；会话认领的目标按地址落在哪定（本镜像代码直达、本镜像其他节经本镜像桩、镜像之外经 cache 共用桩）。常驻索引把路线存在每条记录 `flags` 的第 5–7 位。

## 地址符号化

`symbolication(of:)` 回答「这个未滑动地址是什么」（第 6 步）：在哪个镜像、段与节，以及在那里的意思——函数体里（起点、名字、偏移；名字的来源与 `functions(inImageAt:)` 相同，含 ObjC 方法表与 Swift 元数据的后备名）、桩或跳板（经过的每一跳与最终目标）、指针槽（种类与里面装的东西）、字符串、最近的符号加偏移、映射着但什么都不是（`.data`），或没有映射。核心层的 `AddressPlace`（MachOKitExtensions 的 `MachOCodeReferences/Symbolication/`）判断结构：先找镜像（按各镜像用到的 slide 逐一试，cache 优先），再看节——`__text` 是函数，`S_SYMBOL_STUBS` 是本镜像的桩（经 `CallTargetResolver` 解目标），镜像之间的可执行映射是跳板链（逐跳读 `ARM64Trampoline`），GOT、懒指针与语言层报上来的引用节是槽（经读取层解槽），C 字符串节与 `__cfstring` 是字符串，其余给最近的符号。门面再补语言层知道的：`__objc_stubs` 的 selector、槽里的类与 Swift 类型、selector 引用的 selector、protocol 引用的名字、`__objc_ivar` 的 ivar。一组独立文件各留自己的地址，两个文件都有的地址取第一个，`symbolication(of:inImageAt:)` 指定镜像。符号化用留存的函数表：地址很少只问一个。

## 子系统

| 子系统 | 文件 | 分工 |
|---|---|---|
| 0. 读取 | Core `Memory/CrossReferenceMemory`、`Memory/InProcessCrossReferenceMemory` | 分析器读镜像内存的唯一入口：按分析器地址空间里的地址取一段只读字节、问一个指针槽里装着什么（`slotContent(at:)`，去掉签名与标记位）、给出地址掩码；整段读槽与把一组地址换成指针各有批量接口（selector 预筛按块读，不再每个槽一次 existential 调用）。进程内实现直接读本进程内存，槽里是 dyld 已绑定的值；`Memory/FileCrossReferenceMemory` 读文件，在槽上解 fixup（「文件模式」一节）。三个模块里只有进程内实现那一个文件允许把地址变成指针（`MemoryAccessScanTests`） |
| 1. 指令字与跳板 | MachOKitExtensions 的 `ARM64InstructionDecoding` 模块的 `ARM64InstructionWord`、`ARM64Trampoline` | 手写读取少数几类 A64 编码；按形状认 GOT 桩、stub island 与全缓存共用的 selector 桩。与 SwiftThunkAnalysis 共用 |
| 2. 地址空间 | Core `Images/CodeImageSet`、`Images/CodeImage`（含 `ImageLinkEdit`）；门面 `CrossReferenceAnalyzer` | 进程里全部镜像（整个共享缓存加缓存外已加载的镜像），或一个 cache 文件、一组独立文件的镜像；各镜像的路径与安装名、`__TEXT` 的内存区间、缓存的可执行与可读映射、运行时库里的辅助函数位置；给函数起名要用的函数表按需建一次并记住。宿主可以预先读好一个镜像起名、查类、查类型要用的一切（`prepareNames(inImageAt:)`），放掉其余镜像的（`releaseImageData(exceptForImagesAt:)`），并估算一个镜像留着多少（`approximateByteCount(ofImageDataAt:)`，`Scanning/ApproximateSize`） |
| 3. 函数表 | Core `Scanning/ImageFunctionTable` | 函数起点（`LC_FUNCTION_STARTS` 与 `__text` 里的符号取并集）、主名与代码合并留下的别名、辅助函数（名单由两个语言层给）、镜像自带的 `__stubs` / `__auth_stubs`、GOT、各段的地址区间；各层的附件 |
| 3a. 补充名字 | Core `Scanning/ExportedFunctionNames`、ObjC `ObjCMethodNames`、Swift `Scanning/SwiftMetadataNames`；门面 `codeFunction(at:in:)` | 符号表没有名字的函数，依次从导出表、ObjC 方法表、Swift 元数据起名；起名时按镜像按需读，扫描不读 |
| 3b. 类索引 | ObjC `ObjectiveCClassIndex`、`ObjCImageSections` | 一个镜像定义的类与元类，按地址；直接读 `__objc_classlist` 与各类的 `isa`。扫描时按需建、ObjC 识别器记住；类名只在报出引用时读。`ObjCImageSections` 是镜像的 `__objc_stubs`、selref、classref 与 superref |
| 3c. 类型索引 | Swift `Scanning/SwiftTypeIndex` | 一个镜像 `__swift5_types` 列出的描述符与各自的元数据访问器；类型的 key 按需算，优先取 `…Mn` 符号；按 key 找类型时只算描述符名字相同的那几个 |
| 4. 扫描 | Core `Scanning/ReferenceScanner`（含 `CallTargetResolver`）、`Scanning/RegisterFile`、`Recognition/`；ObjC `ObjCCodeReferenceRecognizer`；Swift `Scanning/SwiftCodeReferenceRecognizer`；`ObjCRuntimeHelperNames`、`Scanning/SwiftRuntimeHelperNames` | 逐条解码、跟踪寄存器、解析调用目标（核心）；发送与类引用（ObjC 会话）；Swift 类型引用（Swift 会话） |
| 5. 结果 | `Models/*`（`CodeLocation`、`CodeReferenceKind`、`IndirectCallEvidence` 在核心层，`ReceiverClassHint` 在 ObjC 层） | `CodeLocation`、`CodeFunction`、`CodeReference`、`CodeReferenceTarget`、按目标分组的 `CodeReferenceTable`，以及给宿主常驻用的紧凑版 `CodeReferenceIndex` |
| 6. 预筛与过滤 | Core `Images/CodeImageSet+Linkage`、`Scanning/RenamedReexportIndex`；ObjC `ObjCCodeReferenceRecognizer+Prefiltering`；门面 `CrossReferenceAnalyzer+Prefiltering`、`+Linkage`、`references(to:inImageAt:)` | 按未定义符号（只对 C 与 ObjC 符号，连同别的镜像改名再导出的名字）、链接关系（Swift 符号）、`__objc_selrefs`、类对象上的符号筛出可能引用某个符号、selector 或类的镜像；扫描时只留命中的引用；`preparePrefilters()` 让宿主在后台单线程预先读好链接关系与改名再导出表 |
| 7. 类型查询 | `CrossReferenceAnalyzer+SwiftTypes` | Swift 类型的身份、预筛与按类型的扫描；`SwiftTypeQuery` 比对描述符位置与名字里的符号引用 |

## 关键契约

### 地址

`CodeLocation` 是（镜像在 `images` 里的位置，镜像自己的未滑动地址）。缓存外两个镜像的未滑动地址可能重合，所以位置必须带镜像。跨镜像的查找一律换成运行时地址（未滑动地址加该镜像的 slide）再查 `__TEXT` 区间表，算完再换回 `CodeLocation`。

**镜像的路径是 dyld 加载它的路径。** 缓存里的镜像就是安装名；缓存外的取 `dladdr` 按镜像头读到的加载路径——App 的主程序与插件 bundle 没有安装名（`MachOImage.path` 为空），App 自带的框架的安装名是 `@rpath/…`，哪个都对不上宿主手里的路径（交叉引用审查 B3，2026-10-17 之前就是这样，缓存外的镜像查不到）。另有一张「安装名 → 镜像」的表给加载命令解析链接关系用：同一安装名的两份拷贝（两个插件各带一份同一框架）都算；`imageIndex(forPath:)` 先按路径、再按安装名找。用 `-bundle_loader` 链接宿主的插件经 `EXECUTABLE_ORDINAL` 绑定主程序，没有加载命令指向它，所以每个 bundle 都算作主程序的依赖方。

函数起点由 `ImageLinkEdit` 自己解 `LC_FUNCTION_STARTS`：ULEB128 增量从 `__TEXT` 的 vmaddr 起算，得到的就是未滑动地址。（以前经 MachOKit 在内存镜像上读，它给的 `FunctionStart.offset` 已经是绝对地址，与文档注释「相对 mach header 的偏移」不符，当成偏移再加一次基址会整张表被滤空。）

### 两种桩布局

macOS 27 / iOS 27 起的那种见术语表 [cache-shared stub（全缓存共用桩）](../../Glossary.md)。

| 缓存 | ObjC 消息 | 跨库调用 |
|---|---|---|
| macOS 15 至 26、iOS 26 及更早的真机，以及 Simulator | 镜像自己的 `__objc_stubs`（经 MachOKit `objcStubs(in:)` 读 selector 引用） | 镜像自己的 `__stubs` / `__auth_stubs`（MachOKit `stubs(in:)` 给出槽位；它读不出的 ld64 改写形态由 `ARM64Trampoline` 补读，见「链接器改写过的代码」） |
| macOS 27、iOS 27 真机 | 镜像里的段大小为 0；`bl` 落到全缓存共用的 selector 桩：`adrp x1; add x1; b <objc_msgSend 副本>`，`x1` 就是 selector 字符串 | 全缓存共用的 GOT 桩：`adrp x17; add x17; ldr x16, [x17]; braa x16, x17` |

同一个 selector 在不同子缓存里各有一份共用桩（macOS 27.2：被调用的 155 万个桩只对应 104 万个字符串），所以 selector 以字符串为键，不以桩地址为键。GOT 槽在进程内已经绑定，读出指针、去掉指针认证位就是目标；读之前先确认槽位落在缓存的映射里。

**去掉哪些位按平台定。** 从进程内存读出的指针（GOT 槽、selector 引用、类列表与 `isa`、Swift 类元数据 +0x40 与值类型元数据 +8 的描述符）一律经读取层的 `slotContent(at:)` / `pointer(at:)`，进程内用 `InProcessContext.addressMask`，即 MachOKitExtensions 按镜像平台给的 `vmaddrMask`。Mac 的用户地址是 47 位，iPhone 等真机是 36 位，arm64e 的签名从地址宽度之上开始，iPhone 上从第 39 位开始。0.24.0 在六处写死了 Mac 的 47 位掩码，在 iOS、tvOS、watchOS、visionOS 真机上会把签名的第 39–46 位留在地址里，带签名的槽位全都跟不过去（第二轮审查 N1）；`AddressMaskScanTests` 扫遍库的源码，不许再出现这种常量。

不经桩、直接 `bl` / `b` 到 `objc_msgSend` 的传统写法还有第三种形态：缓存构建器把读 selector 引用的 `adrp` / `ldr` 改写成了 `adrp` / `add` 出字符串本身的地址，指令里只剩字符串地址。macOS 27.2 的 `-[NSObject debugDescription]` 就是 `adrp x8; add x1, x8, #…; b _objc_msgSend`（`objc_msgSend` 在 `/usr/lib/objc/libobjcMsgSend.dylib` 里）。所以传统发送的 selector 两处都要认：`x1` 从本镜像的 `__objc_selrefs` 读来，或 `x1` 是 `adrp` / `add` 算出的地址；后者要确认它落在映射里、到结尾为止是不含空格的可打印字符（最长 1,024 字节），不满足就不当作发送。第一批漏了后一种，这些发送全被当成对 `objc_msgSend` 的普通调用；RuntimeViewer 第 3 步查 `-[NSObject description]` 的调用者时发现。

### libobjc 的发送入口（提案 [0076-objc-runtime-send-entry-points](../../Evolutions/0076-objc-runtime-send-entry-points.md)）

clang 把一部分发送编成对 libobjc 专用入口的调用：`[[Foo alloc] init]` 是 `objc_alloc_init(Foo)`，`[Foo alloc]`、`[Foo allocWithZone:nil]`、`[Foo new]` 是 `objc_alloc`、`objc_allocWithZone`、`objc_opt_new`，`[x self]`、`[x class]` 是 `objc_opt_self`、`objc_opt_class`，`[x isKindOfClass:c]`、`[x respondsToSelector:s]` 是 `objc_opt_isKindOfClass`、`objc_opt_respondsToSelector`。这样的发送不经 `objc_msgSend`，镜像里也可能没有这个 selector 的引用。macOS 26.6 的 AppKit 里 `objc_alloc_init` 有 2,488 处，按 selector 发送的 `init` 只有 720 处；`objc_opt_isKindOfClass` 3,369 处、`objc_opt_respondsToSelector` 2,977 处、`objc_opt_new` 590 处，对应的 selector 一次直接发送都没有。0.24.0 只认 `objc_msgSend`，这些都记成对 libobjc 函数的普通调用，查 `init` 的调用者漏掉约 78%，查另外几个一处都查不到（第二轮审查第 2 条）。

现在每处这样的调用记成它代表的发送（ObjC 层的 `MessageSendEntryPoints`）：

- 入口按 libobjc 里的位置认，经桩、GOT 或共用桩到达都算；桩跟不过去、只剩导入名时按名字认。
- 接收者按 `x0` 判断，与 `objc_msgSend` 相同。`objc_alloc_init` 在同一条指令上记 `alloc` 与 `init` 两条发送，`init` 发给 `alloc` 返回的实例，接收者记 `.unknown`。
- 这些调用不再同时记成对 C 函数的调用：按函数查 `_objc_alloc_init` 的调用者没有结果，按 selector 查才对，与 `objc_msgSend` 的处理一致。
- `objc_opt_self` 调用之后 `x0` 照旧保留；`objc_opt_class` 只在 `x0` 是类对象时照旧保留（见「类引用」的类字面量接收者）。
- `objc_retain`、`objc_release`、`objc_autorelease` 不算：ARC 插入的调用与源码里的 `[x retain]` 编出来是同一个调用，分不开，仍是运行时辅助调用。
- selector 预筛（`imageIndices(referencingSelector:among:)`）对这几个 selector 另外留下导入或定义对应入口的镜像：只经 `objc_alloc_init` 发送 `init` 的镜像，`__objc_selrefs` 里根本没有 `init`。

### 链接器改写过的代码（第二轮审查）

ld64——Xcode 14 及更早的链接器，以及 Xcode 15、16 加 `-ld_classic` 时用的那个——排好地址之后，会按编译器留下的 linker optimization hint 改写指令：槽位在一兆字节以内的 `adrp` / `ldr` 改成 `nop` / `ldr xN, <槽>`，地址在一兆字节以内的 `adrp` / `add` 改成 `adr xN, <地址>` / `nop`，懒绑定的桩改成 `nop` / `ldr x16, <槽>` / `br x16`。Xcode 26 的链接器不做这种改写，Xcode 27 不再带 `ld-classic`，Apple 自己的二进制里也没有；用旧工具链链接的第三方 App 里却常见。抽查的 12 个第三方 App 里有 2 个，其中 Asset Catalog Viewer（macOS 12 SDK）有 357 处 selector 引用和 71 处类引用以字面量 `ldr` 载入，212 个桩全是改写过的形态。

扫描把这些形态读成改写之前的样子：

- 字面量 `ldr` 是从已知槽位载入（`RegisterFile.load(into:fromSlotAt:)`），载入的偏移记成槽位在页内的偏移，与改写前那对指令记下的相同。之后按槽位认 selector、类引用与 `__objc_superrefs`，与 `adrp` / `ldr` 一样。
- `adr` 与 `adrp` / `add` 一样：算出的地址是类对象、元数据或元数据访问器时，报一处引用。`ARM64InstructionWord.addressMaterialization` 的 `isPageAddress` 区分两者，只给出页地址的 `adrp` 不报。
- 改写过的桩，MachOKit（0.54.101）的 `stubs(in:)` 读不出槽位，给的是 `.unknown`；`ImageFunctionTable` 这时改用 `ARM64Trampoline` 读桩自己的字节，`ARM64Trampoline` 认字面量 `ldr`。SwiftThunkAnalysis 也经 `ARM64Trampoline` 认桩，同样受益。0.24.0 时这些桩只剩导入名，经它们调用 `objc_msgSend` 的发送一处也认不出来。

SwiftThunkAnalysis 自己的 Capstone 解码器原先也把字面量 `ldr` 当成不建模的指令，同一轮补上了 `ThunkOperation.loadFromSlot`，求值时按槽位读，与 `adrp` / `ldr` 相同。0.24.0 之前的设计判断是「缓存与几个缓存外的系统 App 里都没有这两种形态，不解码」，那次只量了 Apple 自己的二进制。

`LinkerOptimizationHintTests` 现编两个 dylib，按 ld64 的做法把这几种指令改写好、重新签名后加载，核对四种形态都读对；修复前四个测试都失败。

### 读任何目标之前先确认它可读

`__text` 里夹着数据（跳转表之类，缓存镜像的 `LC_DATA_IN_CODE` 是空的），按指令解码会得到指向任意地址的「跳转」。扫描只在目标落在某个镜像的 `__TEXT`、或缓存的可执行映射里时才去读那里的指令；读槽位前确认它在缓存或镜像的映射里。探针第一次全量扫描就崩在没做这一步上。

### 寄存器跟踪只记确定的事

`RegisterFile` 只记录 `adrp` / `adr` / `add` 算出的地址、从已知地址加载的槽位（`ldr` 的基址算得出来，或者是字面量 `ldr xN, <槽>`）、ObjC 方法入口时 `x0` 里的接收者、指针认证常量，以及「这个寄存器的值是从内存读来的」和读取时的偏移。不建模的指令一律作废它写的寄存器（宁可多忘，不留陈旧的值）；调用作废 `x0`–`x18` 与 `x30`——原样返回所传类的三个函数例外，`x0` 留着（见「类引用」）。PAC 与 AUT 原地签名或认证，寄存器的含义不变，保留；XPAC 作废。

一条指令写哪些寄存器由 `RegisterFile.registersWritten(by:)` 按 A64 的编码分组判断，容易漏的几类：前 / 后变址的读写（单寄存器与寄存器对、通用与 SIMD 寄存器都一样）会改掉基址寄存器；原子指令不论内存序都返回旧值，不带内存序的那种（`ldadd`、`swp`）编码像存储；`ldxp` 写第二个寄存器，`casp` 写 `Rs` 与 `Rs+1`；`umov` / `smov`、浮点转整数与转定点写通用寄存器；SVE / SME 里有几条写通用寄存器（`cntd`、`addvl`、`rdsvl`）；`mrs` 与 `sysl`；`svc` 的结果在 `x0`、`x1`。第一批漏了其中大半（交叉引用审查 A1）；`RegisterFileTests` 用汇编器编出的 48 条指令逐条核对，并用 Capstone 的寄存器访问表独立核对那张表没有漏项（Capstone 把 `cas` / `casp` 的基址也算作被写，架构上并不写，测试里列为已知偏差）。SwiftThunkAnalysis 的两个跟踪器同一轮补上了成对回写的基址。

**寄存器状态沿着分支走（第二批）。** 一个函数内：向前的分支（条件跳转与 `b`）把当时的寄存器状态带到目标处；目标处若前一条是无条件转移（`b`、`br`、`ret`），就以带来的状态为准，否则与顺序走下来的状态取交集——同一个寄存器两条路径放的东西一致才保留。无条件转移之后没有分支指向的指令（跳转表的落点之类）、以及向后分支的目标（循环头，回边的状态此时还不知道）忘掉调用方保存的寄存器。第一批只按指令顺序往下读，汇合处会沿用最后一条路径的值：`-[NSString stringByAppendingString:]` 里一个块把参数放进 `x0`、下一个块放 `self`，两者跳到同一处发送 `copyWithZone:`，顺序读法把接收者说成 `self`。这一改动让 AppKit 80 万处引用里 9,699 处发送多认出了 `self`（前一条路径的调用冲掉了 `x0`，而实际到达的路径没有），78 处不再说 `self`，selector 几乎不受影响；release 下全缓存整表扫描由 1.6–1.8 s 变为 2.0 s。快照是定长值（`SIMD32`），不分配内存；待到的目标与循环头按地址排序、随扫描游标前进。只记「无条件转移后忘掉」的简化版试过，会丢掉 `+[NSObject instanceMethodForSelector:]` 这类早退之后的正确接收者，弃用。

**已知局限（审查 A5，2026-10-17）。** 循环头与没人指向的落点只作废 `x0`–`x18`，`x19`–`x28` 可能带着到不了那里的旧值：`-[NSMenuItem _titlePathForUserKeyEquivalents]` 的循环把 `x22` 从 `self` 换成父菜单项再跳回，循环头之后的发送仍被说成发给 `self`。量过（release，六个大镜像 332 万条引用、257 个抽样镜像 711 万条）：对含循环的函数反复扫到回边状态不变的精确做法，与现行做法相差 0.04% / 0.02% 的引用，扫描多花 42% / 61%；循环头一律全部作废则会丢掉约 3.9 万条正确的事实（`self` 发送少 15%）。只作废「循环里写过的寄存器」的近似试了几版，都还会丢掉正确的事实，弃用。数据与抽查见 [2026-10-17 审查记录](../../../Roadmaps/2026-10-17-cross-reference-analysis-review-findings.md) A5。看过数据后决定保持现状，理由与复审条件见 [ReviewAdjudications A68](../ReviewAdjudications.md)。

### 尾调用与跳转表

`b` / 条件跳转的目标在本函数之外就是尾调用。经寄存器的 `br`：带认证的（`braa` 等）一律算尾调用；不带认证的，只有寄存器的值是从内存读来的（函数指针）才算——跳转表的目标是 `add` 算出来的，不算。

### 运行时辅助调用

名单分在两层维护（ObjC 层的 `ObjCRuntimeHelperNames`、Swift 层的 `SwiftRuntimeHelperNames`）：libobjc 的 retain / release / autorelease / weak 系列，Swift 运行时的 retain / release / bridgeObject / unknownObject / unowned / weak / beginAccess / endAccess，编译器写进每个镜像的 `___swift_*_boxed_opaque_existential*` / `___swift_memcpy*`，以及以 `WO` 加小写字母结尾的 outlined 值操作。跨镜像的辅助函数只在 libobjc、libswiftCore、libswift_Concurrency 里找；镜像内的在该镜像的函数表里标出。结果只打标记，过滤交给宿主。

### 类引用（第二批）

一条指令取了某个类对象的地址、但不跳转，就是一处类引用：`CodeReference.Kind.reference`，目标 `.objectiveCClass(name:location:)`。macOS 27.2 的缓存里几乎没有 `__objc_classrefs` 了，类有三种取法：`adrp` / `add` 出本镜像的类对象（AppKit 3,319 处）；从本镜像的 `__got` / `__auth_got` 载入；从缓存放在所有镜像之外的共用 GOT 池载入别的镜像的类（AppKit 后两种合计 53,026 处）。缓存外的二进制还经 `__objc_classrefs`。别的槽里即使放着类指针也不算：常量字符串的 `isa`（`__cfstring`）、缓存某个类的全局变量都不是对类的静态引用。ld64 改写出的 `adr` 与字面量 `ldr` 也按这三种取法认，见下文「链接器改写过的代码」。元类的引用按它的类报。

**一个值是不是类对象，看它所在的镜像列没列它。** 不能按所在的节判断：缓存里 9.2 万个 Swift 类与元类放在 `__data` 而不是 `__objc_data`。`ObjectiveCClassIndex` 直接读 `__objc_classlist` 与每个类的 `isa`（即元类），不经 `MachOImage.objc.classes64`——后者对每个类都重新查一遍 load command，扫描全缓存时让整表扫描慢了一倍。类名只在要报出引用时经 `MachOObjCSection` 读 `class_ro_t`（类已被运行时实现时经 `class_rw_t`）。

**类的身份带位置。** 全缓存 203,621 个类名里有 18,906 个不止一个镜像定义——多是 `/System/iOSSupport` 下的 Mac Catalyst 变体，两个 SwiftUI 都定义 `_TtC7SwiftUI13PinnedBarView`。引用表的键是类名（`CodeReferenceTable.Key.objectiveCClass`，预筛与过滤都按它），引用目标另带类对象的 `CodeLocation`，宿主按位置区分。`objectiveCClassLocations(named:inImageAt:)` 把宿主手里的（镜像，类名）换成位置。

**类字面量接收者。** 发送时 `x0` 里是这样取来的类，接收者记为 `.classLiteral(名字)`（AppKit 35,175 处，发送的 11%）。`objc_opt_self`、`swift_getInitializedObjCClass` 原样返回传入的参数，调用之后 `x0` 不作废：Swift 调 ObjC 类方法先过 `objc_opt_self`，SwiftUI 665 处类字面量接收者里 478 处经它。`objc_opt_class` 返回的是参数的类，只有参数本身是类对象时才等于参数：`x0` 是类字面量、或在类方法（`+[…]`）里是方法自己的接收者时照旧保留；在实例方法里，`[[self class] foo]` 的 `x0` 已是接收者的类而不是接收者，调用之后作废，接下来的发送记 `.unknown`（2026-11-16 体检第 1 条：此前一律保留，把对类方法的发送记成了发给实例，`ClassOfReceiverSendTests`）。`objc_opt_self`、`objc_opt_class` 本身也记成 `self`、`class` 发送（见「libobjc 的发送入口」）。

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

**查询**（`references(toSwiftType:inImageAt:)`）带一个比对器：访问器与元数据的引用比描述符位置；名字逐字节走，符号引用（`\x01` 直接、`\x02` 经指针）指向的描述符就是这个类型，就算提到了它。只有名字可能直接拼出来的类型——标准库、`_Concurrency`、从 C / ObjC 导入的，key 以 `s` 或 `S` 开头——才解开名字确认；文本子串比对不可靠，mangling 会把同一名字里重复出现的单词换成替身。前提是其他类型在名字里一定以符号引用出现：在 Foundation、SwiftData、libswift_Concurrency、SwiftUI 里逐个解开全部名字核对过，没有例外（AppIntentsServices 有 56 处 key 对不上，原始字节全是符号引用，是那个镜像没有 `…Mn` 符号造成的拼法差别）。导入的类型每个用到它的镜像各有一份描述符，比的是 key，比 key 之前先比描述符给的名字。名字只从类型描述符读（`SwiftTypeIndex.name(ofDescriptorAt:)` 先看标志位低五位的种类是不是 16–31）：符号引用指向的也可能是不透明类型（`some View`）的描述符，它在 +8 放的是泛型头，一个参数、一个约束读成偏移就是 64 KiB，在小镜像里读出镜像之外。0.24.0 没有这道检查，查导入类型时可能让宿主崩溃（第二轮审查 11，`importedTypeQueriesReadNoNameWhereNoTypeDescriptorIs` 在子进程里复现到 SIGBUS）。Swift 类同时比它的 ObjC 类对象的位置。macOS 与 Mac Catalyst 变体里的同一个类型按位置分开。协议没有类型描述符，不在这一批。

宿主的用法：类型对象 → 描述符位置（或经 `swiftTypeDescriptorLocations(withKey:inImageAt:)`，先找 `…Mn` 符号）→ `swiftTypeIdentity(ofDescriptorAt:)` → 预筛 → 每个候选镜像 `references(toSwiftType:inImageAt:)`。`swiftTypeKeys(in:)` 解开一个 `SwiftTypeName`，供显示用。

按 key 找类型，`…Mn` 符号在符号表里逐条比、在导出表里按名字查（不读整个导出表）。找不到符号时——缓存里的内部类型都是这样——只给描述符名字（`+8` 处的 `Name`）与 key 末段相同的类型算 key 再比：key 解开一次取出末段的名字（private 与局部类型取声明名），读不出名字的才退回给每个类型都算。从 C / ObjC 导入、在 Swift 里改了名的类型（`URLSession.ResponseDisposition`、`RunLoop.Mode`、`CFURL`），描述符的名字是 Swift 名，key 拼的却是 C 名（`So31NSURLSessionResponseDispositionV`、`So13NSRunLoopModea`、`So8CFURLRefa`）；C 名记在名字后面的导入信息里——描述符标志位 `HasImportInfo`（第一个字的第 18 位）为真时，名字后面跟着若干以 NUL 结尾、首字母是标签的串，空串结束，`N` 开头的那段是 C 名——两个都比。头一版只比 Swift 名，Foundation 与 AppKit 有 115 个导入类型因此找不到，核对全部类型的测试当场抓到。2026-10-18 之前每个类型都算一遍，一次 demangle 一个，AppKit 的第一次查找在 Debug 构建下要 0.7 秒、SwiftUICore 0.4 秒；现在约 1 毫秒。`typeLookupsCompareSameNamedTypesOnly` 对 Foundation 与 AppKit 的全部类型核对两种查法结果相同，且读不出名字的 key 不到 1%。

**预筛**（`imageIndices(referencingSwiftType:among:)`）：定义镜像本身；定义镜像导出了这个类型的符号时（描述符 `…Mn`、元数据访问器 `…Ma`、元数据 `…N` 任何一个），再加上能绑定到它的镜像（按链接关系，见下一节），类再并上类预筛；名字可能拼出来的类型——标准库的、导入的，每个镜像都可能自己命名——凡是 Swift 镜像都算。**一个符号都没导出的类型（内部类型）只可能被定义镜像引用**：别的镜像要引用它，只能经这几个符号绑定，或者在名字里拼出它，而内部类型在别的模块里拼不出来。2026-10-17 之前没有这条，AppKit 的内部结构体 `NSSmartNamingSuggestion` 一次类型引用查询要扫所有链接 AppKit 的镜像——几乎整个缓存，Debug 构建下要好几分钟（用户实测，CPU 占满）；现在只扫 AppKit 一个（测试 `typesNoImageExportsAreLookedForInTheirOwnImage`，并对链接 AppKit 的镜像每 64 个抽 1 个确认确实没有引用）。导出了没有，在导出表里按名字查这三个符号（`exportsSymbol(named:fromImageAt:)`）；2026-10-18 之前把整个导出表读成集合留着，SwiftUICore 第一次要 0.1 秒（Debug）、留下 6 MiB（`exportLookupsAgreeWithTheWholeTrie` 对 Foundation 与 AppKit 的全部类型核对两种查法结果相同）。Swift 函数不需要同样处理：缓存里没导出的函数在进程内看不到本地符号，没有 `.symbol` 名字，本来就不会按链接关系去扩大候选。

**代价**（release，28 核，与只有分支跟踪的那次提交交替跑）：全缓存整表 2.1 → 3.0 秒（引用 1.16 亿 → 1.26 亿条），查 `init` 的调用者 1.6 → 1.8 秒——只查 selector 或函数时不找类与类型引用，发送处的类字面量接收者照认。踩过两个坑。一是 `keep(reference(to: …))` 这种写法：参数里修改扫描器，外层又在同一个扫描器上调非 mutating 方法，Swift 只好每次把整个扫描器连同它的备忘字典复制一份，整表扫描一度要 95 秒——第一批的 `keep` 是静态方法，没有这个问题。二是类型索引若每次都去分析器的锁里取，等锁占掉大半时间；现在扫描器自己留一份（`ScanIndexes`，引用类型，解析调用目标的非 mutating 路径也用得上）。

### 预筛：缓存几乎不留 Swift 的未定义符号

macOS 27.2 的缓存里，4,113 个镜像只有 245 个在符号表里留着 Swift 的未定义符号（libswift 系列、Foundation、CoreData、AXCoreUtilities 等），其余的绑定 Swift 符号后什么也不留：SharedWithYou 留了 314 个未定义符号，全是 C 函数与 ObjC 类，可它照样经全缓存共用的 GOT 桩调用 `URL` 的元数据访问器；AppKit 的 5,085 个里也没有一个 `$s…`。所以「导入了某个符号的镜像」只对 C 与 ObjC 符号成立。第一批的函数预筛只拿 C 函数（`CFRelease`、`dispatch_async`）测过，对 Swift 函数一直是错的：查 `URL.path` 的调用者时只留下按名字导入它的 44 个镜像，其余调用它的镜像全被丢掉（`swiftFunctionPrefilterKeepsEveryCaller` 在旧做法下变红）。

**改名再导出。** 一个镜像可以把别的镜像的符号换个名字导出：libsystem_c 把 libsystem_platform 的 `__platform_strlen` 导出成 `_strlen`，CoreGraphics 把 SkyLight 的 1,112 个 `_SL…` 函数导出成 `_CG…`，UIFoundation 把 CoreText 的 `CTEmojiImageAsset` 类导出成 `NSEmojiImageAsset`。调用方导入的是新名字——AppKit 按 CoreGraphics 的名字导入了 273 个 SkyLight 函数——所以按导入预筛时这些名字也要比。macOS 27.2 的缓存里 12 个镜像共 1,438 条这样的再导出。`RenamedReexportIndex` 在第一次需要时并发走一遍所有镜像的导出表，只记改名的再导出（名字只在命中时拼出），按「被再导出的镜像与名字」归档，之后留着；`reexportedNames(ofSymbolsNamed:inImageAt:)` 顺着改名再改名、以及经伞形框架整体再导出的情形找全别名（acfsSupport 从 CoreServices 再导出 Metadata 的 `_kMDConfigErase`）。函数预筛与类预筛都把别名一并比对。2026-10-17 之前没有这一步，查 `__platform_strlen`、`_SLSMainConnectionID` 的跨库调用者会漏掉 AppKit（`RenamedReexportTests`）。

这张表与链接关系是跨全部已索引镜像查询的第一次必读的，宿主可以用 `preparePrefilters()` 在后台预先读好。它只用调用线程：Debug 构建单线程读完 macOS 27.2 缓存 144 MiB 的导出表要 3.9 秒，28 核并行也要 3.4 秒——并行几乎不快，后台工作不该为此占满所有核（`serialAndConcurrentReadsAgree` 核对两种读法结果相同）。表只建一次：建的时候来了要用它的查询，会等它建完，而不是再读一遍（`prefiltersAreBuiltOnce`）。链接关系 Debug 下约 60 毫秒。

Swift 符号改按链接关系预筛（`imageIndices(linkingImageAt:among:)`，`CrossReferenceAnalyzer+Linkage`）：一个镜像只能绑定到它链接的镜像，以及这些镜像（层层）再导出的镜像的符号，这些加载命令在缓存里完整保留——SwiftUI 再导出 SwiftUICore，链接 SwiftUI 的镜像就算能绑定 SwiftUICore。比按导入粗得多（链接 Foundation 的镜像数以千计），但不漏。宿主查函数的调用者用 `imageIndices(callingFunctionAt:symbolNames:among:)`：C 与 ObjC 名字按导入，Swift 名字按链接。Swift 类的类预筛、Swift 类型的类型预筛同理。链接关系第一次用到时读一遍所有镜像的加载命令，之后留着。

### 名字从哪来（第二批）

`CodeFunction.name` 依次取：符号表（`<redacted>` 当没有）；导出表（一个缓存镜像的符号表不一定带导出的符号——SiriAppIntents 的只有两条，导出表却给它的 76,318 个函数起了名；iOS 真机的缓存抹掉本地符号，导出表还在）；ObjC 方法表（类、元类、本镜像的分类；列表的列表里属于别的镜像的条目跳过，它们一定也在那个镜像自己的 `__objc_catlist` 里；元数据不记分类名，读出来是 `-[NSTextView draggingUpdated:]`）；Swift 元数据（类型的元数据访问器 `…Ma` 与 singleton 完成函数 `…Mr`，名字取描述符的 `…Mn` 符号，没有就经 `SymbolicDemangler` 从描述符重建；虚表实现取方法描述符的 `…Tq` 符号，没有就不起；async 实现先跟一步 `{rel32 函数, u32 大小}` 记录）。Swift 元数据给的名字是不带 C 前缀下划线的完整 mangled 名字（`.swiftMetadata(mangledName:)`），可以直接 demangle。

这些名字只在起名时（`codeFunction(at:)`，即 `functions(inImageAt:)`、`function(containing:)`、`functions(containing:)`、`symbolName(at:)`）按镜像读一次、记在函数表上；三个来源各自按需读，前面的来源已经起了名，后面的就不读。扫描不读它们：扫描只需要知道一个函数是不是 ObjC 方法（决定 `x0` 是不是接收者），这一点仍只看符号名。

宿主要第一次查询也不等，用 `prepareNames(inImageAt:)` 预先读好（2026-10-18，RuntimeViewer 的预先准备）：三个来源全读、类索引里的类名全读、类型索引的 `…Mn` 符号读好，函数表留住。每个函数的 Swift 名字仍在第一次给它起名时重建并记住。Debug 构建实测：

| 镜像 | 用时 | 留下的（连同函数表，`approximateByteCount(ofImageDataAt:)` 估算） | 引用索引 |
|---|---|---|---|
| AppKit | 0.33 s | 13.9 MiB | 21.1 MiB |
| SwiftUICore | 0.28 s | 12.5 MiB | 10.0 MiB |
| Foundation | 0.16 s | 7.1 MiB | 9.7 MiB |
| libswiftCore | 0.08 s | 3.1 MiB | 1.7 MiB |

估算按集合的容量与元素步长、字符串的堆存储算，不计分配器的取整；同一次运行里 malloc 的实测增量比它多一成左右。

代价（release，28 核）：给一个镜像的全部函数起名，AppKit 0.24 s（方法表补了 3,961 个、Swift 元数据补了 1,147 个），SiriAppIntents 1.5 s，Matter 0.04 s（方法表补了 30,863 个）。每个镜像起 32 个函数的名字、走遍整个缓存要 6.9 s，4 线程 6.1 s——并发几乎不变快：时间耗在 Swift 运行时的泛型元数据缓存（查找与锁等待）和加载命令的动态转换上，来自 `MachOObjCSection` 与元数据读取代码的泛型实现。宿主给大批结果起名时应只给要保留的那些起。

分析器自己找 `objc_msgSend`、`objc_msgSendSuper2` 与运行时辅助函数的位置时，也读运行时库的导出表，不只读符号表。

### 缓存外镜像的 GOT 槽

缓存外的镜像（第三方 App 自己的二进制）经自己的 `__stubs` / `__auth_stubs` 调别的镜像，槽位由 dyld 在加载时绑定，按 macOS 11 部署目标、不用 chained fixups 编出来的懒绑定二进制也一样：macOS 27.2 上以 `RTLD_LAZY` 加载，函数第一次被调用之前槽里已经是目标地址。所以扫描直接读槽。`LazyBindingTests` 是这件事的哨兵：哪天 dyld 不再在加载时绑定，槽会指回镜像自己的 `__stub_helper`，测试变红，那时再退回桩上的导入名。它在 macOS 27.2 与 26.6 上都通过（2026-10-27 第二轮审查据此把「懒绑定的槽指向 `__stub_helper`」判为误报，[ReviewAdjudications A80](../ReviewAdjudications.md)）。ld64 链接的懒绑定桩多半是改写过的 `nop` / `ldr x16, <槽>` / `br x16`，槽位由 `ARM64Trampoline` 读出，见上文「链接器改写过的代码」。

### 缓存、内存与生命周期

库里没有全局的按镜像缓存（因此不需要 `SharedCache`，理由见 [ReviewAdjudications](../ReviewAdjudications.md) A62）。`CrossReferenceAnalyzer` 记住宿主让它起过名的镜像的函数表（`functions(inImageAt:)`、`function(containing:)`、`references(madeBy:)`）；整镜像扫描（`referenceTable(ofImageAt:)`、`references(to:inImageAt:)`）临时建表、用完即丢；给一批结果起名用 `functions(containing:)`，同样临时建表——查 `init` 的调用者会碰到 2,759 个镜像，逐个记住又是上 GB——早先扫描也记表，扫完一遍 macOS 27.2 缓存后常驻 1.5 GB（`wholeImageScansKeepNoFunctionTable` 钉住）。

第二批起分析器还在自己的生命期里留着：扫描碰到的每个镜像的类索引（类与元类按地址，类名读过的记住）与类型索引（描述符与访问器，key 算过的记住），链接关系，以及改名再导出表。它们以缓存里的类与类型的总数为上限（macOS 27.2 有 203,621 个类名），没有单独测过占用；下面那个约 170 MB 的数字是第二批之前测的。宿主想放掉，用 `releaseImageData(exceptForImagesAt:)` 放掉指定镜像以外按镜像留着的一切——函数表连同读过的名字、类索引、类型索引；链接关系与改名再导出表不按镜像，留着——或者换一个分析器。RuntimeViewer 的会话在缓存外的镜像变化时换分析器；起过名的镜像（预先准备的除外）超过 64 个时，只放掉预先准备之外的。2026-10-18 之前后一种情况也是换分析器，预先读好的名字跟着丢了，下一次查询又得重读。

分析器存活期间若有缓存外的镜像被卸载，再读它会读到已释放的内存；极少见，没有防（A63）。名字的解开一律是瞬时的：类型查询碰到的访问器符号与 mangled 名字不进全局的 `NodeCache`，也不进进程级的 demangle 记忆（交叉引用审查 B2，`TypeNameRetentionTests`）。例外是没有 `…Mn` 符号的类型算 key、起名时用的 `SymbolicDemangler.demangleContext`：它的结果记在按镜像的 `SharedCache` 里，`releaseImageData(exceptForImagesAt:)` 不管它，由宿主调 `SharedCacheRegistry.shared.evictImagesWithoutLiveOwners()` 回收，与库里其它按镜像的缓存相同（[ReviewAdjudications A78](../ReviewAdjudications.md)）。

`CodeReferenceTable` 是值，宿主想留多久就留多久，按 `approximateByteCount` 计预算（不含字符串的堆存储；同一次扫描里重复的名字共用一份）。大镜像的整表很大（GeoServices 约 121 MiB，全缓存合计约 9 GB），28 个线程同时建整表时峰值约 1.5 GB，分配器之后还留着 1.2 GB 脏页不还。**查调用者用 `references(to:inImageAt:)`**：扫描时只留命中的引用，同样扫完全缓存后常驻约 170 MB（4 线程约 106 MB）。

**要为少数几个镜像常驻、反复查，用 `CodeReferenceIndex`**（`referenceIndex(ofImageAt:)`，2026-10-18 为 RuntimeViewer 的预先准备新增）。它按目标分组存放：选择子、导入名、类名每个只存一份，引用所在的函数与指令存成 32 位偏移（一条 16 字节），从镜像最低的函数起点算起。这个起点通常就是 `__text` 的起点，但主可执行文件的符号表把 `__mh_execute_header`（Mach header 本身）记在 `__text` 下，扫描把 header 连同 load commands 当成 `__text` 之前的一个函数来读。2026-11-20 之前偏移从 `__text` 起点算，那里扫出的引用存不下：Debug 构建触发断言，Release 构建存进截断的偏移、还原出的函数地址差 4 GiB（RuntimeViewer 在 iOS 27 上给 `Preferences` 建索引时撞上）。只留查调用者与查类型引用会读的引用，间接调用与落在镜像外的跳转不留。macOS 27.2 实测（`approximateByteCount`，含名字的堆存储）：AppKit 21 MiB（整表 67 MiB，87.5 万条引用里留 85.6 万条），Foundation 9 MiB（34），SwiftUICore 9 MiB（35），libswiftCore 1 MiB（7）。`index.references(to:)` 与 `references(toSwiftType:in:)` 回答的和过滤扫描完全相同，顺序也相同（按指令地址，同一条指令的调用排在它顺带的类型引用前面）。建索引会**留住**镜像的函数表——给结果起名要用；名字本身还要第一次起名时读，宿主要连这一步也提前，再调 `prepareNames(inImageAt:)`（见上文「名字从哪来」）。分析器被换掉后，索引照样能读（它不持有分析器），宿主用 `keepFunctionTable(ofImageAt:)` 让新分析器重新留住。`referenceIndex(ofImageAt:reportingProgress:)` 每扫 2,048 个函数报一次进度，回答「停」就不建了。Debug 构建建 AppKit 的索引约 6 秒。

分析器是一个快照：之后才加载的镜像需要新的分析器。

## 吞吐（macOS 27.2，28 核的 Mac Studio）

| 操作 | 现在（28 核） | 第一批：28 核 / 8 线程 / 4 线程 |
|---|---|---|
| 建分析器（4,114 个镜像：缓存的 4,113 个，加基准程序自己） | 0.06 秒 | 0.02 秒 |
| 每个镜像都建整表 | 3.0 秒（1.26 亿条引用） | 1.6–1.8 / 3.5 / 5.9 秒（1.16 亿条） |
| `init` 的调用者：预筛出 2,759 个镜像再过滤扫描 | 0.05 + 1.8 秒 | 0.05 + 1.5 秒 / — / 6.1 秒 |
| `makeKeyAndOrderFront:` 的调用者：105 个镜像 | 0.06 + 0.33 秒 | 0.06 + 0.26 秒 |

比第一批多出来的是寄存器状态沿着分支走（约 +10–20%）、类引用与 Swift 类型引用（整表约 +45%，只查 selector 或函数时约 +10%）。「现在」一列是在别的会话同时编译、负载较高的机器上交替跑多轮取的最好值。

**读取层与拆层的代价**（2026-11-19，同一台 Ultra，release，`ScanThroughputBenchmarkTests` 三方交替各三轮取最好；提案 [0097-offline-cross-references-and-symbolication](../../Evolutions/0097-offline-cross-references-and-symbolication.md) 第 1、2 步）：

| 操作 | 拆分前的 `next` | 第 1 步：读取层 | 第 2 步：三层与识别器 |
|---|---|---|---|
| 建分析器 | 0.054 秒 | 0.055 秒 | 0.055 秒 |
| 每个镜像都建整表（1.274 亿条引用） | 2.42 秒 | 2.54 秒 | 2.52 秒 |
| `init` 的调用者：预筛 2,880 个镜像 + 过滤扫描 | 0.038 + 1.663 秒 | 0.038 + 1.667 秒 | 0.039 + 1.698 秒 |
| `makeKeyAndOrderFront:` 的调用者：105 个镜像 | 0.050 + 0.309 秒 | 0.062 + 0.311 秒 | 0.059 + 0.325 秒 |

第 2 步相对第 1 步在 −0.5% 到 +3% 之间；整表多出的约 5% 来自第 1 步——每次读槽、读字符串都经读取层的 existential 调用。拆层第一次量时超过 5%，采样后改掉的几处见提案的决策日志：读槽先做区间排除再查认领表、调用计划不持有数组、只调用角色需要的会话方法、热路径上的类属性去掉运行时独占检查、函数表记下各节免得 ObjC 层再遍历 load command、selector 预筛按块批量读槽。

**文件模式**（2026-11-19，同一台 Ultra，release，`ScanThroughputBenchmarkTests` 加 `CROSS_REFERENCE_BENCHMARK_DYLD_CACHE`，三轮取最好；第 4 步）：

| 操作 | 进程内（第 4 步） | 归档的 macOS 27.2 cache 文件（外置卷） |
|---|---|---|
| 建分析器 | 0.055 秒 | 0.135 秒 |
| 进程里第一次查 `makeKeyAndOrderFront:` / `init` 的调用者 | — | 0.50 / 1.89 秒 |
| 每个镜像都建整表 | 2.48 秒（1.274 亿条；第 5、6 步之后 2.57–2.66 秒、1.292 亿条，多出的是 ivar 引用） | 2.58 秒（1.263 亿条，4,114 个镜像） |
| `init` 的调用者 | 0.033 + 1.713 秒 | 0.042 + 1.74 秒 |
| `makeKeyAndOrderFront:` 的调用者 | 0.057 + 0.326 秒 | 0.110 + 0.335 秒 |

读运行中的 cache 文件与外置卷上的归档一样快。文件模式第一版慢得多（整表 37 秒），差在每读一个槽都经 `FullDyldCache` 重新找 mapping、新建子 cache 对象、重读 slide info，以及读取层是类、每次经 existential 复制都计数——修法见「文件模式」一节与提案决策日志。第 4 步对进程内的影响在 ±3% 以内（与第 1 步交替量）。

单线程解码 AppKit 约 187 MiB/s，比 Capstone 快 25–50 倍（RuntimeViewer 提案落地第一步的探针）。库比探针慢一些（4 线程扫完整个缓存，探针 4.1 秒，库 5.9–6.3 秒），多出来的是起名、建 `CodeReference` 与 selector 字符串；过滤扫描也是先建好每条引用再丢弃，按键提前跳过是能做的优化。

**搬家之后**（2026-11-19，同一台 Ultra，Xcode 26.6，release；提案 [0098 move-cross-reference-layers](../../Evolutions/0098-move-cross-reference-layers.md)）：核心层与 ObjC 层跨包、接口改成 SPI 之后没有变慢，各项比 `next` 快 1% 到 11%（整 cache 建表进程内 2.67 → 2.53 秒、归档 27.2 cache 文件 2.75 → 2.51 秒），引用逐条一致。逐项数字记在 MachOKitExtensions 的 `Documentations/Internal/MachOCodeReferences.md`「吞吐」一节。

## 测试锚点

- `ARM64InstructionWordTests` / `ARM64TrampolineTests`：手写编码器造指令字；`capstoneAgreesWithTheEncoders` 让 Capstone 反汇编同一批字，编码器写错也藏不住。`linkerRewrittenAddressesAndLoads` 与 `linkerRewrittenSlotStub` 核对 ld64 改写出的 `adr`、字面量 `ldr` 与桩。
- `LinkerOptimizationHintTests`：现编的 dylib 按 ld64 的做法改写后，字面量 `ldr` 载入的 selector 认成发送、载入的类与 `adr` 取的类认成类引用，改写过的桩跟到 libsystem_c 的 `puts`。编译与改写的辅助代码在 `CompiledFixture`。
- `RuntimeSendEntryPointTests`：现编的 dylib 里八个 libobjc 入口各调用一处，每处都记成对应的发送（`objc_alloc_init` 两条，在同一条指令上），不再有对 libobjc 函数的调用；八个 selector 的预筛都留下这个没有一个 selector 引用的镜像。修复前全部失败。
- `AddressMaskScanTests`：库的源码里不许出现 33 到 62 位宽的地址掩码常量，指针一律按平台的掩码去掉签名。`AbbreviatedIdentifierScanTests`：`Sources` 与 `Tests` 里不许再用 `pc`、`lhs`、`rhs` 当名字（`Tests/Projects` 的 fixture 源码除外）。
- `CrossReferenceAnalyzerTests`（只在 arm64 进程里跑）：`-[NSWindow makeKeyAndOrderFront:]` 发出的三条消息及接收者；SwiftUICore 经桩调用 `swift_beginAccess` 落到 libswiftCore；按键过滤与整表一致；整镜像扫描不留函数表；给一批结果起名也不留；预筛；`branchesCarryTheirStateToTheirTargets` 与 `pathsThatDisagreeLeaveTheRegisterUnknown`：寄存器状态沿着分支走（见上文），后者在第一批的顺序读法下失败；`classicSendsInsideTheCacheNameTheirSelector`：libobjc 的 `-[NSObject debugDescription]` 认出发给 `self` 的 `description`（上文「两种桩布局」末段的第三种形态）；`selectorPrefilterKeepsEverySender` / `importPrefilterKeepsEveryCaller` / `swiftFunctionPrefilterKeepsEveryCaller`：预筛只丢掉引用不到主体的镜像（最后一个是 Swift 函数，见上文「预筛：缓存几乎不留 Swift 的未定义符号」）——在它丢掉的镜像里每 16 个抽 1 个扫描，一处引用也不许有（Debug 构建扫完整个缓存要几分钟，所以抽样）；`callSitesMatchCapstone` 抽样 400 个 AppKit 函数，双向比对：Capstone 找到的每一处调用与跳出函数的跳转，扫描都找到了；扫描报的每一处也都是 Capstone 眼里的调用或跳转（`br` 除外，Capstone 分不出跳转表与尾调用）。Capstone 不开 detail 模式就不给操作数，那半边比对曾因此什么都没比，测试断言比对过不止一处。
- `ObjectiveCClassReferenceTests`：AppKit 里三种取法都有（取本镜像类的地址、载入本镜像的类、载入别的镜像的类，`NSString` 在其中）；`+[NSThread currentThread]` 发给类字面量 `NSNotificationCenter`；`_BenchmarkHost._started(test:)` 经 `objc_opt_self` 发给 `NSApplication`；分类方法与类方法的 super 类；Block 里的 super 发送按 `__objc_superrefs` 得到所在方法的类（Block 的符号不是方法名，只有槽位能给出类；分类方法那个测试里槽位与符号给出的类相同，分辨不出）；Matter 里没有符号的方法，super 类与方法表一致；两个 SwiftUI 的同名类各自指向自己；类预筛（`NSWindow`、`NSUUID`、`__NSStackBlock__`、`OS_xpc_dictionary`）丢掉的镜像里抽样一处引用也没有。其中三个在去掉对应做法时变红过：经 `objc_opt_self` 不保留 `x0`、不读 `__objc_superrefs`、预筛只认 `_OBJC_CLASS_$_`。
- `SwiftTypeReferenceTests`：SwiftUICore 里访问器调用报出的类型与访问器符号全部一致（一万处以上）；紧邻的 `adrp` / `add` 取出的地址上若有符号，报出的类型与符号一致；Foundation 的名字取自 `x1` 的记录、落在 `__swift5_typeref`、能解开；Foundation 与 SwiftData 里，查询保留的名字恰是解开后提到该类型的名字（40 个最常被符号引用的类型；另四个标准库类型，查询退回的正是同一套解开，所以它们只守着符号引用不指错描述符）；两个 SwiftUI 的同名类型按位置分开；类型预筛（Foundation 的 `URL` 与 `JSONEncoder`、SwiftUICore 的 `Text`）丢掉的镜像里抽样一处引用也没有——按导入符号预筛时三者都漏；Foundation 与 AppKit 的每一个类型，按名字先筛再比 key 的查找与比每个类型的 key 结果相同（`typeLookupsCompareSameNamedTypesOnly`），按名字查导出表与读整个导出表判断导出与否相同（`exportLookupsAgreeWithTheWholeTrie`）；查导入类型时不从不透明类型的描述符读名字，子进程里拿一页末尾的假描述符核对（`importedTypeQueriesReadNoNameWhereNoTypeDescriptorIs`，修复前子进程 SIGBUS）。
- `FallbackNamingTests`：导出表给的名字落在导出的地址上（SiriAppIntents）；AppKit 里方法表给的名字与 `-[C sel]` 符号一致（去掉分类名后 99.9% 以上）；SwiftUICore 里从元数据重建的名字与真实的 `…Ma`、`…Mr`、方法符号一致（99% 以上）；Matter 的方法在没有符号时由方法表起名；SiriAppIntents 几乎每个类型的访问器都有名字，重建的名字 demangle 出来是元数据访问器。
- `StandaloneImageTests`：SymbolTestsCore fixture 经自己的桩调用 libswiftCore，没有一条停在只有名字的导入上；它的路径是加载路径而不是 `@rpath/…`，安装名也能查回它；测试包（`MH_BUNDLE`，没有安装名）的路径等于 `dladdr` 给的；测试包算作主程序的依赖方。
- `RegisterFileTests`：48 条汇编器编出的指令，每条写的寄存器都被作废，Capstone 的寄存器访问表独立核对这张表；普通读写只作废目标寄存器。
- `RenamedReexportTests`：AppKit 按 `_strlen`、`_CGSMainConnectionID` 调用 `__platform_strlen`、`_SLSMainConnectionID`，CharacterPicker 按 `NSEmojiImageAsset` 引用 CoreText 的类，三者的预筛都留住了它们；别名经伞形框架的那一种（`_xkMDConfigErase`）。
- `TypeNameRetentionTests`：类型查询解开的访问器符号、mangled 名字与描述符符号都不留在全局 `NodeCache` 与进程级 demangle 记忆里（用每次随机的名字，与并行跑的测试互不干扰）。
- `LazyBindingTests`：现编一个懒绑定的 dylib，见上文「缓存外镜像的 GOT 槽」。
- `PreparedImageDataTests`（每个测试用自己的分析器）：`prepareNames(inImageAt:)` 之后三个来源、类名、类型符号都已读好，给 Foundation 全部函数起的名字与不预读时相同；估算随留着的东西增减，放掉后为零；`releaseImageData(exceptForImagesAt:)` 只留指定镜像（连同读过的名字），其余放掉、之后照样能起名；一个线程预读预筛表、另一个线程同时要用，表只建一次；单线程读与并行读导出表结果相同。
- `CodeReferenceIndexTests`：Foundation 整表的每一个键，索引给出的引用与整表逐条相同、顺序相同，条数等于整表里有键的加上 Swift 类型名；AppKit 里一次查几个键（selector、libswiftCore 的函数、`NSWindow`）与过滤扫描逐条相同；Foundation 里 `URL`、`JSONEncoder`（类，经类对象）与标准库的 `Sa`（名字里拼出来，要解开）从索引查与按类型扫描逐条相同；索引不到整表的一半大；建索引留住函数表；进度从 0 报到函数总数，回答「停」就不建。
- 层的边界：下层搬走之后 SwiftPM 本身就不让它们 import 本库的模块，原来的 import 白名单测试删了。核心层源码里没有 `objc_` / `swift_` 开头的字面量、只有 `InProcessCrossReferenceMemory` 把地址变成指针、不写地址掩码常量，由 MachOKitExtensions 的 `SourceScanTests` 守着；ObjC 层只经 `CrossReferenceMemory` 读内存、不写 `swift_` 字面量，由 MachOObjCSection 的 `SourceScanTests` 守着；本库的 `MemoryAccessScanTests` 只扫 `CrossReferenceAnalysis`。核心层不装任何语言层也能扫，见 MachOKitExtensions 的 `CoreOnlyScanTests`。
- `RecognizerExtensionPointTests`：测试里定义的会话（代替一切调用 libobjc 的调用）接进核心的扫描，核心不改就生效；只查 selector 时 Swift 会话不建任何镜像的类型索引。`PublicNameTests`：只 `import CrossReferenceAnalysis` 也看得到下移的 `CodeLocation`、`CodeReference.Kind`、`ReceiverClassHint`、`IndirectCallEvidence`。
- `FunctionStartOutsideTextTests`：符号表把函数起点放在 `__text` 起点之下的镜像照常扫描（第 1 步曾因此下溢陷入）；这样的函数里扫出的引用，索引照样存得下：编一个可执行文件，在 `__text` 前的填充区写一条 `bl`，从 `__mh_execute_header` 这个函数里调用，索引与整表逐键相同。
- 两个按环境变量启用的 A/B 套件，库里没有可存的基线：`ReferenceTableDigestTests`（AppKit、SwiftUICore、Foundation 的整表摘要，在基线检出上生成、在候选上比对，也能整表导出逐行比较）与 `ScanThroughputBenchmarkTests`（上面「读取层与拆层的代价」那张表，release 下跑）。用法写在各自的文档注释里。
- `FileModeTests`（文件模式，提案第 4 步）：运行中的 cache 从文件读与进程内读，AppKit、SwiftUICore、Foundation 的整张引用表逐行一致，函数名、ObjC 方法表与 Swift 元数据给的名字、selector 预筛也一致；cache 的每个指针槽（v5 与没有 slide info 的模拟器 cache）解出的与 MachOKit 一致；归档 27.0、27.2 里 `UINSPasteboardWritingItemProvider` 的两个经 GOT 的调用者；iOS 26.3.1 设备 cache 里经 stub island 的发送；现编的独立文件——`-interposable` 的 dylib（self-bind 落到自己的函数、`puts` 是导入名）、Objective-C 可执行文件（`__TEXT` 在 0x100000000 时 rebase 与 objc 桩都解对）、C++ 的 `retab` 之后的异常清理代码。归档卷不在时相应用例跳过。
- `StandaloneFileReferenceDumpTests`：按环境变量启用，把一个独立文件（universal 取 arm64e 切片）的全部引用按函数导出成文本，供与反汇编器对照。第 4 步拿它与 IDA 抽样核对过 ControlCenter 26.7。
- `ReferenceKindAndRouteTests`（第 5 步）：现编的 ObjC 库里，读 ivar 的两个方法各有一条 ivar 引用（带符号与剥了符号两种）；字符串只在打开时或查字符串键时记；8 位与 UTF-16 的 `CFString` 常量带字符；Swift 大字符串只在 `add` 处记一条；调用、经本镜像桩的调用与发送、字符串的路线；常驻索引与整表对新种类与路线一致；运行中的 cache 里 AppKit 的路线覆盖直达、经槽、算地址、间接与桩；cache 里有一个恰好页对齐的类对象由 `adrp; add #0` 引用。`ARM64InstructionWordTests.decoderDecodesThirtyTwoBitLoadAndLoadSignedWord` 核对 32 位载入的解码，Capstone 对拍。
- `SymbolicationTests`（第 6 步）：26.7 SwiftUICore 的全部 `__auth_stubs` 都解到函数或导入名，其中 5 个经 `ipsw` 独立核对、间接符号表给错名的桩解对；macOS 27 AppKit 经 cache 共用桩的发送，桩要么是 selector 桩（selector 与发送一致），要么是通向 libobjc 入口的 GOT 桩；现编库的 GOT 槽给出导入名与 self-bind 的函数；Matter 里只有方法表起名的函数，地址落在函数体里；cache 文件里 0x10 与 0x7FFF00000000 没有映射；现编库的 C 字符串、`CFString` 与 ivar 偏移变量。
- 键集合不共享存储（第 7 步）：`ReferenceCollector` 把调用方的键集合拷一份自己的，检查时不经闭包捕获。并发扫描共用一个键集合时，每条引用一次 retain/release 曾让整 cache 的调用者查询慢 15 到 70 倍；`ScanThroughputBenchmarkTests` 的 `callersOf` 一行按共用一个集合量，回归会直接反映在数字上。
