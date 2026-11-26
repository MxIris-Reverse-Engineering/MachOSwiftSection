# 0111 - IntegrationTests 的 diff 与接口套件合并：三类手检输出共用一套骨架

- **状态**: Implemented
- **作者**: JH
- **创建日期**: 2026-11-26
- **最后更新**: 2026-11-26
- **所属愿景**: 无
- **关联提案**: [0110-unify-evolution-integration-suites](0110-unify-evolution-integration-suites.md)（演进套件的合并；本提案把同样的结构推到 diff 与单版本接口，并让 diff 与演进共用它的版本轴）；[0061-dyld-shared-cache-path-versions](0061-dyld-shared-cache-path-versions.md)（按版本号取归档 cache、`versionLabel`）
- **实现分支 / PR**: `feature/unify-diff-and-interface-integration-suites`（worktree `.worktrees/MachOSwiftSection-UnifyDiffAndInterfaceIntegrationSuites`）
- **配套文档**: 无（见决策日志「收尾判断」）
- **网页版**: 同目录同名的 `.html`

## 摘要

`Tests/IntegrationTests/` 里维护者手检的输出有三类：单版本接口（`SwiftInterfaceBuilderTests.swift`）、两版本 diff（`SwiftDiffableInterfaceBuilderTests.swift`）、N 版本演进（`Evolution/`，0110 刚合并过）。演进那一类已经是「一个套件声明一次镜像、`dump(.kind, to: .file / .console)` 一行一个测试、Swift 与 ObjC 都出」；另两类还是各写各的：diff 自带三个「新旧两版」基类，读 cache 只开主文件，和演进套件、CLI 都不一样；接口套件为了多开一个选项把整份配置抄一遍；两类都只出 Swift。

本提案把三类放进同一个目录 `Tests/IntegrationTests/InspectionDumps/`，共用一套骨架：

- **一个公共协议 `InspectionDumpTests`**（原 `SwiftInterfaceDumpTests`）：输出目录、计时、打印、写文件，以及三类共用的输出形状 `DumpOutput` / `DumpDestination`、元数据语言 `MetadataLanguage`、准备 ObjC 索引的函数。
- **diff 与演进共用版本轴**：diff 就是只有两个版本的轴。`MultiVersionDyldCacheImageTests`（整份打开每个 cache）给 diff 的 cache 对用；模拟器文件对、Xcode 框架对的两个基类搬到顶层，也各自给出轴。原 `Evolution*` 前缀的轴类型去掉前缀（`VersionAxis`、`AxisVersion`、`AxisImage`、`AvailabilityPlatform`）。
- **每类一个「输出种类」枚举 + 一个 `dump` 入口**：`InterfaceDumpKind`（`swiftInterface` / `objcInterface`）、`DiffDumpKind`（`swiftReport` / `swiftInterface` / `objcReport`）、`EvolutionDumpKind`（不变）。
- **新增 ObjC 输出**：AppKit 的两个接口套件多出整镜像的 ObjC 头文件（`objc dump` 的管线），AppKit 的两个 diff 套件多出 ObjC 变更列表与 JSON（`objc diff` 的管线）；Swift diff 报告也多写一份 JSON（`diff --json`）。

测试从 20 个（接口 10、diff 10）变成 38 个（接口 14、diff 24），演进的 43 个不变。只动 IntegrationTests 与它在 `Package.swift` 里的依赖表，不碰库代码。

## 动机

0110 合并演进套件时把 diff 与接口划在范围外。现在三类并排，差异本身就成了要维护的东西：

1. **diff 有自己的一套「新旧两版」基类，和演进的版本轴是同一件事的两种写法**。`SwiftDiffableInterfaceBuilderTestSuite` 里的 `CrossVersionMachOFileTests`（`Tests/IntegrationTests/SwiftInterface/SwiftDiffableInterfaceBuilderTests.swift:95`）、`CrossVersionDyldCacheImageTests`（`:113`）、`CrossVersionXcodeFrameworkTests`（`:138`）各自持有一对 `MachOFile`；演进套件 `EvolutionTestSuite.SwiftUICoreSimulatorTests` 还得借 diff 的 `CrossVersionMachOFileTests`（`Tests/IntegrationTests/Evolution/EvolutionTests.swift:326`），再自己把这一对包成 `EvolutionAxis`（`:330-339`）。
2. **diff 读 cache 的方式和演进、CLI 都不同**。`CrossVersionDyldCacheImageTests` 用 `DyldCache(path:)` 只打开主文件（`:124-125`），从主 cache 取镜像；`MultiVersionDyldCacheImageTests` 与 `swift-section --dyld-shared-cache` 都整份打开（`FullDyldCache`，见 `Tests/IntegrationTests/Evolution/EvolutionAxis.swift:92-96` 的注释）。同一个 AppKit，在 diff 与演进两个手检输出里经两条读路径。
3. **注释和代码对不上**。diff 的 `DyldCacheTests` 注释写「The same macOS image (SwiftUI) extracted from two dyld shared caches (macOS 15.5 → current)」（`:190-191`），实际读 AppKit，26.5.1 → 27.0（`:193-195`）。0110 在演进套件里修过同一类问题。
4. **接口套件为一个选项抄整份配置**。`XcodeMachOFileTests` 只想开 `printExportedDeclarationsOnly`，却把 `builderConfiguration` 的十几个参数整段重写（提交版 `SwiftInterfaceBuilderTests.swift:151-173`），以后改默认配置要改两处。
5. **接口套件用类型转换判读取器**。`buildFile` 用 `machO is MachOImage` 决定文件后缀（提交版 `:66`）。项目规则要求问 `asMachOImage`，不转具体类型（`CLAUDE.md`「you need to know whether a reader is a MachOImage or a MachOFile」一节）；这里是测试代码，扫描不到，但同样会把包装类型认错。
6. **只有演进出 ObjC**。AppKit 的 ObjC 部分远大于 Swift，维护者却只能在演进套件里看到它；看单个 cache 的 AppKit 头文件、两版之间的 ObjC 变化，得另跑 CLI。
7. **三类的 `indexConfiguration` 各写一份**（`SwiftDiffableInterfaceBuilderTests.swift:25`、`EvolutionDumpTests.swift:82`、接口配置里的 `indexConfiguration:`），值都是 `.init(showCImportedTypes: false)`。

## 前期调研

1. **CLI 里对应的管线**（测试要复现的就是它们）：
   - Swift 单版本接口：`SwiftInterfaceBuilder` + `SwiftInterfaceBuilderOpaqueTypeProvider`，`prepare()` 后 `printRoot()`。现状测试照此做，打印配置开满（字段偏移、地址、vtable/PWT 偏移、布局、按偏移排序等）。
   - ObjC 整镜像头文件：`swift-section objc dump`（`Sources/Commands/SwiftSectionKit/ObjC/ObjCDumpRequest.swift`）。`ObjCInterfaceSession.make` 建 `ObjCInterfaceIndexer(machO:imagePath:suppliedClasses:)`（`suppliedClasses` 用 `ObjCSuppliedClass.swiftClassesWithoutClassObjects(in:)`）、`prepare()`，再用 `ObjCInterfaceBuilder(indexer:machO:)` 按 `classes, protocols, categories, structs, unions` 的顺序、每种名字排序后逐个取 `classInterface(named:…)` / `protocolInterface` / `categoryInterface(uniqueName:…)` / `structInterface` / `unionInterface`，写文件时每段后接一个空行。`ObjCDeclarationKind` 在 SwiftSectionKit 里，IntegrationTests 不依赖 SwiftSectionKit，测试里照这个顺序自己写五个分支。
   - Swift diff：变更列表是 `ABIDiffer().diff(old:new:)` + `ABIDiffReporter().report(_:)` + 一行 `ABI-breaking: … · backward-compatible: …`；`--json` 是 `ABIJSON.encoder().encode(diff)`；`--interface` 是 `SwiftDiffableInterfaceRenderer(old:new:).printAnnotatedInterface(format:)`（`Sources/Commands/SwiftSectionKit/Swift/ABIDiffRequest.swift:67-150`）。现状测试的变更列表直接用两个 builder 的 `abiModule()`，不经快照文档。
   - ObjC diff：`ObjCAPIDiffRequest`（`Sources/Commands/SwiftSectionKit/ObjC/ObjCAPIRequests.swift:56-108`）把两边各读成 `ObjCAPISnapshotDocument`，`ObjCAPIDiffer().diff(old:new:)`，变更列表 `ObjCAPIDiffReporter().report(_:)` + 一行 `API-breaking: … · backward-compatible: …`，`--json` 是 `ObjCAPIJSON.encoder().encode(diff)`。ObjC diff **没有**带标注的头文件。
2. **用到的 ObjC 接口在锁定版本里都有**。`Package.resolved` 锁 MachOObjCSection 0.8.209；在这个 tag 上 `ObjCInterfaceBuilder` 的五个 `…Interface` 方法、`ObjCInterfaceIndexer` 的五个 `…Names`、`ObjCGenerationOptions.printExportedDeclarationsOnly` 都在，`MachOImage` 与 `MachOFile` 都遵循 `ObjCMetadataSource`。`ObjCGenerationOptions` 在 `ObjCDeclarationRendering` 这个 product 里，IntegrationTests 目前没依赖它，要在 `Package.swift` 加一行；`Tuist/Package.swift` 不逐个列 MachOObjCSection 的 product，不用改。
3. **`swiftClassesWithoutClassObjects(in:)` 收 `some MachORepresentableWithCache`**（`Sources/Declaration/SwiftIndexing/ObjCSuppliedClass+SwiftClassesWithoutClassObjects.swift:26`），`ObjCInterfaceIndexer` 对 `MachO: ObjCMetadataSource` 泛型，所以准备 ObjC 索引的函数可以改成泛型，接口套件的进程内镜像也能用。
4. **测试支撑的基类**（MachOKitExtensions 的 `MachOTestingSupport`）：`DyldCacheTests` 在 `cachePath == .current` 时用 `FullDyldCache.cachedHost`，否则 `FullDyldCache(path:)`，`machOFileInCache` 取自整份 cache；`MachOFileTests`、`MachOImageTests` 是 `@MainActor`；`XcodeMachOFileTests` 没有隔离。接口套件继续用这些基类，不需要版本轴。
5. **文件命名**：`write(_:for:…)` 与 `write(_:forImageGroup:…)` 在单镜像时逐字相同（0110 调研第 3 条），所以 diff 改用轴之后输出文件名不变。
6. **IntegrationTests 外引用这些名字的地方**：`Documentations/Internal/ABIEvolutionDesign.md:235` 写着 `Tests/IntegrationTests/Evolution/`；账本、任务报告、已落地提案里的 `SwiftInterfaceBuilderTestSuite` 等旧名是历史记录。`Scripts/`、`Sources/`、别的测试目标都不引用。

## 提议方案

### 三类的分工

| 类 | 协议 | 输入 | 输出种类（CLI 对应） | 文件后缀 |
|---|---|---|---|---|
| 接口 | `InterfaceDumpTests` | 一个镜像，任意读取器（文件、cache 里的文件、进程内镜像） | `swiftInterface`（`interface`）、`objcInterface`（`objc dump`） | `-FileDump.swiftinterface` / `-ImageDump.swiftinterface`；`-ObjCFileDump.h` / `-ObjCImageDump.h` |
| diff | `DiffDumpTests` | 版本轴的第一个与最后一个版本（主镜像） | `swiftReport`（`diff` + `diff --json`）、`swiftInterface`（`diff --interface`，inline 与 unified）、`objcReport`（`objc diff` + `--json`） | `-Diff.txt` / `.json`；`-AnnotatedInterface-Inline` / `-Unified.swiftinterface`；`-ObjCDiff.txt` / `.json` |
| 演进 | `EvolutionDumpTests` | 整条版本轴 | 不变 | 不变 |

diff 与演进都是 `VersionAxisDumpTests`（要求 `versionAxis(for:)`），都由三个轴基类之一供轴：

| 轴基类 | 版本来自 | 谁用 |
|---|---|---|
| `MultiVersionDyldCacheImageTests` | `cachePaths` 列出的 cache，整份打开 | 演进的九个 cache 套件；diff 的两个 AppKit 套件 |
| `CrossVersionMachOFileTests` | 两个模拟器运行时里的同一个文件 | 演进的 `SwiftUICoreSimulatorTests`；diff 的 `SwiftUICoreTests`、`SwiftUITests` |
| `CrossVersionXcodeFrameworkTests` | 两个已安装的 Xcode 里同一个共享框架 | diff 的 `XcodeFrameworkTests` |

### 套件与测试

套件类名保留现状（接口与 diff 的套件是「指向任意镜像」的探针，维护者常临时改读别的镜像，按来源命名比按镜像命名更不易过时）；外层的枚举改名，测试函数改成「种类 + 去向」：

| 套件 | 读什么 | 测试 |
|---|---|---|
| `InterfaceTestSuite.DyldCacheTests` | 本机 cache 的 AppKit | `swiftInterfaceFile/String`、`objcInterfaceFile/String` |
| `InterfaceTestSuite.ArchivedDyldCacheTests` | 归档 26.6 cache 的 AppKit | 同上 4 个 |
| `InterfaceTestSuite.MachOFileTests` | SymbolTestsCore fixture | `swiftInterfaceFile/String` |
| `InterfaceTestSuite.MachOImageTests` | 进程内 SwiftUICore | `swiftInterfaceFile/String` |
| `InterfaceTestSuite.XcodeMachOFileTests` | Xcode 的 SourceEditor，只印导出声明 | `swiftInterfaceFile/String` |
| `DiffTestSuite.SwiftUICoreTests` | 模拟器 18.5 → 26.5 的 SwiftUICore | `swiftReportFile/String`、`swiftInterfaceFile/String` |
| `DiffTestSuite.SwiftUITests` | 模拟器 18.5 → 26.5 的 SwiftUI | 同上 4 个 |
| `DiffTestSuite.DyldCacheTests` | cache 26.5.1 → 27.0 的 AppKit | 同上 4 个 + `objcReportFile/String` |
| `DiffTestSuite.ArchivedDyldCacheTests` | 归档 cache 26.6 → 27.0 的 AppKit | 同上 6 个 |
| `DiffTestSuite.XcodeFrameworkTests` | Xcode 26.3.0 → 26.4.0 的 DVTProductsUI | `swiftReportFile/String`、`swiftInterfaceFile/String` |

ObjC 输出只加在 AppKit 套件上（ObjC 是 AppKit 的大头；别的套件要看 ObjC，加一对一行测试即可）。

### 采用的假设

- **diff 的 cache 对改为整份打开**（用户在澄清时选定）。输出可能与现状有出入，以与 CLI 一致为准。
- **ObjC 头文件开满注释**：ivar 偏移、属性特性、方法 IMP 地址、访问器地址四种注释都开。Swift 接口这边本来就开满了字段偏移与成员地址，手检输出以信息最多为目标。
- **Swift diff 报告多写一份 `-Diff.json`**，与演进报告、ObjC diff 报告对齐；变更列表照旧用两个 builder 的 `abiModule()`，不改成快照文档往返（不改变现有输出）。
- **diff 比较轴上第一个与最后一个版本的主镜像**。diff 套件只声明两个版本、一个镜像；轴筛掉版本后不足两个时，打印一行说明、不写文件（与演进轴为空时直接返回一致，IntegrationTests 不设断言）。
- **控制台只打印一份**：diff 的 `swiftInterface` 写文件时出 inline 与 unified 两份，打到控制台只出 inline（现状 `diffString` 也只印 inline）；为此这条管线按去向决定要不要渲染 unified，省一次完整渲染。
- **Xcode 对按版本号取**：`CrossVersionXcodeFrameworkTests` 的类属性从 `oldXcodeApplicationPath` / `newXcodeApplicationPath` 改为 `oldXcodeVersion` / `newXcodeVersion`（`"26.3.0"` / `"26.4.0"`），路径拼成 `/Applications/Xcode-<版本>.app`，版本号也当轴标签，与归档 cache 按版本号取一致。
- **旧测试名直接删除，不留别名**：IntegrationTests 没有调用方，测试名只在维护者手动运行时用到。
- **维护者在公司那台 `next` 检出里未提交的 `SwiftInterfaceBuilderTests.swift` 实验不碰**（用户在澄清时选定）：本提案照提交版重构；合回那个检出前，由维护者自己提交或丢弃那份实验，否则合并会被它挡住。实验里的「改读 AttributeGraph」在新结构里是给 `InterfaceTestSuite.DyldCacheTests` 改 `cacheImageName`。

### 非目标

- 不动 `SwiftDump/` 的 `DumpableTests` 一族（`dump` 子命令的手检，结构另成一套）。
- 不动 `RenderingVerificationTests`（渲染 A/B 验证的 MachOImage 腿，有自己的约定）与 `SwiftInterfaceIndexerTests`。
- 不给 diff 加镜像组：`ABIDiffer` 与 `ObjCAPIDiffer` 没有镜像组入口。
- 不改库代码、不改 CLI。

## 改动地图

| 文件 · 类型 | 动作 | 改什么 | 为什么 | 步骤 |
|---|---|---|---|---|
| `Tests/IntegrationTests/InspectionDumps/` | 新增目录 | 三类手检输出的家 | 三类共用骨架，放一处 | 1 |
| `InspectionDumps/InspectionDumpTests.swift`（`git mv` 自 `SwiftInterface/SwiftInterfaceTestSupport.swift`） | 移动 + 修改 | 协议改名 `InspectionDumpTests`；加 `indexConfiguration`、`MetadataLanguage`（自 `EvolutionMetadataLanguage`）、`DumpDestination`、`DumpFile`、`DumpOutput`、`deliver(_:to:writingFile:)`、泛型的 `preparedObjCIndexer(of:)`；`write(_:forImageGroup:)` 收 `[AxisImage]` | 三类共用的部分只写一次 | 1 |
| `InspectionDumps/VersionAxis.swift`（`git mv` 自 `Evolution/EvolutionAxis.swift`） | 移动 + 修改 | 去掉 `Evolution` 前缀：`AvailabilityPlatform`、`AxisImage`、`AxisVersion`、`VersionAxis`；新增 `VersionAxes`（两种语言各一条轴）与协议 `VersionAxisDumpTests`（含共享的 `objcSnapshotDocument(of:label:)`）；`MultiVersionDyldCacheImageTests` 改存 `VersionAxes`；`CrossVersionMachOFileTests`、`CrossVersionXcodeFrameworkTests` 从 diff 文件搬来，加版本标签与轴 | diff 与演进共用版本轴 | 1 |
| `InspectionDumps/EvolutionDumpTests.swift`（`git mv` 自 `Evolution/`） | 移动 + 修改 | 改继承 `VersionAxisDumpTests`；`EvolutionDumpOutput` 换成 `DumpOutput`；`evolutionAxis(for:)` 改名 `versionAxis(for:)`；删自己的 `indexConfiguration`、`preparedObjCIndexer`、`objcSnapshotDocument` | 共用骨架 | 1 |
| `InspectionDumps/EvolutionTests.swift`（`git mv` 自 `Evolution/`） | 移动 + 修改 | 换新类型名；`SwiftUICoreSimulatorTests` 改继承顶层 `CrossVersionMachOFileTests`，删掉自己拼轴的那段 | 轴由基类给 | 1 |
| `SwiftInterface/SwiftDiffableInterfaceBuilderTests.swift` | 修改（第 1 步）→ 删除（第 3 步） | 第 1 步只把协议名改成 `InspectionDumpTests`、删自己的 `indexConfiguration`，保证能编 | 分步可编 | 1、3 |
| `SwiftInterface/SwiftInterfaceBuilderTests.swift` | 修改（第 1 步）→ 删除（第 2 步） | 第 1 步只改协议名 | 分步可编 | 1、2 |
| `InspectionDumps/InterfaceDumpTests.swift` | 新增 | `InterfaceDumpKind`；协议 `InterfaceDumpTests`（`printsExportedDeclarationsOnly`）；`builderConfiguration`、`objcGenerationOptions`；`dump(_:of:to:)` 与两条管线 | 接口一类的管线 | 2 |
| `InspectionDumps/InterfaceTests.swift` | 新增 | `enum InterfaceTestSuite`，五个套件、14 个测试 | 取代旧接口套件 | 2 |
| `InspectionDumps/DiffDumpTests.swift` | 新增 | `DiffDumpKind`；协议 `DiffDumpTests: VersionAxisDumpTests`；`dump(_:to:)` 与三条管线 | diff 一类的管线 | 3 |
| `InspectionDumps/DiffTests.swift` | 新增 | `enum DiffTestSuite`，五个套件、24 个测试 | 取代旧 diff 套件 | 3 |
| `Tests/IntegrationTests/Evolution/` | 删除（目录） | 三个文件移走后为空 | — | 1 |
| `Package.swift` · `IntegrationTests` 目标 | 修改 | 加 `.product(name: "ObjCDeclarationRendering", package: "MachOObjCSection")`；注释从「ObjC API evolution dumps」改为三类 ObjC 输出 | `ObjCGenerationOptions` 在这个 product 里 | 2 |
| `Documentations/Internal/ABIEvolutionDesign.md:235` | 修改 | 目录改 `Tests/IntegrationTests/InspectionDumps/` | 路径变了 | 4 |
| `Documentations/Internal/ProjectEvolutionLog.md` | 修改 | 追加一节 | 账本 | 4 |
| `Documentations/Evolutions/README.md`、`Documentations/README.md` | 修改 | 登记本提案 | 索引 | 起草时 / 4 |

## 架构图

改了什么（文件与类型）：

```
Tests/IntegrationTests/
- SwiftInterface/SwiftInterfaceTestSupport.swift     protocol SwiftInterfaceDumpTests
- SwiftInterface/SwiftInterfaceBuilderTests.swift    protocol SwiftInterfaceBuilderTests + enum SwiftInterfaceBuilderTestSuite (5)
- SwiftInterface/SwiftDiffableInterfaceBuilderTests.swift
-     protocol SwiftDiffableInterfaceBuilderTests
-     enum SwiftDiffableInterfaceBuilderTestSuite
-         CrossVersionMachOFileTests / CrossVersionDyldCacheImageTests (DyldCache, main file only) / CrossVersionXcodeFrameworkTests
-         5 suites
- Evolution/EvolutionAxis.swift / EvolutionDumpTests.swift / EvolutionTests.swift
  SwiftInterface/SwiftInterfaceIndexerTests.swift, RenderingVerificationTests.swift   (unchanged)
+ InspectionDumps/
+   InspectionDumpTests.swift   protocol InspectionDumpTests
+                               MetadataLanguage, DumpDestination, DumpFile, DumpOutput, preparedObjCIndexer(of:)
+   VersionAxis.swift           AvailabilityPlatform, AxisImage, AxisVersion, VersionAxis, VersionAxes
+                               protocol VersionAxisDumpTests: InspectionDumpTests
+                               MultiVersionDyldCacheImageTests (FullDyldCache)
+                               CrossVersionMachOFileTests, CrossVersionXcodeFrameworkTests
+   InterfaceDumpTests.swift    InterfaceDumpKind { swiftInterface, objcInterface }
+                               protocol InterfaceDumpTests: InspectionDumpTests
+   InterfaceTests.swift        enum InterfaceTestSuite (5 suites, 14 tests)
+   DiffDumpTests.swift         DiffDumpKind { swiftReport, swiftInterface, objcReport }
+                               protocol DiffDumpTests: VersionAxisDumpTests
+   DiffTests.swift             enum DiffTestSuite (5 suites, 24 tests)
~   EvolutionDumpTests.swift    protocol EvolutionDumpTests: VersionAxisDumpTests
~   EvolutionTests.swift        enum EvolutionTestSuite (10 suites, 43 tests)
```

协议与基类的关系：

```
InspectionDumpTests (rootDirectory, indexConfiguration, measuringPreparation, printResult, write, deliver)
├── InterfaceDumpTests          dump(_: InterfaceDumpKind, of: machO, to:)
│     suites inherit MachOTestingSupport bases: DyldCacheTests / MachOFileTests / MachOImageTests / XcodeMachOFileTests
└── VersionAxisDumpTests        versionAxis(for: MetadataLanguage) -> VersionAxis
      ├── DiffDumpTests         dump(_: DiffDumpKind, to:)        reads versions.first / versions.last
      └── EvolutionDumpTests    dump(_: EvolutionDumpKind, to:)   reads every version
            axis providers: MultiVersionDyldCacheImageTests | CrossVersionMachOFileTests | CrossVersionXcodeFrameworkTests
                            each stores VersionAxes (swift axis, objc axis) built in init
```

一个 diff 测试的调用链：

```
DiffTestSuite.DyldCacheTests.objcReportFile()
  └─ dump(.objcReport, to: .file)                           DiffDumpTests
       ├─ versionAxis(for: .objc)                            MultiVersionDyldCacheImageTests (26.5.1, 27.0 / AppKit)
       ├─ old = versions.first, new = versions.last
       ├─ objcReport(old:new:)
       │    ├─ measuringPreparation { objcSnapshotDocument(of: old.primaryImage) ; … new … }
       │    │      └─ preparedObjCIndexer(of:) → ObjCAPISnapshotBuilder.snapshot() → JSON round trip
       │    ├─ ObjCAPIDiffer().diff(old:new:)
       │    └─ DumpOutput(console: report, files: [ObjCDiff.txt, ObjCDiff.json])
       └─ deliver(output, to: .file) → write(_:forImageGroup: [new.primaryImage], …)
```

## 详细设计

### `InspectionDumpTests.swift`

```swift
/// Shared scaffolding for the maintainer-inspection dumps: the single-version
/// interfaces, the two-version diffs and the N-version evolutions.
protocol InspectionDumpTests {}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension InspectionDumpTests {
    var rootDirectory: URL                                   // unchanged: Documents/SwiftInterfaceTests
    var indexConfiguration: SwiftDeclarationIndexConfiguration { .init(showCImportedTypes: false) }
    func measuringPreparation<Prepared>(_ prepare: () async throws -> Prepared) async rethrows -> Prepared   // now returns what it prepared
    func printResult(_ string: String)                       // unchanged
    func write(_:for:suffix:fileExtension:) throws           // unchanged
    func write(_:forImageGroup images: [AxisImage], suffix:fileExtension:) throws

    /// Prints the console text, or writes every file through `writeFile`.
    func deliver(_ output: DumpOutput, to destination: DumpDestination, writingFile writeFile: (DumpFile) throws -> Void) rethrows
}

enum MetadataLanguage: Sendable { case swift, objc; func isCarried(by machOFile: MachOFile) -> Bool }
enum DumpDestination: Sendable { case console, file }

/// One file a dump writes: named `<build version>-<image names>-<suffix>.<fileExtension>`.
struct DumpFile: Sendable { let suffix: String; let fileExtension: String; let text: String }

/// What one pipeline produced: what the console destination prints, and
/// what the file destination writes.
struct DumpOutput: Sendable { let consoleText: String; let files: [DumpFile] }

/// One image indexed the way the `objc` subcommands index it.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
func preparedObjCIndexer<MachO: ObjCMetadataSource & MachORepresentableWithCache>(of machO: MachO) async throws -> ObjCInterfaceIndexer<MachO>
```

`BuildVersionCommand` 与 `Platform.stringValue` 的扩展原样搬来。`deliver` 让三类各自决定文件名怎么起：接口按 `write(_:for: machO…)`，演进按 `write(_:forImageGroup: newest.images…)`，diff 按 `write(_:forImageGroup: [newVersion.primaryImage]…)`（diff 只读主镜像；单镜像时三种写法得到同一个文件名）。`measuringPreparation` 改成泛型、返回准备好的值：ObjC 头文件与 ObjC diff 要在计时的那一步里拿回索引器或快照文档。

### `VersionAxis.swift`

`AvailabilityPlatform`、`AxisImage`、`AxisVersion`（含 `keepingImages(carrying:)`）、`VersionAxis` 只改名，语义不变。新增：

```swift
/// One axis per metadata language, each keeping the versions whose primary
/// image carries that language's metadata. Built once at initialization:
/// the class properties it derives from are isolated to the test actor,
/// the pipelines are not.
struct VersionAxes: Sendable {
    init(versions: [AxisVersion], comparesImageGroups: Bool, availabilityPlatform: AvailabilityPlatform?)
    func axis(for language: MetadataLanguage) -> VersionAxis
}

/// A dump over an ordered series of versions: a diff reads its first and
/// last version, an evolution every version.
protocol VersionAxisDumpTests: InspectionDumpTests {
    func versionAxis(for language: MetadataLanguage) -> VersionAxis
}

extension VersionAxisDumpTests {
    /// moved from EvolutionDumpTests (was private); the diff's ObjC report uses it too
    func objcSnapshotDocument(of image: AxisImage, label: String) async throws -> ObjCAPISnapshotDocument
}
```

`VersionAxes` 存成两个 `let`（`swiftAxis`、`objcAxis`）加 `switch`，与 0110 落地时的写法一致。三个轴基类都 `@TestActor`，都存一个 `let axes: VersionAxes`，都实现 `nonisolated func versionAxis(for:) -> VersionAxis { axes.axis(for: language) }`：

- `MultiVersionDyldCacheImageTests`：类属性（`cachePaths`、`cacheImageName`、`cacheImageNames`、`availabilityPlatform`、`defaultMacOSCachePaths`、`archivedMacOSCachePaths` 与 51 个版本）与 `init` 的取镜像逻辑原样保留，最后一步改成 `self.axes = VersionAxes(versions:comparesImageGroups:availabilityPlatform:)`。文档注释里指向 diff 基类的那句改掉。
- `CrossVersionMachOFileTests`：保留 `oldMachOFile` / `newMachOFile`、`oldFileName` / `newFileName`（默认 SwiftUICore 18.5 / 26.5）；新增 `oldVersionLabel` / `newVersionLabel`（默认 `"18.5"` / `"26.5"`）。轴的镜像名取 `machOFile.imagePath.lastPathComponent`（单镜像轴的管线不读这个名字，演进输出不变）。`comparesImageGroups: false`、`availabilityPlatform: nil`。
- `CrossVersionXcodeFrameworkTests`：`oldXcodeVersion` / `newXcodeVersion`（`"26.3.0"` / `"26.4.0"`）、`sharedFrameworkName`（`"DVTProductsUI"`）；路径 `/Applications/Xcode-<版本>.app/Contents/SharedFrameworks/<名>.framework/Versions/A/<名>`；轴标签就是版本号。

### `InterfaceDumpTests.swift`

```swift
/// The two single-version outputs, each the pipeline of one subcommand.
enum InterfaceDumpKind: Sendable {
    /// `swift-section interface`: `-FileDump.swiftinterface` / `-ImageDump.swiftinterface`.
    case swiftInterface
    /// `swift-section objc dump`: every Objective-C declaration of the image,
    /// `-ObjCFileDump.h` / `-ObjCImageDump.h`.
    case objcInterface
}

protocol InterfaceDumpTests: InspectionDumpTests {
    /// Whether both interfaces print only what the image exports — what
    /// `interface --exported-only` and `objc dump --exported-only` do.
    var printsExportedDeclarationsOnly: Bool { get }
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension InterfaceDumpTests {
    var printsExportedDeclarationsOnly: Bool { false }
    var builderConfiguration: SwiftInterfaceBuilderConfiguration   // today's configuration + printExportedDeclarationsOnly: printsExportedDeclarationsOnly
    var objcGenerationOptions: ObjCGenerationOptions               // .default + the four comment options + printExportedDeclarationsOnly

    func dump<MachO: MachOFieldLayoutRenderable & ObjCMetadataSource>(
        _ kind: InterfaceDumpKind, of machO: MachO, to destination: DumpDestination
    ) async throws
}
```

- 读取器后缀：`machO.asMachOImage != nil ? "ImageDump" : "FileDump"`，ObjC 加前缀 `ObjC`。
- `swiftInterface`：`SwiftInterfaceBuilder(configuration: builderConfiguration, eventHandlers: [], in: machO)` + `addExtraDataProvider(SwiftInterfaceBuilderOpaqueTypeProvider(machO:))`，`measuringPreparation { prepare() }`，`printRoot().string`。与现状逐字相同。
- `objcInterface`：`measuringPreparation` 里 `preparedObjCIndexer(of: machO)`；`ObjCInterfaceBuilder(indexer:machO:)`；按 classes、protocols、categories、structs、unions 的顺序，名字排序，逐个取接口（类别用 `categoryInterface(uniqueName:)`），每段后接 `"\n\n"`，与 `objc dump --file` 的拼法一致。
- 套件若要改 `printsExportedDeclarationsOnly`，在 `@MainActor` 的基类上要写 `nonisolated var`；`XcodeMachOFileTests` 的基类不隔离，直接写 `var`。

### `DiffDumpTests.swift`

```swift
enum DiffDumpKind: Sendable {
    /// `swift-section diff` and `diff --json`: `-Diff.txt` / `-Diff.json`.
    case swiftReport
    /// `swift-section diff --interface`: `-AnnotatedInterface-Inline.swiftinterface`
    /// and `-AnnotatedInterface-Unified.swiftinterface`; the console prints the inline one.
    case swiftInterface
    /// `swift-section objc diff` and `objc diff --json`: `-ObjCDiff.txt` / `-ObjCDiff.json`.
    case objcReport
    var language: MetadataLanguage
}

protocol DiffDumpTests: VersionAxisDumpTests {}

extension DiffDumpTests {
    func dump(_ kind: DiffDumpKind, to destination: DumpDestination) async throws {
        let axis = versionAxis(for: kind.language)
        guard axis.versions.count >= 2, let oldVersion = axis.versions.first, let newVersion = axis.versions.last else {
            printResult("No diff: \(axis.versions.count) version(s) carry \(kind.language) metadata")
            return
        }
        let output: DumpOutput = switch kind { … }
        try deliver(output, to: destination) { file in
            try write(file.text, forImageGroup: [newVersion.primaryImage], suffix: file.suffix, fileExtension: file.fileExtension)
        }
    }
}
```

- `swiftReport`：两个 `SwiftDiffableInterfaceBuilder` 在一个 `measuringPreparation` 里各 `prepare()`（与现状同）；`ABIDiffer().diff(old: abiModule(), new: abiModule())`；正文 = 报告 + `\n\n` + 结论行；JSON = `ABIJSON.encoder().encode(diff)`。
- `swiftInterface`：同样准备两个 builder；inline 必出，unified（`.unified()`，与现状相同的默认标签）只在去向是文件时渲染。两种格式各建一个 `SwiftDiffableInterfaceRenderer`，与现状相同。
- `objcReport`：两边 `objcSnapshotDocument(of: version.primaryImage, label: version.label)`，`ObjCAPIDiffer().diff(old:new:)`，正文 = `ObjCAPIDiffReporter().report(diff)` + 结论行（`API-breaking: … · backward-compatible: …`，与 CLI 同），JSON = `ObjCAPIJSON.encoder().encode(diff)`。

### 套件的样子

```swift
enum DiffTestSuite {
    /// AppKit extracted from two dyld shared caches (macOS 26.5.1 → 27.0), each
    /// opened whole the way `swift-section --dyld-shared-cache` opens it.
    final class DyldCacheTests: MultiVersionDyldCacheImageTests, nonisolated DiffDumpTests, @unchecked Sendable {
        override class var cachePaths: [DyldSharedCachePath] { [.macOS_26_5_1, .macOS_27_0] }
        override class var cacheImageName: MachOImageName { .AppKit }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func swiftReportFile() async throws {
            try await dump(.swiftReport, to: .file)
        }
        // swiftReportString, swiftInterfaceFile/String, objcReportFile/String: the same shape
    }
}

enum InterfaceTestSuite {
    class XcodeMachOFileTests: SwiftSectionTestingSupport.XcodeMachOFileTests, InterfaceDumpTests {
        override class var fileName: XcodeMachOFileName { .sharedFrameworks(.SourceEditor) }
        var printsExportedDeclarationsOnly: Bool { true }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func swiftInterfaceFile() async throws {
            try await dump(.swiftInterface, of: machOFile, to: .file)
        }
        // swiftInterfaceString: the same shape
    }
}
```

### 与现状的行为差异

| 方面 | 现状 | 之后 |
|---|---|---|
| diff 的 cache 对 | `DyldCache(path:)` 只开主文件，从主 cache 取镜像 | `FullDyldCache(path:)` 整份打开，与演进、CLI 一致；输出可能有出入 |
| diff 的输出 | `diffFile` 写三个文件；`diffString` 印变更列表与 inline | `swiftReport` 写 `-Diff.txt` 与新增的 `-Diff.json`，印变更列表；`swiftInterface` 写 inline 与 unified，印 inline |
| 新增 ObjC 输出 | 无 | AppKit 接口套件：`-ObjCFileDump.h`；AppKit diff 套件：`-ObjCDiff.txt` / `.json` |
| 接口的文件名 | `-FileDump` / `-ImageDump`，按 `is MachOImage` | 文件名不变，按 `asMachOImage` |
| Xcode diff 的类属性 | 两个 `.app` 路径 | 两个版本号 |
| 测试标识 | `SwiftInterfaceBuilderTestSuite.*/buildFile()` 等、`SwiftDiffableInterfaceBuilderTestSuite.*/diffFile()` 等 | `InterfaceTestSuite.*/swiftInterfaceFile()` 等、`DiffTestSuite.*/swiftReportFile()` 等；演进的不变 |
| 演进 | — | 输出与测试标识都不变；只换类型名与目录 |

## 替代方案考量

1. **单版本接口也走版本轴（一个版本的轴）**：放弃。接口套件要读进程内的 `MachOImage`（SwiftUICore），而轴里的镜像是 `MachOFile`，演进构建器也只收 `MachOFile`；为接口把 `AxisImage` 泛型化，会让 diff 与演进的每条管线都背上它用不到的泛型。接口套件继续用 MachOKitExtensions 的四个基类，`dump` 直接收这个镜像。
2. **三类合成一个大的 `DumpKind` 枚举、一个协议**：放弃。三类的输入不同（一个镜像 / 两个版本 / N 个版本），合成一个就得让每个种类在运行时检查自己拿到的输入形状对不对；分三个枚举，编译期就排除了「对单个镜像跑 diff」这类组合。
3. **diff 保留自己的两版基类**：用户在澄清时否掉——两套写法表达同一件事，读 cache 的方式还和 CLI 不一致。
4. **只统一结构、不加 ObjC**：用户在澄清时否掉——三类都能一处声明镜像、同时看两种语言，才算统一。
5. **ObjC 输出加在每个套件上**：暂不。SymbolTestsCore、SwiftUICore、SourceEditor、DVTProductsUI 的 ObjC 部分不是维护者常看的；需要时加一对一行测试即可。
6. **套件按镜像改名（如 `AppKitDyldCacheTests`）**：放弃。接口与 diff 的套件是维护者临时指向别的镜像的探针（任务报告里出现过改读 SnippetUI，未提交的实验在改读 AttributeGraph），按镜像命名会随手变得名不副实。

## 影响

### 源码兼容性（source compatibility）

纯测试改动，不涉及任何公开 API：IntegrationTests 不是 product，没有调用方。

### ABI 兼容性（条件项）

不适用 —— 本库以 SPM 源码分发，使用方每次重新编译；本提案也只改测试目标。

### 下游影响

本仓库只有 IntegrationTests 目标受影响，`Package.swift` 只为它多列一个已有的 MachOObjCSection product。下游仓库不依赖 IntegrationTests，无影响。维护者手动运行时用的测试名会变（见行为差异表）。

### 文档与示例

`Documentations/Internal/ABIEvolutionDesign.md:235` 的目录改成 `Tests/IntegrationTests/InspectionDumps/`。账本、任务报告与已落地提案里的旧套件名是历史记录，不改。

## API 演进与废弃策略

不适用 —— 没有公开 API 变化；旧测试名直接删除，不留别名。

## 落地步骤

验证一律在 Ultra 上做（本机是公司那台，不编大工程）：`queued-build swift build --build-tests`，scratch 用 `/Volumes/DerivedData/Agents.noindex/claude/SwiftPM/MachOSwiftSection-UnifyDiffAndInterfaceIntegrationSuites`，默认 Xcode 编一遍，再用 `DEVELOPER_DIR=…/Xcode-26.6.0.app`（CI 的版本）编一遍。第一次 26.6 构建若报 `no such module 'swift_section'`，是已知的构建顺序竞态，原样重跑。不运行 IntegrationTests。

1. **公共骨架与版本轴**（已完成，Ultra 上 Xcode 27.2 编过；26.6 首次撞上已知的构建顺序竞态，随第 2 步重跑通过）——`InspectionDumps/` 目录；`InspectionDumpTests.swift`、`VersionAxis.swift`、`EvolutionDumpTests.swift`、`EvolutionTests.swift` 移入并改名；两个旧文件只做机械改名以保持能编。
   - 行为：`evolutionSuitesKeepTheirFortyThreeTestsAndOutputs`
   - 行为：`multiVersionCacheAxisStoresOneAxisPerLanguage`
   - 行为：`simulatorFilePairGivesItsOwnAxisLabeledByVersion`
   - 行为：`objcSnapshotDocumentIsSharedByDiffAndEvolution`
2. **接口一类**（已完成，Ultra 上 Xcode 26.6 与 27.2 都编过，新文件没有警告）——`InterfaceDumpTests.swift`、`InterfaceTests.swift`；删除 `SwiftInterface/SwiftInterfaceBuilderTests.swift`；`Package.swift` 加 `ObjCDeclarationRendering`。
   - 行为：`swiftInterfaceMatchesTodaysConfigurationAndFileName`
   - 行为：`exportedOnlySuiteOverridesOneFlagInsteadOfTheWholeConfiguration`
   - 行为：`objcInterfaceConcatenatesEveryKindInObjcDumpOrder`
   - 行为：`readerSuffixComesFromAsMachOImage`
   - 行为：`appKitInterfaceSuitesWriteBothLanguages`
3. **diff 一类**（已完成，Ultra 上 Xcode 26.6 与 27.2 都编过，新文件没有警告）——`DiffDumpTests.swift`、`DiffTests.swift`；删除 `SwiftInterface/SwiftDiffableInterfaceBuilderTests.swift`。
   - 行为：`diffCachePairOpensEachCacheWhole`
   - 行为：`swiftReportWritesChangeListAndJSON`
   - 行为：`swiftInterfaceRendersUnifiedOnlyForFiles`
   - 行为：`objcReportUsesTheObjCDifferAndVerdictLine`
   - 行为：`diffWithFewerThanTwoVersionsPrintsANoteAndWritesNothing`
   - 行为：`xcodePairIsPickedByVersion`
4. **文档**（已完成）——`ABIEvolutionDesign.md`、账本一节、两个索引；提案状态与决策日志随代码同批提交。
   - 维护者比对（可选）：挑 `InterfaceTestSuite.MachOFileTests.swiftInterfaceFile` 与 `DiffTestSuite.SwiftUICoreTests` 的两个 file 测试前后各跑一次，`diff` 输出；cache 对的 diff 预期可能因整份打开而不同。

**收尾时必须判断两件事**（判断结果写进决策日志，不允许沉默跳过）：

- **要不要配套专题文章** —— 预计不需要：这是维护者手检目标的内部整理，用法写在新文件的文档注释里。
- **有没有引入新术语** —— 「版本轴」0110 已判断不登记；本提案不新增术语。

## 决策日志

| 日期 | 变更 | 说明 |
|------|------|------|
| 2026-11-26 | Created as Draft | 0110 合并演进套件后，用户要求把 diff 与单版本接口两类手检套件也按同样的结构统一。澄清一轮：两类都加上 ObjC 输出；diff 改用演进套件的版本轴（cache 对因此整份打开，与 CLI 一致）；维护者未提交的接口套件实验不碰，照提交版重构，由维护者自己收掉。 |
| 2026-11-26 | Accepted | 用户看过简报后批准，开始实现。 |
| 2026-11-26 | In Progress：第 1 步开工 | 功能分支从 `next` 切出，`next` 上已有本提案的 Accepted 提交。第 1 步首次在 Xcode 27.2 上编译时，`VersionAxis.swift` 缺 `FoundationToolbox` 与 `SwiftStdlibToolbox` 的导入（成员导入可见性检查），补了一个提交；Xcode 26.6 首次撞上已知的 `no such module 'swift_section'` 构建顺序竞态，第 2 步重跑通过。 |
| 2026-11-26 | 第 2、3 步完成 | `measuringPreparation` 改成泛型、返回准备好的值（详细设计原写不变）：ObjC 头文件要在计时的一步里拿回索引器，ObjC diff 要拿回两份快照文档。diff 的文件名按新版本的主镜像起（`[newVersion.primaryImage]`），不按整组镜像：diff 只读主镜像，单镜像时文件名与原来相同。带标注的接口两种格式各建一个渲染器，与现状一致。 |
| 2026-11-26 | 第 4 步完成 | `ABIEvolutionDesign.md` 的集成套件一段改成新目录并链接本提案；账本追加一节（节号落地时取）。只编译、没运行 IntegrationTests。 |
| 2026-11-26 | 收尾判断 | 不配使用指南或实现说明：这是维护者手检目标的内部整理，用法写在新文件的文档注释里。没有新术语：「版本轴」0110 已判断不登记。 |
| 2026-11-26 | 实现完成，待用户看过后收尾 | 功能分支已推送。合进 `.worktrees/MachOSwiftSection` 的 `next` 时被维护者在 `SwiftInterfaceBuilderTests.swift` 里未提交的实验挡住，没有合并。 |
| 2026-11-26 | 维护者的实验先提交，合并按新结构处理 | 用户要求先提交工作区的改动再合并收尾：实验（接口套件读 AttributeGraph、显示 C 导入类型、只印导出声明、注册 `SwiftInterfaceBuilderTypeNameProvider`）与 Xcode 自动改写的两个工作区设置各成一个提交进 `next`。合并时功能分支删掉的 `SwiftInterfaceBuilderTests.swift` 与实验的修改冲突，按澄清时的选择取删除：实验不搬进新套件，只留在历史里。合并后的代码与 Ultra 上编过的功能分支逐字相同（只多两个 Xcode 设置文件），没有重新验证。 |
| 2026-11-26 | Implemented，取号 0111 | 用户要求收尾，以 `--no-ff` 合进 `next` 并推送。没有收到改前改后的输出比对结果。 |
