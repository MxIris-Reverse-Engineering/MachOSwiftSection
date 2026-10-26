# 0075 - 包装类型读取器的识别：库看穿宿主的包装，按底下的读取器回答

- **状态**: Implemented
- **创建日期**: 2026-10-13
- **最后更新**: 2026-10-26
- **所属愿景**: 无
- **关联提案**: [0057-reading-context-migration](0057-reading-context-migration.md)（`ReadingContext.bindRebaseResolver` 已经让包装类型声明自己能解 bind / rebase）、[0053-shared-cache-composition-and-eviction-registry](0053-shared-cache-composition-and-eviction-registry.md)（按镜像缓存以读取器的 `identifier` 为键）
- **实现分支 / PR**: 本库 `fix/wrapped-reader-recognition`（直接合入 `next`，没有开 PR）；MachOKitExtensions `feature/reader-wrapper`，2026-10-26 快进成 `main` 并发 1.3.0
- **配套文档**: [Internal/ReadingContextAbstraction.md](../Internal/ReadingContextAbstraction.md)「包装类型读取器」一节；术语表 [reader wrapper](../Glossary.md)

## 摘要

MachOKitUI 把 `MachOImage` 包成 `MachOImageSource`、把 `MachOFile` 包成 `MachOFileSource` 交给本库，两者都转发全部读取，`identifier` 与背后的读取器相同。在 MachOViewer 里查看一个已加载镜像的 Swift section 时进程崩溃：`Fatal error: Negative value is not representable`，崩溃点是 `SymbolicDemangler.swift:469`（0.22.0 上是 320 行）。原因是本库判断「读取器是不是本进程里的镜像 / 是不是文件」时写死了具体类型：next 上 16 个文件共 38 处，加上 MachOKitExtensions 的 `asMachOImage`，以及一处转成库内部协议 `ObjCImplementationClassReading` 的取法。包装类型一处都走不进对应的路径。崩溃的那一处把 opaque type descriptor 的位置按「文件偏移」存进节点：描述符落在地址更低的另一个已加载镜像里时偏移是负数，转成 `UInt64` 就 trap。其余各处不崩，结果却悄悄变差或出错：符号按原值入索引、成员地址从 shared region 起点算、三个 ObjC 索引对包装类型是空的；一个不转发 `MachOBindRebaseResolving` 的文件包装还会让整份 interface 读到未解析的 chained fixup 原值而段错误。这个口子以前开过一半：`c348fd58`（2026-04-26）为包装类型加了 `MachOBindRebaseResolving`，`77e536f5`（2026-06-03）随后新增进程内 opaque 指针路径时又写死了 `MachOContext<MachOImage>`。本提案让宿主的类型声明「我是另一个读取器的包装」，库里每个「这是哪种读取器」的问题都问到包装底下的读取器；解析不了的引用不再 trap；源码扫描测试防止写死的类型判断回来。

## 方案

**1. MachOKitExtensions 1.3.0：一个泛型包装协议，三个取法。** 只描述「包装」这个关系，不列举库认识哪些读取器：`Base` 可以是任何读取器，宿主自定义的读取器类型也能被包装，包装也能套包装。

```swift
public protocol MachOReaderWrapper: MachORepresentableWithCache {
    associatedtype Base: MachORepresentableWithCache

    var base: Base { get }
}

extension MachORepresentableWithCache {
    /// The reader beneath every layer of wrapping; `self` when it wraps nothing.
    public var underlyingReader: any MachORepresentableWithCache { … }
}

extension MachORepresentable {
    public var asMachOImage: MachOImage? { … }   // 放宽：看穿包装
    public var asMachOFile: MachOFile? { … }     // 新增
}
```

契约写进协议的文档注释：遵循者在每个偏移读到的内容与 `base` 完全一样，`identifier` 也相同。按镜像的缓存（符号索引、ObjC 索引、demangle 记忆缓存……）以 `identifier` 为键，包装类型和底下的读取器共用同一份。`address(forOffset:)` 经 `asMachOImage` 取镜像，放宽后包装过的 cache 镜像打印的成员地址与局部类型的位置名随之正确。

**2. 本库：判据的两个源头与 opaque 引用。**

- `Package.swift` 的 MachOKitExtensions 下限从 `1.1.2` 抬到 `1.3.0`。
- `MachOContext.runtimePointer(at:)` 改用 `machO.asMachOImage`；`TypeContextDescriptorProtocol.swift:31` 取 metadata accessor 也走它，包装类型从此能用进程内 metadata。`bindRebaseResolver` 先问读取器自己，再问 `underlyingReader`。
- `SymbolicDemangler`：opaque type descriptor 的节点值由 `context.runtimePointer(at:)` 决定——能给出本进程指针就存绝对地址（`MachOContext<MachOImage>` 与 `InProcessContext` 得到的值和以前逐位相同），否则存偏移。偏移转不成 `UInt64`（负数）时，这个 symbolic reference 当作解析不了（resolver 返回 `nil`，与它里面其他失败的处理相同），不再 trap。`.direct`、`.indirect` 两支与 `accessorFunctionReference` 一起改。读这个节点值的两处（`Node+OpaqueType.swift:365/443`、`OpaqueReferenceSpelling.swift:74`）问 `asMachOImage`，与生产方用同一个判据。

**3. 本库：其余写死的判断改成 `asMachOImage` / `asMachOFile`。** 行号按 next @ `956b4e09`：

| 文件 | `MachOImage` 判断 | `MachOFile` 判断 |
|---|---|---|
| `Analysis/SwiftInspection/SymbolicDemangler.swift` | 451、465（见第 2 条） | — |
| `MachO/MachOReading/ReadingContext/MachOContext.swift` | 136（见第 2 条） | — |
| `Analysis/SwiftLayout/ImageReference.swift` | 151、164、178 | 154、167、181 |
| `Analysis/SwiftThunkAnalysis/ObjCMembers/ObjCMethodThunkReferences.swift` | 34 | 32 |
| `Analysis/SwiftInspection/ObjCAncestorResolver.swift` | 207 | 203 |
| `Analysis/SwiftInspection/ObjCClassMethodIndex.swift` | 163、399 | 161、396 |
| `Declaration/SwiftIndexing/SwiftDeclarationIndexer.swift` | 393 | 388 |
| `MachO/MachOSymbols/SymbolIndexStore.swift` | 620 | 784（提到循环外只问一次） |
| `MachO/MachOSymbols/SymbolValueOffsetConverter.swift` | — | 37 |
| `MachO/MachOSymbols/MachO+Symbol.swift` | — | 19 |
| `Output/SwiftDeclarationRendering/Extensions/Node+OpaqueType.swift` | 365、443 | 281、399、605 |
| `Output/SwiftDeclarationRendering/DependentMemberProjection.swift` | 97、141 | 91、136 |
| `Output/SwiftDeclarationRendering/PropertyWrapperTypeCatalog.swift` | 111 | 106 |
| `Output/SwiftDeclarationRendering/OpaqueReferenceSpelling.swift` | 74 | — |
| `Output/SwiftDeclarationRendering/InProcessAccessorFunctionResolution.swift` | 73 | — |
| `Output/SwiftPrinting/InterfaceHeader.swift` | 100 | 99 |

另外三处不是写死的类型转换，同样认不出包装：

- `MachORepresentableWithCache+ReaderKinds.swift` 的 `objcImplementationClassReader` 转成 SwiftInspection 的内部协议，包装类型遵循不了，改为从 `underlyingReader` 取；`swiftSectionReader` 自己转不成时也退到 `underlyingReader`。
- `FieldLayoutRenderable` 按类型在编译期选渲染后端，所有打印器都要求它。新增 `FieldLayoutRenderable+MachOReaderWrapper.swift`：对 `MachOReaderWrapper` 的七个静态 witness 都转给 `Base`，包装类型写一个空的遵循就能进打印器。
- `DependentMemberProjection.project` 拆包后在 `MachOFile` / `MachOImage` 的 universe 里投影，原来的 `as? MachO` 回转会把包装类型的结果整个丢掉。返回值改为 `Projection`，`image` 抹成 `any MachOSwiftSectionRepresentableWithCache`，重写器经一个泛型辅助函数打开它（SE-0352）。这个函数是 `package` 级别，不算公开 API。

**4. 明确不动的地方。**

- 按类型静态约束的 API：`ImageUniverse+DependencyClosure.swift:27/42`、`GenericSpecializer.swift:778/1306/1846`、`GenericSpecializer+StaticSpecialization.swift:24/78`、`DependencyClosure.swift:90/100`。它们不是运行时判断，持有包装类型的宿主自己传 `base`。
- MachOObjCSection 内部对 `self` 的 `as? MachOFile`：那里的 `self` 永远是裸类型（包装类型的 `objc` 转发给背后的读取器）。
- 没有声明 `MachOReaderWrapper` 的包装类型：行为与以前相同，只是原来 trap 的地方变成「这个引用解析不了」。

**5. 测试。** 每条在修复前都确认是红的，修完转绿，永久保留。测试用的包装读取器 `ForwardingMachOReader<Base, Declaration>` 放 `MachOTestingSupport`，转发全部读取要求（带默认实现的也转），`Declaration` 区分声明与不声明 `MachOReaderWrapper` 两种。

| 测试 | 修复前 | 修复后 |
|---|---|---|
| `WrappedReaderDemanglingTests`（SwiftInspectionTests）：子进程里经包装 demangle 进程内 SwiftUI 的全部 associated type witness。声明的包装与裸 `MachOImage` 逐个节点相同，且至少出现一个 opaque 引用，任何宿主上都跑。不声明的包装那条先确认至少有一个引用落在 SwiftUI 之下、再确认不 trap；这种引用只在 SwiftUICore 映射在 SwiftUI 下方时存在——macOS 27 起的 cache 布局（本机 27 上 SwiftUICore 的 `__TEXT` 在 `0x190404000`，SwiftUI 在 `0x19A048000`），macOS 15 与 26 都放在上方——所以这条按已加载 cache 的镜像表判断布局，只在这种布局下启用（落地前核查时这样拆开，见决策日志）。 | 两条都以 SIGTRAP 结束 | 通过 |
| `WrappedReaderInterfaceTests`（SwiftInterfaceTests）：fixture `SymbolTestsCore` 分别经 `MachOFile`、进程内 `MachOImage` 及各自的包装打印 interface（全部注释与文件头都开），逐字节相同；包装先打印。 | 测试进程 SIGSEGV（文件包装读到未解析的 fixup 原值） | 通过 |
| `WrappedReaderSymbolTests`（MachOSymbolsTests）：包装 cache 里的 Combine 后 `swiftSymbols` 与裸文件相同；Combine 自己的类型描述符符号按偏移查得到；包装进程内 cache 镜像 Foundation 后 `address(forOffset:)` 与裸镜像相同。 | 三条都失败（272 + 1 + 3 处） | 通过 |
| `ReaderKindCastScanTests`（SwiftInterfaceTests）：`Sources/`（`TestSupport` 除外）里不许出现对 `MachOImage` / `MachOFile` / `MachOContext<…>` 的类型转换；另一条确认扫描能看见转换、不会误报泛型约束。 | 列出上表 38 处 | 通过 |

MachOKitExtensions 自己的 `MachOReaderWrapperTests`：声明的文件包装、包装的包装、不声明的包装、成员地址四种语义，23 个测试全过。

**6. 验收与文档。** 跑完整测试（不含 `IntegrationTests`）；这次改了读取器与 demangle 路径，按规定跑三条读取路径的渲染 A/B，输出必须逐字节相同。文档：`Internal/ReadingContextAbstraction.md` 新增「包装类型读取器」一节；术语表登记 reader wrapper；`AGENTS.md` 加一个条件块「判断读取器种类用三个取法，不写类型转换」；MachOKitExtensions 的 README 与提案索引登记；`ProjectEvolutionLog` 随代码写一节，节号落地时分配；发版时写进当次的 Changelog（0.23.0 没赶上，见决策日志）。CLI 的参数与输出不变，agent 插件不用改。

**7. 下游。** MachOKitUI 升到含本提案的本库版本（0.23.0 之后的下一个版本）与 MachOKitExtensions 1.3.0 后，给 `MachOImageSource` / `MachOFileSource` 各加一行遵循 `MachOReaderWrapper`（`base` 返回它们持有的 `machO`），同时删掉 `MachOSwiftSectionDetailBuilder.demangleTypeNode` 里的特判；`MachOFileSource` 手写的 `MachOBindRebaseResolving` 转发可留可删。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-10-13 | Created as Draft | 来源：MachOKitUI 会话交接。用户选定方案 B：给包装类型一个协议，把写死的判断改成按协议判断，负偏移不再 trap。交接方在 MachOKitUI 里先做了只绕开崩溃点的方案 A。 |
| 2026-10-13 | 协议放 MachOKitExtensions，发 1.3.0 | 用户选择。和 `MachOBindRebaseResolving`、`asMachOImage` 放在一起；放本库 `MachOReading` 的话，`asMachOImage` 与 `address(forOffset:)` 仍只认裸类型，包装过的 cache 镜像打印的成员地址照样是错的。 |
| 2026-10-13 | `MachOFile` 一侧一起改 | 用户选择。同一类问题：`SymbolValueOffsetConverter` 只给裸 `MachOFile` 换算符号值，依赖闭包、ObjC 祖先链、thunk 读取也只认裸类型。 |
| 2026-10-13 | 随 0.23.0 从 next 发 | 用户选择。MachOKitUI 已用方案 A 挡住崩溃点，不单独从 main 发 0.22.1。 |
| 2026-10-13 | 直接打开 dyld cache 文件不会出负偏移 | 交接方的怀疑，已核实：cache 文件里 `MachOFile` 的偏移以 shared region 起点为基准（MachOKitExtensions 的 `resolveRebase` 返回「目标地址 − sharedRegionStart」），cache 里任何地址都不低于起点；独立文件是文件偏移。实测：现有 CLI 从本机 macOS 27 cache 文件 dump 整个 SwiftUI 的 associatedTypes（4960 条，765 处展开到 `ModifiedContent`，没有未展开的 opaque 引用），正常退出。 |
| 2026-10-13 | 否决：草案初稿的两个协议 `MachOImageBacked` / `MachOFileBacked` | 用户要求再想更优雅的接口。按具体类型各开一个协议，包装第三种读取器就得再加一个协议，把库认识的类型写进了扩展点。 |
| 2026-10-13 | 否决：`enum MachOReaderKind { case file, image }` 作为 `MachORepresentableWithCache` 的必需要求 | 用户否决：用户自定义一个 MachO 类型就必须改库，违反开闭原则。 |
| 2026-10-13 | 采用：泛型包装协议 `MachOReaderWrapper`（`associatedtype Base`） | 只描述「包装」这个结构性事实，`Base` 可以是任何读取器；库在一处（三个取法）看穿包装，能力协议与编译期选策略的协议也经它对包装生效。MachOKitExtensions 只加接口，1.3.0 不破坏兼容。用户说「先改试试」，开始实现。 |
| 2026-10-13 | 生产方改用 `runtimePointer(at:)` 判断 | 它本来就是「这个 context 是否映射在本进程」的协议要求，生产方与消费方共用同一个判据。 |
| 2026-10-13 | 不从 `identifier == .image(ptr)` 推断进程内镜像 | 隐式约定，只覆盖 `MachOImage` 一侧；`identifier` 是缓存身份，不是类型契约。 |
| 2026-10-13 | `FieldLayoutRenderable` 给包装类型默认实现 | 打印器全都要求它，包装类型原本要手写七个静态转发；默认实现让它写一个空遵循即可，按 `Base` 的后端渲染。 |
| 2026-10-13 | 符号测试只查 Combine 自己的描述符符号 | 符号表也列出 Combine 引用的外部描述符（`$ss12StaticStringVMn`），它们不在 Combine 的任何偏移上；收窄后修复前 272 处失败、修复后 0 处，仍能区分修复前后。 |
| 2026-10-13 | 试做验收 | 在两个沙盒里构建（本地 sibling；swift-demangling 与 MachOObjCSection 用各自远端 `next` 的导出副本，因为本机这两个 sibling 的 `next` 落后于远端）。全量测试（不含 `IntegrationTests`）只红了 `Arm64eSignedVWTPointer` 的 strip 探针一条，单独重跑 3/3 通过、基线也通过，与本次改动无交集，按偶发处理。渲染 A/B：归档 cache 26.6 / 15.5、模拟器 runtime 15.5–26.5、进程内镜像三条读取路径共 96 对，全部逐字节一致。 |
| 2026-10-14 | 提交并推送两个功能分支 | 用户看过试做结果后要求提交推送。发 MachOKitExtensions 1.3.0 与合进 next 另等用户决定；本库 `Package.swift` 已要求 1.3.0，所以发版必须在落地之前。 |
| 2026-10-26 | 合并前核查：`WrappedReaderDemanglingTests` 依赖宿主的 cache 布局，拆开 | 代码能干净合进 `next`：基线 `956b4e09` 之后又进了 50 多个提交，只有两份索引表冲突，合并结果里写死的读取器转换为 0。但「至少一个引用落在 SwiftUI 之下」只在 SwiftUICore 映射在 SwiftUI 下方时成立，这是 macOS 27 起的布局；macOS 15 与 26 都放在上方（26.6：`0x22d953000` 对 `0x1b594e000`），这条在 macOS 26 宿主上必红，CI 不跑这个套件所以没人发现。用户批准先修再落地：声明的包装那条在任何宿主上比较，只要求至少出现一个 opaque 引用（修复前它在任何宿主上都会红）；落在下方的引用改作不声明的包装那条的前提，用 `.enabled(if:)` 按已加载 cache 的镜像表（`DyldCacheLoaded.current`）判断布局，判断时不加载任何镜像。 |
| 2026-10-26 | `ReaderKindCastScanTests` 与 `WrappedReaderInterfaceTests` 进 CI 名单 | 前者只读源码、后者只读 fixture，符合 CI 只跑不依赖开发机环境的规则；另两个读系统 dyld cache 或把 SwiftUI 加载进进程，留在本地。 |
| 2026-10-26 | MachOKitExtensions 1.3.0 发版 | 用户批准。`feature/reader-wrapper` 快进成 `main`，打空消息的注释 tag，与以往版本一样不建 GitHub Release；发前在该提交上跑 MachOKitExtensions 自己的 23 个测试全过，发后只走远端依赖的副本能解析到 1.3.0。 |
| 2026-10-26 | 合入 `next`，编号 0075；状态 → Implemented | 用户批准。先把 `next@7adbe83c` 合进功能分支（两份索引表两边都保留），在最终 tree 上重跑：全量 2574 个测试全过、退出码 0；渲染 A/B 96 对全部逐字节一致（各腿对数见演进账本第 106 节）。0.23.0 发版时本提案还在等 MachOKitExtensions 1.3.0，改随下一个版本发。文档判断：`ReadingContextAbstraction.md` 的「包装类型读取器」一节就是实现说明；宿主只需写一行遵循，写法在 MachOKitExtensions 的 README 里，不另写使用指南；术语表的 reader wrapper 实现时已登记，没有新词。 |
| 2026-10-26 | 后续项：量进程内指针解析的额外开销 | `MachOContext.bindRebaseResolver` 在每次指针解析时都会被调用；对进程内 `MachOImage`，它现在多做两次失败的协议转换和一次 existential 装箱（`MachOImage` 32 字节，超出内联缓冲）。全量与 A/B 只验证了正确性，没量时间；要在性能足够的机器上按 instructions retired 对比前后。 |
