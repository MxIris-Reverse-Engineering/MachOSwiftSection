# Draft - 把 SwiftInspection 的 ObjC 部分拆成 SwiftObjCInterop 模块

- **状态**: In Progress
- **作者**: JH
- **创建日期**: 2026-11-09
- **最后更新**: 2026-11-09
- **所属愿景**: 无
- **关联提案**: [0055-group-sources-by-layer](0055-group-sources-by-layer.md)（上一次整理 target 的位置，新模块沿用它的 `Sources/<层>/<Target>` 布局）；[0018-self-contained-abi-layer](0018-self-contained-abi-layer.md)（把符号归属定在 SwiftInspection，后来的 ObjC 功能以此为由就近落户）；要搬的代码出自 [0046](0046-objc-implementation-class-recognition.md)、[0047](0047-objc-ancestor-override-recovery.md)、[0048](0048-objc-member-selector-recovery.md)、[0049](0049-objc-ancestor-dependency-closure.md)、[0052](0052-objc-custom-class-name.md)、[0078](0078-objc-classes-without-class-objects.md)、[0079](0079-swift-declared-objc-protocols.md)；[0057-reading-context-migration](0057-reading-context-migration.md)（0.25.0 删除废弃的读取转发，本提案随同一个破坏性版本发布）
- **实现分支 / PR**: `refactor/swift-objc-interop-module`（worktree `.worktrees/MachOSwiftSection-SwiftObjCInterop`）；RuntimeViewer 一侧是 `feature/swift-objc-interop-module`（worktree `RuntimeViewer/.worktrees/RuntimeViewer-SwiftObjCInterop`）
- **配套文档**: 模块参考 [Modules/SwiftObjCInterop.md](../Internal/Modules/SwiftObjCInterop.md)

## 摘要

SwiftInspection 的 39 个源文件里有 19 个、约 6100 行（整个模块的一半）讲的是 Swift 类型在 Objective-C 一侧的样子：Swift 类的 class object、`@objc @implementation` 类、Swift 里声明的 `@objc` 协议、ObjC 方法表与祖先链、从 ClangImporter 移植的命名规则。本提案把这 19 个文件整块搬进新模块 `SwiftObjCInterop`（`Sources/Analysis/SwiftObjCInterop/`），它在依赖层级上紧挨在 SwiftInspection 之上、在 SwiftLayout 与 SwiftThunkAnalysis 之下。类型名、访问级别、日志的 subsystem 与 category、缓存淘汰分组的名字一律不变，只换所在模块；SwiftInspection 从此不再依赖 MachOObjCSection。这是源码层面的破坏性改动：直接用到这些公开类型的下游要多写一行 `import SwiftObjCInterop`，RuntimeViewer 的两处在同一批改好。dump 与 interface 的输出不变。

## 动机

SwiftInspection 的定位是 Swift runtime metadata 分析：带 symbolic reference 的 demangle、enum 布局、泛型参数分层、in-process metadata 构建。可今天它有一半代码在读 `__objc_classlist`、`class_ro_t`、`protocol_t` 和 ObjC 方法表，模块名已经说不清模块里装着什么：

- **一项模块依赖只为这一半而存在**。SwiftInspection 里 import MachOObjCSection 的 8 个文件全在 ObjC 一侧，另一半一个都不用它（`Package.swift:521`）。
- **入口文档失去主题**。`AGENTS.md` 里 SwiftInspection 的条目约 4400 个字符，是所有模块条目里最长的（第二长的 SwiftThunkAnalysis 约 2800），大半篇幅在讲 ObjC 索引；模块参考 `Internal/Modules/SwiftInspection.md` 至今「待写」，一个模块装着两个主题，很难写成一篇。
- **这种混杂是一份份提案就近累积出来的，没有人通盘决定过**。0046 的决策日志写的理由是「它已经依赖 MachOObjCSection 与 MachOFoundation，位于 SwiftDump 与 SwiftDeclaration 之下，两条路径共用」（`0046-objc-implementation-class-recognition.md:126`）；此后 0047、0048、0049、0052、0078、0079 都以「与已有的 ObjC 索引同层同模式」跟进。新模块同样位于 SwiftDump 与 SwiftDeclaration 之下，同样满足这个理由；但只要 ObjC 代码还留在 SwiftInspection，下一个 ObjC 功能还会照这个理由放进去。

## 前期调研

### 要搬的 19 个文件

全部在 `Sources/Analysis/SwiftInspection/`，括号里是 `next` 当前的行数：

| 主题 | 文件 |
|------|------|
| Swift 类在 ObjC 一侧的样子 | `SwiftClassObjectIndex.swift`（237）、`SwiftClassWithoutClassObjectIndex.swift`（454）、`CustomObjCClassName.swift`（38）、`ObjCRuntimeNames.swift`（79）、`ClassHierarchyDumper.swift`（81） |
| `@objc @implementation` 类 | `ObjCImplementationClassIndex.swift`（740）、`ObjCImplementationClassFacts.swift`（208） |
| ObjC 协议 | `SwiftDeclaredObjCProtocolIndex.swift`（289）、`ObjCProtocolAdoptionIndex.swift`（283）、`ObjCProtocolRecord.swift`（213）、`ObjCProtocolRequirements.swift`（424） |
| 成员与祖先链 | `ObjCClassMethodIndex.swift`（641）、`ObjCClassHierarchy.swift`（257）、`ObjCAncestorResolver.swift`（286）、`ObjCMember.swift`（193）、`ObjCMemberShape.swift`（433） |
| 命名规则与类型编码 | `ObjCImporterNaming.swift`（924）、`ObjCImporterVerbs.swift`（88）、`ObjCTypeEncoding.swift`（274） |

合计 6142 行；留下的 20 个文件约 6000 行。

`ClassHierarchyDumper` 是 in-process 专用的调试工具（`@_spi(Internals)`），沿 Swift 类的 metadata 一路走进 ObjC 父类，用的是 MachOObjCSection 的 `ObjCClass64`，并在同一个文件里给 `ObjCClass64` 补了几个 retroactive conformance。它若留下，SwiftInspection 就得为这 81 行继续依赖 MachOObjCSection，所以一起搬。

### 依赖方向只有一个

- **ObjC 一侧用到核心的只有三样，都已经是 `public` 或 `package`**：`SymbolicDemangler.demangleTypeUncached(for:in:)` 与 `demangleContext(for:in:)`（`public`，`SymbolicDemangler.swift:327`、`:342`）、`NodeTypeNaming`（`package`，`NodeTypeNaming.swift:53`–`:130`）、`GenericParameterDepthLayout.make(for:in:)`（`public`，`GenericParameterDepthLayout.swift:87`）。搬过去不需要放宽任何访问级别。调用点：`ObjCProtocolAdoptionIndex.swift:245`、`ObjCRuntimeNames.swift:73`、`SwiftClassObjectIndex.swift:175`、`SwiftClassWithoutClassObjectIndex.swift:339`、`:389`、`:425`、`ObjCClassMethodIndex.swift:557`、`ObjCImporterNaming.swift:270`、`ObjCMemberShape.swift:428`、`SwiftDeclaredObjCProtocolIndex.swift:268`。
- **核心不用 ObjC 一侧的任何东西**。只有两个共用文件里夹着 ObjC 一侧的声明：`SharedCacheEvictionGroup+SwiftInspection.swift` 五个分组里的 `objcImplementationClasses`、`objcHierarchy`、`objcAncestorResolver`，以及 `Extensions/MachORepresentableWithCache+ReaderKinds.swift:28` 的 `objcImplementationClassReader`。
- `RuntimeMetadataTypeBuilder.swift` 的 `import ObjectiveC` 是系统的 ObjC runtime 模块（in-process 构建 metadata 时用），与 MachOObjCSection 无关，留在原处。

### 包内的消费方

37 个源文件提到要搬的类型，分布在 8 个模块：SwiftDeclaration 19、SwiftDump 7、SwiftIndexing 4、SwiftLayout 2、SwiftThunkAnalysis 2、SwiftDeclarationRendering 1、SwiftPrinting 1、SwiftSectionKit 1。其中 3 个只在文档注释里提到（`SwiftDeclarationIndexConfiguration.swift`、`StandInMemberSymbolBuilder.swift`、`SwiftIndexEvents.swift`），真正要加 import 的是 34 个。CrossReferenceAnalysis 只用 `SymbolicDemangler`，不受影响；TestSupport、Executables、Plugins 一处都没用到。

### 测试

20 个测试文件用到要搬的类型：

- SwiftInspectionTests 里 5 个纯 ObjC 的套件：`ObjCImporterNamingTests`、`ObjCProtocolRequirementBuilderTests`、`SwiftClassObjectIndexTests`、`SwiftClassWithoutClassObjectIndexTests`、`SwiftDeclaredObjCProtocolIndexTests`。
- SwiftInspectionTests 里 4 个两边都测的套件：`AnonymousContextPrivateDiscriminatorTests`、`DyldCacheTwinImageTests`、`MalformedSymbolValueTests`、`SymbolicManglingIndexTests`。其中 `AnonymousContextPrivateDiscriminatorTests` 与 `SymbolicManglingIndexTests` 经 `internal` 的协议 `ObjCImplementationClassReading` 读 ObjC class。
- 其余 11 个分布在 SwiftDumpTests、SwiftInterfaceTests、SwiftIndexingTests、SwiftDeclarationRenderingTests、SwiftSectionCommandTests、SwiftSectionKitTests、IntegrationTests。SwiftSectionCommandTests 与 SwiftSectionKitTests 的那两个只用到同名的 dump 段名字 `objcImplementationClasses`（不是淘汰分组），不需要 import，所以要加 import 的测试文件是 13 个，要加依赖的测试 target 是 6 个。

CI 按套件名过滤（`.github/workflows/macOS.yml:123` 的 `\.(…)(/|$)`），套件换了测试 target 照样匹配；名单里的 `MalformedSymbolValueTests` 本来也留在原处。没有源码扫描测试写死 `SwiftInspection` 的路径。

### 下游

- **RuntimeViewer** 有两处：`RuntimeViewerCore/Sources/RuntimeViewerCore/Sections/ObjC/RuntimeObjCSection.swift:67`（`ObjCImplementationClasses.all(in:)`）与 `RuntimeViewerCore/Sources/RuntimeViewerCore/Images/RuntimeLoadedImageReading.swift:29`（SPI 的 `ClassHierarchyDumper`）。RuntimeViewerCore 在 `USING_LOCAL_DEPENDENCIES=1`（写在它的 `.package.env` 里）时经 `../../MachOSwiftSection` 直接读本库的集成 worktree，否则跟远端的 `next` 分支（`RuntimeViewerCore/Package.swift:128`），所以本库一合进 `next`，这两处就编不过。
- **MachOKitUI**（`MachOSwiftSectionDetailBuilder.swift`）与 **REAgent**（`StaticAnalysisSwiftSession.swift`）import SwiftInspection，但不用要搬的类型。swift-decompiler、MachOViewer 不 import SwiftInspection。

### 留不了过渡别名

新模块依赖 SwiftInspection，SwiftInspection 就不能反过来写 `public typealias ObjCMember = SwiftObjCInterop.ObjCMember`，那是循环依赖。`@_originallyDefinedIn` 只服务于带平台可用性标注的二进制框架，对 SwiftPM 源码包不起作用。所以没有废弃过渡期，只能直接搬。

### 输出不会变

要搬的文件里没有 `Error` 类型，也没有 `String(reflecting:)`、`localizedDescription`、`type(of:)` 这类会把模块名带进输出的写法；改动只是文件位置和 import。

### 日志

要搬的类型里有 6 个用 `@Loggable(.private, subsystem: "com.machoswiftsection.swift-inspection", category: "<类型名>")`。`AGENTS.md` 规定 subsystem 与 category 跨重构保持稳定（RuntimeViewer 按它们过滤日志流），所以搬过去照旧写 `swift-inspection`。

## 提议方案

新增 target `SwiftObjCInterop`（`Sources/Analysis/SwiftObjCInterop/`）与同名 library product，把上表 19 个文件原样搬进去（`git mv`，只改 import），两个共用文件里 ObjC 一侧的声明拆到新模块的文件里。SwiftInspection 去掉对 MachOObjCSection 的依赖。8 个消费方模块在 `Package.swift` 里加上对新模块的依赖，34 个源文件各加一行 import。

测试照同一条分界：5 个纯 ObjC 套件搬进新的测试 target `SwiftObjCInteropTests`（`Tests/SwiftObjCInteropTests/`），其余用到这些类型的测试文件留在原处，加一行 import。

RuntimeViewer 同批改：两个文件各加一行 import，`RuntimeViewerCore/Package.swift` 加上这个 product。本库先合进 `next`，RuntimeViewer 紧接着合进它自己的 `next`。

没有询问就采用的假设：

- 新模块和 SwiftInspection 一样平铺，只有一个 `Extensions/` 子目录，不按主题再分：19 个文件名本身已按主题成组。
- 现行文档里写着「在 SwiftInspection」的地方全部改成新模块；带日期的记录（TaskReports、Roadmaps、Reviews、已落地的提案、ProjectEvolutionLog、Changelogs）保留当时的写法——与 [0055](0055-group-sources-by-layer.md) 同一条规则。

### 非目标

- 不改任何类型名、签名、访问级别或逻辑；日志的 subsystem 与 category、缓存淘汰分组的字符串都不变。
- 不搬 SwiftThunkAnalysis 的 `ObjCMembers/`：`ObjCMethodThunkReferences.swift:87` 用 Capstone 解码 thunk，搬进新模块会让 SwiftLayout 间接依赖 Capstone，而 SwiftThunkAnalysis 单独成 target 正是为了把 Capstone 挡在其他模块之外（`Package.swift:590`）。
- 不搬 SwiftLayout 自己的 `ObjCClassIndex` / `ObjCProtocolIndex`，也不碰 CrossReferenceAnalysis 的 `ObjectiveCClassIndex`。它们各自服务于布局与交叉引用，要不要与新模块的索引合并是另一个问题。
- 不整理 `Tests/` 的其他部分。
- CLI 不变，`AgentPlugins/` 里的 skill 不用改。

## 详细设计

### `Package.swift`

新 target 放在 SwiftInspection 之后：

```swift
    /// The Objective-C side of Swift types: the class objects of Swift
    /// classes, `@objc @implementation` classes, `@objc` protocols declared
    /// in Swift, ObjC method tables and ancestor chains, and the
    /// ClangImporter's naming rules (evolution proposal
    /// `swift-objc-interop-module`). Sits directly above `SwiftInspection`,
    /// whose demangler it uses; this is where `MachOObjCSection` enters the
    /// Swift-facing stack.
    static let SwiftObjCInterop = Target.target(
        name: "SwiftObjCInterop",
        dependencies: [
            .product(.MachOKit),
            .product(.MachOObjCSection),
            .product(.Demangling),
            .product(name: "FoundationToolbox", package: "FrameworkToolbox"),
            .target(.Utilities),
            .target(.MachOCaches),
            .target(.MachOFoundation),
            .target(.MachOSwiftSection),
            .target(.SwiftInspection),
        ],
        path: "Sources/Analysis/SwiftObjCInterop",
    )
```

其余改动：

- `SwiftInspection` 的依赖去掉 `.product(.MachOObjCSection)`。
- `SwiftLayout`、`SwiftThunkAnalysis`、`SwiftDeclarationRendering`、`SwiftDump`、`SwiftDeclaration`、`SwiftIndexing`、`SwiftPrinting`、`SwiftSectionKit` 各加 `.target(.SwiftObjCInterop)`。
- products 在 `.library(.SwiftInspection)` 之后加 `.library(.SwiftObjCInterop)`。
- 新测试 target：

  ```swift
      static let SwiftObjCInteropTests = Target.testTarget(
          name: "SwiftObjCInteropTests",
          dependencies: [
              .target(.MachOSwiftSection),
              .target(.MachOTestingSupport),
              .target(.MachOFixtureSupport),
              .target(.SwiftInspection),
              .target(.SwiftObjCInterop),
          ],
          swiftSettings: testSettings,
      )
  ```

- 直接 import 新模块的其他测试 target（SwiftInspectionTests、SwiftDumpTests、SwiftInterfaceTests、SwiftIndexingTests、SwiftDeclarationRenderingTests、IntegrationTests）各加 `.target(.SwiftObjCInterop)`。

### 依赖层级

`AGENTS.md` 的层级图在 SwiftDump 与 SwiftInspection 之间加一层：

```
                                    └── SwiftDump
                                            └── SwiftObjCInterop (the Objective-C side of Swift types — MachOObjCSection enters here)
                                                    └── SwiftInspection
                                                            └── MachOSwiftSection (ABI model — depends on MachOBase ONLY)
```

SwiftThunkAnalysis 与 SwiftLayout 依赖 SwiftObjCInterop；CrossReferenceAnalysis 仍只依赖 SwiftInspection。

### 拆开两个共用文件

- `SharedCacheEvictionGroup+SwiftInspection.swift` 留下 `symbolicMangling` 与 `demangleMemo`。`objcImplementationClasses`、`objcHierarchy`、`objcAncestorResolver` 连同各自的文档注释搬到新文件 `Sources/Analysis/SwiftObjCInterop/SharedCacheEvictionGroup+SwiftObjCInterop.swift`，构造时传的字符串不变。这正是 `AGENTS.md` 的约定：每个模块在自己的 `SharedCacheEvictionGroup+<Module>.swift` 里声明分组。
- `objcImplementationClassReader` 搬到新模块的 `Extensions/MachORepresentableWithCache+ObjCReaderKinds.swift`，原文件的文档注释里讲 ObjC 那一半的段落随它走；`swiftSectionReader` 只有 Swift 一侧在用，留在 SwiftInspection。

### import 的写法

消费方文件照原来 import SwiftInspection 的方式加一行：

```swift
import SwiftInspection
import SwiftObjCInterop
```

用到 SPI 的（目前只有 `ClassHierarchyDumper`）写 `@_spi(Internals) import SwiftObjCInterop`；`package` 级的类型在同一个包内照常可见；测试里用到 `internal` 的 `ObjCImplementationClassReading` 的写 `@testable import SwiftObjCInterop`。

## 替代方案考量

1. **只在 SwiftInspection 里分一个 `ObjC/` 子目录**。零破坏，下游一行都不用改。否决（用户选定拆模块）：模块边界与对 MachOObjCSection 的依赖都不变，入口文档仍是一个模块两个主题，下一个 ObjC 功能还会以「同层同模式」放进 SwiftInspection。
2. **模块名用 `SwiftObjCInspection`**。与 SwiftInspection 对称，一眼看出两者是一对。否决（用户选定 `SwiftObjCInterop`）：「ObjC interop」是编译器（`-enable-objc-interop`）与本库 ABI 层（`ClassMetadataObjCInterop`）已有的说法，正好描述「Swift 类型在 ObjC 一侧」这件事；`Swift` 前缀也与包内其他 Swift 侧模块一致。
3. **再细拆成两个模块**（不读 Mach-O 的命名规则与类型编码一个，按镜像建的索引一个）。否决：命名规则那几个文件也要用 SwiftInspection 的 `NodeTypeNaming`（`ObjCImporterNaming.swift:270`、`ObjCMemberShape.swift:428`），细拆之后依赖并不减少，却在同一个功能区里多出一道模块边界。
4. **并进 MachOObjCSection**。做不到：这些代码读 Swift metadata（descriptor、`SymbolicDemangler`），而 MachOObjCSection 不依赖本库，反过来依赖就成了跨包循环。
5. **新模块放在 SwiftThunkAnalysis 之上，连 `ObjCMembers/` 一起收进来**。否决：SwiftLayout 要用 `SwiftClassObjectIndex` 与 `SwiftDeclaredObjCProtocolIndex`，那样它会经 SwiftThunkAnalysis 间接依赖 Capstone。
6. **在 SwiftInspection 留 typealias 过渡一个版本**。做不到，见前期调研「留不了过渡别名」。
7. **`ClassHierarchyDumper` 留在 SwiftInspection**。否决：为一个 81 行的 in-process 调试工具保留整项 MachOObjCSection 依赖，拆分就不完整。
8. **RuntimeViewer 等升级到 0.25.0 再改，本库只在发版说明里写迁移**。否决（用户选定同批改）：RuntimeViewer 的本地构建直接读本库的集成 worktree，远端依赖又跟 `next` 分支，本库一合入它就编不过。

## 影响

### 源码兼容性（source compatibility）

**有破坏。** 下列 13 个公开类型换到 `SwiftObjCInterop` 模块，名字与形状都不变：`CustomObjCClassName`、`ObjCAncestorResolver`、`ObjCAncestorResolverStore`、`ObjCClassHierarchy`、`ObjCClassHierarchyProviding`、`ObjCClassHierarchyProviderStore`、`ObjCClassHierarchies`、`ObjCImplementationClassFacts`、`ObjCImplementationClasses`、`ObjCMember`、`ObjCMemberTable`、`ObjCMemberShape`，以及 SPI 的 `ClassHierarchyDumper`。其余要搬的类型是 `package` 级，只影响本包。

调用方若在只 import 了 SwiftInspection 的文件里直接写到这些类型——或在开启 `MemberImportVisibility` 时访问它们的成员，例如经 `VariableDefinition.objcMember`、`ExtensionDefinition.unrepresentedObjCImplementationInstanceVariables` 拿到的值——就会编不过。改法是加一行 import，并在 SwiftPM 清单里加上 product：

```swift
// Before
import SwiftInspection

let classNames = ObjCImplementationClasses.all(in: machO).map(\.className)
```

```swift
// After
import SwiftInspection
import SwiftObjCInterop

let classNames = ObjCImplementationClasses.all(in: machO).map(\.className)
```

```swift
// The consumer's Package.swift
.product(name: "SwiftObjCInterop", package: "MachOSwiftSection"),
```

用 `@available(*, deprecated, renamed:)` 平滑过渡不可行：类型名没变，变的是所在模块，而旧模块无法再声明指向新模块的别名（循环依赖）。

### ABI 兼容性

不适用 —— 本库以 SPM 源码分发，使用方每次重新编译。

### 下游影响

本仓库内：上述 8 个源码模块与 6 个测试 target 加依赖、加 import；SwiftInspection 去掉一项依赖；CrossReferenceAnalysis 不受影响。

下游仓库：

- **RuntimeViewer**：`RuntimeObjCSection.swift` 加 `import SwiftObjCInterop`，`RuntimeLoadedImageReading.swift` 加 `@_spi(Internals) import SwiftObjCInterop`，`RuntimeViewerCore/Package.swift` 加 product。与本库同批合入 `next`。
- **MachOKitUI、REAgent**：import SwiftInspection，但不用要搬的类型，不受影响。
- **swift-decompiler、MachOViewer**：不 import SwiftInspection。

### 文档与示例

- `AGENTS.md`：层级图加一层；SwiftInspection 条目删去 ObjC 那部分，Swift 一侧原样保留（它没有模块参考可承接细节）；新的 SwiftObjCInterop 条目只列组成部分和三条最容易做错的事实，细节进模块参考；SwiftLayout 的 peer 说明与缓存规则里的模块归属改成新模块。
- 新写模块参考 `Documentations/Internal/Modules/SwiftObjCInterop.md`，登记进 `Modules/README.md` 与 `Documentations/README.md`。它串起已有的六篇专题文档（`ObjCImplementationClassRecognition.md`、`ObjCMemberRecovery.md`、`ThunkOnlyObjCMembers.md`、`CustomObjCClassNames.md`、`ClassesWithoutClassObjects.md`、`SwiftDeclaredObjCProtocols.md`），不复述它们。
- 改写写着「在 SwiftInspection」的现行文档：`Glossary.md`（7 处）、`Documentations/README.md`（2 处）、`SwiftDeclaredObjCProtocols.md`、`StaticFieldOffsetComputation.md`、`ClassesWithoutClassObjects.md`、`ObjCImplementationClassRecognition.md`、`CustomObjCClassNames.md`、`ObjCMemberRecovery.md`、`ReadingContextAbstraction.md`、`Modules/SwiftLayout.md`、`Modules/SwiftDeclaration.md`、`Modules/MachODependencies.md`、`Modules/SwiftSectionKit.md`、`Modules/SwiftThunkAnalysis.md`、`ProjectMap.md` 的模块分层表；代码里两处讲模块归属的注释（`ObjCMembers.swift`、`SwiftDeclarationIndexer.swift`）。
- 根目录 `README.md`（英文公开文档）：模块表加 `SwiftObjCInterop` 一行，`ClassHierarchyDumper` 从 SwiftInspection 的介绍里移出，import 说明改成 `@_spi(Internals) import SwiftObjCInterop`。
- `Changelogs/0.25.0.md` 写明搬迁与改法。项目惯例是发版时才写 Changelog，所以迁移说明先记在 ProjectEvolutionLog 本节的「对应版本」里，发版时照着写。

## API 演进与废弃策略

- 旧位置不保留废弃别名（做不到，见上），直接搬。
- 随 0.25.0 发布。这一版已计划删除 [0057](0057-reading-context-migration.md) 留下的废弃读取转发，本来就是破坏性版本；放在同一版里，下游只经历一次破坏。
- 0.x 版本的次版本号可以带破坏性改动，不需要跳主版本号。

## 落地步骤

1. 从 `next` 切出 worktree `.worktrees/MachOSwiftSection-SwiftObjCInterop` 与分支 `refactor/swift-objc-interop-module`，fixture 只链 `DerivedData/SymbolTests`。（已完成）
2. `Package.swift`：新 target、product、测试 target；SwiftInspection 去掉 MachOObjCSection；8 个消费方模块加依赖。（已完成，`d5a9f332`）
3. `git mv` 19 个文件，拆开两个共用文件，34 个源文件加 import；编译整个库，原始退出码为 0。（已完成，`d5a9f332`）
4. 测试：5 个套件搬进 `Tests/SwiftObjCInteropTests/`，其余 13 个测试文件加 import，6 个测试 target 加依赖；编译全部测试 target。（已完成，`d5a9f332`）
5. 在 Ultra 上跑 `swift test --skip IntegrationTests`，以原始退出码为准。（已完成：2804 个测试全部通过，原始退出码 0）
6. 在 Ultra 上跑渲染 A/B（`Scripts/run-rendering-ab-verification.py`，基线是合入前的 `next`）：三条读取路径的 dump 与 interface 逐字节一致。（已完成：96 对全部一致）
7. 文档：按「文档与示例」一节改；提案状态与决策日志同批更新。（已完成，`f7d77dd6`）
8. RuntimeViewer 照跨仓库的流程单独建 worktree 与分支 `feature/swift-objc-interop-module`，改两个文件与清单。验证在 Ultra 的沙盒里做：把 RuntimeViewerCore 与本分支各导出一份放在一起，只有 MachOSwiftSection 走本地、其余依赖照常解析远端的 `next`，编译 RuntimeViewerCore。通过后两边各自在本地合进集成 worktree 的 `next`（不推送）；之后推送时本库在前。（已完成：RuntimeViewer `e7e5a1b1`，沙盒编译通过）

**收尾时必须判断两件事**（判断结果写进决策日志，不允许沉默跳过）：

- **要不要配套专题文章** —— 新模块的模块参考就是配套文档，登记到头部；预计不另写实现说明或使用指南：搬迁本身没有代码里看不出来的决策，迁移改法写进 Changelog。
- **有没有引入新术语** —— 预计没有：`SwiftObjCInterop` 是模块名，不是术语。

## 决策日志

| 日期 | 变更 | 说明 |
|------|------|------|
| 2026-11-09 | Created as Draft | 用户指出 SwiftInspection 里 ObjC 的内容太多。调研确认 39 个源文件里有 19 个（约 6100 行）属于 ObjC 一侧，且只单向依赖模块的其余部分，可以拆出去而不成环 |
| 2026-11-09 | 按完整档处理 | 模块拆分属于架构改动，公开类型换模块是破坏性的 API 改动 |
| 2026-11-09 | 拆成独立模块，不只在模块内分子目录 | 用户选定。只分子目录虽然零破坏，但模块边界与对 MachOObjCSection 的依赖都不变，之后的 ObjC 功能仍会以同样的理由落进 SwiftInspection |
| 2026-11-09 | 模块名定为 `SwiftObjCInterop` | 用户选定，没选 `SwiftObjCInspection`：沿用编译器与 ABI 层已有的「ObjC interop」说法，`Swift` 前缀与包内其他 Swift 侧模块一致 |
| 2026-11-09 | RuntimeViewer 同批改 | 用户选定，没选「只在发版说明里写迁移」：RuntimeViewer 的本地构建直接读本库的集成 worktree，远端依赖跟 `next` 分支，本库一合入它就编不过 |
| 2026-11-09 | 默认做法定稿 | 用户确认：只换模块，类型名、访问级别、日志 subsystem 与 category、缓存淘汰分组名都不变；`ClassHierarchyDumper` 一起搬；5 个纯 ObjC 测试套件搬进新测试 target，4 个两边都测的留在原处；`ObjCMembers/` 与 SwiftLayout 自带的 ObjC 索引不动；验收含全量测试与渲染 A/B，都在 Ultra 上跑；新写模块参考、缩短 `AGENTS.md` 的条目；随 0.25.0 发布。提问到此结束 |
| 2026-11-09 | Draft → Accepted | 用户批准，开始实现 |
| 2026-11-09 | Accepted → In Progress | 从 `next` 切出分支 `refactor/swift-objc-interop-module` 与 worktree `.worktrees/MachOSwiftSection-SwiftObjCInterop` |
| 2026-11-09 | 加 import 的文件数按实际用法核定：源码 34 个、测试 13 个、测试 target 6 个 | 调研时按名字出现次数数的。3 个源文件只在文档注释里提到要搬的类型；SwiftSectionCommandTests 与 SwiftSectionKitTests 里的 `objcImplementationClasses` 是同名的 dump 段名字，不是淘汰分组。正文的数字已改成实际值 |
| 2026-11-09 | 消费方源码一律加不带属性的 `import SwiftObjCInterop`；测试照搬原来那行 `import SwiftInspection` 的 `@testable` / `@_spi(Internals)` | 源码里没有用到新模块的 SPI（`ClassHierarchyDumper` 只有 RuntimeViewer 与 IntegrationTests 用）；测试照搬属性，原来经 SwiftInspection 能访问的 `internal` 与 SPI 成员搬过去后照样能访问 |
| 2026-11-09 | `AGENTS.md` 的 SwiftInspection 条目只删 ObjC 部分，Swift 一侧原样保留；SwiftObjCInterop 条目保留三条最容易做错的事实 | 原定两条都缩到「一两行加链接」。SwiftInspection 没有模块参考可以承接删掉的细节（`Modules/README.md` 仍记为待写），删了就没有去处；SwiftObjCInterop 那三条（`@objc` 协议没有协议描述符、ObjC 协议遵循没有 conformance record、按名字查 Swift 类查不到时回退 `SwiftClassObjectIndex`）是 agent 默认会做错的，其余细节都进了模块参考 |
| 2026-11-09 | Changelog 留到发版时写 | 项目惯例是 `release:` 提交里才写 `Changelogs/<版本>.md`；迁移说明先记在 ProjectEvolutionLog 本节的「对应版本」里 |
| 2026-11-09 | RuntimeViewer 单独建 worktree 与功能分支，验证改在 Ultra 的沙盒里做 | 原定在 RuntimeViewer 的集成 worktree 里改、用本机的本地依赖编译。改成照跨仓库流程各建各的分支；编译放到 Ultra，因为本机只改代码、构建与测试都去 Ultra，而本机的集成 worktree 在推送之前 Ultra 看不到，所以沙盒里只把 MachOSwiftSection 换成本分支的副本，其余依赖走远端的 `next` |
| 2026-11-09 | 沙盒里 `swift-helper-service` 与 `swift-injection-peer` 也走本地 | 它们的发布版本依赖只有分支版本的包，纯远端解析不出来；RuntimeViewer 平时就从兄弟目录取这两个，沙盒里照样链到 Ultra 上的检出。沙盒第一次解析把 MachOKit 的 `next` 定在 Ultra 上 SwiftPM 缓存里的旧提交（缺 `fileBytes`），`swift package update` 之后取到远端最新的 `next` 才编过——与本次改动无关 |
| 2026-11-09 | 实现完成，待用户看过后收尾 | 全部在 Ultra 上验证：全量 `swift test --skip IntegrationTests`（Xcode 26.6）2804 个测试、534 个套件全部通过，原始退出码 0；渲染 A/B 96 对逐字节一致（归档 cache 15.5 与 26.6、iOS 15.5 / 16.4 / 17.5 / 18.5 / 26.5 模拟器文件、进程内 `MachOImage`）；RuntimeViewerCore 在沙盒里编译通过。配套文档只有新模块的模块参考，已登记到头部，不另写实现说明或使用指南：搬迁本身没有代码里看不出来的决策，迁移改法记在 ProjectEvolutionLog 本节、发版时写进 Changelog。没有新术语：`SwiftObjCInterop` 是模块名 |
