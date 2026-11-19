# Draft - 交叉引用的核心层与 ObjC 层迁出本库

- **状态**: Accepted
- **作者**: JH
- **创建日期**: 2026-11-19
- **最后更新**: 2026-11-19
- **所属愿景**: [不依赖 IDA 的逆向](../Visions/ReverseEngineeringWithoutIDA.md)（「我们选的方向」第 6 条：分层归属）
- **关联提案**:
  - [0097 offline-cross-references-and-symbolication](0097-offline-cross-references-and-symbolication.md)：在本库里把交叉引用拆成核心、ObjC、Swift 三层，并给下层定好了落脚处与名字；它的「非目标」第一条留给本提案的五个问题，在这里逐一定下。
  - MachOKitExtensions [draft-move-reading-and-resolving-modules](https://github.com/MxIris-Reverse-Engineering/MachOKitExtensions/blob/feature/move-reading-and-resolving-modules/Documentations/Evolutions/draft-move-reading-and-resolving-modules.md) 与 [draft-move-macho-infrastructure-modules](https://github.com/MxIris-Reverse-Engineering/MachOKitExtensions/blob/feature/move-macho-infrastructure-modules/Documentations/Evolutions/draft-move-macho-infrastructure-modules.md)（都已 Accepted，已实现、未落地）：把本库的读取层与 MachO 基础模块搬进 MachOKitExtensions 2.0.0。本提案的实现叠在它们的分支上，三份同日落地。
- **跨仓库**: 本提案是 MachOKitExtensions、MachOObjCSection 与本库共用的唯一提案；另外两个仓库的提案索引各加一行 cross-repository draft 指向这里（落地步骤第 1 步）。
- **实现分支 / PR**: 三个仓库都是 `feature/move-cross-reference-layers`。本库与 MachOKitExtensions 从各自的 `feature/move-macho-infrastructure-modules` 切出，MachOObjCSection 从 `next` 切出。
- **配套文档**: 待定 —— 落地时登记实现说明 / 使用指南的链接
- **网页版**: 同目录同名的 `.html`

## 摘要

0097 在本库里把交叉引用拆成了三层，并约定下层量完、跑稳之后再搬走。本提案就做这次搬家：与语言无关的三个模块搬进 MachOKitExtensions——`CrossReferenceCore` 改名 `MachOCodeReferences`，`CodeAddressResolution` 改名 `MachOAddressResolution`，`ARM64InstructionDecoding` 名字不变；ObjC 层 `CrossReferenceObjC` 搬进 MachOObjCSection，成为新 target `ObjCCodeReferences`。下层只给本库开 SPI（`@_spi(Internals)`），对外的分析器、公开模型和 Swift 层留在本库的 `CrossReferenceAnalysis`，RuntimeViewer 不用改代码。核心层的进程内部分用 `#if canImport(Darwin)` 包住，文件模式在 Linux 上也能编；顺带删掉从来只写 `.none`、没人读过的 `IndirectCallEvidence.table`。测试跟着代码走，但因为分析器留在本库，真正搬走的只有直接测下层的几组和源码扫描。实现叠在两份 MachOKitExtensions 搬迁提案的分支上，按 MachOKitExtensions 2.0.0、MachOObjCSection 0.8.207、本库 0.25.0 的顺序同日落地。

## 动机

完整动机见愿景《[不依赖 IDA 的逆向](../Visions/ReverseEngineeringWithoutIDA.md)》「我们选的方向」第 6 条：与语言无关的部分归 MachOKitExtensions，ObjC 专属的归 MachOObjCSection，Swift 专属的与命令入口留在本库；新代码先在本库写成独立模块、用源码扫描守住边界，量过、跑稳之后另写迁移提案整体搬过去。这一步特有的部分：

- **拆层的前提已经满足。** 0097 留下的四项「先实测」的未知都已量完：离线整 cache 建表 2.58 秒，与进程内持平；拆层前后吞吐差别在 −0.5% 到 +3% 之间；全量 2,993 个测试零失败，渲染 A/B 84 对逐字节一致（0097 决策日志「吞吐验收」「第 4 步完成」「实现完成」三行）。识别器接口在扫描热路径上量过，不再需要在一个仓库里反复改。
- **下层现在借住在一个读 Swift 元数据的库里。** `MachOAddressResolution` 要做的事（桩链、槽、cache 镜像定位）与 Swift 无关，本库的 `SwiftThunkAnalysis` 与 `SwiftDeclarationRendering` 只是它的两个使用者；ObjC 层读类表要借 MachOObjCSection 的 SPI（`@_spi(Core) import MachOObjCSection`，`Sources/Analysis/CrossReferenceObjC/ObjectiveCClassIndex.swift:3`，为了 `ObjCClass64(layout:offset:)`），搬进 MachOObjCSection 之后这就是包内调用。愿景后面几个阶段（带注解的反汇编、数据解码、常量追踪）都要建在核心层上，核心在 MachOKitExtensions，它们就不必依赖一个 Swift 元数据库。
- **趁 2.0.0 一起搬最省。** MachOKitExtensions 2.0.0 本来就是大版本（两份搬迁提案加模块），本库 0.25.0 本来就是破坏性版本（模块搬走、`MachOSymbols` 拆分）。同日落地只走一轮三个仓库的发版；之后单独搬，就要再来一轮 MachOKitExtensions → MachOObjCSection → 本库的发版，本库还要再发一个破坏性版本。
- **本库里的名字就是为这一步起的。** 0097 刻意让下层在本库里的名字不同于落脚处（`CrossReferenceCore` 对 `MachOCodeReferences`），避免本库已发布版本里的模块与 MachOKitExtensions 2.x 的新模块同名；下层两个模块也没有做成 product，没有外部使用方。搬的时候改名，只动本库内部的 import。

## 前期调研

### 现状代码怎么走的

**四个要搬的模块**（`next` 的 `a98cbc15`；`package` 与 `public` 的个数按声明关键字 grep，近似值）：

| 模块（本库） | 位置 | 文件 | 行数 | `public` | `package` | 实际 import |
|---|---|---|---|---|---|---|
| `CrossReferenceCore` | `Sources/Analysis/CrossReferenceCore` | 19 | 3,292 | 14（`CodeLocation`、`CodeReferenceKind`、`CodeReferenceRoute`、`IndirectCallEvidence` 及其成员） | 约 230 | Foundation、MachOKit（`CodeImage.swift:2`、`FileCrossReferenceMemory.swift:2` 带 `@_spi(Support)`，为了 `MemoryTrieTree`）、MachOKitExtensions、ARM64InstructionDecoding、CodeAddressResolution、MachOFoundation（只在 `Memory/InProcessCrossReferenceMemory.swift:1`） |
| `CrossReferenceObjC` | `Sources/Analysis/CrossReferenceObjC` | 8 | 1,152 | 1（`ReceiverClassHint`） | 约 78 | Foundation、MachOKit、MachOObjCSection（`ObjCMethodNames.swift`）、`@_spi(Core) import MachOObjCSection`（`ObjectiveCClassIndex.swift:3`）、CrossReferenceCore |
| `CodeAddressResolution` | `Sources/Analysis/CodeAddressResolution` | 4 | 434 | 0 | 33 | Foundation、MachOKit、MachOKitExtensions、MachOReading（只为 `readElements(offset:numberOfElements:)`，`StubChainResolver.swift:52`、`ImageAddressSpace.swift:35`）、ARM64InstructionDecoding |
| `ARM64InstructionDecoding` | `Sources/Support/ARM64InstructionDecoding` | 2 | 311 | 0 | 28（全部） | 无 |

- **核心层经 `MachOFoundation` 间接带进了 Utilities。** `InProcessCrossReferenceMemory.swift:40` 只用到 `InProcessContext.addressMask`（在 MachOReading），但 `import MachOFoundation` 经 `MachOBase/Exported.swift:10` 的 `@_exported import Utilities` 把 FrameworkToolbox、AssociatedObject、MemberwiseInit、Dependencies、AsyncAlgorithms 都带了进来（`Package.swift:356-368`）。`MemberImportVisibility` 没有在任何 target 上打开，所以核心层别的文件可能悄悄用了这条链带进来的成员——这一点没有逐个核实，搬的时候编译会告诉我们。
- **声明了但没用的依赖。** `CrossReferenceObjC` 在 `Package.swift:675-685` 声明了 `MachOFoundation` 与 `ARM64InstructionDecoding`，没有一个源文件 import 它们。
- **跨模块的 `package` 边**（只数类型，不数成员）：
  - 核心 → ObjC（16 个）：`ApproximateSize`、`CallTargetClaim`、`CalleeRole`、`CodeImage`、`CodeImageSet`、`CodeReferenceRecognitionSession`、`CodeReferenceRecording`、`CrossReferenceMemory`、`ImageFunctionTable`、`ImageFunctionTableAttachment`、`ImageLinkEdit`、`RegisterFile`、`ResolvedCallTarget`、`ScanSite`、`ScannedCall`，以及 public 的 `CodeLocation`。
  - 核心 → `CrossReferenceAnalysis`（27 个）：上面这些，加 `CallTargetResolver`、`ExportedFunctionNames`、`Linkage`、`ReferenceScanner`、`RenamedReexportIndex`、`RuntimeLibraryRules`、`SlotContent`、`StringLiteralReference`，以及 public 的 `CodeReferenceKind`、`CodeReferenceRoute`、`IndirectCallEvidence`。
  - ObjC → `CrossReferenceAnalysis`（10 个）：`ObjCCodeReferenceRecognizer`、`ObjCCodeReferenceRecording`、`ObjCImageSections`、`ObjCInstanceVariableNames`、`ObjCMethodNames`、`ObjCRuntimeFunctions`、`ObjCRuntimeHelperNames`、`ObjectiveCClassIndex`、`ObjectiveCClassObject`，以及 public 的 `ReceiverClassHint`。
  - `CodeAddressResolution` → 核心：`ImageAddressSpace`、`SlotResolver`（搬家后同在 MachOKitExtensions，不跨包）。
  - `CodeAddressResolution` → `SwiftThunkAnalysis`：`CacheImageLocator`、`ImageAddressSpace`、`SlotResolver`、`StubChainResolver`，在 `AccessorThunkReader`、`DependencyImageResolver`、`MachOThunkEnvironment`、`ThunkTypeNodeBuilder`、`ObjCMethodThunkReferences` 里。
  - `CodeAddressResolution` → `SwiftDeclarationRendering`：`ImageAddressSpace`（`Extensions/Node+OpaqueType.swift:4`）。
  - `ARM64InstructionDecoding` → 核心与 `CodeAddressResolution`：`ARM64InstructionWord` 几乎全部、`ARM64Trampoline`（搬家后同包）；→ `CrossReferenceAnalysis`：`ARM64InstructionWord` 的 `adding`、`branchTarget`、`callTarget`、`load`（跨包）。
  - MachOReading → 核心：`InProcessContext.addressMask` 在本库是 `package`（`Sources/MachO/MachOReading/ReadingContext/InProcessContext.swift:62`）；MachOKitExtensions 那份已是 public（读取层搬迁提案第 286 行就是为它改的），搬过去同包，不成问题。
- **只有在 Darwin 上才编得过的代码都在核心层的进程内部分。** `CodeImageSet.inProcess(...)`（`Images/CodeImageSet.swift:86-130`）只有 `#if arch(arm64)`，却用了 `DyldCacheLoaded.current`（:90，MachOKit 里在 `#if canImport(Darwin)` 内，`DyldCacheLoaded+static.swift:9-20`）、`_dyld_image_count` / `_dyld_get_image_header`（:112-113）、`MachOImage(ptr:)`（:114）、`dladdr`（:116-117）。`InProcessCrossReferenceMemory` 是唯一把地址变成指针的地方（`UnsafeRawPointer(bitPattern:)` 在 :14、:19、:25、:29），它的掩码来自 `InProcessContext.addressMask`，而 MachOKitExtensions 的 `InProcessContext` 整个在 `#if canImport(Darwin)` 里（`Sources/MachOReading/ReadingContext/InProcessContext.swift:7`）。ObjC 层在 `ObjectiveCClassIndex.swift:146`、`ObjCMethodNames.swift:52-78`、`ObjCImageSections.swift:46` 按 `asMachOImage` 分支，用的是类型而不是 dyld 调用；MachOKit 在 Linux 上也有 `MachOImage`，这几处大概能编，没有在 Linux 上验证过。锁都是 `NSLock`，没有 `Mutex` 或 FrameworkToolbox。
- **`IndirectCallEvidence.table` 从来只写 `.none`，也没人读。** 枚举在 `Models/IndirectCallEvidence.swift:4-9`（`classVirtualTable`、`protocolWitnessTable`、`valueWitnessTable`、`none`），扫描器唯一的写入点给的是 `.none`（`Scanning/ReferenceScanner.swift:355`）。本库没有读 `.table` 的代码；RuntimeViewer 只读 `tableOffset` 与 `pointerAuthenticationConstant`（`RuntimeViewerCore/Sources/RuntimeViewerCrossReferences/Analysis/CrossReferenceQuery.swift:118`、`:977`）。
- **使用方。** `CrossReferenceAnalysis` 是 library product（`Package.swift:1523`），经 `Sources/Analysis/CrossReferenceAnalysis/Exports.swift` 的 `@_exported import` 把两个下层的公开类型带出去。本库里 SwiftSectionKit 的 `refs` / `symbolicate`（`Sources/Commands/SwiftSectionKit/CrossReferences/` 的四个文件）用门面。RuntimeViewer 只有 `RuntimeViewerCore` 的 `RuntimeViewerCrossReferences` 一个 target import `CrossReferenceAnalysis`（`Analysis/` 下 9 个文件、3 个测试），用到下层的公开类型只有 `CodeLocation`（13 处）与 `ReceiverClassHint`（`CrossReferenceQuery.swift:764`、`ObjectiveCSendMatching.swift:28,41-65`）。MachOKitUI 与 swift-decompiler 都不用这几个模块。四个要搬的模块都不是本库的 product（product 列表 `Package.swift:1508-1536`）。

### 上游或依赖是否已具备能力

- **MachOKitExtensions 在两份搬迁落地后**（本机的本地 `next`，`f67d290`，已合入基础设施搬迁分支）有九个 product：`MachOKitExtensions`、`MachOReading`、`MachOResolving`、`MachOPointers`、`MachOCaches`、`MachODependencies`、`MachOSymbols`（与语言无关的那一半）、`MachOBase`、`MachOFoundation`（`Package.swift:66-112`）；外部依赖只有 MachOKit ≥ 0.55.102、AssociatedObject、swift-fileio。核心层与地址解析要用的东西全在其中，没有一样留在本库。
- **MachOKitExtensions 没有 CI**（基础设施搬迁提案第 82 行；`main` 与 `next` 都没有 `.github`），**README 承诺支持 Linux**（`README.md:127-136`，理由是 MachOObjCSection 支持 Linux），`Package.swift` 只列 Apple 平台；Darwin 专属的代码用 `#if canImport(Darwin)`（`InProcessContext.swift`、`DependencyLocating.swift`、`DyldCacheLoaded+Cached.swift`）。两份搬迁提案都写明本机验证不了 Linux、也不加 Linux CI。SPI 分组已有 `@_spi(Internals)`（24 处）与 `@_spi(Support)`（4 处）。最新 tag 1.3.3；2.0.0 是大版本，保证本库的旧版本永远不会与它同时解析。
- **基础设施搬迁提案写着 `ARM64InstructionDecoding` 留在本库**（第 109 行「不迁 `Utilities`、`MachOMacros`、`ARM64InstructionDecoding` 及任何 Swift 层模块」，第 189 行的图也是）。核心层离不开它，本提案要改这一条，并在那份提案的决策日志里记一行。
- **读取层搬迁提案的落地清单**（决策日志第 298 行）的顺序是「MachOObjCSection 打 tag → MachOKitExtensions 合入 `main` 并发 2.0.0 → 本库抬 MachOObjCSection 下限、合入 `next`、随 0.25.0 发布」。`ObjCCodeReferences` 要依赖 MachOKitExtensions 2.0.0 的 `MachOCodeReferences`，所以 MachOObjCSection 的 tag 必须挪到 MachOKitExtensions 2.0.0 之后。
- **MachOObjCSection**（`.worktrees/MachOObjCSection`，`next`）：library product 有 `MachOObjCSection`、`ObjCMetadataSource`、`ObjCDeclarationRendering`、`ObjCIndexing`、`ObjCInterface`、`ObjCOutputTransformer`、`ObjCDiffing`（`Package.swift:65-98`）；要求 MachOKitExtensions `"1.2.0"..<"3.0.0"`（`:145-162`）；SPI 分组是 `@_spi(Core)`（50 处）与 `@_spi(Support)`（46 处）。**fork 新增的东西放单独的 target**，上游的 `MachOObjCSection` target 目录不碰，合上游时才不冲突（`Documentations/Internal/ObjCMetadataSourceGenericization.md:37-55`）。版本号形状是 `<上游 major>.<上游 minor>.<P>NN`（`Documentations/Glossary.md:41-46`），fork 最新 tag 是 0.8.206；**`0.9.0` 与 `0.10.0` 是上游 p-x9 的 tag**，fork 不能发 0.9.0（0097 非目标里「MachOObjCSection 发 0.9.0」的说法不成立）。CI 只有 `ci.yml`：推 `main` 与 PR 时跑，macos-26、Xcode 26.6，`swift test --skip MachOObjCSectionTests`，没有 Linux job。本库要求它 `"0.8.200"..<"0.9.0"`（`Package.swift:185`）。
- **RuntimeViewer 跟的是本库与 MachOObjCSection 的 `next` 分支**（`RuntimeViewerCore/Package.swift:119-137`），五个提交进仓库的 `Package.resolved` 钉 revision；落地后照 `chore: pin MachOSwiftSection …` 的惯例抬钉。
- **本库的搬迁分支落后 `next`。** `feature/move-macho-infrastructure-modules`（已包含读取层那条分支）落后 `origin/next` 13 个提交，正好是 0097 的全部实现；它的 `Package.swift` 里还是拆层之前的 `CrossReferenceAnalysis`，`SwiftThunkAnalysis` 的几个文件改成了 import `SwiftSymbols`，`MachOFixtureSupport` 等测试支持模块要改名。合 `next` 进来预计在 `Package.swift`、`MachOThunkEnvironment.swift`、`AGENTS.md`、两份模块文档、`MachOCaches.md` 上冲突（MachOKitExtensions 那边的记录；没有实际试合）。

### 前人怎么做的

- **读取层与基础设施两次搬迁**（MachOKitExtensions 的两份提案）就是本提案的模板：文件原样搬、`package` 改成 `@_spi(Internals) public`、模块名在 2.0.0 里一次定下、三个仓库按依赖顺序同日落地、功能分支只推送不合进常驻检出（MachOKitExtensions 的 `main` 一合，本库主检出与 MachOKitUI 就报模块重名，直到本库 0.25.0）。
- **SwiftPM 的两条硬约束**：一个依赖图里模块名不能重复；`package` 访问级别只在一个 package 之内有效，跨包的「不对外承诺的公开」只能用 `@_spi`。Apple 自己的框架（SwiftUI 等）大量用 SPI 把内部接口开给自家的其他模块。

### 验证过什么

- **测试几乎都经门面建分析器。** 逐个看了 `Tests/CrossReferenceAnalysisTests` 的 31 个文件与 `Tests/CodeAddressResolutionTests`：除了 Capstone 对照的两组（`ARM64InstructionDecodingTests`、`RegisterFileTests`）、`MalformedExportTrieTests` 与几个源码扫描，其余都要 `CrossReferenceAnalyzer`（`SharedAnalyzer` / `ProcessAnalyzer`），或者要 Swift 元数据、SymbolTestsCore 夹具。分析器留在本库，所以「测试跟代码走」实际搬走的很少（见「提议方案」第 5 节）。`RecognizerExtensionPointTests` 的第一条测的正是核心的扩展点，它借门面建分析器，改成直接驱动 `ReferenceScanner` 就能在 MachOKitExtensions 里证明核心不靠任何语言层也能扫。`CodeAddressResolutionTests` 五条里有三条只借门面拿 AppKit 镜像和运行中的 cache，改成直接从 MachOKit 拿就能搬；`slotResolverResolvesStandaloneBinds` 要 SymbolTestsCore 夹具，留在本库。
- **0097 没有改任何包依赖。** `git diff 3181325d origin/next -- Package.swift` 里没有 `.package(` 一行的变化；RuntimeViewer 抬钉只是改 revision。
- **没验证的**：Linux 上能否编过；搬迁分支合 `next` 的确切冲突；`MemberImportVisibility` 关着时核心层还暗中依赖了哪些经 Utilities 带进来的成员。

## 提议方案

### 1. 去向与名字

| 本库现在 | 去向 | 新名字 | product | 依赖 |
|---|---|---|---|---|
| `ARM64InstructionDecoding` | MachOKitExtensions | `ARM64InstructionDecoding`（不变） | 是 | 无 |
| `CodeAddressResolution` | MachOKitExtensions | `MachOAddressResolution` | 是 | MachOKit、MachOKitExtensions、MachOReading、ARM64InstructionDecoding |
| `CrossReferenceCore` | MachOKitExtensions | `MachOCodeReferences` | 是 | MachOKit、MachOKitExtensions、MachOReading、MachOAddressResolution、ARM64InstructionDecoding |
| `CrossReferenceObjC` | MachOObjCSection | `ObjCCodeReferences`（新 target，不进上游的 `MachOObjCSection` target） | 是 | MachOKit、MachOObjCSection、MachOCodeReferences |
| `CrossReferenceAnalysis` | 留在本库 | 不变 | 是（已是） | ARM64InstructionDecoding、MachOAddressResolution、MachOCodeReferences、ObjCCodeReferences，以及原有的 Swift 层依赖 |

- `ARM64InstructionDecoding` 不是 Mach-O 专有的，不加 `MachO` 前缀。本库 0.25.0 起不再有同名模块；本库 0.24.0 及更早的版本要求 MachOKitExtensions 1.x，永远不会与 2.0.0 同时解析，所以不会撞名。
- 核心层改为直接依赖 `MachOReading`，不再依赖 `MachOFoundation`：只有这样，`MachOCodeReferences` 才不会带进 `MachOSymbols`、`MachODependencies`（以及本库那份 `MachOBase` 里的 Utilities）。ObjC 层去掉两个没用的依赖。
- 文件原样搬，目录结构照旧（`Images/`、`Memory/`、`Models/`、`Recognition/`、`Scanning/`、`Symbolication/`），除了下面几节列出的改动，只改 import 与访问级别。

### 2. API：只给本库开 SPI

- **跨包用到的 `package` 声明改成 `@_spi(Internals) public`，同包里用到的保持 `package`。** 判据是「另一个 package 的模块要不要用它」：`MachOAddressResolution` → `MachOCodeReferences`、`ARM64InstructionDecoding` → 两者都在 MachOKitExtensions 一个包里，保持 `package`；`MachOCodeReferences` 被 `ObjCCodeReferences`（MachOObjCSection）和 `CrossReferenceAnalysis`（本库）用到的那些、`MachOAddressResolution` 被 `SwiftThunkAnalysis` 与 `SwiftDeclarationRendering` 用到的四个类型、`ARM64InstructionWord` 被门面用到的四个成员、`ObjCCodeReferences` 被门面用到的十个类型，改成 SPI。两个仓库都用 `Internals` 这个分组名：MachOKitExtensions 已有这个分组；MachOObjCSection 现有的是 `Core` 与 `Support`，新分组不与它们冲突。
- **已经公开的值类型保持 public**：`CodeLocation`、`CodeReferenceKind`、`CodeReferenceRoute`、`IndirectCallEvidence`（删掉 `table` 之后）、`ReceiverClassHint`。它们今天就是本库公开 API 的一部分（经 `@_exported`），RuntimeViewer 用着其中的 `CodeLocation` 与 `ReceiverClassHint`。
- **对外的分析器、公开模型与 Swift 层留在本库。** `CrossReferenceAnalyzer`、`CodeReference`、`CodeReferenceTarget`、`CodeReferenceTable`、`CodeReferenceIndex`、`CodeFunction`、`AddressSymbolication` 都不动。单用 MachOKitExtensions 做不了交叉引用；下层对外该长什么样（没有 Swift 层时引用目标用什么类型表示），等真有不经本库的使用方时再定——0097 非目标里留下的问题 (a) 因此不在本提案里回答。
- **SPI 不承诺 semver。** MachOKitExtensions 与 MachOObjCSection 的模块文档写明：`@_spi(Internals)` 的接口只给 MachOSwiftSection 用，随时可能变，不算破坏性变更。
- **门面的导出照旧。** `Exports.swift` 改成 `@_exported import MachOCodeReferences` 与 `@_exported import ObjCCodeReferences`，`import CrossReferenceAnalysis` 的使用方照旧看得到那几个公开值类型；门面里要用内部接口的文件另写 `@_spi(Internals) import`。

### 3. 删掉 `IndirectCallEvidence.table`

`IndirectCallEvidence` 只保留与语言无关的事实：`tableOffset`、`pointerAuthenticationConstant`、`isAddressBlended`。`Table` 枚举与 `table` 属性删掉，构造器去掉 `table:` 参数，扫描器的写入点（`ReferenceScanner.swift:355`）跟着改。将来要区分 vtable、协议见证表、值见证表时，由 Swift 层在门面里另加，不回到核心层。这是本库公开 API 的破坏性改动，随 0.25.0 发布，写进 changelog 的 Breaking 一节；没有使用方（本库、RuntimeViewer、MachOKitUI、swift-decompiler 都查过），不留废弃期。

### 4. Linux：文件模式能编，进程内部分用 `#if` 包住

- `MachOCodeReferences` 里，`CodeImageSet.inProcess(...)` 从 `#if arch(arm64)` 改成 `#if canImport(Darwin) && arch(arm64)`；`InProcessCrossReferenceMemory.swift` 整个文件包进 `#if canImport(Darwin)`。文件模式（`FileCrossReferenceMemory`、从 `FullDyldCache` 或一组 `MachOFile` 建镜像集）不包。
- `ObjCCodeReferences` 里按 `asMachOImage` 分支的几处先不包，编译报错再包。
- 照两份搬迁提案的做法：不加 Linux CI，本机验证不了，模块文档写明「Linux 上未验证」。门面（本库）不变——本库不承诺 Linux。

### 5. 测试：跟着代码走

分析器留在本库，所以只有直接测下层、不经门面的测试能搬：

| 测试 | 去向 | 怎么改 |
|---|---|---|
| `MalformedExportTrieTests`（`RenamedReexportIndex`） | MachOKitExtensions `MachOCodeReferencesTests` | 改 import |
| `RecognizerExtensionPointTests.aRecognizerDefinedInTestsPlugsInWithoutChangingTheCore` | 同上，改名 `theCoreScansWithOnlyARecognizerFromTests` | 不借门面：从运行中的 cache 直接建 `CodeImageSet`，只装测试里定义的识别器，驱动 `ReferenceScanner` |
| `CodeAddressResolutionTests` 里不要夹具的三条（`stubChainCarriesTheSelectorRegisterConstantOfACacheSharedSelectorStub`、`slotResolverMatchesTheProcessForEveryGlobalOffsetTableSlotOfAppKit`、`cacheImageLocatorFindsTheImageAnAddressLiesIn`）与要归档 iOS cache 的 `stubChainRecordsEveryStubIslandHop` | MachOKitExtensions `MachOAddressResolutionTests` | AppKit 镜像与 cache 改从 MachOKit（`DyldCacheLoaded.current`、`FullDyldCache`）直接拿，不借门面的 `ProcessAnalyzer` |
| 源码扫描：核心不写 `objc_` / `swift_` 字面量（`crossReferenceCoreSpellsNoRuntimeSymbolName`）、只有 `InProcessCrossReferenceMemory` 把地址变成指针（`MemoryAccessScanTests` 的核心部分）、不写自定义地址掩码常量（`AddressMaskScanTests`，连同 `FileCrossReferenceMemory` 那条 slide info 的白名单） | MachOKitExtensions `MachOCodeReferencesTests` | 扫描目录换成 `Sources/MachOCodeReferences` |
| 源码扫描：ObjC 层只经 `CrossReferenceMemory` 读内存、不写 `swift_` 字面量 | MachOObjCSection `ObjCCodeReferencesTests`（新） | 扫描目录换成 `Sources/ObjCCodeReferences` |
| `CrossReferenceLayerBoundaryTests` 的两条 import 白名单 | 删除 | 下层搬走之后 SwiftPM 本身就不允许它们 import 本库的模块 |
| `ARM64InstructionDecodingTests`、`RegisterFileTests`（Capstone 对照）与辅助的 `InstructionEncoding.swift` | 留在本库 | 改成 `@_spi(Internals) import`；MachOKitExtensions 不加 Capstone 依赖 |
| `slotResolverResolvesStandaloneBinds`（SymbolTestsCore 夹具） | 留在本库，挪进 `CrossReferenceAnalysisTests` | `CodeAddressResolutionTests` target 删除 |
| 其余经门面的测试、`ReferenceTableDigestTests`、`ScanThroughputBenchmarkTests`、`PublicNameTests`、`MemoryAccessScanTests` 与 `AddressMaskScanTests` 对本库文件的部分 | 留在本库 | 用到下层内部接口的改成 `@_spi(Internals) import` |

- MachOKitExtensions 没有 CI，那边的测试只在本地跑；MachOObjCSection 的 CI 在 PR 与推 `main` 时跑新 target 的测试。
- 本库的缩写扫描（`AbbreviatedIdentifierScanTests`）不复制到另外两个仓库。

### 6. 版本与落地顺序

叠在两份搬迁提案的分支上实现，三份同日落地，顺序：

1. MachOKitExtensions 合入 `main`、发 **2.0.0**（两份搬迁加本提案的三个模块）。
2. MachOObjCSection 把 MachOKitExtensions 的下限抬到 2.0.0（`"2.0.0"..<"3.0.0"`），推 `main`、等 CI、打 **0.8.207**。这意味着 0.8.207 起的 MachOObjCSection 不能再与本库 0.24.0 及更早的版本同时解析——它们要 MachOKitExtensions 1.x。
3. 本库把 MachOObjCSection 要求改成 `"0.8.207"..<"0.9.0"`、MachOKitExtensions 改成 `from: "2.0.0"`，随 **0.25.0** 发布。
4. RuntimeViewer 抬钉（本库与 MachOObjCSection 的 `next` revision）。

读取层搬迁提案落地清单里「MachOObjCSection 先打 tag」的顺序因此改成上面这样，那份提案的决策日志记一行。

### 7. 文档

- 模块文档跟着代码走：本库的 `Internal/Modules/CrossReferenceCore.md`、`CodeAddressResolution.md` 搬进 MachOKitExtensions 的 `Documentations/Internal/`（改名 `MachOCodeReferences.md`、`MachOAddressResolution.md`，加一份 `ARM64InstructionDecoding.md`），`CrossReferenceObjC.md` 搬进 MachOObjCSection 的 `Documentations/Internal/ObjCCodeReferences.md`；本库的 `CrossReferenceAnalysis.md` 改写「三个模块」一节，指向它们。
- 本库 `AGENTS.md`：模块依赖图、`CrossReferenceAnalysis` 那一大段里「It is three modules」与 `ARM64InstructionDecoding`、`CodeAddressResolution` 两条改写成「下层在 MachOKitExtensions 与 MachOObjCSection，经 `@_spi(Internals)` 接入」。
- 愿景第 6 条的「之后另写迁移提案」改成指向本提案；愿景的相关提案表加一行。
- MachOKitExtensions 的 README 模块列表、两个仓库的提案索引与文档索引。

### 非目标

- **下层的独立公开 API**：MachOKitExtensions 里不提供自己的分析器、不定义与语言无关的引用目标类型。等有不经本库的使用方时另写提案。
- **在 Linux 上真编、加 Linux CI。**
- **给 MachOKitExtensions 加 CI**（基础设施搬迁提案已把它留给单独的提案）。
- **改扫描行为、加新的引用种类。** 除了删 `IndirectCallEvidence.table`，搬家前后每张引用表逐条一致。
- **搬 Swift 层或门面**，以及 `SwiftThunkAnalysis`、`SwiftDeclarationRendering` 本身。
- **MachOKitUI 的改动**：它不用这几个模块；它因两份搬迁提案要做的 `import MachOSymbols` → `import SwiftSymbols` 由它自己的提案负责。
- **把门面经 `@_exported` 带出的类型改名。**

## 改动地图

### MachOKitExtensions（`feature/move-cross-reference-layers`，从 `feature/move-macho-infrastructure-modules` 切出）

| 文件 / 类型 | 动作 | 改什么 | 为什么 | 步骤 |
|---|---|---|---|---|
| `Package.swift` | 修改 | 加 product 与 target `ARM64InstructionDecoding`、`MachOAddressResolution`、`MachOCodeReferences`；加 test target `MachOAddressResolutionTests`、`MachOCodeReferencesTests` | 第 1 节 | 2、3 |
| `Sources/ARM64InstructionDecoding/ARM64InstructionWord.swift`、`ARM64Trampoline.swift` | 新增（搬入） | 原样搬；门面用到的 `adding`、`branchTarget`、`callTarget`、`load` 改 `@_spi(Internals) public`，其余保持 `package` | 核心与地址解析离不开它 | 2 |
| `Sources/MachOAddressResolution/CacheImageLocator.swift`、`ImageAddressSpace.swift`、`SlotResolver.swift`、`StubChainResolver.swift` | 新增（搬入） | 原样搬；四个类型及本库用到的成员改 `@_spi(Internals) public` | `SwiftThunkAnalysis`、`SwiftDeclarationRendering` 跨包使用 | 2 |
| `Sources/MachOCodeReferences/`（`Images/`、`Memory/`、`Models/`、`Recognition/`、`Scanning/`、`Symbolication/` 共 19 个文件） | 新增（搬入） | 原样搬；本库与 MachOObjCSection 用到的约 27 个类型及其成员改 `@_spi(Internals) public` | 第 2 节 | 3 |
| `Sources/MachOCodeReferences/Memory/InProcessCrossReferenceMemory.swift` | 修改 | `import MachOFoundation` 改 `import MachOReading`；整个文件包进 `#if canImport(Darwin)` | 第 1、4 节 | 3 |
| `Sources/MachOCodeReferences/Images/CodeImageSet.swift` · `inProcess(...)` | 修改 | `#if arch(arm64)` 改 `#if canImport(Darwin) && arch(arm64)` | 第 4 节 | 3 |
| `Sources/MachOCodeReferences/Models/IndirectCallEvidence.swift` · `IndirectCallEvidence` | 修改 | 删 `Table` 与 `table`，构造器去掉 `table:` | 第 3 节 | 3 |
| `Sources/MachOCodeReferences/Scanning/ReferenceScanner.swift` | 修改 | 写入 `IndirectCallEvidence` 处去掉 `table: .none` | 第 3 节 | 3 |
| `Tests/MachOAddressResolutionTests/MachOAddressResolutionTests.swift` | 新增（搬入并改写） | 本库 `CodeAddressResolutionTests` 的四条，镜像与 cache 从 MachOKit 直接拿 | 第 5 节 | 2 |
| `Tests/MachOCodeReferencesTests/MalformedExportTrieTests.swift` | 新增（搬入） | 改 import | 第 5 节 | 3 |
| `Tests/MachOCodeReferencesTests/CoreOnlyScanTests.swift` | 新增 | `theCoreScansWithOnlyARecognizerFromTests`：只装测试里的识别器，驱动 `ReferenceScanner` | 证明核心在 MachOKitExtensions 里不靠语言层也能扫 | 3 |
| `Tests/MachOCodeReferencesTests/SourceScanTests.swift` | 新增（搬入并合并） | 不写 `objc_` / `swift_` 字面量、只有 `InProcessCrossReferenceMemory` 把地址变成指针、不写自定义地址掩码常量（含 slide info 白名单） | 第 5 节 | 3 |
| `README.md` | 修改 | 模块列表加三个模块，写明 SPI 只给 MachOSwiftSection 用、Linux 上进程内部分不可用 | 文档 | 5 |
| `Documentations/Internal/Modules/MachOCodeReferences.md`、`MachOAddressResolution.md`、`ARM64InstructionDecoding.md` | 新增（从本库搬入并改写） | 本库同名模块文档的内容，加 SPI 与 Linux 说明 | 文档跟代码走 | 5 |
| `Documentations/Evolutions/README.md` | 修改 | 加 cross-repository draft 一行指向本提案 | 跨仓库提案的登记方式 | 1 |
| `Documentations/Evolutions/draft-move-macho-infrastructure-modules.md` | 修改 | 第 109 行与第 189 行的图改为 `ARM64InstructionDecoding` 也搬；决策日志加一行；落地清单的顺序改成第 6 节 | 第 1、6 节 | 1 |
| `Documentations/Evolutions/draft-move-reading-and-resolving-modules.md` | 修改 | 决策日志加一行：落地顺序改成 MachOKitExtensions 2.0.0 先于 MachOObjCSection 的 tag | 第 6 节 | 1 |
| `Documentations/README.md` | 修改 | 登记三份模块文档 | 文档索引 | 5 |

### MachOObjCSection（`feature/move-cross-reference-layers`，从 `next` 切出）

| 文件 / 类型 | 动作 | 改什么 | 为什么 | 步骤 |
|---|---|---|---|---|
| `Package.swift` | 修改 | 加 product 与 target `ObjCCodeReferences`（依赖 MachOKit、`MachOObjCSection`、MachOKitExtensions 的 `MachOCodeReferences`）与 test target `ObjCCodeReferencesTests`；MachOKitExtensions 要求改 `"2.0.0"..<"3.0.0"` | 第 1、6 节 | 4 |
| `Sources/ObjCCodeReferences/`（8 个文件） | 新增（搬入） | 原样搬；本库门面用到的十个类型改 `@_spi(Internals) public`；`@_spi(Core) import MachOObjCSection` 照旧 | fork 新增放单独 target | 4 |
| `Tests/ObjCCodeReferencesTests/SourceScanTests.swift` | 新增 | 只经 `CrossReferenceMemory` 读内存、不写 `swift_` 字面量 | 第 5 节 | 4 |
| `Documentations/Internal/ObjCCodeReferences.md` | 新增（从本库 `CrossReferenceObjC.md` 搬入并改写） | 加 SPI 说明 | 文档跟代码走 | 5 |
| `Documentations/README.md`、`Documentations/Evolutions/README.md` | 修改 | 登记模块文档；加 cross-repository draft 一行 | 索引 | 1、5 |

### MachOSwiftSection（`feature/move-cross-reference-layers`，从合过 `next` 的 `feature/move-macho-infrastructure-modules` 切出）

| 文件 / 类型 | 动作 | 改什么 | 为什么 | 步骤 |
|---|---|---|---|---|
| `feature/move-macho-infrastructure-modules`（分支） | 修改 | 合入 `origin/next`（含 0097），解冲突，新 target 的 `.target(.MachOFoundation)` / `.target(.MachOReading)` 改成 `.product(...)`，测试支持模块按那份提案改名 | 本提案的基线 | 0 |
| `Package.swift` | 修改 | 删 target `CrossReferenceCore`、`CrossReferenceObjC`、`CodeAddressResolution`、`ARM64InstructionDecoding` 与 test target `CodeAddressResolutionTests`；`CrossReferenceAnalysis`、`SwiftThunkAnalysis`、`SwiftDeclarationRendering`、`CrossReferenceAnalysisTests`、`SwiftThunkAnalysisTests` 改依赖 MachOKitExtensions 的三个 product 与 MachOObjCSection 的 `ObjCCodeReferences`；MachOObjCSection 要求改 `"0.8.207"..<"0.9.0"` | 第 1、6 节 | 2、3、4、6 |
| `Sources/Support/ARM64InstructionDecoding/`、`Sources/Analysis/CodeAddressResolution/` | 删除 | 搬到 MachOKitExtensions | 第 1 节 | 2 |
| `Sources/Analysis/CrossReferenceCore/` | 删除 | 搬到 MachOKitExtensions | 第 1 节 | 3 |
| `Sources/Analysis/CrossReferenceObjC/` | 删除 | 搬到 MachOObjCSection | 第 1 节 | 4 |
| `Sources/Analysis/SwiftThunkAnalysis/`（`AccessorThunkReader`、`DependencyImageResolver`、`MachOThunkEnvironment`、`ThunkTypeNodeBuilder`、`ObjCMethodThunkReferences`） | 修改 | `import CodeAddressResolution` 改 `@_spi(Internals) import MachOAddressResolution`；用到解码器的改 `@_spi(Internals) import ARM64InstructionDecoding` | 第 2 节 | 2 |
| `Sources/Declaration/SwiftDeclarationRendering/Extensions/Node+OpaqueType.swift` | 修改 | 同上 | 第 2 节 | 2 |
| `Sources/Analysis/CrossReferenceAnalysis/Exports.swift` | 修改 | `@_exported import MachOCodeReferences`、`@_exported import ObjCCodeReferences` | 门面的公开类型照旧可见 | 3、4 |
| `Sources/Analysis/CrossReferenceAnalysis/` 其余文件 | 修改 | import 改名，用到内部接口的加 `@_spi(Internals) import`；构造 `IndirectCallEvidence` 处去掉 `table:`（若有） | 第 2、3 节 | 3、4 |
| `Tests/CrossReferenceAnalysisTests/MalformedExportTrieTests.swift` | 删除 | 搬到 MachOKitExtensions | 第 5 节 | 3 |
| `Tests/CrossReferenceAnalysisTests/RecognizerExtensionPointTests.swift` | 修改 | 第一条搬走，`selectorQueriesLookUpNoSwiftType` 留下 | 第 5 节 | 3 |
| `Tests/CrossReferenceAnalysisTests/CrossReferenceLayerBoundaryTests.swift` | 删除 | 两条白名单不再需要，运行时名字扫描搬到 MachOKitExtensions | 第 5 节 | 3 |
| `Tests/CrossReferenceAnalysisTests/MemoryAccessScanTests.swift` | 修改 | 只扫 `CrossReferenceAnalysis` | 下层的部分搬走 | 3 |
| `Tests/CrossReferenceAnalysisTests/ARM64InstructionDecodingTests.swift`、`RegisterFileTests.swift`、`InstructionEncoding.swift` | 修改 | `@_spi(Internals) import` 搬走的模块 | Capstone 对照留在本库 | 2、3 |
| `Tests/CrossReferenceAnalysisTests/StandaloneBindSlotTests.swift` | 新增（从 `CodeAddressResolutionTests` 挪入） | `slotResolverResolvesStandaloneBinds` | 要 SymbolTestsCore 夹具 | 2 |
| `Tests/CodeAddressResolutionTests/` | 删除 | 四条搬走、一条挪入 `CrossReferenceAnalysisTests` | 第 5 节 | 2 |
| `Tests/CrossReferenceAnalysisTests/` 其余用到内部接口的文件、`Tests/SwiftThunkAnalysisTests/ThunkEnvironmentImageTablesTests.swift` | 修改 | `@_spi(Internals) import` | `package` 不再跨包 | 2、3、4 |
| `AGENTS.md` | 修改 | 模块依赖图；`CrossReferenceAnalysis`、`ARM64InstructionDecoding`、`CodeAddressResolution` 三条改写 | 第 7 节 | 5 |
| `Documentations/Internal/Modules/CrossReferenceCore.md`、`CrossReferenceObjC.md`、`CodeAddressResolution.md` | 删除 | 搬到另外两个仓库 | 第 7 节 | 5 |
| `Documentations/Internal/Modules/CrossReferenceAnalysis.md`、`SwiftThunkAnalysis.md`、`SwiftSectionKit.md` | 修改 | 改写分层一节与模块链接 | 第 7 节 | 5 |
| `Documentations/README.md`、`Documentations/Glossary.md`、`Documentations/Visions/ReverseEngineeringWithoutIDA.md` | 修改 | 模块文档索引与链接；愿景第 6 条与相关提案表 | 第 7 节 | 1、5 |
| `Documentations/Evolutions/README.md` | 修改 | 登记本提案 | 索引 | 1 |
| `Changelogs/0.25.0.md` | 修改 | Breaking：`IndirectCallEvidence.table` 删除；下层模块移到 MachOKitExtensions / MachOObjCSection | 发版说明 | 6 |
| `Documentations/Internal/ProjectEvolutionLog.md` | 修改 | 落地时加一节 | 账本 | 6 |

### RuntimeViewer

| 文件 / 类型 | 动作 | 改什么 | 为什么 | 步骤 |
|---|---|---|---|---|
| 五个提交进仓库的 `Package.resolved` | 修改 | 落地后抬本库与 MachOObjCSection 的 `next` revision | 惯例 | 6 |

## 架构图

改了什么（模块与依赖，`+` 新增、`-` 删除、`~` 改动）：

```text
Before (MachOSwiftSection next, after 0097)        After (all three land together)

MachOSwiftSection                                  MachOSwiftSection 0.25.0
  CrossReferenceAnalysis (facade, Swift layer)       CrossReferenceAnalysis (facade, Swift layer)   ~ imports below via @_spi(Internals)
    |-- CrossReferenceObjC                       -     |-- ObjCCodeReferences      (MachOObjCSection)
    |     `-- MachOObjCSection (package)                |-- MachOCodeReferences     (MachOKitExtensions)
    |-- CrossReferenceCore                       -     |-- MachOAddressResolution  (MachOKitExtensions)
    |     |-- CodeAddressResolution              -     `-- ARM64InstructionDecoding (MachOKitExtensions)
    |     |-- ARM64InstructionDecoding           -   SwiftThunkAnalysis              ~ -> MachOAddressResolution
    |     `-- MachOFoundation (-> Utilities)         SwiftDeclarationRendering       ~ -> MachOAddressResolution
  SwiftThunkAnalysis -> CodeAddressResolution
  SwiftDeclarationRendering -> CodeAddressResolution

MachOKitExtensions 1.3.x                           MachOKitExtensions 2.0.0
  MachOKitExtensions                                 MachOKitExtensions, MachOReading, ... (two move proposals)
                                                   + ARM64InstructionDecoding
                                                   + MachOAddressResolution  -> MachOReading, ARM64InstructionDecoding
                                                   + MachOCodeReferences     -> MachOReading, MachOAddressResolution, ARM64InstructionDecoding
                                                                                (in-process parts: #if canImport(Darwin))

MachOObjCSection 0.8.206                           MachOObjCSection 0.8.207
  MachOObjCSection (upstream target)                 MachOObjCSection (upstream target, untouched)
                                                   + ObjCCodeReferences      -> MachOObjCSection, MachOCodeReferences
                                                   ~ MachOKitExtensions requirement 2.0.0..<3.0.0
```

一次扫描的调用链（搬家前后不变，只是模块换了包）：

```text
CrossReferenceAnalyzer.references(to:inImageAt:)                 [MachOSwiftSection / CrossReferenceAnalysis]
  -> ReferenceScanner.scan(function:...)                         [MachOKitExtensions / MachOCodeReferences, @_spi(Internals)]
       -> CodeReferenceRecognitionSession (one per layer)
            ObjCCodeReferenceRecognizer.makeSession()            [MachOObjCSection / ObjCCodeReferences, @_spi(Internals)]
            SwiftCodeReferenceRecognizer.makeSession()           [MachOSwiftSection / CrossReferenceAnalysis]
       -> StubChainResolver / SlotResolver                       [MachOKitExtensions / MachOAddressResolution]
       -> ARM64InstructionWord                                   [MachOKitExtensions / ARM64InstructionDecoding]
  <- CodeReference (built by the facade's recorders)             [MachOSwiftSection]
```

落地顺序（发版依赖）：

```text
MachOKitExtensions 2.0.0  ->  MachOObjCSection 0.8.207  ->  MachOSwiftSection 0.25.0  ->  RuntimeViewer pin bump
(three modules added)         (ObjCCodeReferences needs     (requires both)
                               MachOCodeReferences)
```

## 详细设计

### MachOKitExtensions 的 `Package.swift`

```swift
// Products, added beside the nine from the two move proposals.
.library(name: "ARM64InstructionDecoding", targets: ["ARM64InstructionDecoding"]),
.library(name: "MachOAddressResolution", targets: ["MachOAddressResolution"]),
.library(name: "MachOCodeReferences", targets: ["MachOCodeReferences"]),

// Targets.
.target(name: "ARM64InstructionDecoding"),
.target(
    name: "MachOAddressResolution",
    dependencies: [
        .product(name: "MachOKit", package: "MachOKit"),
        "MachOKitExtensions",
        "MachOReading",
        "ARM64InstructionDecoding",
    ]
),
.target(
    name: "MachOCodeReferences",
    dependencies: [
        .product(name: "MachOKit", package: "MachOKit"),
        "MachOKitExtensions",
        "MachOReading",
        "MachOAddressResolution",
        "ARM64InstructionDecoding",
    ]
),
.testTarget(name: "MachOAddressResolutionTests", dependencies: ["MachOAddressResolution"]),
.testTarget(name: "MachOCodeReferencesTests", dependencies: ["MachOCodeReferences"]),
```

### MachOObjCSection 的 `Package.swift`

```swift
.library(name: "ObjCCodeReferences", targets: ["ObjCCodeReferences"]),

.target(
    name: "ObjCCodeReferences",
    dependencies: [
        .product(name: "MachOKit", package: "MachOKit"),
        "MachOObjCSection",
        .product(name: "MachOCodeReferences", package: "MachOKitExtensions"),
    ]
),
.testTarget(name: "ObjCCodeReferencesTests", dependencies: ["ObjCCodeReferences"]),
```

MachOKitExtensions 的要求从 `"1.2.0"..<"3.0.0"` 改成 `"2.0.0"..<"3.0.0"`（本地兄弟依赖的写法照该仓库现有的 `USING_LOCAL_DEPENDENCIES` 分支）。

### 本库的 `Package.swift`

```swift
// CrossReferenceAnalysis after the move.
.target(
    name: "CrossReferenceAnalysis",
    dependencies: [
        .product(name: "ARM64InstructionDecoding", package: "MachOKitExtensions"),
        .product(name: "MachOAddressResolution", package: "MachOKitExtensions"),
        .product(name: "MachOCodeReferences", package: "MachOKitExtensions"),
        .product(name: "ObjCCodeReferences", package: "MachOObjCSection"),
        // ...the Swift-layer dependencies it already has (SwiftInspection, MachOSwiftSection, ...)
    ],
    path: "Sources/Analysis/CrossReferenceAnalysis"
),
```

`SwiftThunkAnalysis` 与 `SwiftDeclarationRendering` 的 `.target(.CodeAddressResolution)` 换成 `.product(name: "MachOAddressResolution", package: "MachOKitExtensions")`。

### SPI 的写法

```swift
// MachOKitExtensions/Sources/MachOAddressResolution/StubChainResolver.swift
@_spi(Internals)
public struct StubChainResolver {
    @_spi(Internals)
    public init(addressSpace: ImageAddressSpace, ...)
    ...
}

// MachOSwiftSection/Sources/Analysis/SwiftThunkAnalysis/AccessorThunkReader.swift
@_spi(Internals) import MachOAddressResolution
```

一个类型在同一个包里被别的模块用、又被另一个包的模块用时，只改成 SPI 一次；`package` 与 `@_spi(Internals) public` 不并存。

### `IndirectCallEvidence` 删掉 `table` 之后

```swift
/// Evidence for where an indirect call may go.
public struct IndirectCallEvidence: Hashable, Sendable {
    /// The displacement of the load that produced the callee, when it came
    /// from memory.
    public let tableOffset: Int64?
    /// The 16-bit arm64e discriminator constant, when there is one.
    public let pointerAuthenticationConstant: UInt16?
    /// Whether the constant was blended into an address (`movk xN, #imm,
    /// lsl #48`) or used alone (`mov x17, #imm`).
    public let isAddressBlended: Bool

    public init(tableOffset: Int64?, pointerAuthenticationConstant: UInt16?, isAddressBlended: Bool)
}
```

### 进程内部分的条件编译

```swift
// MachOCodeReferences/Images/CodeImageSet.swift
#if canImport(Darwin) && arch(arm64)
extension CodeImageSet {
    @_spi(Internals)
    public static func inProcess(...) -> CodeImageSet? { ... }
}
#endif

// MachOCodeReferences/Memory/InProcessCrossReferenceMemory.swift
#if canImport(Darwin)
import MachOReading
...
#endif
```

### 门面的导出

```swift
// MachOSwiftSection/Sources/Analysis/CrossReferenceAnalysis/Exports.swift
@_exported import MachOCodeReferences
@_exported import ObjCCodeReferences
```

`@_exported` 只带出 public 声明；SPI 声明要在用的文件里写 `@_spi(Internals) import`，不会经门面漏给 RuntimeViewer。

### 验收

- **整表一致**：`ReferenceTableDigestTests` 的 A/B（0097 第 1 步做的那套）以本提案开工时的 `next` 为基线，AppKit、SwiftUICore、Foundation 逐条一致；比较前去掉 `IndirectCallEvidence` 描述里的 `table` 与模块名前缀两处拼写差异。
- **吞吐**：Ultra、release、`ScanThroughputBenchmarkTests` 三方交替各三轮取最好，整 cache 建表与两条调用者查询相对基线不超过 +5%；超了先查跨包调用是否失去了包内的跨模块优化（`package` 函数本来也不吃默认的跨模块优化，预计不变）。
- **渲染 A/B**：`SwiftThunkAnalysis` 的读取路径换了模块，按 `AGENTS.md` 跑系统框架渲染 A/B，三条读取路径逐字节一致。
- **三个仓库的全量测试**：本库跳过 IntegrationTests；MachOKitExtensions 本地全量；MachOObjCSection 本地全量，并在 PR 上等 CI。
- **RuntimeViewer**：在沙盒里用本地兄弟依赖编过 Core、CLI 与 MCP 三个包，交叉引用测试单跑通过。

## 替代方案考量

- **在 MachOKitExtensions 里做能单独用的公开 API**（自己的分析器、与语言无关的引用目标类型）：非 Swift 的工具也能用，但要走一轮完整的 API 设计、多问一两轮，工作量明显变大；今天没有任何不经本库的使用方。用户选了只开 SPI，等有使用方再做。
- **`package` 原样全部改成 `public`**：约 300 个内部符号会变成要守 semver 的公开 API，以后每次改内部都可能是破坏性变更。否。
- **核心层整个只在 Darwin 上有**（模块包进 `#if canImport(Darwin)`）：省事，但文件模式本来与平台无关，MachOKitExtensions 又承诺 Linux。**在 Linux 上真编一遍**：要另找 Linux 环境，两份搬迁提案也都没做。都否。
- **测试全部留在本库**：改动最少，但搬走的仓库里没有自己的测试，下层改了只有本库能发现。用户选了测试跟代码走。
- **Capstone 对照测试搬去 MachOKitExtensions、给它加测试专用的 swift-capstone 依赖**：要先核实 SwiftPM 会不会让使用方也去拉 Capstone，MachOKitExtensions 也不该为两组测试多一个大 C 库；**改成写死的期望值**：以后新增的解码就没有独立对照了。都否，这两组留在本库。
- **`ARM64InstructionDecoding` 改成 `MachO` 前缀**（比如 `MachOARM64Decoding`）：与 MachOKitExtensions 其余模块的命名一致，但它与 Mach-O 无关。**并进 `MachOAddressResolution`**：少一个 product，但门面要用解码器时得从地址解析模块导入，概念上不对。都否。
- **`IndirectCallEvidence.table` 原样搬过去**：核心层里留几个 Swift 专有的名字，与「核心不认识任何语言」相悖；**改成与语言无关的叫法**：给一个从来只写 `.none` 的字段换名字没有意义。都否。
- **不等 0.25.0、先单独落地**：做不到——核心层依赖的 `MachOReading` 要靠两份搬迁提案先进 MachOKitExtensions，而它们定了随 0.25.0 落地。**把 0.25.0 提前**：要先给 swift-demangling 发版、处理 0057 读取接口旧转发的去留（MachOKitUI 与 swift-decompiler 还没改用新接口），用户选了不提前。
- **MachOObjCSection 发 0.9.0**（0097 非目标里的设想）：`0.9.0` 已是上游 p-x9 的 tag，fork 照自己的编号规则发 0.8.207。

## 影响

### 源码兼容性（source compatibility）

**有破坏**，都随 0.25.0（本库本来就是破坏性版本）：

- **`IndirectCallEvidence.table` 与 `IndirectCallEvidence.Table` 删除，构造器去掉 `table:`。** 本库、RuntimeViewer、MachOKitUI、swift-decompiler 都没有调用点。

  ```swift
  // Before
  IndirectCallEvidence(table: .none, tableOffset: offset, pointerAuthenticationConstant: constant, isAddressBlended: false)
  // After
  IndirectCallEvidence(tableOffset: offset, pointerAuthenticationConstant: constant, isAddressBlended: false)
  ```

- **`CrossReferenceCore`、`CrossReferenceObjC`、`CodeAddressResolution`、`ARM64InstructionDecoding` 四个模块从本库消失。** 它们不是 product，外部不能直接 import；经 `CrossReferenceAnalysis` 用到的公开类型（`CodeLocation`、`CodeReferenceKind`、`CodeReferenceRoute`、`IndirectCallEvidence`、`ReceiverClassHint`）照旧经 `@_exported` 可见，名字不变。
- 写了 `CrossReferenceCore.CodeLocation` 这种带模块名的全称的代码要改成 `MachOCodeReferences.CodeLocation`；查过的使用方里没有这样写的。

不提供 `@available(*, deprecated, renamed:)` 过渡：被删的字段没有使用方，模块改名也没有外部 import。

### ABI 兼容性

不适用 —— 本库以 SPM 源码分发，使用方每次重新编译。

### 下游影响

- **本库**：`CrossReferenceAnalysis`、`SwiftThunkAnalysis`、`SwiftDeclarationRendering`、SwiftSectionKit（经门面，不改代码）、`CrossReferenceAnalysisTests`、`SwiftThunkAnalysisTests`。
- **MachOKitExtensions**：多三个 product，2.0.0 本来就是大版本。
- **MachOObjCSection**：多一个 product；MachOKitExtensions 下限抬到 2.0.0，0.8.207 起不能与本库 0.24.0 及更早的版本同时解析（MachOKitUI 这类同时用两个库的使用方要和本库一起升到 0.25.0，而它本来就因两份搬迁提案要等 0.25.0）。
- **RuntimeViewer**：不改代码，落地后抬钉；它的 Local workspace 的兄弟检出要包含三个仓库的新分支才能编（落地前在沙盒里验）。
- **MachOKitUI、swift-decompiler**：不用这几个模块，不受影响。

### 文档与示例

见「提议方案」第 7 节。`swift-section` 插件的 skill 只讲命令行，不受影响；README 里 `refs` / `symbolicate` 的用法不变。

## API 演进与废弃策略

- `IndirectCallEvidence.table` 直接删除，不留废弃期：从来只写 `.none`，没有读者。
- 下层的 `@_spi(Internals)` 接口不承诺 semver，改它不算破坏性变更；公开的五个值类型照常守 semver。
- 版本号：MachOKitExtensions 2.0.0（大版本，本来就是）、MachOObjCSection 0.8.207（fork 的补丁号）、本库 0.25.0（本来就是破坏性版本）。

## 落地步骤

0. **把基线备好** —— 改动地图里本库的「`feature/move-macho-infrastructure-modules`（分支）」一行。把 `origin/next` 合进这条分支（merge，不 rebase、不强推），解冲突，按基础设施搬迁提案改名测试支持模块；先告诉在用这两条搬迁分支的会话。三个仓库从这里切出 `feature/move-cross-reference-layers`。
   - 行为：基础设施搬迁分支合入 `next` 后本库全量测试（跳过 IntegrationTests）通过，`ReferenceTableDigestTests` 与 `next` 逐条一致
1. **登记提案** —— 本提案状态改 Accepted；三个仓库的提案索引、两份搬迁提案的决策日志（ARM64 也搬、落地顺序）、愿景的相关提案表。
   - 行为：无代码改动
2. **解码与地址解析搬进 MachOKitExtensions** —— 改动地图里步骤列为 2 的各行。
   - 行为：`SwiftThunkAnalysisTests` 全套照旧通过（线程读取经新模块，结果不变）
   - 行为：`stubChainCarriesTheSelectorRegisterConstantOfACacheSharedSelectorStub`、`slotResolverMatchesTheProcessForEveryGlobalOffsetTableSlotOfAppKit`、`cacheImageLocatorFindsTheImageAnAddressLiesIn`、`stubChainRecordsEveryStubIslandHop` 在 MachOKitExtensions 里通过，且不依赖本库
   - 行为：`slotResolverResolvesStandaloneBinds` 在本库的 `CrossReferenceAnalysisTests` 里通过
   - 行为：`ARM64InstructionDecodingTests`、`RegisterFileTests` 经 `@_spi(Internals) import` 照旧通过
3. **核心层搬进 MachOKitExtensions** —— 步骤列为 3 的各行。
   - 行为：`theCoreScansWithOnlyARecognizerFromTests`（MachOKitExtensions 里，只装测试的识别器，扫出它认领的调用）
   - 行为：`aTerminalSizePastTheTrieEndsTheNodeWithoutTrapping` 在 MachOKitExtensions 里通过
   - 行为：`coreSpellsNoRuntimeSymbolName`、`onlyInProcessMemoryTurnsAddressesIntoPointers`、`coreDefinesNoAddressMaskConstant`（MachOKitExtensions 的源码扫描）
   - 行为：`indirectCallEvidenceCarriesNoTable`（`IndirectCallEvidence` 只有偏移、常量与是否混入地址三项）
   - 行为：`inProcessReferenceTablesAreUnchangedForAppKitSwiftUICoreAndFoundation`（整表 A/B，基线为开工时的 `next`）
   - 行为：`publicNamesStillResolveThroughCrossReferenceAnalysis`（只 `import CrossReferenceAnalysis` 的测试文件仍能用 `CodeLocation`、`CodeReferenceKind.call`、`ReceiverClassHint.methodReceiver`）
4. **ObjC 层搬进 MachOObjCSection** —— 步骤列为 4 的各行。
   - 行为：`objectiveCLayerReadsMemoryOnlyThroughCrossReferenceMemory`、`objectiveCLayerSpellsNoSwiftRuntimeName`（MachOObjCSection 的源码扫描）
   - 行为：整表 A/B 照旧逐条一致；`selectorQueriesLookUpNoSwiftType` 照旧通过
5. **文档与验收** —— 步骤列为 5 的各行；吞吐、渲染 A/B、三个仓库的全量测试、RuntimeViewer 沙盒构建。
   - 行为：`scanThroughputAfterTheMoveIsRecordedInTheModuleDocument`（不是断言：整 cache 建表与两条查询的耗时写进 `MachOCodeReferences.md`，相对基线超过 +5% 先查原因再落地）
   - 行为：渲染 A/B 三条读取路径逐字节一致
6. **落地（随 0.25.0）** —— 第 6 节的顺序：MachOKitExtensions 2.0.0 → MachOObjCSection 0.8.207 → 本库 0.25.0（要求改成 `"0.8.207"..<"0.9.0"`）→ RuntimeViewer 抬钉；本提案取号、改 Implemented，`Changelogs/0.25.0.md` 写 Breaking，账本加一节。
   - 行为：用远端依赖（不设 `USING_LOCAL_DEPENDENCIES`）、Xcode 26.6 编过本库并跑完 CI 名单里的套件

**收尾时必须判断两件事**（判断结果写进决策日志，不允许沉默跳过）：

- **要不要配套专题文章** —— 预判不要：调用方契约没变（门面不变），SPI 的约定写进两份模块文档即可。
- **有没有引入新术语** —— 预判没有：「识别器」等已在 0097 登记；术语表里指向旧模块文档的链接要改。

## 决策日志

| 日期 | 变更 | 说明 |
|------|------|------|
| 2026-11-19 | Created as Draft | 0097 落地当天，用户提出开始把交叉引用迁到 MachOKitExtensions。核心层依赖的 `MachOReading` 要靠两份 MachOKitExtensions 搬迁提案先搬过去，而那两份定了随本库 0.25.0 落地；用户在「现在写提案、随 0.25.0 落地」「把 0.25.0 提前」「先不动」三者中选了第一个。按完整档问了两轮，结论见下面几行 |
| 2026-11-19 | 下层只开 SPI | 用户在「只给本库用的 SPI」「做成能单独用的公开 API」「原样全部改成 public」中选了第一个：今天没有不经本库的使用方，独立公开 API 要多一轮设计，全部改 public 则约 300 个内部符号要守 semver。0097 留下的问题 (a)「没有 Swift 层时引用目标用什么类型」因此不在本提案回答 |
| 2026-11-19 | Linux：文件模式能编 | 用户选了用 `#if canImport(Darwin)` 包住进程内部分、文件模式在 Linux 上也能编、不加 Linux CI；否掉了「整个模块只在 Darwin 上有」与「另找 Linux 环境真编一遍」 |
| 2026-11-19 | 测试跟代码走 | 用户选了测试跟代码走，否掉了全部留在本库。之后核实：交叉引用的测试几乎都经门面建分析器，所以实际搬走的只有直接测下层的几组与源码扫描，另新写一条只装测试识别器的核心扫描测试，证明核心在 MachOKitExtensions 里不靠语言层也能扫 |
| 2026-11-19 | `ARM64InstructionDecoding` 也搬，名字不变 | 核心层与地址解析都离不开它，而基础设施搬迁提案写着它留在本库，这一条要改。用户选了独立 product、名字不变；否掉了改成 `MachO` 前缀与并进 `MachOAddressResolution` |
| 2026-11-19 | 删掉 `IndirectCallEvidence.table` | 扫描器从来只写 `.none`，本库与 RuntimeViewer 都没读过。用户选了删掉；否掉了原样搬过去与改成与语言无关的叫法 |
| 2026-11-19 | Capstone 对照测试留在本库 | 用户选了留在本库、经 SPI 测搬走的解码器，作为「测试跟代码走」的例外；否掉了给 MachOKitExtensions 加测试专用的 swift-capstone 依赖与改成写死的期望值 |
| 2026-11-19 | 其余按默认定 | 沿用 0097 定好的名字；ObjC 层在 MachOObjCSection 里另起 target；SPI 分组统一叫 `Internals`；MachOObjCSection 发 0.8.207（`0.9.0` 是上游的 tag）；核心层改为直接依赖 `MachOReading`；落地顺序改为 MachOKitExtensions 2.0.0 先于 MachOObjCSection 的 tag；开工第一步把 `next` 合进基础设施搬迁分支；验收沿用 0097 的标准。用户确认了这些决定 |
| 2026-11-19 | Accepted | 用户看过简报后批准，开始实现 |
