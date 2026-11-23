# Draft - 类型索引独立成 swift-type-indexing 包，并接入 MachOObjCSection 与 RuntimeViewer

- **状态**: In Progress
- **作者**: JH
- **创建日期**: 2026-11-23
- **最后更新**: 2026-11-23
- **所属愿景**: 无
- **关联提案**: [0009 TypeIndexing 重启](0009-type-indexing-revival.md)、[0010 补充类型映射](0010-community-type-mapping-bundles.md)、[0096 Swift 优先的导入声明](0096-swift-first-imported-declarations.md)（`ObjCSwiftImportNotes` 的来历）
- **跨仓库范围**: 新仓库 `MxIris-Reverse-Engineering/swift-type-indexing`、swift-apinotes fork（`MxIris-DeveloperTool-Forks/swift-apinotes`，实现中加入，见决策日志）、MachOObjCSection、MachOSwiftSection（本仓库，持有这份唯一的提案）、RuntimeViewer。另外三个仓库的提案索引各加一行「cross-repository」链接指回这里
- **实现分支 / PR**: 新仓库 `swift-type-indexing` 的 `main`；MachOObjCSection、MachOSwiftSection、RuntimeViewer 各自的 `feature/swift-type-indexing-package`（各从 `next` 切）
- **配套文档**: 待定 —— 落地时登记实现说明 / 使用指南的链接
- **网页版**: 同目录同名的 `.html`

## 摘要

把本仓库的 `TypeIndexing` target（SDK 模块索引、API notes 索引、ObjC 元数据归属、按 SDK 版本的磁盘缓存）整体搬进新的独立包 `swift-type-indexing`，模块名仍是 `TypeIndexing`。新包不依赖本仓库，也不依赖 MachOObjCSection：原来直接调用 `ObjCIndexing` 补私有类归属的那一层改成新包声明的协议 `DeclaredTypeNameSource`，由 MachOObjCSection 实现。搬家同时修两处错误：API notes 的改名规则（只有 `SwiftPrivate` 的类型要加 `__` 前缀，有 `SwiftName` 的直接用它——现在两种都不改名）；sourcekitd 只认 Xcode 的目录结构，装 Command Line Tools 时找不到。之后三方接入：MachOObjCSection 打印 ObjC 头文件时，按 API notes 在类、协议、category 及其成员上标出 `NS_SWIFT_NAME(...)` / `NS_REFINED_FOR_SWIFT`；本仓库删掉 `TypeIndexing` target，只留一个薄适配层，`swift-section interface --resolve-c-module-names` 照常可用，`swift-section objc` 加一个同类开关；RuntimeViewer 在找得到对应平台 SDK 的 Mac 上默认把 `__C.UICellConfigurationState` 打印成 `UIKit.__UICellConfigurationState`，索引在 engine 连上后后台预建、进 Report，建好前先显示 `__C.`、建好后自动刷新，MCP、命令行与导出一起换成解析后的名字。

## 动机

**现象**。RuntimeViewer 显示 UIKit 的 `UICellConfigurationState` 结构体时，桥接相关的成员都打印成 `__C.UICellConfigurationState`：

```swift
static func _unconditionallyBridgeFromObjectiveC(_: __C.UICellConfigurationState?) -> UIKit.UICellConfigurationState
func _bridgeToObjectiveC() -> __C.UICellConfigurationState
var _cachedImpl: __C.UICellConfigurationState?
```

而 SDK 的 `UIKit.swiftinterface` 写的是 `__UICellConfigurationState`（`_ObjectiveCType = __UICellConfigurationState`）。`__C.UITraitCollection` 之类的普通导入类型同样只显示占位模块 `__C`，不是 `UIKit`。

**二进制里本来就没有这些信息**（见前期调研 1、2）：Swift 给导入的 ObjC 类做 mangling 时用的是 ObjC 运行时名，Swift 侧的改名只记在 SDK 的 API notes 与头文件里；模块归属同样不在 mangled 名里。所以要显示对，只能借助 SDK——这正是本仓库 `TypeIndexing` 已经在做的事（提案 0009 / 0010），只是：

1. **RuntimeViewer 用不上它**。RuntimeViewer 不经 `SwiftInterfaceBuilder`，而是自己在每个镜像的 `SwiftDeclarationPrinter` 上注册解析器（`RuntimeViewerCore/Sources/RuntimeViewerCore/Sections/Swift/RuntimeSwiftSection.swift:1933-1936`），从来没有注册过 `TypeIndexing` 的解析器，所以界面、MCP、命令行和导出里全是 `__C.`。
2. **它不只是「Swift 的」索引**。它的三个数据源里，API notes 与 ObjC 元数据都是 C / Objective-C 一侧的知识；MachOObjCSection 打印 ObjC 头文件时同样需要它（`NS_SWIFT_NAME` / `NS_REFINED_FOR_SWIFT` 在二进制里没有痕迹，`ObjCSwiftImportNotes` 现在只能靠本仓库从 Swift 侧倒推出 `NS_REFINED_FOR_SWIFT`，`NS_SWIFT_NAME` 完全没有来源）。但 MachOObjCSection 是本仓库的依赖，不可能反过来依赖本仓库的 target。
3. **两处错误**：`SwiftPrivate` 与 `SwiftName` 的改名都没生效；只装 Command Line Tools 的机器上 sourcekitd 路径必然错。

**为什么不能只在二进制层面推断**。曾考虑过「Swift 类型与 ObjC 类同名、且遵循 `_ObjectiveCBridgeable`，就推断 ObjC 类在 Swift 里叫 `__X`」。对 macOS 27.2 / iOS SDK 的统计否定了它：同名又桥接的 20 个类型里只有 6 个是 `__X`，14 个是 `XReference`（见前期调研 3），而两者在二进制里一模一样。

## 前期调研

1. **导入的 ObjC 类按 ObjC 运行时名 mangling**。`swift/lib/AST/ASTMangler.cpp` 的 `tryAppendClangName`（约 3173 行起）：「Always use Clang names for imported Clang declarations」，ObjC 类走 `interface->getObjCRuntimeNameAsString()`。SDK 的 `UIKit.tbd` 里 `$s5UIKit24UICellConfigurationStateV19_bridgeToObjectiveCSoABCyF` 的 `SoABC` 直接复用了结构体名那个标识符，demangle 为 `-> __C.UICellConfigurationState`；`PencilKit.PKDrawing`（`$s9PencilKit9PKDrawingV19_bridgeToObjectiveCSoABCyF`）与 `UniformTypeIdentifiers.UTType` 的符号形状完全相同。
2. **改名只在 SDK 里**。`UICellConfigurationState` 的改名来自 `MacOSX27.2.sdk/System/iOSSupport/.../UIKit.framework/Headers/UIKit.apinotes:275-276` 的 `SwiftPrivate: true`，头文件 `UICellConfigurationState.h:34` 没有宏；`PKDrawing` 来自 `PencilKit.apinotes:4-6` 的 `SwiftName: PKDrawingReference` + `SwiftBridge: PKDrawing`。
3. **SDK 统计**（macOS 27.2 SDK 与 iOS SDK 的全部 `.tbd` 里导出了 `_bridgeToObjectiveC` 的类型，与 swiftinterface 逐个对照）：同名又桥接的 22 个，其中 2 个在私有框架（`ASCredentialProvider`、`WFVariableString`，SDK 无资料）；其余 20 个：
   - `__X`（`SwiftPrivate`）6 个：UIKit 的 `UICellConfigurationState`、`UIViewConfigurationState`、`UIContentUnavailableConfigurationState`、`UIListSeparatorConfiguration`、`UIPointerEffect`、`UIPointerShape`
   - `XReference`（`SwiftName` + `SwiftBridge`）14 个：PencilKit 8 个、`NSDiffableDataSource(Section)Snapshot`（UIKit / AppKit）、`UTType`、`INShortcut`、`INMediaDestination`
   - 另有 15 个 `__` 类型与对应 Swift 类型不同名（如 Foundation 的 `NSMorphology` ↔ `Morphology`、`UIButtonConfiguration` ↔ `UIButton.Configuration`）。
4. **Clang importer 的改名规则**（`swift/lib/ClangImporter/ImportName.cpp`）：`importNameImpl` 遇到 `swift_name`（约 1659 行 `findSwiftNameAttr`）直接用它并在 1776 行 `return result`，**不再**加 `__`；只有没有 `swift_name` 时才走 2446 行「If this declaration has the swift_private attribute, prepend "__"」。API notes 的 `SwiftName:` / `SwiftPrivate:` 就是这两个属性。
5. **现有实现的改名表跳过了这两种情况**：`Sources/Declaration/TypeIndexing/APINotesIndex.swift:117` 是 `guard let swiftName = entity.swiftName, entity.isSwiftPrivate != true else { continue }`——没有 `SwiftName` 的不进表，有 `SwiftName` 但标了 `SwiftPrivate` 的也不进表。测试 `Tests/TypeIndexingTests/APINotesIndexTests.swift:93` `swiftPrivateEntitiesAreAttributedButNotRenamed` 断言后一种不改名。追查来历：提案 0009 落地时（`1785a9e7`，2026-08-22）`Documentations/Internal/TypeIndexingPipeline.md:95` 写「改名表仍跳过 `SwiftPrivate`」，没有给理由，是沿用历史实现「只注册有 `SwiftName` 的实体」的保守做法；按上一条的编译器规则，这个保守做法是错的。
6. **sourcekitd 路径**：`SourceKitManager.swift:62-63` 用 `xcode-select -p` 拼 `/Toolchains/XcodeDefault.xctoolchain/usr/lib/sourcekitd.framework/Versions/A/sourcekitd`。只装 Command Line Tools 时 `xcode-select -p` 是 `/Library/Developer/CommandLineTools`，sourcekitd 在 `usr/lib/sourcekitd.framework`（本机核对过，没有 `Toolchains/` 一层），拼出的路径不存在。Command Line Tools 自带 `SDKs/MacOSX.sdk`，其中有 `System/iOSSupport/.../UIKit.apinotes`，所以 macOS 与 Mac Catalyst 的 API notes 都在；iOS 等其他平台的 SDK 只有 Xcode 里有。
7. **`TypeIndexing` 的耦合面**（`next` 上 `Sources/Declaration/TypeIndexing/` 12 个文件约 1300 行）：
   - 只依赖 Foundation / FoundationToolbox / SourceKitD / swift-apinotes、可以原样搬走的 9 个：`InterfaceDeclarationNode`、`InterfaceTypeNameExtractor`、`ModuleIndexCache`、`ModuleInterfaceIndexer`、`SDKIndexer`、`SDKPlatform`、`SourceKitManager`、`Subprocess`、`SupplementaryAPINotes`。
   - 要解耦的 2 个：`APINotesIndex.swift`（用了 SwiftPrinting 的 `CImportedTypeNameCategory`）与 `TypeDatabase.swift`（泛型 `TypeDatabase<MachO: ObjCMetadataSource & Sendable>`，在 `indexObjCMetadata(of:)`（211-233 行）里用 `ObjCInterfaceIndexer(machO:imagePath:)` + `prepare()` + `classNames` / `protocolNames` / `structNames` / `unionNames`，以及 MachOKitExtensions 的 `imagePath`；同时用了 `CImportedTypeNameCategory`）。
   - 留在本仓库的 1 个：`SwiftInterfaceBuilderTypeNameProvider.swift`（依赖 `SwiftInterface`、`SwiftPrinting` 的角色协议、MachOKit 的 `Platform`）。
   - `CImportedTypeNameCategory` 声明在 `Sources/Output/SwiftPrinting/NodePrintables/TypeNameResolving.swift:8-26`，它的 `init(nodeKind:)` 依赖 Demangling，打印器本身也用它（`TypeNodePrintable.swift:240`），所以不能搬走，新包要有自己的分类枚举。
   - 缓存目录写死在 `ModuleIndexCache.swift:46-54`（`Application Support/MachOSwiftSection/SDKIndexer/<platform>/<SDK 版本-build>`），`TypeDatabase.index` 内部直接构造它（`TypeDatabase.swift:72`），调用方无法指定。
   - 本组织里没有别的仓库依赖 `TypeIndexing` product；本仓库内的使用方只有 `SwiftSectionKit` 的 `InterfaceRequest.swift:245-297`（`--resolve-c-module-names`）与测试。
8. **API notes 不需要 sourcekitd**：`SDKIndexer.discover` 只扫文件、解析 `.apinotes`（秒级）；只有「从模块接口取类型名」这一层才要 sourcekitd（提案 0009 A 节）。所以「改名」与「ObjC 头文件的 Swift 命名标注」只要找得到 SDK 就能做，模块归属在没有 sourcekitd 时退化为「API notes 列出的实体 + ObjC 元数据」。
9. **MachOObjCSection 现状**（`MachOObjCSection` 的 `next`）：
   - `Sources/ObjCDeclarationRendering/ObjCSwiftImportNotes.swift:25`，`Note` 只有 `isRefinedForSwift`，只能标成员，没有类型一级的标注；渲染在 72-84 行。
   - 只有按类打印的入口接收标注（`ObjCInterfaceBuilder.swift:116-131`、`149-163`），协议（336 / 354）、category（445 / 463）不接收。
   - 类型声明行由 `ObjCDeclarationHeader`（`ObjCDump+SemanticString.swift:109-153`）打印；演进视图把可用性宏单独打一行放在声明行上面（`Sources/ObjCInterface/Internal/ObjCEvolutionContainerLayout.swift:268-271`），是类型一级宏的现成写法。
   - 包支持 macOS 10.15，而 `TypeDatabase` 要求 macOS 13，接入处要加可用性判断。
   - 全仓库没有任何 `apinotes`、`SwiftName`、`moduleName` 相关代码。
10. **RuntimeViewer 现状**（`next`）：
    - 打印：每个 Swift 镜像一个 `SwiftDeclarationPrinter`（`RuntimeSwiftSection.swift:68`、`:234`），Find 语料用另一个打印器（`:2313-2333`）。关掉「Synthesize Opaque Type」时调用 `printer.removeAllTypeNameResolvers()`（`:1937-1939`），会把所有解析器一起清掉。
    - ObjC：`RuntimeEngine.swift:956-962` 只给类传 `swiftSection.objcSwiftImportNotes(for:)`（`RuntimeSwiftSection.swift:516-531`），语料一侧同样（`RuntimeEngine+Search.swift:355-356`）。
    - 打印发生在服务进程：本机、Catalyst、文件、框架四个 XPC service（`ServicePluginEntry.swift`），以及独立运行的命令行 host；App 进程只转发。
    - 生成选项随每个请求发出（`InterfaceCommand.options`），用 MetaCodable 的 `@Default` 声明（`RuntimeObjectInterface+GenerationOptions.swift`），旧版对端缺字段时取默认值；界面入口是 Generation Options 面板（`GenerationOptionsViewController.swift`，`Synthesize Opaque Type` 等开关都在这里）。
    - 刷新：App 的接口缓存在 `engine.dataChangePublisher` 上清空（`RuntimeInterfaceCache.swift:121-139`），但内容区只在对象或选项变化时重新取（`ContentTextViewModel.swift:227-247`）；`RuntimeDataChange` 只有 `fullReload` 与 `specializationAdded` 两个 case。
    - 后台工作与 Report：`RuntimeEngineBackgroundWork.swift:85-137`、`ReportNode.swift:9-64`（`ReportCategory` 现有 `backgroundIndexing`、`searchableInterfaces`、`crossReferences`、`manualLoading`）、`ReportTreeBuilder.swift`、`ReportViewModel.swift`；协调器模板是 `CrossReferencePreparationCoordinator.swift`。
    - 缓存位置：`RuntimeDerivedDataLocation.swift:36-68` 只在 `.app` 与 `Contents/XPCServices` 下给出 `~/Library/Caches/<bundle id>/DerivedData`，独立命令行 host 与 Catalyst helper 得到 `nil`；删除走 `RuntimeDerivedDataMaintenance.swift:64-75`，App 侧 `RuntimeDerivedDataController.swift:50-93`。
    - Find 语料的 variant 是 `"\(transformer.derivedDataDigest)-ByCategory"`（`RuntimeInterfaceCorpusSnapshot.swift:29-31`），内存里只比 transformer（`RuntimeInterfaceCorpusStore.swift:357-369`）。
    - MCP（`MCPBridgeServer.swift:822-834`）、命令行（`CommandExecutor.swift:578`、`ApplicationOptionsReader.swift:49-55`）、导出（`RuntimeEngine+Export.swift:44`）都走同一个 `engine.interface(for:options:)`；命令行插件 `AgentPlugins/runtime-viewer/` 两个清单都是 `1.3.0`。
    - 依赖：`RuntimeViewerCore/Package.swift:139-158` 以 `branch: "next"` + 本地候选声明 MachOObjCSection 与本仓库；`Tuist.swift:100` 把本仓库的 `"TypeIndexing"` 列为源码依赖 target；SourceKitD 与 swift-apinotes 已经经本仓库进了三个 workspace 的 `Package.resolved`。
11. **依赖包**：SourceKitD（`Mx-Iris/SourceKitD` 0.1.0，只声明 macOS 10.15）；swift-apinotes（`MxIris-DeveloperTool-Forks/swift-apinotes` 0.1.0，依赖 MetaCodable 与 Yams，MetaCodable 是宏包，构建时要 swift-syntax）。两者现在都只是本仓库的普通 URL 依赖。

## 提议方案

四个仓库，依赖方向自下而上：

```text
swift-type-indexing  ←  MachOObjCSection  ←  MachOSwiftSection  ←  RuntimeViewer
```

1. **新包 `swift-type-indexing`**（`MxIris-Reverse-Engineering/swift-type-indexing`，公开，MIT，模块与唯一 product 都叫 `TypeIndexing`）。内容是本仓库 `TypeIndexing` 的 11 个文件，外加：
   - `TypeDatabase` 去泛型，ObjC 元数据那一层改为接收 `[any DeclaredTypeNameSource]`；
   - 自己的 `ImportedTypeNameCategory`；
   - 改名规则按 Clang importer 修正（有 `SwiftName` 用它；只有 `SwiftPrivate` 时 `__` + C 名）；
   - sourcekitd 定位同时认 Xcode 与 Command Line Tools；找不到 sourcekitd 时退化而不是失败（API notes 与 ObjC 元数据照常工作，只少了「模块接口」这一层归属）；
   - 缓存目录由调用方传入（不传就用 `Application Support/swift-type-indexing/…`）；
   - 可用性探测 `TypeIndexingAvailability`；
   - ObjC 容器的 API notes 查询（类、协议及其方法与属性的 `SwiftName` / `SwiftPrivate`），给 MachOObjCSection 打标注用。
   - 所有类型 `public`，源码仍包在 `#if os(macOS)` 里、类型标 `@available(macOS 13.0, *)`，包的平台声明与现在本仓库一致，消费方按 `.when(platforms: [.macOS])` 依赖它。
2. **MachOObjCSection**：
   - 新 target 与 product `ObjCTypeIndexing`（只在 macOS 依赖新包），提供 `ObjCDeclaredTypeNames<MachO>`（`DeclaredTypeNameSource` 的实现，包一层 `ObjCInterfaceIndexer`）与「API notes → `ObjCSwiftImportNotes`」的转换；`ObjCIndexing`、`ObjCDeclarationRendering` 本身不依赖新包。
   - `ObjCSwiftImportNotes` 加成员的 `swiftName` 与类型一级的标注；协议与 category 的打印入口也接收标注；类型一级的宏单独打一行放在 `@interface` / `@protocol` 上面，成员的宏放在 `;` 前，顺序是 `NS_SWIFT_NAME(...)` 在前、`NS_REFINED_FOR_SWIFT` 在后。
3. **MachOSwiftSection（本仓库）**：
   - 删除 `TypeIndexing` target、product 与 `TypeIndexingTests`（测试随代码搬进新包），不再直接依赖 SourceKitD 与 swift-apinotes。
   - 新 target 与 product `SwiftTypeNameResolution`（macOS 才依赖新包）：`TypeDatabaseTypeNameResolver`（把一个 `TypeDatabase` 适配成打印器的 `ModuleNameResolving` + `CImportedNameResolving`，负责两种分类枚举的映射）与原来的 `SwiftInterfaceBuilderTypeNameProvider`（改为建立在前者之上）。
   - `swift-section interface --resolve-c-module-names` / `--supplementary-apinotes` 名字与行为不变（改名修正随之生效）；`swift-section objc interface` 新增 `--mark-sdk-swift-names`，按 SDK 的 API notes 标出 Swift 命名。
4. **RuntimeViewer**：
   - Core 新增 `TypeNames/` 功能目录：每个服务进程每个 SDK 平台一个 `TypeDatabase`（`RuntimeTypeIndex`），engine 连上后后台预建它用到的模块；建好后广播新的 `RuntimeDataChange.typeNamesResolved`，各镜像的打印器注册解析器、清掉旧的接口缓存。
   - Swift：`SwiftGenerationOptions.resolvesImportedTypeNames`（默认开）。ObjC：`GenerationOptions.marksSwiftNamesFromAPINotes`（默认开；`objcHeaderOptions` 是 MachOObjCSection 的类型，这个开关只管 RuntimeViewer 传不传标注，所以放顶层），类、协议、category 都把 API notes 的标注并进现有的 `objcSwiftImportNotes`。两个开关放在 Generation Options 面板各自的分组里。
   - 界面请求不等索引（先显示 `__C.`，建好后刷新）；MCP、命令行、导出、Find 语料构建等索引就绪（或确认不可用）再打印，保证输出稳定。
   - Report 新增「Imported Type Names」一类，显示每个平台的索引状态（建立中 / 就绪 / 不可用及原因）与缓存大小；工具栏活动显示建立进度。
   - 缓存放在 `~/Library/Caches/<App 的 bundle id>/TypeIndex/`，所有进程共用（App 内嵌的命令行从可执行文件往上找到 `.app`；不在 App 里的命令行用 `~/Library/Caches/runtime-viewer-cli/TypeIndex/`）；「Delete Derived Data」一起删除并计入大小。
   - Find 语料的 variant 带上「是否解析了类型名」与 SDK 版本。
   - 命令行插件的 skill 说明输出变化，两个插件清单抬到 `1.4.0`。

### 非目标

- **iOS 设备、注入的进程、Simulator payload 不解析**：那些进程里没有 SDK。它们照旧打印 `__C.`。
- **ObjC 头文件不加 `@import` 行**，也不标 nullability、`NS_SWIFT_UNAVAILABLE` 等其余 API notes 属性——只标 Swift 命名。
- **MachOObjCSection 自带的 `objc-section` 命令行不加开关**；只有 `swift-section objc` 加。
- **不在纯二进制层面推断改名**（见动机最后一段）；找不到 SDK 时如实显示 `__C.`。
- **不保留 git 历史**：新仓库的首个提交注明来自本仓库哪个提交，不做 `filter-repo` 式的历史迁移。
- **不保留过渡层**：本仓库不留转发旧 `TypeIndexing` product 的壳——组织里没有外部使用方。
- **不改 Find 语料以外的 derived data**：类型索引的缓存是按 SDK 版本的独立目录，不是 `RuntimeDerivedDataKind`。

## 改动地图

步骤编号见「落地步骤」。

### swift-type-indexing（新仓库）

| 文件 / 类型 | 动作 | 改什么 | 为什么 | 步骤 |
|---|---|---|---|---|
| `Package.swift` | 新增 | 包名 `swift-type-indexing`，product / target `TypeIndexing`，测试 target `TypeIndexingTests`；依赖 SourceKitD、swift-apinotes（`from: "0.3.0"`，本地候选 `../../../Fork/Library/swift-apinotes`）、FrameworkToolbox（后两者均 `.when(platforms: [.macOS])`）；平台与本仓库一致（macOS 10.15 / iOS 13 / tvOS 13 / watchOS 6 / visionOS 1）；打开 `ExistentialAny`、`MemberImportVisibility`、`InferIsolatedConformances` | 独立成包；平台声明不能高于 MachOObjCSection，否则 SwiftPM 拒绝解析 | 1 |
| `Sources/TypeIndexing/{InterfaceDeclarationNode,InterfaceTypeNameExtractor,ModuleIndexCache,ModuleInterfaceIndexer,SDKIndexer,SDKPlatform,SourceKitManager,Subprocess,SupplementaryAPINotes}.swift` | 移入 | 从本仓库原样搬入；`package` 改 `public`（只公开调用方需要的，其余 `internal`）；`@Loggable` 子系统改为 `com.mxiris.type-indexing` | 搬家 | 1 |
| `Sources/TypeIndexing/APINotesIndex.swift` · `APINotesIndex` | 移入 + 修改 | 用 `ImportedTypeNameCategory`；改名规则：有 `SwiftName` 用它（不论 `SwiftPrivate`），只有 `SwiftPrivate` 时 `"__" + cName`；`cNamesBySwiftName` 同步登记；新增 ObjC 容器的方法、属性条目索引 | 修正改名；给 ObjC 标注提供数据 | 1、2、3 |
| `Sources/TypeIndexing/TypeDatabase.swift` · `TypeDatabase` | 移入 + 修改 | 去泛型；`index(dependencies:moduleFilter:)` 改收 `[any DeclaredTypeNameSource]`，可多次调用（第一次发现 SDK、登记 API notes，之后只补新模块与新依赖）；API notes、模块接口、运行时元数据三张表在查询时按优先级查，不再靠写入顺序覆盖；`moduleName(forImagePath:)` 保持纯函数；构造器加 `cacheDirectory:`；没有 sourcekitd 时只读缓存；新增 `swiftImportAnnotations(forObjCClassNamed:)` / `forObjCProtocolNamed:` | 去掉对 MachOObjCSection 的依赖；RuntimeViewer 加载新镜像时要追加模块；缓存位置由调用方决定；给 ObjC 标注用 | 1、2、3 |
| `Sources/TypeIndexing/DeclaredTypeNameSource.swift` · `DeclaredTypeNameSource` | 新增 | 协议：`imagePath`、`declaredTypeNames() async throws -> [String]` | 取代直接调用 `ObjCInterfaceIndexer` | 1 |
| `Sources/TypeIndexing/ImportedTypeNameCategory.swift` · `ImportedTypeNameCategory` | 新增 | `objcClass` / `objcProtocol` / `valueType` / `other` | 取代 SwiftPrinting 的 `CImportedTypeNameCategory` | 1 |
| `Sources/TypeIndexing/SourceKitLocator.swift` · `SourceKitLocator` | 新增 | 依次试 `<developer dir>/Toolchains/XcodeDefault.xctoolchain/usr/lib/sourcekitd.framework/sourcekitd` 与 `<developer dir>/usr/lib/sourcekitd.framework/sourcekitd`；`SourceKitManager` 改用它 | 支持 Command Line Tools | 2 |
| `Sources/TypeIndexing/TypeIndexingAvailability.swift` · `TypeIndexingAvailability` | 新增 | `static func availability(for: SDKPlatform) -> TypeIndexingAvailability`：`sdkSettings`（含 SDK 路径与版本，供 RuntimeViewer 的语料 variant 用）、sourcekitd 路径、不可用原因 | 调用方决定开不开、在界面上说明原因 | 2 |
| `Sources/TypeIndexing/SDKPlatform.swift` · `SDKPlatform.macCatalyst`、`SDKSettings.macCatalystVersion`、`compilerArguments(for:)` | 修改 | 新 case `macCatalyst`：读 macOS SDK（`xcrunSDKName`），target `ios<SupportedTargets.iosmac.DefaultDeploymentTarget>-macabi`，给 sourcekitd 显式补 `-Fsystem …/System/iOSSupport/System/Library/Frameworks`；`SDKIndexer` 的 Catalyst 搜索路径先 `System/iOSSupport/…` 再 macOS 的；缓存目录与 macOS 分开 | Mac Catalyst 的 UIKit 与其 API notes 只在 `iOSSupport` 里，原来按 `.macOS` 索引找不到 | 2、3 |
| `Sources/TypeIndexing/SwiftImportAnnotation.swift` · `SwiftImportAnnotation`、`ObjCContainerSwiftImportAnnotations`、`ObjCMemberKey` | 新增 | 单个声明与一个类 / 协议的 API notes 命名标注 | 给 MachOObjCSection 用 | 3 |
| `Tests/TypeIndexingTests/*` | 移入 + 修改 | 本仓库 `Tests/TypeIndexingTests/` 的 7 个文件搬入；`TypeDatabase<MachOFile>` 改为用假的 `DeclaredTypeNameSource`；`swiftPrivateEntitiesAreAttributedButNotRenamed` 改写为新规则 | 搬家；规则修正 | 1、2 |
| `Tests/TypeIndexingTests/{DeclaredTypeNameSourceTests,SwiftNameRuleTests,SourceKitLocatorTests,TypeIndexingAvailabilityTests,CacheDirectoryTests,MacCatalystPlatformTests,ObjCSwiftImportAnnotationTests}.swift` | 新增 | 见各步骤的行为清单 | 回归测试 | 1、2、3 |
| `Tests/TypeIndexingTests/SDKIntegrationTests.swift` | 新增 | 对本机真实 SDK 的核对，默认关闭：`TYPE_INDEXING_SDK_TESTS=1`（只读 API notes，约 2 秒），再加 `TYPE_INDEXING_SOURCEKIT_TESTS=1` 经 sourcekitd 冷生成 Catalyst 的 UIKit 接口（实测 126 秒） | 单测覆盖不到 SDK 布局与 sourcekitd 参数 | 2、3 |
| `README.md`、`LICENSE`、`AGENTS.md` + `CLAUDE.md`（符号链接）、`Documentations/README.md`、`Documentations/Evolutions/README.md`（项目类型：库）、`Documentations/Internal/TypeIndexingPipeline.md`（从本仓库移入并更新） | 新增 / 移入 | 用法、三层数据源、改名规则、缓存布局、可用性 | 新仓库的文档 | 1、3 |
| `.github/workflows/macOS.yml` | 新增 | 照本仓库 `macOS.yml` 配 macOS 构建与测试 | CI | 1 |

### swift-apinotes（fork，实现中加入）

| 文件 / 类型 | 动作 | 改什么 | 为什么 | 步骤 |
|---|---|---|---|---|
| `Sources/APINotes/TopLevelItems/ObjCContext.swift` · `ObjCContext.methods` / `properties` | 修改 | 标 `public`；打 tag `0.3.0` | 0.2.0 里是 internal，包外读不到类与协议的成员，ObjC 成员的标注没有来源 | 3 |
| `Tests/APINotesTests/ObjCContextMemberAccessTests.swift` | 新增 | 不带 `@testable` 读成员（修复前编译失败） | 回归 | 3 |

### MachOObjCSection

| 文件 / 类型 | 动作 | 改什么 | 为什么 | 步骤 |
|---|---|---|---|---|
| `Package.swift` | 修改 | `.package(local: ../swift-type-indexing, remote: …swift-type-indexing, from: "0.1.0")`，带理由注释；新 target `ObjCTypeIndexing`（依赖 `ObjCIndexing`、`ObjCDeclarationRendering`、`TypeIndexing` 限 macOS）与同名 product；测试 target `ObjCTypeIndexingTests` | 接入新包，且只有新 target 依赖它 | 4 |
| `Sources/ObjCTypeIndexing/ObjCDeclaredTypeNames.swift` · `ObjCDeclaredTypeNames<MachO>` | 新增 | 实现 `DeclaredTypeNameSource`：`ObjCInterfaceIndexer(machO:imagePath:)` → `prepare()` → 类、协议、struct、union 名 | 取代本仓库 `TypeDatabase.indexObjCMetadata(of:)` 的那段 | 4 |
| `Sources/ObjCTypeIndexing/ObjCSwiftImportNotes+TypeDatabase.swift` | 新增 | `ObjCSwiftImportNotes.init(apiNotesForClassNamed:in:)`、`init(apiNotesForProtocolNamed:in:)` | API notes → 标注 | 5 |
| `Sources/ObjCDeclarationRendering/ObjCSwiftImportNotes.swift` · `ObjCSwiftImportNotes`、`Note` | 修改 | `Note` 加 `swiftName: String?`；值上加 `declarationNote: Note?`；加 `merging(_:)`；渲染 `NS_SWIFT_NAME(name)`（在 `NS_REFINED_FOR_SWIFT` 前）；新增类型一级的渲染函数 | 标 Swift 命名 | 5 |
| `Sources/ObjCDeclarationRendering/ObjCDump+SemanticString.swift` · `ObjCClassInfo` / `ObjCProtocolInfo` / `ObjCCategoryInfo` 的 `semanticString(using:)` | 修改 | 声明行之前打印类型一级的宏行；category 成员也读标注 | 类型一级宏 | 5 |
| `Sources/ObjCInterface/ObjCInterfaceBuilder.swift` · `protocolInterface` / `markedProtocolInterface` / `categoryInterface` / `markedCategoryInterface` | 修改 | 加 `swiftImportNotes:` 参数（默认空） | 协议与 category 也能标 | 5 |
| `Tests/ObjCInterfaceTests/SwiftImportNotesRenderingTests.swift` | 修改 | 加 `NS_SWIFT_NAME`、类型一级、协议、category 的用例 | 回归 | 5 |
| `Tests/ObjCTypeIndexingTests/*` | 新增 | `ObjCDeclaredTypeNames` 对 Foundation 镜像列出 `NSObject` 等；API notes 转换（临时 `.apinotes` 驱动） | 回归 | 4、5 |
| `README.md`、`Documentations/Guides/ObjCSectionCommandLine.md`（库调用方一节）、`Documentations/Glossary.md:167-177`、`Documentations/Evolutions/README.md`（cross-repository 行） | 修改 | 新 target、新标注、指向本提案 | 文档同批 | 4、5 |

### MachOSwiftSection（本仓库）

| 文件 / 类型 | 动作 | 改什么 | 为什么 | 步骤 |
|---|---|---|---|---|
| `Package.swift` | 修改 | 删 `TypeIndexing` target（886-903）、product（1535）、`TypeIndexingTests`（1225-1231）、SourceKitD 与 swift-apinotes 两个依赖（105-108）；加 swift-type-indexing 本地候选依赖；加 target / product `SwiftTypeNameResolution`（依赖 `SwiftPrinting`、`SwiftInterface`、`TypeIndexing` 与 `ObjCTypeIndexing` 限 macOS）；`SwiftSectionKit`、`IntegrationTests` 改依赖它 | 搬家后的接线 | 6 |
| `Sources/Declaration/TypeIndexing/`（除适配器外 11 个文件） | 删除 | 已移入新包 | 搬家 | 6 |
| `Sources/Output/SwiftTypeNameResolution/TypeDatabaseTypeNameResolver.swift` · `TypeDatabaseTypeNameResolver` | 新增 | 包一个 `TypeDatabase`，实现 `ModuleNameResolving` + `CImportedNameResolving`，映射 `CImportedTypeNameCategory` → `ImportedTypeNameCategory` | 打印器与新包之间唯一的适配点，RuntimeViewer 也用它 | 6 |
| `Sources/Output/SwiftTypeNameResolution/SwiftInterfaceBuilderTypeNameProvider.swift` | 移动 + 修改 | 从 `Sources/Declaration/TypeIndexing/` 移来；依赖改为 `TypeDatabaseTypeNameResolver` 与 `ObjCDeclaredTypeNames`；`buildVersionCommand` 改用 MachOKitExtensions 的公开版本 | 名字不变以免动 CLI 调用方 | 6 |
| `Sources/Commands/SwiftSectionKit/Swift/InterfaceRequest.swift` | 修改 | `import TypeIndexing` 改为新模块；`APINotesFile(path:)` 预校验照旧 | 接线 | 6 |
| `Sources/Executables/swift-section/ObjC/Commands/ObjCInterfaceCommand.swift`、`Sources/Commands/SwiftSectionKit/ObjC/*` | 修改 | 新增 `--mark-sdk-swift-names`：按镜像平台建 `TypeDatabase`，把 API notes 标注交给 `ObjCInterfaceBuilder`；找不到 SDK 时警告并照常输出 | `swift-section objc` 的同类开关 | 7 |
| `Tests/TypeIndexingTests/` | 删除 | 已移入新包 | 搬家 | 6 |
| `Tests/IntegrationTests/TypeIndexing/TypeNameProviderTests.swift`、`Tests/SwiftSectionCommandTests/CommandRequestMappingTests.swift:137-144` | 修改 | import 改名；加 `--mark-sdk-swift-names` 的映射用例 | 接线 | 6、7 |
| `Tests/SwiftTypeNameResolutionTests/TypeDatabaseTypeNameResolverTests.swift` | 新增 | 分类映射、`__C` 解析经适配器到达打印器 | 回归 | 6 |
| `README.md`（:76 product 表、:445-451）、`Documentations/README.md`、`Documentations/SupplementaryTypeMappings.md`、`Documentations/Internal/{TypeIndexingPipeline.md（删，改为指向新包）,ProjectMap.md,Modules/README.md}`、`Documentations/Glossary.md:445-448`、`Documentations/SwiftSectionKit{,_zh}.md`、`Documentations/ObjCCommandLine{,_zh}.md`、`AGENTS.md:69` / `CLAUDE.md:69`、`AgentPlugins/swift-section/skills/swift-section-cli/SKILL.md`（:46、:216-217、§8 :352-357，加 objc 新开关）及其插件清单的 `version` | 修改 | 指向新包、新 target、新开关 | 文档同批 | 6、7 |
| `Documentations/Evolutions/README.md` | 修改 | 登记本提案 | 索引 | 0 |

### RuntimeViewer

| 文件 / 类型 | 动作 | 改什么 | 为什么 | 步骤 |
|---|---|---|---|---|
| `RuntimeViewerCore/Package.swift` | 修改 | 加 swift-type-indexing（本地候选 `../../swift-type-indexing` + 远端，限 macOS）；`RuntimeViewerCore` target 加 `TypeIndexing`、`ObjCTypeIndexing`、`SwiftTypeNameResolution` 三个 product（限 macOS） | 接线 | 8 |
| `RuntimeViewer-Local.xcworkspace/contents.xcworkspacedata`、`.worktrees/swift-type-indexing` 链接、`Documentations/Guides/LocalDependencies.md:37-44` | 修改 | 加 `../swift-type-indexing` | 本地联调 | 8 |
| `Tuist.swift:49-110`、`TuistScript.sh:82` | 修改 | 删本仓库的 `"TypeIndexing"`，加 `"SwiftTypeNameResolution"`、MachOObjCSection 的 `"ObjCTypeIndexing"`；swift-type-indexing 加进 `SOURCE_DEPENDENCIES` 并列出它的 target | Tuist 描述同批 | 8 |
| `AGENTS.md`「Dependency floors」 | 修改 | 加 swift-type-indexing 的版本下限与理由 | 规则 | 8 |
| `RuntimeViewerCore/Sources/RuntimeViewerCore/TypeNames/RuntimeTypeIndex.swift` · `RuntimeTypeIndex` | 新增 | actor，每进程一个；每个 `SDKPlatform` 一个 `TypeDatabase`；`prepare(for images:)` 后台预建；`status`；`resolver(forImageAt:)`；完成时回调 | 进程级共享索引 | 9 |
| `.../TypeNames/RuntimeTypeIndexLocation.swift` | 新增 | 缓存目录：`.app` / `Contents/XPCServices` / `Contents/Applications` 往上找 `.app` → `~/Library/Caches/<bundle id>/TypeIndex`；不在 App 里 → `~/Library/Caches/runtime-viewer-cli/TypeIndex`；测试用临时目录 | 所有进程共用缓存 | 9 |
| `.../TypeNames/RuntimeTypeIndexStatus.swift` | 新增 | 线上类型：每个平台 `building(progress)` / `ready` / `unavailable(reason)`、缓存字节数 | Report 与工具栏 | 9 |
| `.../TypeNames/RuntimeEngine+TypeIndex.swift` · `TypeIndexStatusCommand` | 新增 | Core 自有命令 `typeIndexStatus`，路由属于「问服务进程本身」（neither），带说明注释；加进 `SharedCacheRoutingDeclarationTests` 的清单 | 让 App 读状态 | 9 |
| `.../Engine/RuntimeDataChange.swift` | 修改 | 新 case `typeNamesResolved(platform: String)` | 通知 App 刷新 | 9 |
| `.../Sections/Swift/RuntimeSwiftSection.swift` | 修改 | 显示打印器与语料打印器都注册 `TypeDatabaseTypeNameResolver`；`updateConfiguration` 每次按开关重建解析器列表（不再被 `removeAllTypeNameResolvers()` 误删）；收到索引就绪时清 `interfaceByObject` / `importedInterfaceByObject` | 打印解析后的名字 | 9 |
| `.../Sections/ObjC/RuntimeObjCSection.swift:146-236`、`RuntimeEngine.swift:956-962`、`Search/RuntimeEngine+Search.swift:355-356` | 修改 | 类、协议、category 都取 API notes 标注，与 `objcSwiftImportNotes(for:)` 合并后传入 | ObjC 标注 | 9 |
| `.../Interfaces/SwiftGenerationOptions.swift` | 修改 | `@Default(true) resolvesImportedTypeNames` | 开关 | 9 |
| `.../Interfaces/RuntimeObjectInterface+GenerationOptions.swift` · `GenerationOptions` | 修改 | `@Default(true) marksSwiftNamesFromAPINotes`（ObjC 头文件的开关，放顶层：`objcHeaderOptions` 是 MachOObjCSection 的 `ObjCGenerationOptions`，而这个开关只决定 RuntimeViewer 传不传标注）；`@Default(false) waitsForTypeIndex` | 开关；非交互的调用方等索引 | 9 |
| `.../Search/Corpus/RuntimeInterfaceCorpusSnapshot.swift:29-31`、`RuntimeInterfaceCorpusStore.swift:357-369` | 修改 | variant 加 `-TypeNames<SDK build>` 或 `-UnresolvedTypeNames`；内存比较加同一条件；语料构建前等索引 | 语料与显示一致 | 9 |
| `ServicePluginEntry.swift`（本机、Catalyst、文件、框架四个入口）、命令行 host 入口 | 修改 | 进程启动时配置 `RuntimeTypeIndex` 的缓存位置 | 每个打印的进程 | 9 |
| `RuntimeViewerAppCore/BackgroundWork/TypeIndex/TypeIndexCoordinator.swift` | 新增 | 照 `CrossReferencePreparationCoordinator`：读状态、`isWorkInProgress`、`close()` | Report 与 App Nap | 10 |
| `RuntimeEngineBackgroundWork.swift:85-137` | 修改 | 创建协调器，并入 `isWorkInProgress`、activity reporter、`close()` | 接入后台工作 | 10 |
| `Reports/ReportNode.swift`、`ReportTreeBuilder.swift`、`ReportViewModel.swift` | 修改 | 新 `ReportCategory.importedTypeNames` 及其节点；状态、原因、缓存大小 | Report 可见 | 10 |
| `Activity/RuntimeEngineActivityReporter.swift`、`Activity/ToolbarActivity.swift` | 修改 | 新活动种类与文案 | 工具栏进度 | 10 |
| `Content/ContentTextViewModel.swift:227-247`、`Base/ViewModel.swift:52-63` | 修改 | 收到 `.typeNamesResolved` 时重新取当前内容 | 建好后自动刷新 | 10 |
| `RuntimeViewerUsingAppKit/.../Generation Options/GenerationOptionsViewController.swift` | 修改 | Swift 组加「Resolve Imported Type Names」，ObjC 组加「Mark Swift Names From SDK」 | 开关 | 10 |
| `RuntimeViewerUsingAppKit/.../App/RuntimeDerivedDataController.swift:50-93`、`DerivedDataStorage/RuntimeDerivedDataMaintenance.swift` | 修改 | 量与删都包括 `TypeIndex` 目录；确认框文案提到它 | Delete Derived Data 一起删 | 10 |
| `RuntimeViewerMCPBridge/MCPBridgeServer.swift:822-834`、`RuntimeViewerCommandLineInterface/CommandExecutor.swift:444-450,578-596`、`Export/RuntimeEngine+Export.swift:44` | 修改 | 置 `waitsForTypeIndex = true` | 输出稳定 | 11 |
| `AgentPlugins/runtime-viewer/skills/runtime-viewer-cli/SKILL.md`、`.claude-plugin/plugin.json`、`.codex-plugin/plugin.json` | 修改 | 说明 `__C.` 解析与首次等待；版本 `1.3.0` → `1.4.0` | 插件规则 | 11 |
| `Documentations/DerivedData.md`、`Documentations/Guides/CommandLineInterface.md`、`Documentations/Evolutions/README.md`（cross-repository 行）、`Documentations/README.md` | 修改 | 新缓存目录、输出变化、索引 | 文档同批 | 8、11 |
| 测试（见各步骤的行为清单） | 新增 | `RuntimeViewerCoreTests` 与 `RuntimeViewerAppCoreTests` 中的对应套件 | 回归 | 9、10、11 |

## 架构图

### 模块依赖（改了什么）

```text
before                                              after

MachOSwiftSection                                   + swift-type-indexing
├── TypeIndexing  ─┬─> SourceKitD                   + └── TypeIndexing ──┬─> SourceKitD
│                  ├─> swift-apinotes               +                    ├─> swift-apinotes
│                  ├─> ObjCIndexing (MOS)           +                    └─> FrameworkToolbox
│                  ├─> SwiftInterface
│                  └─> SwiftPrinting                  MachOObjCSection
├── SwiftInterface                                    ├── ObjCIndexing
├── SwiftPrinting                                     ├── ObjCDeclarationRendering   ~ notes: swiftName, type-level
└── SwiftSectionKit ──> TypeIndexing                  ├── ObjCInterface              ~ protocol/category take notes
                                                    + └── ObjCTypeIndexing ─┬─> TypeIndexing
MachOObjCSection                                    +                       ├─> ObjCIndexing
├── ObjCIndexing                                    +                       └─> ObjCDeclarationRendering
├── ObjCDeclarationRendering
└── ObjCInterface                                     MachOSwiftSection
                                                    - ├── TypeIndexing
RuntimeViewerCore                                   + ├── SwiftTypeNameResolution ─┬─> TypeIndexing
├── SwiftInterface (MSS)                            +                              ├─> ObjCTypeIndexing (MOS)
├── SwiftPrinting (MSS)                             +                              └─> SwiftPrinting, SwiftInterface
└── ObjCInterface (MOS)                               └── SwiftSectionKit ──> SwiftTypeNameResolution

                                                      RuntimeViewerCore
                                                      ├── SwiftInterface, SwiftPrinting (MSS)
                                                      ├── ObjCInterface (MOS)
                                                    + ├── SwiftTypeNameResolution (MSS)   [macOS]
                                                    + ├── ObjCTypeIndexing (MOS)          [macOS]
                                                    + └── TypeIndexing                    [macOS]
```

### 新包内部（改了什么）

```text
TypeDatabase                                   (actor, no longer generic)
├── SDKIndexer.discover()           -> .swiftmodule list, .apinotes files       (no sourcekitd)
├── ModuleInterfaceIndexer          -> type names per module                    (sourcekitd; skipped when missing)
│   ├── SourceKitManager
│   │ + └── SourceKitLocator        -> Xcode toolchain | Command Line Tools
│   └── ModuleIndexCache            ~ directory injected by the caller
├── APINotesIndex                   ~ SwiftName wins; SwiftPrivate alone -> "__" + C name
│                                   + ObjC container entries (methods, properties)
- ├── ObjCInterfaceIndexer (MOS)
+ └── [any DeclaredTypeNameSource]   -> lazy fallback, first image wins
```

### RuntimeViewer 的数据流（建立与刷新）

```text
engine connects (service process)
  └─> RuntimeTypeIndex.prepare(platform, linked modules)          background, Report row "Imported Type Names"
        ├─> TypeIndexingAvailability.availability(for:)          unavailable -> status .unavailable(reason), stop
        └─> TypeDatabase.index(dependencies:moduleFilter:)       reads/writes ~/Library/Caches/<id>/TypeIndex
              └─> done
                    ├─> RuntimeSwiftSection: register TypeDatabaseTypeNameResolver, clear interface caches
                    └─> broadcast RuntimeDataChange.typeNamesResolved(platform:)
                          └─> app: RuntimeInterfaceCache.invalidateAll()
                                └─> ContentTextViewModel refetches -> "UIKit.__UICellConfigurationState"

interface request
  ├─ UI           (waitsForTypeIndex = false) -> prints now: "__C.X" until ready
  └─ MCP/CLI/export/Find corpus (waitsForTypeIndex = true) -> awaits ready | unavailable, then prints
```

## 详细设计

### 新包的公开 API

```swift
#if os(macOS)
import Foundation

/// One dependency image whose runtime metadata lists the types it declares.
/// `TypeDatabase` consults these, in order, only for names that neither the
/// SDK's module interfaces nor its API notes attribute; the first image that
/// declares a name wins.
public protocol DeclaredTypeNameSource: Sendable {
    /// The image's install path; the module name is derived from it
    /// (`TypeDatabase.moduleName(forImagePath:)`).
    var imagePath: String { get }

    /// Every class, protocol, struct and union name the image's metadata declares.
    func declaredTypeNames() async throws -> [String]
}

/// The namespace a C-imported name lives in, as the printer asks about it.
public enum ImportedTypeNameCategory: Sendable, Hashable {
    case objcClass
    case objcProtocol
    case valueType
    case other
}

/// Whether this Mac can index an SDK platform, and why not.
public struct TypeIndexingAvailability: Sendable, Hashable {
    public enum UnavailabilityReason: Sendable, Hashable {
        case noDeveloperDirectory
        case sdkNotInstalled(SDKPlatform)
    }
    public let sdkSettings: SDKSettings?       // path, version, build, Mac Catalyst version
    /// `nil` when the developer directory has no sourcekitd: API notes and
    /// runtime metadata still resolve names, module interfaces are skipped.
    public let sourceKitPath: String?
    public let unavailabilityReason: UnavailabilityReason?
    public var isAvailable: Bool { unavailabilityReason == nil }

    public static func availability(for platform: SDKPlatform) -> TypeIndexingAvailability
}

public enum SDKPlatform: String, CaseIterable, Hashable, Codable, Sendable {
    case macOS = "macosx"
    case macCatalyst = "maccatalyst"            // the macOS SDK read through System/iOSSupport
    case iOS = "iphoneos"
    // tvOS, watchOS, visionOS, driverKit and the simulators, as before
}

/// What an API notes file says about how Swift imports one declaration.
public struct SwiftImportAnnotation: Sendable, Hashable {
    /// `SwiftName:`; when present, it is the Swift name as is.
    public var swiftName: String?
    /// `SwiftPrivate: true`; without a `SwiftName`, Swift prefixes `__`.
    public var isSwiftPrivate: Bool
}

/// The key API notes files use for an Objective-C member.
public enum ObjCMemberKey: Sendable, Hashable {
    case method(selector: String, isClassMethod: Bool)
    case property(name: String, isClassProperty: Bool)
}

/// API notes for one Objective-C class or protocol and its members.
public struct ObjCContainerSwiftImportAnnotations: Sendable, Hashable {
    public var declaration: SwiftImportAnnotation?
    public var members: [ObjCMemberKey: SwiftImportAnnotation]
}

@available(macOS 13.0, *)
public actor TypeDatabase {
    public init(
        platform: SDKPlatform,
        cacheDirectory: URL? = nil,                  // nil: Application Support/swift-type-indexing
        supplementaryAPINotesURLs: [URL] = []
    )

    public func index(
        dependencies: [any DeclaredTypeNameSource],
        moduleFilter: @Sendable (String) -> Bool
    ) async throws

    public func moduleName(forTypeName typeName: String) async -> String?
    public func swiftName(forCName cName: String, category: ImportedTypeNameCategory) -> String?
    public func swiftImportAnnotations(forObjCClassNamed className: String) -> ObjCContainerSwiftImportAnnotations?
    public func swiftImportAnnotations(forObjCProtocolNamed protocolName: String) -> ObjCContainerSwiftImportAnnotations?

    public static func moduleName(forImagePath imagePath: String) -> String
}
#endif
```

- `SDKPlatform` 公开，并新增 `macCatalyst`（落地时发现，见决策日志）；`SDKSettings`（`sdkPath`、`version`、`productBuildVersion`、`macCatalystVersion`、`cacheDirectoryComponent`）与 `APINotesFile(path:)` 一并公开——后者是 `swift-section` 预检 `--supplementary-apinotes` 路径用的。
- `index(dependencies:moduleFilter:)` 可多次调用：第一次发现 SDK 并登记 API notes，之后只补新的模块与依赖镜像；因此 API notes 优先于模块接口改为查询时决定（三张表），不再靠写入顺序。
- 搬家时保留的三个 `register(...)` 测试钩子（提案 0009「与提案的差异」一节）降为 `internal`，测试用 `@testable import`。
- 命名照 `apple-style-api-design`：协议按「是什么」命名并沿用组织里 `ObjCMetadataSource` 的 `Source` 后缀；查询读成名词短语（`moduleName(forTypeName:)`）；不给 MachOKit 的类型补遵循新包的协议（由 MachOObjCSection 的包装类型实现）。

### 改名规则

```swift
// APINotesIndex.registerEntities(_:declaredIn:into:)
for entity in entities {
    let cName = entity.name
    moduleNamesByCName[cName] = moduleName
    let swiftName: String? = if let explicitSwiftName = entity.swiftName {
        explicitSwiftName                                   // swift_name wins, no "__"
    } else if entity.isSwiftPrivate == true {
        "__" + cName                                         // swift_private alone
    } else {
        nil
    }
    guard let swiftName, swiftName != cName else { continue }
    self[keyPath: renameTable][cName] = Name(moduleName: moduleName, name: swiftName)
    cNamesBySwiftName[swiftName] = Name(moduleName: moduleName, name: cName)
}
```

ObjC 成员（`Methods:` 的 `Selector` + `MethodKind`，`Properties:` 的 `Name` + `PropertyKind`）按同样的两条规则记进 `ObjCContainerSwiftImportAnnotations`，但只记原始的两个属性（`swiftName` / `isSwiftPrivate`）——成员一级要打印的是宏，不是推导后的 Swift 名。

### 缓存目录

`ModuleIndexCache` 的目录改为 `<cacheDirectory>/<platform rawValue>/<SDK 版本-build>/`；`cacheDirectory` 为 `nil` 时是 `Application Support/swift-type-indexing/SDKIndexer`。`currentGeneratorVersion` 不变（条目格式没变）；目录名换了，旧的 `Application Support/MachOSwiftSection/SDKIndexer` 不再读，也不自动删（新包第一次运行重建，属一次性成本）。

### MachOObjCSection

```swift
// ObjCTypeIndexing
#if os(macOS)
public struct ObjCDeclaredTypeNames<MachO: ObjCMetadataSource & Sendable>: DeclaredTypeNameSource {
    public init(machO: MachO, imagePath: String)
    public var imagePath: String { get }
    public func declaredTypeNames() async throws -> [String]
}

extension ObjCSwiftImportNotes {
    /// The notes the SDK's API notes give a class and its members.
    @available(macOS 13.0, *)
    public init(apiNotesForClassNamed className: String, in typeDatabase: TypeDatabase) async
    @available(macOS 13.0, *)
    public init(apiNotesForProtocolNamed protocolName: String, in typeDatabase: TypeDatabase) async
}
#endif

// ObjCDeclarationRendering
extension ObjCSwiftImportNotes {
    public struct Note: Sendable, Hashable {
        public var isRefinedForSwift: Bool
        public var swiftName: String?                     // + NS_SWIFT_NAME(swiftName)
    }
    public var declarationNote: Note?                    // + the type itself
    public func merging(_ other: ObjCSwiftImportNotes) -> ObjCSwiftImportNotes   // other wins per field
}
```

打印效果：

```objc
NS_REFINED_FOR_SWIFT
@interface UICellConfigurationState : UIViewConfigurationState
@property (nonatomic, getter=isEditing) BOOL editing;
@end

NS_SWIFT_NAME(PKDrawingReference)
@interface PKDrawing : NSObject <NSCopying, NSSecureCoding>
- (instancetype)initWithData:(NSData *)data error:(NSError **)error;
@end
```

`declarationNote` 两个字段都有时打成一行 `NS_SWIFT_NAME(X) NS_REFINED_FOR_SWIFT`。成员一级 `- (void)foo NS_SWIFT_NAME(bar()) NS_REFINED_FOR_SWIFT;`。标注不进可折叠区域（与现在的 `NS_REFINED_FOR_SWIFT` 一致：它是声明的一部分，不是注释）。

### MachOSwiftSection 的适配层

```swift
#if os(macOS)
@available(macOS 13.0, *)
public struct TypeDatabaseTypeNameResolver: ModuleNameResolving, CImportedNameResolving {
    public init(typeDatabase: TypeDatabase)
    public func moduleName(forTypeName typeName: String) async -> String?
    public func swiftName(forCName cName: String, category: CImportedTypeNameCategory) async -> String?
}
#endif
```

`SwiftInterfaceBuilderTypeNameProvider` 保留公开名字与构造器签名，内部改为：按镜像平台建 `TypeDatabase`（`LC_BUILD_VERSION` 的 macCatalyst 映射到 `.macCatalyst`，原来映射到 `.macOS`，Catalyst 镜像因此读不到 UIKit 的 API notes），依赖镜像包成 `ObjCDeclaredTypeNames`，把查询转给一个 `TypeDatabaseTypeNameResolver`。

`swift-section objc interface --mark-sdk-swift-names`：按镜像 `LC_BUILD_VERSION` 的平台建 `TypeDatabase`（只读 API notes，`moduleFilter` 返回 `false`，所以不碰 sourcekitd），对每个类与协议取 `ObjCSwiftImportNotes(apiNotesFor…:in:)` 传给 `ObjCInterfaceBuilder`。找不到 SDK 时打印一条 warning，输出与不加开关时相同。

### RuntimeViewer

**进程内的索引**。`RuntimeTypeIndex` 是每个服务进程一个的 actor（经 `@Dependency` 取得，`fileprivate static let shared`），按 `SDKPlatform` 各持一个 `TypeDatabase`：

- 平台：共享缓存镜像用 `RuntimeSharedCachePartition.platform(ofImageAt:)`（macOS → `.macOS`，Mac Catalyst → `.macCatalyst`）；文件用 `RuntimeFile.platform`；其余镜像读 `LC_BUILD_VERSION`（`macCatalyst` 平台号映射到 `.macCatalyst`）。
- 预建：engine 连上后、以及新加载的镜像，把它们的依赖模块名并进 `moduleFilter`，依赖镜像包成 `ObjCDeclaredTypeNames` 交给 `index(dependencies:moduleFilter:)`。同一平台已在建时合并请求，不重复建。
- 不可用：`TypeIndexingAvailability` 不可用时状态记为 `.unavailable(reason)`，打印器不注册解析器，输出保持 `__C.`。
- 内存：每个打印的服务进程各有一份（本机、Catalyst、每个文件、每个框架实例），落地时量一次 `malloc` 在用量写进提案（步骤 9）。

**打印**。`RuntimeSwiftSection.updateConfiguration` 现在在 opaque 开关关闭时 `removeAllTypeNameResolvers()`；改为每次按当前选项重建完整的解析器列表（opaque 解析器 + 类型名解析器），两者互不误删。显示打印器与语料打印器都这样做。索引就绪时 `RuntimeTypeIndex` 通知各 section 清掉 `interfaceByObject` / `importedInterfaceByObject` 并重建解析器列表，然后由 engine `broadcast(.typeNamesResolved(platform:))`。

**等待**。`GenerationOptions.waitsForTypeIndex` 为 `true` 时，`RuntimeEngine._interface(for:options:)` 在打印前 `await` 该镜像平台的索引就绪或不可用；`false`（界面）时直接打印。MCP、命令行、导出把它置 `true`；Find 语料构建一律等待。等待只发生在第一次（磁盘缓存冷）建立某个 SDK 版本的模块时。

**兼容性**。三个新选项都用 `@Default`，旧版对端解码时取默认；`RuntimeDataChange` 新 case 只由新版 Mac 服务发出，iOS 设备等旧对端不会收到也不会发出；`typeIndexStatus` 命令对旧对端没有处理器，App 把「无应答」当作 `.unavailable`。

**语料 variant**。`RuntimeInterfaceCorpusSnapshot.variant(for:)` 变为 `"\(transformer.derivedDataDigest)-ByCategory-\(typeNamesComponent)"`，`typeNamesComponent` 是 `TypeNames<platform>-<SDK 版本-build>`（解析了）或 `UnresolvedTypeNames`；内存里的比较加同样的条件。

**界面**。Generation Options 面板：Swift 组「Resolve Imported Type Names」、ObjC 组「Mark Swift Names From SDK」，都默认勾选。Report 新类别「Imported Type Names」，每个 engine 下每个平台一行：建立中（进度）、就绪（缓存大小）、不可用（原因：没有开发者目录 / 没装这个平台的 SDK）。

## 替代方案考量

- **在二进制层面推断（同名 + `_ObjectiveCBridgeable` ⇒ `__X`）**：否。SDK 里 20 个同名桥接中 14 个是 `XReference`，在二进制里与 `__X` 无法区分；另有 15 个 `__` 类型不同名，规则碰不到。
- **新包留在本仓库、只给 RuntimeViewer 用**：否。MachOObjCSection 需要同一份 API notes 数据，而它是本仓库的依赖，不能反向依赖本仓库的 target。
- **新包继续依赖 MachOObjCSection 的 `ObjCIndexing`**：否。用户选择让 ObjC 头文件也接入，MachOObjCSection 依赖新包，两者互相依赖会成环；改为协议注入。
- **ObjC 一侧另起提案**：用户否了，选择一并做。
- **RuntimeViewer 默认关、手动开**：用户否了，选择找得到 SDK 就自动开。
- **界面等索引建好再显示**：用户否了，选择先显示 `__C.`、后台预建、建好刷新。
- **MCP / 命令行 / 导出保持 `__C.`**：用户否了，选择一起换。
- **开关放进 Settings 的新分支**：否。Swift / ObjC 的打印开关都在 Generation Options 面板，它们随每个请求发出、进接口缓存的键、命令行也读同一份；放进 Settings 要另造一条把设置送到服务进程的通道。
- **类型索引缓存作为 `RuntimeDerivedDataKind`**：否。derived data 按 dyld 共享缓存的系统身份分目录、只给共享缓存镜像用，而类型索引按 SDK 版本，与镜像无关；放成同级的独立目录，删除时一起删。
- **保留 git 历史迁移到新仓库**：不做。路径在历史里变过（`Sources/TypeIndexing` → `Sources/Declaration/TypeIndexing`），迁移收益小；首个提交注明来源提交。

## 影响

### 源码兼容性（source compatibility）

**有破坏**（本仓库）：

- `TypeIndexing` library product 删除。组织内没有外部使用方（逐个仓库的 `Package.swift` 查过）。改前 `.product(name: "TypeIndexing", package: "MachOSwiftSection")`，改后 `.product(name: "TypeIndexing", package: "swift-type-indexing")`，或改用 `SwiftTypeNameResolution`。
- `SwiftInterfaceBuilderTypeNameProvider` 从 `TypeIndexing` 模块移到 `SwiftTypeNameResolution` 模块：调用方 `import TypeIndexing` 改为 `import SwiftTypeNameResolution`，签名不变。
- `swift-section interface` 的输出变化：`SwiftPrivate` / `SwiftName` 改名开始生效（例如 `UIKit.UICellConfigurationState` → `UIKit.__UICellConfigurationState`、`PencilKit.PKDrawing` → `PencilKit.PKDrawingReference`），只在 `--resolve-c-module-names` 打开时。

MachOObjCSection 为纯新增：`Note` 加字段带默认值、`declarationNote` 默认 `nil`、新参数带默认值。

### ABI 兼容性（条件项）

不适用 —— 四个仓库都以 SPM 源码分发，使用方每次重新编译。

### 下游影响

- 本仓库：`SwiftSectionKit`、`IntegrationTests`、`swift-section` 可执行产物。
- MachOObjCSection：新 target `ObjCTypeIndexing`；`ObjCInterface` 的协议与 category 入口多一个带默认值的参数。
- RuntimeViewer（经 `branch: "next"` 跟随两个库）：用户可见的变化见下；依赖图多一个包（SourceKitD、swift-apinotes 早已在图里），`Tuist.swift` 的 target 清单要跟着改。
- MachOKitUI、SymbolViewer 等其他下游：不受影响（不依赖 `TypeIndexing`）。

**RuntimeViewer 用户能看到的变化**：

- Swift 接口里的 `__C.X` 变成真实模块与 Swift 名（`UIKit.UITraitCollection`、`UIKit.__UICellConfigurationState`、`PencilKit.PKDrawingReference`），macOS 与 Mac Catalyst 只要装了 Xcode 或 Command Line Tools；读 iOS 等其他平台的文件需要装了对应 SDK 的 Xcode。
- ObjC 头文件的类、协议、category 与成员上出现 `NS_SWIFT_NAME(...)` / `NS_REFINED_FOR_SWIFT`。
- 第一次在某个 SDK 版本上使用时，Report 里有一行「Imported Type Names」在建立，期间界面先显示 `__C.`，建好后自动刷新；命令行与 MCP 在这期间会等待。
- Generation Options 面板多两个默认勾选的开关；Delete Derived Data 会同时删掉类型索引缓存。

### 文档与示例

见改动地图各仓库的文档行；新仓库的 README 写清三层数据源、改名规则、可用性与缓存位置。

## API 演进与废弃策略

- `TypeIndexing` product 在本仓库直接删除，不留 `@available(*, deprecated)` 的转发：没有外部使用方，转发壳会让本仓库继续依赖 SourceKitD 与 swift-apinotes。
- 本仓库 semver：删除 product 属破坏性改动，按本仓库 0.x 惯例抬 minor 版本，在 changelog 写明迁移方式。
- MachOObjCSection：纯新增，抬 patch 或 minor 按其惯例。
- 新包从 `0.1.0` 起步；`DeclaredTypeNameSource` 的要求、`ImportedTypeNameCategory` 的 case 一经发布就是公开契约——后者落地前确认四个 case 够用（它与 `CImportedTypeNameCategory` 一一对应）。

## 落地步骤

0. **提案入库**——本仓库 `Documentations/Evolutions/README.md` 登记草案；批准后、开工前，在 MachOObjCSection 与 RuntimeViewer 的提案索引各加一行 cross-repository 链接。
   - 行为：无代码。
1. ✅ **建新包并原样搬入**（2026-11-23 完成）——swift-type-indexing 改动地图的 Package.swift、移入的源码与测试、`DeclaredTypeNameSource`、`ImportedTypeNameCategory`、README / LICENSE / AGENTS.md / CI。
   - 行为：`existingTypeIndexingTestsPassAgainstNonGenericDatabase`
   - 行为：`declaredTypeNameSourcesAreQueriedLazilyInDependencyOrder`
   - 行为：`firstImageDeclaringANameWinsTheAttribution`
   - 行为：`failingSourceIsDroppedAndNotRetried`
2. ✅ **改名规则、Command Line Tools 与 Mac Catalyst**（2026-11-23 完成）——`APINotesIndex` 改名规则、`SourceKitLocator`、`TypeIndexingAvailability`、缓存目录注入。先写测试并确认修复前失败。
   - 行为：`swiftPrivateWithoutSwiftNameResolvesToDoubleUnderscorePrefix`
   - 行为：`swiftNameWinsOverSwiftPrivate`
   - 行为：`plainEntityKeepsItsCName`
   - 行为：`sourceKitIsFoundInCommandLineToolsLayout`
   - 行为：`sourceKitIsFoundInXcodeToolchainLayout`
   - 行为：`missingSourceKitSkipsModuleInterfacesButKeepsAPINotes`
   - 行为：`availabilityReportsMissingSDK`
   - 行为：`cacheEntriesAreWrittenUnderTheGivenDirectory`
   - 行为：`macCatalystSearchesIOSSupportFirst`、`macCatalystTargetTripleIsMacABI`、`macCatalystInterfaceGenerationSeesIOSSupportFrameworks`、`macCatalystCachesApartFromMacOS`
   - 实测（`SDKIntegrationTests`）：Catalyst 下 `UICellConfigurationState` → `UIKit` / `__UICellConfigurationState`；macOS 下 `PKDrawing` → `PencilKit` / `PKDrawingReference`；sourcekitd 冷生成 Catalyst 的 UIKit 接口后 `UIStackView` → `UIKit`
3. ✅ **ObjC 容器的 API notes 查询**（2026-11-23 在本机完成；fork 的 0.3.0 与新包的推送待用户批准公开仓库）——`SwiftImportAnnotation`、`ObjCContainerSwiftImportAnnotations`、`TypeDatabase.swiftImportAnnotations(…)`。
   - 行为：`classAnnotationCarriesSwiftNameAndSwiftPrivate`
   - 行为：`methodAnnotationIsKeyedBySelectorAndKind`
   - 行为：`propertyAnnotationIsKeyedByNameAndKind`
   - 行为：`protocolAnnotationsAreSeparateFromClassAnnotations`
   - 前置：swift-apinotes fork 把 `ObjCContext.methods` / `properties` 改成 `public`，打 `0.3.0`。
   - 新包打 `0.1.0` 并推送（公开仓库）。
4. **MachOObjCSection 接入新包**——`Package.swift`、`ObjCTypeIndexing`、`ObjCDeclaredTypeNames`。
   - 行为：`declaredTypeNamesListFoundationClassesProtocolsAndStructs`
   - 行为：`typeDatabaseAttributesPrivateClassThroughObjCDeclaredTypeNames`
5. **ObjC 头文件的 Swift 命名标注**——`ObjCSwiftImportNotes` 扩展、协议与 category 入口、类型一级宏、API notes 转换。
   - 行为：`memberSwiftNamePrintsBeforeRefinedForSwift`
   - 行为：`classDeclarationNotePrintsOnItsOwnLineAboveInterface`
   - 行为：`protocolInterfaceTakesNotes`
   - 行为：`categoryMembersTakeNotes`
   - 行为：`mergingKeepsBothSourcesAndTheArgumentWinsPerField`
   - 行为：`apiNotesForClassBecomeNotes`（临时 `.apinotes` 驱动）
   - 行为：`markedRenderingStillProjectsToPlainRendering`
6. **本仓库切换到新包**——删 `TypeIndexing`、加 `SwiftTypeNameResolution`、CLI 接线、文档与 skill。
   - 行为：`resolverMapsEveryPrinterCategory`
   - 行为：`resolverPrintsResolvedModuleAndSwiftName`（假的 `TypeDatabase` 数据驱动打印器）
   - 行为：`resolveCModuleNamesFlagStillMapsToRequest`
   - 端到端（维护者手动）：`swift-section interface --resolve-c-module-names` 对 UIKitCore（Catalyst）输出 `UIKit.__UICellConfigurationState`、对 PencilKit 输出 `PencilKit.PKDrawingReference`。
7. **`swift-section objc --mark-sdk-swift-names`**。
   - 行为：`markSDKSwiftNamesFlagMapsToRequest`
   - 行为：`missingSDKWarnsAndPrintsUnmarkedOutput`
   - 端到端（手动）：PencilKit 的 `PKDrawing` 头文件出现 `NS_SWIFT_NAME(PKDrawingReference)`。
8. **RuntimeViewer 依赖接线**——`RuntimeViewerCore/Package.swift`、Local workspace 与 `.worktrees` 链接、Tuist、`AGENTS.md` 依赖下限、三个 workspace 的锁文件（`UpdatePackagesScript.sh`）。
   - 行为：`./TuistScript.sh check` 通过；Debug workspace 能编过。
9. **RuntimeViewer Core**——`TypeNames/` 目录、`RuntimeDataChange` 新 case、`typeIndexStatus` 命令、打印器接线、ObjC 标注合并、三个选项、语料 variant、四个服务与命令行 host 的入口配置。实测：Catalyst 镜像的 API notes 确实来自 `iOSSupport`；记录每个服务进程多出的 `malloc` 在用量。
   - 行为：`typeIndexBuildsOncePerPlatformAndMergesConcurrentRequests`
   - 行为：`unavailableSDKLeavesImportedNamesUnresolved`
   - 行为：`resolverSurvivesOpaqueTypeSwitchOff`
   - 行为：`readyIndexClearsSectionInterfaceCaches`
   - 行为：`readyIndexBroadcastsTypeNamesResolved`
   - 行为：`waitingRequestPrintsResolvedNamesOnColdIndex`
   - 行为：`nonWaitingRequestPrintsImportedPlaceholderOnColdIndex`
   - 行为：`switchOffPrintsImportedPlaceholder`
   - 行为：`objcHeaderMergesAPINotesWithRefinedMembers`
   - 行为：`corpusVariantNamesTypeNameResolution`
   - 行为：`typeIndexStatusCommandRoutesToServingProcess`
   - 行为：`olderPeerDecodesOptionsWithDefaults`
   - 行为：`cacheLocationWalksUpToEnclosingApp`（App、XPC service、内嵌命令行三种位置）
10. **RuntimeViewer App**——协调器、Report、工具栏活动、内容刷新、Generation Options 两个开关、Delete Derived Data。
    - 行为：`typeIndexCoordinatorReportsBuildingReadyAndUnavailable`
    - 行为：`reportListsImportedTypeNamesPerPlatform`
    - 行为：`contentRefetchesOnTypeNamesResolved`
    - 行为：`deleteDerivedDataRemovesTypeIndexDirectory`
    - 行为：`derivedDataSizeIncludesTypeIndexDirectory`
11. **MCP、命令行、导出与插件**——`waitsForTypeIndex`、skill、两个插件清单 `1.4.0`、`CommandLineInterface.md`。
    - 行为：`mcpOptionsWaitForTypeIndex`
    - 行为：`commandLineOptionsWaitForTypeIndex`
    - 行为：`exportConfigurationWaitsForTypeIndex`

**收尾时必须判断两件事**（判断结果写进决策日志，不允许沉默跳过）：

- **要不要配套专题文章**——新包的 `Documentations/Internal/TypeIndexingPipeline.md`（从本仓库移入）承担实现说明；RuntimeViewer 一侧预计要在 `Documentations/DerivedData.md` 加一节类型索引缓存，是否另写实现说明到时判断。
- **有没有引入新术语**——预计有「类型索引（type index）」「Swift 命名标注」，登记进各仓库的 `Glossary.md`。

## 决策日志

| 日期 | 变更 | 说明 |
|------|------|------|
| 2026-11-23 | Created as Draft | RuntimeViewer 把 `UICellConfigurationState` 的桥接类型显示成 `__C.UICellConfigurationState`。查明二进制只记 ObjC 运行时名、改名只在 SDK 的 API notes 里，而本仓库已有的 `TypeIndexing` RuntimeViewer 用不上、且改名规则有误；用户决定把它抽成独立的包，三方接入 |
| 2026-11-23 | 否决二进制层面的推断 | 同名又桥接的 20 个 SDK 类型里 14 个是 `XReference`，与 `__X` 在二进制里无法区分 |
| 2026-11-23 | ObjC 一侧并入本提案 | 用户选择一并做，而不是另起提案；新包因此不能依赖 MachOObjCSection，ObjC 元数据一层改为协议注入 |
| 2026-11-23 | 新仓库名 `swift-type-indexing` | 用户选择；模块名仍是 `TypeIndexing` |
| 2026-11-23 | RuntimeViewer 找得到 SDK 就自动开 | 用户选择；可用条件从「装了 Xcode」改为「找得到该平台 SDK」，因为 Command Line Tools 也带 macOS SDK 与 sourcekitd（用户指出，本机核对） |
| 2026-11-23 | ObjC 只标 Swift 命名、不加 `@import` | 用户选择 |
| 2026-11-23 | 后台预建、先显示 `__C.` | 用户选择 |
| 2026-11-23 | 提案放在本仓库 | 用户选择；其余三个仓库的索引加 cross-repository 行 |
| 2026-11-23 | MCP、命令行、导出一起换 | 用户选择；为了输出稳定，这些非交互的调用方等索引就绪（agent 自定，可推翻） |
| 2026-11-23 | 开关放 Generation Options 面板 | agent 自定，可推翻：与现有打印开关同处，随请求发出、进缓存键、命令行也读同一份 |
| 2026-11-23 | 共识确认 | 用户确认以上决定，开始写提案 |
| 2026-11-23 | Accepted | 用户批准，开始实现 |
| 2026-11-23 | swift-apinotes fork 加入范围 | 它的 `ObjCContext.methods` / `properties` 在 0.2.0 是 internal，ObjC 成员的标注读不到。改为 `public` 并打 0.3.0（每个字段一行），比在新包里另写一套 YAML 解析更小；推送与打 tag 和新仓库一起请用户批准 |
| 2026-11-23 | 新增 `SDKPlatform.macCatalyst` | 提案原定 Catalyst 按 `.macOS` 索引并「落地时实测确认」：实测 `SDKIndexer` 不搜 `System/iOSSupport`，Catalyst UIKit 的 API notes 找不到；sourcekitd 按前端调用解析参数，macabi target 不会自动加 iOSSupport 框架路径（报 `Could not load module: UIKit`）。新 case 读 macOS SDK、先搜 iOSSupport、显式传 `-Fsystem` |
| 2026-11-23 | `index` 可多次调用、优先级改为查询时决定 | RuntimeViewer 加载新镜像时要追加模块；原先 API notes 靠写入顺序覆盖模块接口名，追加的接口名会把名字抢回去 |
| 2026-11-23 | 可用性返回 `sdkSettings` 而非 `sdkPath` | RuntimeViewer 的语料 variant 要 SDK 版本与 build，`SDKSettings` 一并给出 |
| 2026-11-23 | 加默认关闭的 `SDKIntegrationTests` | 单测覆盖不到真实 SDK 布局与 sourcekitd 参数，上面两个 Catalyst 问题都是实测才发现的；手动开启，不进 CI |
