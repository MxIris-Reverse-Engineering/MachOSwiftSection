# 0104 - 测试支持的通用部分迁入 MachOKitExtensions：两个包共用 MachOFixtureSupport 与 MachOTestingSupport

- **状态**: Implemented
- **作者**: JH
- **创建日期**: 2026-11-20
- **最后更新**: 2026-11-21
- **所属愿景**: 无
- **关联提案**: [0003（MachOKitExtensions）move-macho-infrastructure-modules](https://github.com/MxIris-Reverse-Engineering/MachOKitExtensions/blob/main/Documentations/Evolutions/0003-move-macho-infrastructure-modules.md)（`MachO` 前缀的模块归 MachOKitExtensions，本包的测试支持因此改名 `SwiftSection…`）；[0098 move-cross-reference-layers](0098-move-cross-reference-layers.md)（跨仓库迁移、由本包维护唯一提案的先例）；MachOKitExtensions 的 [0006-cplusplus-class-hierarchy](https://github.com/MxIris-Reverse-Engineering/MachOKitExtensions/blob/main/Documentations/Evolutions/0006-cplusplus-class-hierarchy.md)（它新加的测试辅助是本提案要合并的重复代码之一，已随 3.1.0 发布）；[0100-fixture-suite-macro](0100-fixture-suite-macro.md)（同一次讨论拆出的本包宏）；[0101-swift6-mode-and-upcoming-features](0101-swift6-mode-and-upcoming-features.md)（两个包开启的三项 upcoming feature，新代码照它们写）
- **实现分支 / PR**: 两个仓库同名 `feature/shared-macho-testing-support`。MachOKitExtensions 从 `main` 切出（3.1.0 与 Swift 6 迁移之后），worktree 在 `.worktrees/MachOKitExtensions-SharedMachOTestingSupport`；本包从 `next` 切出（0100、0101 之后），worktree 在 `.worktrees/MachOSwiftSection-SharedMachOTestingSupport`，第 5、6 步等 MachOKitExtensions 3.2.0 发布后在这里做
- **配套文档**: MachOKitExtensions 的实现说明 [Internal/TestingSupport.md](https://github.com/MxIris-Reverse-Engineering/MachOKitExtensions/blob/main/Documentations/Internal/TestingSupport.md)（落地前在它的功能分支上）
- **网页版**: 同目录同名的 `.html`

## 摘要

把本包测试支持里与 Swift 无关的部分搬到 MachOKitExtensions（下称 MKE），作为两个对外 product 发布，两个包从此共用一套。`MachOFixtureSupport` 不依赖 Testing：dyld cache 路径、打开 cache 与镜像、按本机架构选 slice、取进程内镜像、测试运行时用 `xcrun` 现编 dylib（clang 与 swiftc 都支持）、只转发不加逻辑的包装读取器。`MachOTestingSupport` 依赖 Testing：按镜像互斥的 trait `ExclusiveImageAccess`、测试基类 `MachOFileTests` / `MachOImageTests` / `DyldCacheTests`，以及从本包 `MachOSwiftSectionFixtureTests` 泛化出来、不绑定夹具的基类与闭包式跨读取器写法 `acrossAllReaders`。本包的 `MachOSwiftSectionFixtureTests` 变成它的子类，218 个子类与 429 处 `acrossAllReaders` 调用不动；MKE 自己十几处重复的辅助与约 25 个参数化的跨读取器测试改用共享版本。取本机 cache 统一为整个进程共用一份。MKE 先发 3.1.0（C++ 类恢复），本提案在 MKE 3.2.0 发布，本包随后改依赖。

## 动机

- **两个包各写一套，而且在分叉。** 自 MKE 2.0.0 接过 Mach-O 层以后，MKE 的测试没有可用的测试支持，只能各写各的（下表，路径相对 MKE 的 `Tests/`）。同一件事在两边实现不同：

  | 辅助 | 本包 | MKE |
  |---|---|---|
  | 取本机 cache | `DyldCache(path: .current)`，路径写死在 Cryptexes（`DyldSharedCachePath.swift:45`），每次重新打开（`DyldCacheTests.swift:30-32`） | `FullDyldCache.cachedHost`，由系统定位、整个进程只打开一次（`Sources/MachOKitExtensions/Cached/FullDyldCache+Cached.swift:13-27`）；另有 3 处写死 Cryptexes 路径（`DyldCacheImageSearchTests.swift:161`、`MachOAddressResolutionTests.swift:18`、`SharedDyldCacheOpeningTests.swift:30`） |
  | 选 slice | 固定选 `.arm64`，否则取第一个（`MachOFileTests.swift:19`） | 按进程的 CPU 类型与去掉标志位的子类型匹配（`CPlusPlusSymbolsTests/ClassIndexTestImages.swift:50-63`）；另有 3 处手写 `loadFromFile` 的 switch |
  | 现编 dylib | 17 个 `*Fixture.swift` 各自复制一份 `Process` 加 `Pipe` 的 swiftc 调用，结束时清理临时目录（如 `ExistentialAnyFixture.swift:100-140`） | 5 份 clang 调用（`FixupResolutionMemoTests.swift:122-176`、`SelfBindResolutionTests.swift:80-115`、`ClassIndexTestImages.swift:70-159`、`ClassIndexDemoTests.swift:34-60` 等），不清理 |
  | 归档 cache 路径 | `DyldSharedCachePath.macOS(_:)` / `iOS(_:)` | 3 份各写一遍（`DyldCacheImageIdentifierTests.swift:7-11`、`CacheRootDependencyClosureTests.swift:10-11`、`MachOAddressResolutionTests.swift:81`） |
  | 跨读取器 | `acrossAllReaders`，429 处，但写死 SymbolTestsCore | `@Test(arguments: Reader.allCases)` 参数化，约 25 处 |
  | 包装读取器 | `ForwardingMachOReader`，约束在本包的协议上 | `Support/ForwardingReader.swift`，约束在 `MachORepresentableWithCache`，internal |

- **MKE 的新功能还在继续加重复。** C++ 类恢复（MKE 0006）一次就新增了两份现编 dylib、一份选 slice、两份「cache 文件加进程内同一镜像」。
- **这些代码本该在 MKE。** 0003 定下 `MachO` 前缀的模块归 MKE，本包的测试支持为此从 `MachOFixtureSupport` / `MachOTestingSupport` 改名为 `SwiftSection…`（MKE 0003 的 `:102`），两个名字现在空着。

## 前期调研

**本包的测试支持**（`Sources/TestSupport/`，三个 target，都不是 product，`Package.swift:1020-1080`）

- `SwiftSectionFixtureSupport`：不 import Testing，`baseline-generator` 也用它。依赖 MachOKit、Demangling、SwiftSyntax 三件套、MKE 的 MachOFoundation / MachOReading / MachOResolving，以及本包的 SwiftSymbols、SwiftDump、SwiftDeclaration、SwiftIndexing、SwiftPrinting、SwiftInterface、MachOSwiftSectionC 和 TestingSupportC。
- `SwiftSectionTestingSupport`：放 Testing 基类，另依赖 MachOSwiftSection、SwiftSpecialization、Semantic。
- `SwiftSectionTestingSupportC`：`CDemangleTree.cpp`。
- 17 个测试 target 依赖 `SwiftSectionTestingSupport`（`Package.swift:1069-1411`），CrossReferenceAnalysisTests 只依赖 FixtureSupport。

**哪些可以搬**（只依赖 MachOKit、Foundation、Testing 或 MKE 已有的模块）

| 文件 | 去处 | 要改的 |
|---|---|---|
| `FixtureSupport/DyldSharedCachePath.swift`（无 import） | `MachOFixtureSupport` | `.current` 改由本机 cache 的 URL 得出，不写死 Cryptexes |
| `FixtureSupport/Extensions.swift`（只 import MachOKit；`UniformTypeIdentifiers` 在 `:3` 导入了没用） | `MachOFixtureSupport` | `loadFromFile(named:)` 的 `#filePath` 锚点（`:9`）改由调用方传入；`DyldCache`/`FullDyldCache` 的 `init(path:)`、`machOFile(named:)`、受 `SILENT_TEST` 控制的 `.print()` 原样 |
| `FixtureSupport/MachOFileName.swift`、`MachOImageName.swift` | `MachOFixtureSupport` | 封闭的 `package enum` 改成「struct 加静态成员」，SymbolTests 的条目（`MachOFileName.swift:20-26`、`MachOImageName.swift:26-27`）留在本包用 extension 补 |
| `FixtureSupport/XcodeMachOFileName.swift`（Foundation、Darwin） | `MachOFixtureSupport` | 同上改成 struct |
| `TestingSupport/ExclusiveImageAccess.swift`（只 import Testing） | `MachOTestingSupport` | 只留按 `String` 的初始化；按本包镜像名的便捷初始化（`:89-95`）留在本包 |
| `TestingSupport/TestActor.swift`、`ProcessMemory.swift`（Foundation） | `MachOFixtureSupport` | 无 |
| `TestingSupport/MachOFileTests.swift`、`MachOImageTests.swift`、`DyldCacheTests.swift`、`XcodeMachOFileTests.swift`（MachOKit、MachOFoundation、FixtureSupport） | `MachOTestingSupport` | 选 slice 改用统一的按进程 CPU 匹配；`DyldCacheTests` 的 `.current` 改为共用的本机 cache |
| `TestingSupport/MachOSwiftSectionFixtureTests.swift` 的跨读取器部分（`acrossAllReaders` `:104-118`、`acrossAllContexts` `:121-135`、`usingInProcessOnly` `:147-152`，上下文来自 MKE 的 MachOReading） | `MachOTestingSupport` 的新基类 `MachOFixtureTests` | 夹具改由子类描述；SymbolTestsCore 的加载（`:18-19`、`:70`）留在本包的子类里 |
| `SwiftSectionTestingSupportTests` 里的 `DyldSharedCachePathTests`、`ExclusiveImageAccessTests` | MKE 新测试 target `MachOTestingSupportTests` | 跟着代码走 |

**不搬**：`ForwardingMachOReader`（约束在 `MachOSwiftSectionRepresentableWithCache`，`:5`、`:27`）、`DemangleOptions`、`DumpableTests` / `Snapshot*Tests`、`CommentStructureContract`、`SwiftIndexEventCollector`、`DefinitionName+DeclaredNameForTesting`、`URL+`（依赖 swift-dependencies）、`FixtureLoadError`、`InProcessMetadataPicker`、177 个 Baseline 文件、5 个 Coverage 文件、17 个 Swift 夹具的内容（只把编译那段换成共享的编译器）、TestingSupportC、`ContinuousIntegrationTestFilterTests`。

**用量**（本包 `Tests/` 计数）：`acrossAllReaders` 429、继承 `MachOSwiftSectionFixtureTests` 218、`usingInProcessOnly` 73、`acrossAllContexts` 68、`.print()` 44、`ExclusiveImageAccess(` 42、继承 `MachOFileTests` 37、`machOFile(named:)` 32、`DyldCache(path: .current` 25、继承 `MachOImageTests` 13、继承 `DyldCacheTests` 5。

**测试本身不搬**：本包的 `CrossReferenceAnalysisTests` 测的是 MKE 的 `MachOCodeReferences` 等模块，但几乎每个文件都 import 本包的 `CrossReferenceAnalysis` 与 MachOObjCSection 的 `ObjCCodeReferences`，MKE 不能依赖它们。

**约束**

- 跨包使用只能是 `public`。全局 write-tests skill 的默认做法是包内 `TestingSupport` target、`package` 访问级别、不进 products；要给别的包用时另拆对外 product，对外 API 尽量小，能不 import Testing 就不 import（`references/testing-support.md` 第 11 节）。拆成不依赖 Testing 的 `MachOFixtureSupport` 与依赖 Testing 的 `MachOTestingSupport` 正是这条规则，也是本包当年的拆法（`Package.swift:1020-1050` 的注释）。
- MKE 的 `Package.swift` 末尾有 Tuist 适配块，只在 `TUIST_MAPS_LOCAL_PACKAGE_TESTS=1` 时给「被测试依赖、但不在 product 里」的 target 补 product。两个新 target 是正式 product，无条件声明，不靠它。
- 本包 `AGENTS.md` 规定 `#filePath` 定位源码的深度（0055），`MachOFileName` 从 `Sources/<Group>/<Target>` 往上爬三层到包根。搬到 MKE 后锚点必须由调用方传入。
- 本包 `AGENTS.md` 规定共享整进程状态的套件都要声明 `ExclusiveImageAccess(.TheFixture)`。trait 搬走后，规则与用法不变，只是类型来自 MKE。

## 提议方案

1. **MKE 新增两个 product**（3.2.0）：
   - `MachOFixtureSupport`（`Sources/TestSupport/MachOFixtureSupport`，不 import Testing）：`DyldSharedCachePath`、`MachOImageName` / `MachOFileName` / `XcodeMachOFileName`（可扩展的 struct）、打开 cache 与镜像的扩展、`hostSlice(of:)`、取进程内镜像（按锚点地址 `dladdr`、按名字）、「cache 里的文件与进程内同一镜像」成对返回、`FixtureCompiler`（clang 与 swiftc，同一份源码与参数只编一次，进程结束时清理临时目录）、`ForwardingReader`、`TestActor`、`ProcessMemory`、`.print()`。
   - `MachOTestingSupport`（`Sources/TestSupport/MachOTestingSupport`，import Testing，依赖前者与 MachOReading）：`ExclusiveImageAccess`、`MachOFileTests`、`MachOImageTests`、`DyldCacheTests`、`XcodeMachOFileTests`，以及新的 `MachOFixtureTests`。
2. **测试基类原样搬**：保留「继承基类拿到镜像」的写法，只改访问级别（`open` / `public`）与上面列出的必要改动。改成 Swift Testing trait 的写法以后另写提案。
3. **`MachOFixtureTests`：不绑定夹具的基类**。子类用一个 `MachOFixture` 值说明夹具从哪来（磁盘路径，或进程里某个锚点地址所在的镜像，以及是否要 `dlopen`）；基类据此建出 `machOFile`、`machOImage` 与 `fileContext`、`imageContext`、`inProcessContext`，提供 `acrossAllReaders`、`acrossAllContexts`、`usingInProcessOnly`，签名与本包现在的一致。
4. **本机 cache 统一为进程共用**：`DyldSharedCachePath.current` 与 `DyldCacheTests` 都经 `FullDyldCache.cachedHost` / `DyldCache.host` 的 URL，不写死路径；确实需要新实例的测试显式开一份（`DyldCache(path:)` 照旧可用）。
5. **跨读取器统一用闭包式**：MKE 约 25 个 `@Test(arguments: Reader.allCases)` 的测试改写成 `MachOFixtureTests` 子类里的 `acrossAllReaders`，比对两种读取器的结果相等后再断言。
6. **成对传入、单个闭包的重载**：本包 486 处 `acrossAllReaders` / `acrossAllContexts` 调用里，480 处的 `image:` 闭包只是把 `file:` 闭包里的读取器与被测对象换成 image 版（按读取器命名的被测对象也算在内）。新增两个同名重载，被测对象成对传入、只写一个闭包：`acrossAllReaders(fileSubject, imageSubject) { $0.offset }`；`acrossAllContexts(fileSubject, imageSubject) { subject, context in try subject.mangledTypeName(in: context) }`，`context` 是 `any ReadingContext`，被测 API 收 `some ReadingContext` 时经 SE-0352 隐式打开。先编译验证这两种写法对两种读取器与三种上下文都写得通，再把只差变量名的调用改成单闭包形式（实际改了 478 处）；三闭包形式保留给 8 处：6 处带 `inProcess:`（多一层 `asPointerWrapper`），2 处被测 API 的结果类型依赖上下文的 associated type，打开 `any ReadingContext` 后推不出类型。名字不变，本包按标识符识别跨读取器测试的 `SuiteBehaviorScanner`（`:150`）不受影响。
7. **MKE 自己的重复辅助全部换成共享版本**（动机一节的表）。
8. **本包随后改依赖**：两个 support target 依赖 MKE 的新 product，删掉搬走的文件；`MachOFileName` / `MachOImageName` 的 SymbolTests 条目改为对 MKE struct 的 extension；`ExclusiveImageAccess` 保留一个按本包镜像名的便捷初始化；`MachOSwiftSectionFixtureTests` 改成 `MachOFixtureTests` 的子类；17 个 Swift 夹具与 57 个测试文件里手写的 `xcrun` 调用改用 `FixtureCompiler`，70 处手写的选 slice 改用 `HostSlice`；`DyldCache(path: .current)` 的 25 处改为共用实例后，逐个复查依赖新实例的测试。
9. **Tuist 开发 workspace**（提案 0099）：`TuistScript.sh` 只给角色是 own-path 的包扫描「import Testing 的普通 target」并补 TestingMacros 插件路径（`:686-689` 的 `if role != "own-path"` 之后）。远程模式下 MKE 是 own-remote，它的 `MachOTestingSupport` 用了 `#expect` 等宏，编到它时会报 `plugin for module 'TestingMacros' not found`。改法：把 `testing_support_names` 那几行挪到 `if role != "own-path"` 之前（own-remote 包的检出目录已记在 `packages.tsv`）。在 Ultra 上用 `./TuistScript.sh test` 跑一次远程模式验证。这一条由维护 0099 的会话提醒。
10. **发版顺序**：MKE 先收尾 C++ 类恢复发 3.1.0；本提案的 MKE 部分从收尾后的 `main` 切分支，发 3.2.0；本包在 3.2.0 发布后改依赖（之前用 `USING_LOCAL_DEPENDENCIES=1` 本地验证）。

### 非目标

- 把测试基类改成 Swift Testing trait 的写法。
- 搬 Swift 专用的支持代码（夹具内容、baseline、coverage、快照对比、SymbolTestsCore 相关）。
- 搬测试本身（`CrossReferenceAnalysisTests` 等依赖本包与 MachOObjCSection 的模块）。
- 统一两个包的 `ForwardingMachOReader` / `ForwardingReader`：协议层级不同，本包那份保留。
- `@FixtureSuite` 宏（本包 170 个夹具套件开头的固定 5 行）：只涉及本包的 Swift 夹具覆盖率体系，另写一份本包的提案（已随 [0100-fixture-suite-macro](0100-fixture-suite-macro.md) 落地）。
- 把 `acrossAllReaders` 做成宏：每处只重复约一行，宏得按 `fileX`→`imageX` 的命名约定改写标识符，脆弱，也会让按标识符识别测试的扫描器失效；用上面的普通函数重载代替。
- MachOObjCSection、MachOKitUI 等其他仓库的测试改用新 product：各自另议。
- 给 MKE 加 CI（MKE 0003 记下的后续项，另写提案）。

## 改动地图

| 文件 / 类型 | 动作 | 改什么 | 为什么 | 步骤 |
|---|---|---|---|---|
| MKE `Package.swift` | 修改 | 新增 target 与 product `MachOFixtureSupport`、`MachOTestingSupport`，测试 target `MachOTestingSupportTests`；各测试 target 加依赖；Tuist 适配块留在文件末尾 | 对外发布 | 1 |
| MKE `Sources/TestSupport/MachOFixtureSupport/`（`DyldSharedCachePath`、`MachOImageName`、`MachOFileName`、`XcodeMachOFileName`、`DyldCache+Fixture`、`HostSlice`、`ProcessImages`、`FixtureCompiler`、`ForwardingReader`、`TestActor`、`ProcessMemory`、`Printing`） | 新增 | 从本包搬来并改为 `public`；名字类型改成 struct；`.current` 不写死；锚点由调用方传；编译器统一 clang 与 swiftc | 共用的夹具支持 | 1、2 |
| MKE `Sources/TestSupport/MachOTestingSupport/`（`ExclusiveImageAccess`、`MachOFileTests`、`MachOImageTests`、`DyldCacheTests`、`XcodeMachOFileTests`、`MachOFixture`、`MachOFixtureTests`） | 新增 | 搬来并改为 `open` / `public`；新的夹具基类与跨读取器写法，含成对传入、单个闭包的重载 | 共用的测试基类与 trait | 1、2 |
| MKE `Tests/MachOTestingSupportTests/` | 新增 | 搬来 `DyldSharedCachePathTests`、`ExclusiveImageAccessTests`；新增 `FixtureCompilerTests`、`HostSliceTests`、`MachOFixtureTestsTests` | 共享库自己的测试 | 1、2 |
| MKE `Tests/MachOKitExtensionsTests/`（`FixupResolutionMemoTests`、`SelfBindResolutionTests`、`DyldCacheImageSearchTests`、`DyldCacheImageIdentifierTests`、`DyldCacheSubCacheLookupTests`、`MachOReaderWrapperTests`、`Support/ForwardingReader.swift`、`Support/ChainedFixupsFixture.swift`） | 修改 / 删除 | 现编 dylib、本机 cache、归档 cache 路径、选 slice、包装读取器改用共享版本 | 去重 | 3 |
| MKE `Tests/MachOSymbolsTests/`、`MachODependenciesTests/`、`MachOAddressResolutionTests/`、`MachOReadingTests/` | 修改 | 同上 | 去重 | 3 |
| MKE `Tests/CPlusPlusSymbolsTests/`（`ClassIndexTestImages.swift` 删除，`CPlusPlusClassIndexStoreTests`、`CPlusPlusSymbolIndexStoreTests`、`ImagePointerSlotsTests`、普查、`ClassIndexDemoTests`、`CPlusPlusVirtualFunctionNamingTests`） | 修改 / 删除 | 夹具镜像改用 `MachOFixtureTests` 子类；约 25 个参数化测试改写成 `acrossAllReaders`；现编 dylib 改用 `FixtureCompiler` | 统一写法 | 3 |
| MKE `Documentations/Internal/TestingSupport.md`、`README.md`、索引 | 新增 / 修改 | 两个 product 的用法与契约（只能链接到测试 target、锚点由调用方传、共用本机 cache） | 对外说明 | 4 |
| 本包 `Package.swift` | 修改 | 两个 support target 依赖 MKE 的新 product；去掉不再需要的依赖 | 改依赖 | 5 |
| 本包 `Sources/TestSupport/SwiftSectionFixtureSupport/`（`DyldSharedCachePath`、`Extensions` 的通用部分、`MachOFileName`、`MachOImageName`、`XcodeMachOFileName`） | 删除 / 修改 | 删掉搬走的；`MachOFileName` / `MachOImageName` 只剩 SymbolTests 条目的 extension；本包的 `#filePath` 锚点在这里传给 MKE | 改用共享版本 | 5 |
| 本包 `Sources/TestSupport/SwiftSectionTestingSupport/`（`ExclusiveImageAccess`、`MachOFileTests`、`MachOImageTests`、`DyldCacheTests`、`XcodeMachOFileTests`、`TestActor`、`ProcessMemory`、`MachOSwiftSectionFixtureTests`、17 个 `*Fixture.swift`） | 删除 / 修改 | 删掉搬走的；`ExclusiveImageAccess` 只剩按本包镜像名的便捷初始化；夹具基类改成 `MachOFixtureTests` 子类；夹具的编译改用 `FixtureCompiler` | 改用共享版本 | 5 |
| 本包 `Tests/MachOSwiftSectionTests/` 里只差变量名的 478 处 `acrossAllReaders` / `acrossAllContexts` | 修改 | 改成成对传入、单个闭包的重载 | 去掉重复的 `image:` 闭包 | 5 |
| 本包测试里 57 个手写 `xcrun` 的文件、70 处手写选 slice | 修改 | 改用 `FixtureCompiler`、`HostSlice` | 去重 | 5 |
| 本包 `TuistScript.sh` | 修改 | `testing_support_names` 挪到 `if role != "own-path"` 之前 | 远程模式下给 MKE 的 `MachOTestingSupport` 补 TestingMacros 插件路径 | 5 |
| 本包 `Tests/SwiftSectionTestingSupportTests/` | 修改 | 删掉随代码搬走的两个测试 | 去重 | 5 |
| 本包用 `DyldCache(path: .current)` 的 25 处 | 复查 | 依赖新实例的显式开一份，其余改用共用实例 | 行为统一后的复查 | 5 |
| 本包 `AGENTS.md`、`Documentations/Internal/FixtureTestingAndContinuousIntegration.md`、`Documentations/Internal/Modules/README.md`、`ProjectEvolutionLog.md` | 修改 | 测试支持的来源、`ExclusiveImageAccess` 与 `acrossAllReaders` 的出处、锚点规则 | 文档同步 | 6 |

## 架构图

改了什么：

```text
MachOKitExtensions (package)
  MachOKit, MachOKitExtensions, MachOFoundation, MachOReading, ...      (unchanged)
+ MachOFixtureSupport  (product, no Testing)
+   DyldSharedCachePath, MachOImageName/MachOFileName (extensible structs)
+   HostSlice, ProcessImages, DyldCache+Fixture, FixtureCompiler (clang, swiftc)
+   ForwardingReader, TestActor, ProcessMemory, print()
+ MachOTestingSupport  (product, Testing)  -> MachOFixtureSupport, MachOReading
+   ExclusiveImageAccess, MachOFileTests, MachOImageTests, DyldCacheTests
+   MachOFixture, MachOFixtureTests (acrossAllReaders, acrossAllContexts, usingInProcessOnly)
~ Tests/*                                   -> MachOFixtureSupport / MachOTestingSupport

MachOSwiftSection (package)
~ SwiftSectionFixtureSupport  -> + MachOFixtureSupport
-   DyldSharedCachePath, generic Extensions, MachOFileName/MachOImageName enums
~   MachOFileName/MachOImageName              extensions: SymbolTests entries
~ SwiftSectionTestingSupport  -> + MachOTestingSupport
-   ExclusiveImageAccess, MachOFileTests, MachOImageTests, DyldCacheTests, TestActor, ProcessMemory
~   MachOSwiftSectionFixtureTests : MachOFixtureTests   (SymbolTestsCore fixture)
~   17 *Fixture.swift                         compile through FixtureCompiler
    Baseline, Coverage, Snapshot, ForwardingMachOReader, ...           (unchanged)
```

一个夹具测试的调用链：

```text
SomeSuite : MachOSwiftSectionFixtureTests (MSS) : MachOFixtureTests (MKE)
 ├─ class var fixture -> MachOFixture(SymbolTestsCore path, anchored at MSS's #filePath; dlopen)
 ├─ MachOFixtureTests.init
 │   ├─ hostSlice(of: url) -> machOFile;  dlopen + MachOImage -> machOImage
 │   └─ MachOContext(machOFile), MachOContext(machOImage), InProcessContext
 └─ acrossAllReaders(file: { ... machOFile ... }, image: { ... machOImage ... })
     └─ #expect(fromFile == fromImage)
```

## 详细设计

```swift
// MachOFixtureSupport
public struct DyldSharedCachePath: Hashable, Sendable, CustomStringConvertible {
    public let path: String
    public let versionLabel: String
    public init(path: String, versionLabel: String)
    public var url: URL { get }
    /// This Mac's cache, as the system locates it (`FullDyldCache.cachedHost`), labeled `current`.
    public static var current: DyldSharedCachePath { get }
    public static func macOS(_ version: String) -> DyldSharedCachePath
    public static func iOS(_ version: String) -> DyldSharedCachePath
}

public struct MachOImageName: Hashable, Sendable, ExpressibleByStringLiteral {
    public let name: String
    public init(_ name: String)
    public static let SwiftUI: MachOImageName       // spelled like the image: .AppKit, .Foundation, …
}

public struct MachOFileName: Hashable, Sendable {
    /// A path, absolute or relative to `anchor` — the caller's `#filePath`.
    public init(path: String, relativeTo anchor: URL? = nil)
    public let url: URL
    public static let Finder: MachOFileName         // system files: .Dock, .Freeform, simulator runtimes, …
}

public struct XcodeMachOFileName: Hashable, Sendable {
    public init(location: Location, name: String)
    public static func sharedFrameworks(_ framework: SharedFrameworks) -> XcodeMachOFileName   // and frameworks(_:), plugins(_:)
    public var url: URL { get }
}

public func loadFromFile(named fileName: MachOFileName) throws -> File
extension MachOImage { public init?(named imageName: MachOImageName) }
extension DyldCache { public convenience init(path: DyldSharedCachePath) throws; public func machOFile(named: MachOImageName) -> MachOFile? }
extension FullDyldCache { public convenience init(path: DyldSharedCachePath) throws; public func machOFile(named: MachOImageName) -> MachOFile? }

public enum HostSlice {
    public static var processCPU: CPU { get }
    /// The slice of a file for this process's CPU: same type and subtype, else same type.
    public static func machOFile(at url: URL) throws -> MachOFile
    public static func machOFile(in file: File, path: String = "") throws -> MachOFile
    public static func slice(among slices: [MachOFile]) -> MachOFile?
}

public enum ProcessImages {
    public static func image(containing address: UnsafeRawPointer) -> MachOImage?
    public static func path(ofImageContaining address: UnsafeRawPointer) -> String?
    public static func image(atPath path: String) -> MachOImage?
    /// The image of this Mac's cache at `path`, and the same image loaded here.
    public static func cacheFileAndLoadedImage(path: String) throws -> (file: MachOFile, image: MachOImage)
}

public struct FixtureCompiler: Sendable {           // macOS only
    public enum Language: Sendable { case c, cPlusPlus, swift }
    public static let shared: FixtureCompiler
    /// Compiles `source` into `lib<name>.dylib` (install name `@rpath/lib<name>.dylib`) once per
    /// process for the same name, language, kind, sources and arguments; the directory goes away
    /// when the process exits. Architecture, optimization and target come in `arguments`.
    public func dynamicLibrary(named name: String, language: Language, source: String, arguments: [String] = []) throws -> URL
    public func dynamicLibrary(named name: String, language: Language, sourceFiles: [FixtureSourceFile], arguments: [String] = []) throws -> URL
    /// The main executable `name`.
    public func executable(named name: String, language: Language, source: String, arguments: [String] = []) throws -> URL
    public func executable(named name: String, language: Language, sourceFiles: [FixtureSourceFile], arguments: [String] = []) throws -> URL
    public var productsDirectory: URL { get }
}

/// A file of a build, written under `name`; its extension tells the driver how to read it.
public struct FixtureSourceFile: Hashable, Sendable {
    public init(name: String, contents: String)
}

public struct ForwardingReader<Base: MachORepresentableWithCache, Declaration: ForwardingReaderDeclaration>: MachORepresentableWithCache

/// `print()` on `CustomStringConvertible` and `Error`, quiet when `MACHO_TESTING_SILENT=1`.
public enum TestOutput { public static let isSilent: Bool }

// MachOTestingSupport
public struct ExclusiveImageAccess: SuiteTrait, TestTrait, TestScoping {
    public init(_ imageName: String)
}

public struct MachOFixture: Sendable {
    public init(fileURL: URL, imageName: String, loadsIntoProcess: Bool)
    public init(imageContaining anchor: UnsafeRawPointer)
}

@MainActor
open class MachOFixtureTests: Sendable {
    open class var fixture: MachOFixture { get }
    public let machOFile: MachOFile
    public let machOImage: MachOImage
    public let fileContext: MachOContext<MachOFile>
    public let imageContext: MachOContext<MachOImage>
    public let inProcessContext: InProcessContext
    public init() async throws
    public func acrossAllReaders<Value: Equatable>(file: () throws -> Value, image: () throws -> Value, inProcess: (() throws -> Value)? = nil, sourceLocation: SourceLocation = #_sourceLocation) throws -> Value
    public func acrossAllContexts<Value: Equatable>(file: () throws -> Value, image: () throws -> Value, inProcess: (() throws -> Value)? = nil, sourceLocation: SourceLocation = #_sourceLocation) throws -> Value
    public func usingInProcessOnly<Value: Equatable>(_ work: (InProcessContext) throws -> Value, sourceLocation: SourceLocation = #_sourceLocation) throws -> Value

    /// The same work on the subject each reader gives: `work` runs on
    /// `fileSubject`, then on `imageSubject`, and the results must agree.
    public func acrossAllReaders<Subject, Value: Equatable>(_ fileSubject: Subject, _ imageSubject: Subject, sourceLocation: SourceLocation = #_sourceLocation, _ work: (Subject) throws -> Value) throws -> Value
    /// The same, reading through each subject's context: `fileContext` for
    /// `fileSubject`, `imageContext` for `imageSubject`.
    public func acrossAllContexts<Subject, Value: Equatable>(_ fileSubject: Subject, _ imageSubject: Subject, sourceLocation: SourceLocation = #_sourceLocation, _ work: (Subject, any ReadingContext) throws -> Value) throws -> Value
    /// The same work on each reader itself: `machOFile`, then `machOImage`.
    public func acrossAllReaders<Value: Equatable>(sourceLocation: SourceLocation = #_sourceLocation, _ work: (any MachORepresentableWithCache) throws -> Value) throws -> Value
}

// MachOFileTests, MachOImageTests, DyldCacheTests (the current cache is `FullDyldCache.cachedHost`),
// XcodeMachOFileTests: open classes with `open class var` hooks, `public init() async throws`.
```

- 签名以本包现有的为准，只把泛型参数改成完整的单词（本包的 `T` 换成 `Value`），调用点不变；`MachOFixtureTests` 的初始化因此保持 `async throws`。
- 上面的接口是实现后的样子；与开工前草稿的出入（`versionLabel`、静态成员的拼写、第三个 `acrossAllReaders` 重载、`.print()` 的静默开关等）逐条记在决策日志。
- `FixtureCompiler` 按「名字 + 语言 + 源码 + 参数」缓存产物，失败也缓存，锁保护；每份产物一个目录，失败时错误带命令与编译器 stderr 的全部内容。
- `MachOFixtureTests.fixture` 的默认实现 `fatalError`，提醒子类必须给出夹具；读不到夹具时初始化抛 `MachOFixtureError`。
- 契约与用法写在 MachOKitExtensions 的实现说明 `Internal/TestingSupport.md`。

## 替代方案考量

- **只在 MKE 内部统一，本包不动**：改动小，但两套继续分叉；用户选择两个包一起统一。
- **一个 product**：简单，但只想要路径与打开镜像的使用方也要链接 Testing；用户选择拆两个。
- **测试基类顺便改成 Swift Testing trait**：更现代，但本包 55 个、218 个子类都要改写，风险高；用户选择原样搬，改写另议。
- **保留「每次重开」与「共用」两种取 cache 的入口**：不动行为，但两套写法并存；用户选择统一为共用。
- **跨读取器统一用参数化**：每种读取器在报告里单独成用例，但本包 429 处都要改写；用户选择闭包式。
- **夹具用值类型组合**：更现代，但与「基类原样搬」不一致、两种形状并存；用户选择泛化基类。
- **与 C++ 类恢复一起发 3.1.0**：少发一个版本，但推迟已做完的功能；用户选择 C++ 先发。

## 影响

### 源码兼容性（source compatibility）

- MKE：纯新增两个 product；改的只有 MKE 自己的测试。
- 本包：只改测试支持与测试，对外 product 不变。测试代码的 import 从本包的 support target 换成 MKE 的 product（经本包 support target 的 `@_exported import` 转出，多数测试文件不用改）。

### ABI 兼容性（条件项）

不适用 —— 两个包都以 SPM 源码分发，使用方每次重新编译。

### 下游影响

- MKE 3.2.0 新增 product，不影响现有使用方（RuntimeViewer、MachOObjCSection、MachOKitUI）。
- MachOObjCSection、MachOKitUI 的测试以后可以改用这两个 product，各自另议。
- 本包依赖 MKE 的版本下限升到 3.2.0。

### 文档与示例

MKE 新增实现说明 `Internal/TestingSupport.md`、README 的 product 表；本包 `AGENTS.md` 里 `ExclusiveImageAccess` 与 `acrossAllReaders` 两条规则注明类型来自 MKE，`FixtureTestingAndContinuousIntegration.md` 更新锚点规则。

## API 演进与废弃策略

- 本包搬走的类型直接删除，不留废弃期：它们是 `package` 级别，只有本包自己的测试在用，同一批次改完。
- MKE 新 product 的公开 API 尽量小；名字类型用 struct 加静态成员，以后加镜像不破坏调用方。
- semver：MKE 3.2.0（minor）；本包对外 product 不变，随下一个常规版本。

## 落地步骤

MKE（3.2.0，从 C++ 类恢复收尾后的 `main` 切出）：

1. **两个 product 的骨架与搬来的代码**（完成）—— MKE `Package.swift`、`Sources/TestSupport/MachOFixtureSupport/`、`Sources/TestSupport/MachOTestingSupport/`、`Tests/MachOTestingSupportTests/`
   - 行为：`currentCachePathIsTheOneTheSystemLocates`
   - 行为：`archivedCachePathsKeepTheirLayout`
   - 行为：`hostSliceMatchesTheProcessSubtype`
   - 行为：`exclusiveImageAccessSerializesSuitesOfOneImage`（搬来）
   - 行为：`imageNamesAndFileNamesTakeExtensions`
2. **夹具基类与编译器**（完成）—— `MachOFixture`、`MachOFixtureTests`、`FixtureCompiler`
   - 行为：`fixtureTestsBuildBothReadersAndAllContextsFromAFile`
   - 行为：`fixtureTestsReachAnImageOfThisProcessByAnAnchor`
   - 行为：`acrossAllReadersReportsWhichReaderDiverged`
   - 行为：`compilerBuildsEachSourceOncePerProcess`
   - 行为：`compilerFailureCarriesTheDiagnostics`
   - 行为：`compilerBuildsSwiftAndCPlusPlus`
   - 行为：`pairedSubjectsRunOneClosureOnEachReader`
   - 行为：`pairedSubjectsOpenTheContextForAnAPITakingSomeReadingContext`（编译验证单闭包写法）
3. **MKE 的测试改用共享版本**（完成）—— 动机一节的表，以及 `Tests/CPlusPlusSymbolsTests/`
   - 行为：MKE 全部测试照常通过，跨读取器的约 25 个测试改写为 `acrossAllReaders` 后断言不变
   - 行为：仓库里不再有 `Process` 调用 `xcrun` 的测试辅助、写死 Cryptexes 路径的常量、手写的选 slice
4. **MKE 文档与发版**（完成，3.2.0）—— `Internal/TestingSupport.md`、README、索引；发 3.2.0

本包（MKE 3.2.0 发布后，从 `next` 切出）：

5. **改依赖、删重复**（完成）—— 本包 `Package.swift`、`Sources/TestSupport/`、`Tests/SwiftSectionTestingSupportTests/`、`DyldCache(path: .current)` 的 25 处
   - 行为：本包全部测试（`IntegrationTests` 除外，照 `AGENTS.md`）照常通过
   - 行为：`SymbolTestsCoreFixtureLoadsThroughTheSharedBaseClass`
   - 行为：17 个 Swift 夹具经 `FixtureCompiler` 编出、结果与改前一致
   - 行为：478 处跨读取器调用改成单闭包形式后，`SuiteBehaviorScanner` 认出的跨读取器测试数不变
   - 行为：`./TuistScript.sh test` 的远程模式在 Ultra 上编过 MKE 的 `MachOTestingSupport`
6. **本包文档**（完成）—— `AGENTS.md`、`FixtureTestingAndContinuousIntegration.md`、`Modules/README.md`、`ProjectEvolutionLog.md`

收尾判断：MKE 写实现说明（两个 product 的契约：只能链接到测试 target、锚点由调用方传、共用本机 cache）；不写使用指南；本包与 MKE 都没有新术语要登记（`ExclusiveImageAccess`、`acrossAllReaders` 已在本包术语里）。

## 决策日志

| 日期 | 变更 | 说明 |
|------|------|------|
| 2026-11-20 | Created as Draft | 用户希望把本包 TestingSupport 的通用部分搬到 MachOKitExtensions，统一两个包的测试用例。先由只读调研查清可搬与不可搬的部分、两边的重复与分叉，再经两轮澄清提问定下方案。 |
| 2026-11-20 | 两个包一起统一，走完整档 | 用户选择。否决：只统一 MKE 内部；先不做。 |
| 2026-11-20 | 拆成 `MachOFixtureSupport`（无 Testing）与 `MachOTestingSupport`（Testing） | 用户选择。否决：一个 product。依据 write-tests skill 对外 product 的规则与本包当年的拆法。 |
| 2026-11-20 | 测试基类原样搬 | 用户选择。否决：顺便改成 Swift Testing trait（另议）。 |
| 2026-11-20 | 本机 cache 统一为进程共用 | 用户选择。否决：两种入口并存。本包依赖新实例的测试逐个复查。 |
| 2026-11-20 | 跨读取器统一用闭包式 `acrossAllReaders` | 用户选择。否决：统一用参数化（本包 429 处要改写）。 |
| 2026-11-20 | 夹具基类泛化为 `MachOFixtureTests` | 用户选择。否决：值类型组合（两种形状会并存）。 |
| 2026-11-20 | MKE 先发 C++ 类恢复（3.1.0），本提案随 3.2.0 | 用户选择。否决：一起发 3.1.0。 |
| 2026-11-20 | 按事实或先例自定的四条 | 名字类型改成 struct、`#filePath` 锚点由调用方传（跨包后锚点位置变了）；`FixtureCompiler` 同时支持 clang 与 swiftc，本包 17 个与 MKE 5 个复制的编译代码都改用它；测试本身不搬（依赖本包与 MachOObjCSection 的模块）；提案由本包维护（0098 先例），用户确认。 |
| 2026-11-20 | 状态 → Accepted | 用户批准。实现等 MachOKitExtensions 的 C++ 类恢复收尾、发 3.1.0 之后开始。 |
| 2026-11-20 | 加入成对传入、单个闭包的 `acrossAllReaders` / `acrossAllContexts` 重载 | 用户问能否加宏减少测试样板。调研：486 处跨读取器调用里 480 处的 `image:` 闭包只是换了变量名，但每处只重复约一行；做成宏要按命名约定改写标识符，也会让按标识符识别测试的扫描器失效。用户选择改用普通函数重载，并把能改的调用改过去。另一处值得用宏的样板——170 个夹具套件开头的固定 5 行——用户选择另写一份本包提案（`@FixtureSuite`）。 |
| 2026-11-20 | 加入 `TuistScript.sh` 的改动 | 维护提案 0099 的会话提醒：远程模式下 MKE 是 own-remote，不在扫描 TestingMacros 插件路径的范围内，新的 `MachOTestingSupport` 会编不过。 |
| 2026-11-20 | 用量更正 | 本包手写 `xcrun` 的测试文件是 57 个（原写 17 个 Swift 夹具），手写选 slice 70 处；都改用共享版本。 |
| 2026-11-20 | 状态 → In Progress | 用户批准开工。前置都已就位：MachOKitExtensions 3.1.0 已发布；`@FixtureSuite`（0100）与 Swift 6 迁移（0101）已落地，两个包的每个 Swift target 都开启了 `ExistentialAny`、`MemberImportVisibility`、`InferIsolatedConformances`，新代码照这三项写。先做 MachOKitExtensions 的第 1–4 步；第 4 步的发版（3.2.0）不在开工的授权内，做到文档为止，发版另行确认。 |
| 2026-11-20 | MKE 第 1、2 步完成，合成一个提交 | 两步共用测试 target，第 1 步的选 slice 测试要用第 2 步的编译器造一个三架构的 fat 库，分开提交得各编一遍。新 target `MachOTestingSupportTests` 的 20 个测试在 Ultra 上通过（Xcode 27.2）。 |
| 2026-11-20 | `DyldSharedCachePath` 保留 `versionLabel`，`rawValue` 改名 `path` | 本包 `ABIEvolutionTests` 按它给版本轴命名。本包自己命名的几个 cache（`iOS_18_5` 等，路径在本机的 Generic 卷上）不搬，第 5 步用 extension 补回。 |
| 2026-11-20 | 名字类型的静态成员照镜像本名拼写（`.SwiftUI`、`.Foundation`），不按详细设计的草稿写成 `.foundation` | 成员的值就是镜像名；本包几百处调用照旧编译，第 5 步只补 SymbolTests 那几条。`XcodeMachOFileName` 也改成 struct（位置加名字），用静态函数保留 `.sharedFrameworks(.SourceKitSupport)` 的写法；找不到文件时不再 `fatalError`，读取时报错。 |
| 2026-11-20 | `.print()` 的静默开关改为运行时环境变量 `MACHO_TESTING_SILENT=1` | 原来是编译条件 `SILENT_TEST`，由本包清单加在自己的 target 上，搬到 MKE 后到不了 MKE 的模块。第 5 步要让本包 CI（以及 Tuist 的测试 scheme）设这个变量。 |
| 2026-11-20 | `MachOFixtureTests` 的初始化保持 `async throws`；新增第三个重载 `acrossAllReaders { machO in … }` | 前者照本包现有签名，有子类写了 `override init() async throws`。后者把两个读取器本身交给同一个闭包：MKE 的 C++ 测试要比的就是读取器，而 `MachOFile` 与 `MachOImage` 不能当成同一个泛型参数传给成对的重载。 |
| 2026-11-20 | 实现细节自定 | `FixtureCompiler` 每份产物单独一个目录，库之间用 `-L`、`-l` 链接，`strip -x` 改用链接参数 `-Wl,-x`；失败的结果也缓存。`HostSlice` 先找同 CPU 类型且子类型相同的 slice，再退到同类型，再找不到就报错，不再像本包那样退到第一个 slice；单架构文件不论 CPU 都直接用。`MachOFixture(imageContaining:)` 用 `dladdr` 拿到镜像的文件路径，所以不支持 shared cache 里的镜像（那种用 `ProcessImages.cacheFileAndLoadedImage(path:)`）。读不到夹具时抛 MKE 的 `MachOFixtureError`；本包第 5 步可以在子类里把它换成带重编说明的 `FixtureLoadError`。`DyldCacheTests` 读本机 cache 时用 `FullDyldCache.cachedHost` 和它的 `mainCache`。`ExclusiveImageAccess` 在 MKE 只有按字符串的初始化，同提案。 |
| 2026-11-20 | MKE 第 3 步完成 | `ClassIndexTestImages` 与测试里那份 `ForwardingReader` 删掉；5 处现编库改用 `FixtureCompiler`；写死 Cryptexes 的 3 处与归档 cache 的 3 处改用 `DyldSharedCachePath`；手写选 slice 的 6 处改用 `HostSlice`。`ChainedFixupsFixture` 故意读每一个 slice（要覆盖 x86_64 与 arm64e 两种指针格式），不算选 slice，保留。`CPlusPlusClassIndexStoreTests` 改成 `MachOFixtureTests` 的子类，17 个参数化测试改写为 `acrossAllReaders`，实际数比提案估的约 25 个少。 |
| 2026-11-20 | 跨读取器比较的是去掉偏移的形状 | 同一份数据在文件里与加载后的偏移不同，C++ 测试先把类与 vtable 投影成 `ClassShape`、`VirtualTableShape` 再比较；偏移之间的关系在闭包里各自算成布尔值或距离返回。改写时查出一处读取器之间的真实差别：另一个镜像里的基类，文件读出绑定所写的 `libc++.1.dylib`，进程里读出 dyld 找到符号的 `libc++abi.dylib`（被 libc++ 重新导出）。原测试只查名字含 `libc++`，两边都满足，属于既有行为，不是这次引入的；形状里只记「在另一个镜像」，各读取器分别判断是不是 libc++。 |
| 2026-11-20 | MKE 第 4 步的文档完成，实现完成（MKE 部分），待用户看过后收尾 | 新增实现说明 `Internal/TestingSupport.md`，README 的 product 表加两行，文档索引与提案索引登记（提案索引是跨仓库行）。验证在 Ultra 上（Xcode 27.2）：MKE 全量 `swift test` 271 个测试通过，原始退出码 0；带 `CPLUSPLUS_CLASS_CENSUS_FRAMEWORKS` 的 TSTables 与 Espresso 普查也通过（断言精确计数）。发 3.2.0 不在开工的授权内，等用户确认；第 5、6 步等 3.2.0 发布后在本包做。 |
| 2026-11-20 | `FixtureCompiler` 的锁改用 FrameworkToolbox 的 `OSToolbox.Mutex`，MKE 因此新增依赖 FrameworkToolbox（只有 `MachOFixtureSupport` 用） | 用户要求：不用 `NSLock`，尽量不写 `@unchecked Sendable`。标准库的 `Mutex` 要 macOS 15、`OSAllocatedUnfairLock` 要 macOS 13，MKE 的下限是 macOS 10.15，OSToolbox 的 `Mutex` 用法相同、没有版本限制。产物目录与退出时清理改成两个全局 `let`；`ProcessMemory` 的格式化器改为用时现建，去掉 `nonisolated(unsafe)`；测试里 `MachOFixtureTests` 子类多写的 `@unchecked Sendable` 删掉（MainActor 基类本就 Sendable）。MKE 全量测试通过，退出码 0。本包第 5 步同样不要再写 `NSLock`。 |
| 2026-11-20 | MKE 其余模块的 `NSLock` 也一并换成 `OSToolbox.Mutex`，随 3.2.0 发布 | 用户决定：FrameworkToolbox 本来就是 MSS 与 RuntimeViewer 的依赖。19 个文件、7 个库 target；每段临界区的范围保持不变（先查、出锁构建、再进锁写回的照旧）；能被编译器认作 `Sendable` 的类型去掉了 `@unchecked`，还持有 `DyldCache`、`FullDyldCache`、指针的 5 个保留并写明原因。非 `Sendable` 的值存进锁时用 `withLockUnchecked`（6 处），各有注释。MKE 全量测试与 TSTables、Espresso 普查通过，退出码 0。 |
| 2026-11-20 | MKE 撤掉 Linux 支持 | OSToolbox 的 `Mutex` 基于 `os_unfair_lock`，只在 Apple 平台上有，换锁后 Linux 编不过。用户选择撤掉承诺（否决：给 OSToolbox 补 Linux 实现；在 MKE 里按平台分开用标准库的 `Mutex`）。此前从没有 Linux CI，也没在 Linux 上验证过。MachOObjCSection 依赖 MKE，它对 Linux 的承诺随之失效。 |
| 2026-11-20 | MKE 的 `Sources/` 按层分组，两个测试支持 target 在 `Sources/TestSupport/` 下 | 用户要求照本包 0055 分组，MKE 另写了提案 0007-group-sources-by-layer，同一分支、随 3.2.0。本提案改动地图里 MKE 的源码路径随之更新。 |
| 2026-11-21 | MKE 部分合入 MachOKitExtensions `main` 并推送，未发版 | 用户看过后收尾：测试支持的两个 product、MKE 测试改用它们、全部 `NSLock` 换成 `Mutex`、撤掉 Linux 与 `Sources/` 分组（MKE 0007）一起进了 `main`，最终代码上 MKE 全量测试通过。3.2.0 还没发；本包第 5、6 步等它发布后在本分支继续。 |
| 2026-11-21 | 第 5 步的已知缺口：`FixtureCompiler` 还不能完全替代本包的 `CompiledFixture` | 本包 `Tests/CrossReferenceAnalysisTests/CompiledFixture.swift` 的 `build(libraryName:sources:compilerArguments:isExecutable:)` 能编可执行文件（`FileModeTests`、`FunctionStartOutsideTextTests` 两处用 `isExecutable: true`）、一次编多个源文件、按参数指定架构；MKE 3.1.0 之后的 `FixtureCompiler` 只把单个源字符串编成动态库。要么在发 3.2.0 之前给 `FixtureCompiler` 补可执行文件与多源文件，要么这几处在本包保留自己的辅助，待用户定。另：next 上新进的 `FunctionStartOutsideTextTests.anIndexKeepsTheReferencesOfAFunctionBelowText` 用到 `CompiledFixture.build(…isExecutable:)` 与 `InstructionEncoding.branchWithLink(at:to:)`，第 5 步若搬走或改名它们，这条测试一起改，本分支合 next 时会遇到它。 |
| 2026-11-21 | `FixtureCompiler` 补上可执行文件与多源文件，MKE 3.2.0 发布 | 用户选择发版前先补：新增 `executable(named:language:source:arguments:)`、两个收 `sourceFiles: [FixtureSourceFile]` 的重载，单段源码的写法不变；本包 `CompiledFixture.build` 的可执行文件、多源文件与指定架构（经参数 `-arch`）都能用它替代。`CompiledFixture.load` 的链接后改写、重新签名、再加载留在本包，在复制出的产物上做（共享编译器的产物是缓存，不能原地改）。MKE 全量测试通过，原始退出码 0；随后在 `main` 上打 3.2.0（附注 tag，同以往不建 Release 页面）。本包第 5、6 步可以开始。 |
| 2026-11-21 | 第 5 步第一部分：测试支持改接 MKE 3.2.0 | MKE 下限升到 3.2.0；两个 support target 依赖并 re-export `MachOFixtureSupport` / `MachOTestingSupport`，搬走的 12 个文件删除；SymbolTests 的文件名与镜像名、本包命名的 cache、按本包名字的 `ExclusiveImageAccess` 初始化留在本包作 extension。`ExclusiveImageAccess` 的 key 取镜像名（文件名取路径最后一段去扩展名），同一夹具按文件或按镜像声明仍互斥，新测试 `ExclusiveImageAccessKeyTests` 钉住这一点。`MachOSwiftSectionFixtureTests` 改为 `MachOFixtureTests` 的子类，读不到夹具时把 `MachOFixtureError` 转成带重编说明的 `FixtureLoadError`。MKE 也有公开的 `DeclaredWrapper` / `UndeclaredWrapper`，与本包同名标记冲突，`ForwardingMachOReader` 改用 MKE 的标记（读取器本身留在本包）。CI 加 `MACHO_TESTING_SILENT: 1`。`swift test --skip IntegrationTests` 2,914 个通过，退出码 0（基线 2,916：删 4 个搬走的测试，加 2 个）；IntegrationTests 与可执行文件都编过。 |
| 2026-11-21 | 第 5 步第二部分：现编与选 slice 改用共享版本 | 41 处现编改用 `FixtureCompiler`（5 个 Swift 夹具、交叉引用测试 11 处、其余 25 处），源文件名一律照旧（private 判别符由文件名哈希得出）；约 66 处手写选 slice 改用 `HostSlice`，故意选 arm64e 的 `StandaloneFileReferenceDumpTests` 照旧。`CompiledFixture` 只剩 `load`：经共享编译器编出后复制一份再改写、重签名、加载，不碰共享的缓存产物；`build` 与 `buildSwift` 删除。改过去的库 install name 从绝对临时路径变成 `@rpath/lib<名字>.dylib`；`ReferenceKindAndRouteTests` 的 Swift 库因模块名必须是 `Fixture` 改叫 `libFixture.dylib`（没有断言读文件名）。约 25 处共享编译器表达不了，保留手写，见后续项。`swift test --skip IntegrationTests` 2,914 个通过，退出码 0。 |
| 2026-11-21 | 后续项：`FixtureCompiler` 还替代不了的现编 | 留着手写的约 25 处要的是：产物名与 Swift 模块名不同（`lib<模块>-<变体>` 之类）；`-emit-module`、`.swiftinterface`、bridging header、modulemap 写到调用方选的路径；编完再 `strip` / `codesign`；先编 `.o` 再链接；另一套工具链（`DEVELOPER_DIR`）或 `--sdk iphonesimulator`；放进假系统根里由 install name 决定的路径。要全部收掉，`FixtureCompiler` 得加模块名参数、编译前就能拿到的产物目录和一个后处理步骤，留待以后另议（MKE 次版本）。 |
| 2026-11-21 | 第 5 步第三部分：跨读取器调用改成单闭包 | 486 处调用里 478 处改成成对传入、单个闭包（`acrossAllReaders` 418 处、`acrossAllContexts` 60 处），8 处保留三闭包：6 处带 `inProcess:`，2 处 `functionAddress(in:)` 的结果类型是 `Context.Address?`，依赖上下文的 associated type，打开 `any ReadingContext` 后推不出类型（`AccessibleFunctionRecordTests`、`AsyncFunctionPointerTests` 的 `fromContext`）。提案原估 480 / 6。`SuiteBehaviorScanner` 只看函数体与所在类里有没有这两个名字，前后对比 793 个测试方法，分类（跨读取器 593、只用进程内 61、只注册不读 139）与每个方法里的调用次数都不变。断言一行未动；`swift test --skip IntegrationTests` 2,914 个通过，退出码 0。 |
| 2026-11-21 | 第 5 步第四部分：本机 cache 共用、Tuist 远程模式 | `DyldCache(path: .current)` 等 27 处只读本机 cache，全部改用 `FullDyldCache.cachedHost`（要 `DyldCache` 的取它的 `mainCache`），`GenericSpecializationFixture` 也一并改；`FileMappingTests` 要在调低的描述符上限下打开这些文件，保留新实例并注明。缓存按镜像路径与 UUID 分，不认实例，共用不改变缓存行为。`TuistScript.sh` 的 `testing_support_names` 扫描挪到 `if role != "own-path"` 之前，own-remote 的包也扫；`Workspace.swift` 在设了 `MACHO_SWIFT_SECTION_SILENT_TEST=1` 时给测试 scheme 的环境加 `MACHO_TESTING_SILENT=1`；`TuistDevelopment.md` 同步。`swift test --skip IntegrationTests` 2,914 个通过，退出码 0。`./TuistScript.sh test` 远程模式退出码 65，没走到 MKE 的 `MachOTestingSupport`：`SwiftSectionTestingMacrosTests` 的 `@testable import SwiftSectionTestingMacros` 在 Tuist 里解析不到宏 target。这个测试 target 随 0100 进入 next，Tuist 的适配段没处理依赖宏 target 的测试，是 next 上已有的问题，与本提案无关；已确认远程模式的扫描结果含 `MachOTestingSupport`、生成的工程带 TestingMacros 插件路径、scheme 带 `MACHO_TESTING_SILENT=1`。这一条验证待那个问题修好后补跑。 |
| 2026-11-21 | 修好 Tuist workspace 的宏测试，补跑远程模式 | 用户选择在本分支一起修：清单末尾的 Tuist 适配段把依赖宏 target 的测试也拿掉（与依赖可执行 target 的测试同样处理），宏的展开测试只在 `swift test` 里跑。三个上游库清单末尾的同一段代码按约定该一起改，它们没有宏 target，这次没同步，`TuistDevelopment.md` 记了这一点。`./TuistScript.sh test` 远程模式退出码 0（`TEST SUCCEEDED`，约 26 分钟，2,953 个测试），编过了 MKE 的 `MachOTestingSupport`。 |
| 2026-11-21 | 实现完成，待用户看过后收尾 | 第 5、6 步都已完成。文档：`AGENTS.md`（`Sources/` 一节的锚点、测试一节的测试支持来源与本机 cache、`ExclusiveImageAccess` 的 key、静默变量、新增套件时的写法）、`FixtureTestingAndContinuousIntegration.md`（路径锚定与新的一节）、`Modules/README.md`、`TuistDevelopment.md`、`ProjectEvolutionLog.md`（节号落地时定）。不另写实现说明（契约在 MachOKitExtensions 的 `TestingSupport.md`），没有新术语。后续项：`FixtureCompiler` 还替代不了的约 25 处现编（见上）。 |
| 2026-11-21 | Tuist 适配段的「宏 target」一条同步到三个上游库 | 用户选择保持四份一致：MachOKitExtensions `main`、MachOObjCSection `next`、swift-demangling `next` 各一个提交并推送；三者都没有宏 target，设与不设 `TUIST_MAPS_LOCAL_PACKAGE_TESTS` 时清单解析结果与改前相同。不发版。 |
| 2026-11-21 | 状态 → Implemented，取号 0104 | 用户看过后收尾，合进 `next` 并推送。`next` 上先落地了 0103（跨引用测试的整份 cache 扫描限并发），所以本提案取号 0104、演进账本记为第 150 节。合并前把最新 `next` 合进本分支：只有 `Documentations/README.md` 与演进账本冲突，两边都保留；0103 新规则（`CrossReferenceAnalysisTests` 里不直接调 `DispatchQueue.concurrentPerform`，由 `ParallelScanSourceTests` 检查）合并后仍满足。合并结果上在 Ultra（Xcode 27.2）重跑：`swift test --skip IntegrationTests` 2,971 个通过，退出码 0；`./TuistScript.sh test` 远程模式 3,003 个通过、0 失败、7 个跳过，退出码 0。`next` 上 `./TuistScript.sh test` 因 `SwiftSectionTestingMacrosTests` 编不过的问题随本提案修好。文档判断：不另写实现说明或使用指南（两个 product 的契约在 MachOKitExtensions 的 `TestingSupport.md`），没有新术语；MachOKitExtensions 里指向本提案的链接一并改成 0104。后续项照旧：`FixtureCompiler` 还替代不了的约 25 处现编。 |
