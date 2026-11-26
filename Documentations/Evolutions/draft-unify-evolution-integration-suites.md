# Draft - IntegrationTests 的演进套件合并：Swift 与 ObjC 共用一套版本轴

- **状态**: Accepted
- **作者**: JH
- **创建日期**: 2026-11-26
- **最后更新**: 2026-11-26
- **所属愿景**: 无
- **关联提案**: [0082-image-group-evolution](0082-image-group-evolution.md)（镜像组的演进，本提案合并它在集成测试里加的四组镜像组套件）；[0080-objc-evolution-interface](0080-objc-evolution-interface.md)（ObjC 带标注头文件的那组套件）；[0061-dyld-shared-cache-path-versions](0061-dyld-shared-cache-path-versions.md)（版本轴按 `versionLabel` 命名、跳过没有元数据的版本）
- **实现分支 / PR**: `feature/unify-evolution-integration-suites`（worktree `.worktrees/MachOSwiftSection-UnifyEvolutionIntegrationSuites`）
- **配套文档**: 待定 —— 落地时判断
- **网页版**: 同目录同名的 `.html`

## 摘要

`Tests/IntegrationTests/` 里有四套演进（evolution）的维护者手检套件：Swift 的时间线报告、Swift 带标注的联合接口、ObjC 的时间线报告、ObjC 带标注的联合头文件，分在三个文件里，一共 21 个套件类、43 个测试。它们读的是同几条版本轴（哪几份 dyld cache、哪几个镜像），却各自把轴再定义一遍、互相引用对方的类属性，四条管线各自又把「单镜像」与「镜像组」写成两条几乎一样的路径。本提案把它们合成一套：新目录 `Tests/IntegrationTests/Evolution/` 下，版本轴只定义一次（一个轴一个套件类，共 10 个），轴按管线读的元数据（`__swift5_*` 或 `__objc_*`）各自筛出版本；四条管线收进一个协议，每条只写一遍，镜像组与单镜像在管线里用一个开关分开。每种输出在轴上仍是一对显式的一行测试（写文件 / 打到控制台），原有的 43 个「轴 × 输出」组合一个不增不减，输出文件名不变，只改测试名。只动 IntegrationTests，不碰库代码。

## 动机

维护者每次加一条轴或一种管线，都要在四个地方各改一遍，漏一处就悄悄不一致。现状里的具体重复：

1. **同一条轴定义了四次**。SwiftUI 加 SwiftUICore 这组镜像在默认三版本 cache 上的轴，分别在 `ABIEvolutionTestSuite.SwiftUIImageGroupDyldCacheTests`（`Tests/IntegrationTests/SwiftDiffing/ABIEvolutionTests.swift:239`）、`SwiftEvolutionInterfaceBuilderTestSuite.SwiftUIImageGroupDyldCacheTests`（`Tests/IntegrationTests/SwiftInterface/SwiftEvolutionInterfaceBuilderTests.swift:286`）、`ObjCAPIEvolutionTestSuite.SwiftUIImageGroupDyldCacheTests`（`Tests/IntegrationTests/ObjCDiffing/ObjCAPIEvolutionTests.swift:244`）、`ObjCEvolutionInterfaceTestSuite.SwiftUIImageGroupDyldCacheTests`（同文件 `:460`）各写一次；它在 51 份归档 cache 上的轴同样四次。AppKit 组的两条轴、AppKit 单镜像的两条轴在 ObjC 两组里各写两次。
2. **轴靠互相引用来对齐**。51 份归档 cache 的版本列表只在 `SwiftEvolutionInterfaceBuilderTestSuite.ArchivedDyldCacheTests.cacheVersions`（`SwiftEvolutionInterfaceBuilderTests.swift:200-266`）里，ObjC 两组和 Swift 报告那组都去引用这个 Swift 接口套件的类属性（`ObjCAPIEvolutionTests.swift:186-188`、`:225-227`、`:401-403`；`ABIEvolutionTests.swift:259-261`）。一个「Swift 接口套件」承担了「全体归档版本清单」的职责，改它的镜像或版本会牵动别的语言的套件。
3. **ObjC 的轴是继承 Swift 的轴再改一处**。`ObjCAPIEvolutionTestSuite.MultiVersionDyldCacheImageTests`（`ObjCAPIEvolutionTests.swift:152-158`）继承 `ABIEvolutionTestSuite.MultiVersionDyldCacheImageTests`（`ABIEvolutionTests.swift:174-218`），只为覆写 `isOnAxis(_:)`，把 `__swift5_*` 换成 `__objc_*`。两种语言真正不同的只有这一个判据，却因此多出一层基类，ObjC 两组的 12 个套件都挂在这层基类上。
4. **每条管线把单镜像与镜像组写成两遍**。Swift 报告的「索引一个镜像 → 冻结成快照 → 经 JSON 往返」写了两遍（`ABIEvolutionTests.swift:40-53` 与 `:105-119`）；Swift 接口、ObjC 报告、ObjC 头文件也都是「单镜像一组 private 准备函数 + string/file 两个入口」再加「镜像组一组 private 准备函数 + string/file 两个入口」，四条管线合计 16 个入口、8 个准备函数。`indexConfiguration` 在两个协议扩展里各写一份（`ABIEvolutionTests.swift:26`、`SwiftEvolutionInterfaceBuilderTests.swift:34`）。
5. **注释已经和代码对不上**。`ABIEvolutionTestSuite.DyldCacheTests` 与 `SwiftEvolutionInterfaceBuilderTestSuite.DyldCacheTests` 的注释写着读 AppKit（`ABIEvolutionTests.swift:220`、`SwiftEvolutionInterfaceBuilderTests.swift:137`），实际继承基类默认的 `.SwiftUI`（`ABIEvolutionTests.swift:184`）；而 ObjC 的同名套件确实读 AppKit。同名的 `DyldCacheTests` 在两种语言里读的是两个镜像，正是轴分散定义的后果。

## 前期调研

1. **四条管线的输入与差异**（逐行读过三个文件）：
   - Swift 报告：每个镜像 `SwiftDiffableInterfaceBuilder(configuration:in:)` + `prepare()` + `snapshot()`，包成 `ABISnapshotDocument` 经 `encoded()` / `decode(from:)` 往返；单镜像走 `ABIEvolutionBuilder().evolution(of: documents)`，镜像组走 `evolution(ofImageGroups:versions:)`；`ABIEvolutionReporter().report(_:)` 出文本，`ABIJSON.encoder()` 出 JSON；单镜像且两个版本时追加一行与 `ABIDiffer` 的结论对照。输出 `-Evolution.txt` / `.json`。
   - Swift 接口：`AnySwiftEvolutionInterfaceBuilder` 的 `versions:labels:` 或 `imageGroups:labels:` 构造器，`prepare()` 后 `printAnnotatedInterface()`，末尾加一行 `// ABI-breaking on this axis:`。输出 `-EvolutionInterface.swiftinterface`。
   - ObjC 报告：每个镜像 `ObjCInterfaceIndexer(machO:imagePath:suppliedClasses:)` + `prepare()`，`ObjCAPISnapshotBuilder(indexer:).snapshot()` 包成 `ObjCAPISnapshotDocument` 往返；单镜像 `ObjCAPIEvolutionBuilder().evolution(of:)`，镜像组 `evolution(ofImageGroups:versions:)`；两版本时对照 `ObjCAPIDiffer`。输出 `-ObjCEvolution.txt` / `.json`。
   - ObjC 头文件：`ObjCEvolutionInterfaceBuilder` 每个版本 `addVersion(indexer:machO:version:)` 或 `addVersion(images:version:)`，`build(availabilityPlatform:)`，末尾加一行 `// API-breaking on this axis:`。输出 `-ObjCEvolutionInterface.h`。
2. **单镜像与镜像组的输出不同，不能一律走镜像组**。`ABIEvolutionBuilder.evolution(ofImageGroups:versions:)`（`Sources/Output/SwiftDiffing/ABIEvolutionBuilder.swift:51-62`）给每个版本描述写 `imageNames`、按镜像记移动，而 `evolution(of:)`（`:16-27`）带上文档的 provenance；`AnySwiftEvolutionInterfaceBuilder.prepare`（`Sources/Output/SwiftInterface/AnySwiftEvolutionInterfaceBuilder.swift:189-194`）也按构造器记下的 `comparesImageGroups` 二选一。MachOObjCSection 的 `ObjCEvolutionInterfaceBuilder` 同样按加入的版本形态选路径（`../MachOObjCSection/Sources/ObjCInterface/ObjCEvolutionInterfaceBuilder.swift:269-275`：没有镜像组时走 `evolution(of:versions:)`，两种形态混用则抛 `singleImageVersionsMixedWithImageGroups`）。所以合并后要保留「这条轴比的是不是镜像组」这个开关，取值与现状一致：套件声明了不止一个镜像就是镜像组。
3. **文件命名在单镜像时两种写法相同**。`write(_:for:suffix:fileExtension:)` 用 `<buildVersion>-<镜像文件名>-<后缀>`，`write(_:forImageGroup:suffix:fileExtension:)` 用 `<主镜像 buildVersion>-<各镜像文件名用 + 连起来>-<后缀>`（`Tests/IntegrationTests/SwiftInterface/SwiftInterfaceTestSupport.swift:43-71`）。组里只有一个镜像时两者逐字相同，所以合并后一律用镜像组的写法，文件名不变。
4. **可用性平台两种语言拼法不同**。Swift 接口传 `"macOS"`（`SwiftEvolutionInterfaceBuilderTests.swift:272`，印成 `@available(macOS, …)`），ObjC 头文件传 `"macos"`（`ObjCAPIEvolutionTests.swift:407`，印成 `API_AVAILABLE(macos(…))`）；SwiftSectionKit 两边也各有一个拼写函数（`Sources/Commands/SwiftSectionKit/Swift/ABIEvolutionRequest.swift:201`、`Sources/Commands/SwiftSectionKit/ObjC/ObjCAPIRequests.swift:316`）。现状里只有归档轴的两种「接口」管线传平台，报告管线从不传。
5. **Swift Testing 不继承测试**。`@Test` 只登记在声明它的类型上，子类拿不到父类的测试——这就是现状每个子类都重写一遍 `evolutionFile()` / `evolutionString()` 的原因。合并后每个轴套件仍要自己声明测试，能省的是测试体（缩成一行）和轴的重复定义。
6. **为什么不用参数化测试**：`@Test(arguments:)` 一点就跑完全部参数；在 51 份归档 cache 的轴上，四条管线各要把 51 个版本整个索引一遍，一次要几个小时。维护者要的是在 Xcode 里单独点跑某一种输出，所以每种输出保留一对显式测试（用户选定）。
7. **IntegrationTests 不让 agent 运行**（`CLAUDE.md`「Never run `Tests/IntegrationTests/`」），所以本提案只能验证编译；输出是否与改前逐字相同，要维护者挑一条轴前后各跑一次比对。CI 的 `swift test` 会编译所有测试目标，IntegrationTests 也在内，而 CI 用 Xcode 26.6（`.github/workflows/macOS.yml:22`），所以要用 26.6 也编一遍。
8. **目录无需登记**：IntegrationTests 目标用默认路径 `Tests/IntegrationTests`（`Package.swift:1506`），新子目录自动收进来；Tuist 的映射按目标名列，不按文件（`Tuist/Package.swift:87`）。

## 提议方案

在 `Tests/IntegrationTests/Evolution/` 下用三个文件取代现在的三个演进文件：

1. **`EvolutionAxis.swift`：版本轴只定义一次**。
   - `EvolutionMetadataLanguage`（`swift` / `objc`）：管线读哪种元数据，`isCarried(by:)` 判镜像有没有对应的 `__swift5_*` / `__objc_*` 节。
   - `EvolutionAvailabilityPlatform`（目前只有 `macOS`）：轴给接口标可用性时用的平台，`swiftSpelling` 是 `"macOS"`、`objcSpelling` 是 `"macos"`。
   - `EvolutionImage`（镜像名 + `MachOFile`）、`EvolutionVersion`（标签 + 镜像，主镜像在前）、`EvolutionAxis`（版本、`comparesImageGroups`、`availabilityPlatform`）三个值类型，取代现在到处写的 `(label: String, images: [(imageName: MachOImageName, machO: MachOFile)])` 元组。
   - 基类 `MultiVersionDyldCacheImageTests` 挪到这里：初始化时每份 cache 打开一次，把套件列出的镜像里 cache 有的都收下（不按元数据筛），只要 cache 有主镜像就保留这份 cache；再为两种语言各算一条轴存下——镜像按该语言的元数据筛，主镜像被筛掉的版本不上这条轴。`isOnAxis(_:)` 覆写点删掉。
   - 默认三版本 cache 与 51 份归档 cache 的清单作为基类的两个 `static` 属性放在这里（`defaultMacOSCachePaths`、`archivedMacOSCachePaths`，后者带上 11.0.1 → 11.0、12.0.1 → 12.0 的标签换算），哪个套件都不再引用别的套件。
2. **`EvolutionDumpTests.swift`：四条管线各写一遍**。
   - 协议 `EvolutionDumpTests: SwiftInterfaceDumpTests` 只要求一个 `evolutionAxis(for:)`。
   - `EvolutionDumpKind`（`swiftReport` / `swiftInterface` / `objcReport` / `objcInterface`）对应 CLI 的四种输出，各自带它读的语言。
   - 协议扩展的 `dump(_:to:)` 是唯一入口：取轴、跑管线得到 `EvolutionDumpOutput`（后缀、正文、正文扩展名、可选的 JSON），再按 `EvolutionDumpDestination`（`.console` / `.file`）打到控制台或写文件，文件一律按最新版本的镜像组命名。
   - 每条管线一个 private 函数，内部按 `axis.comparesImageGroups` 选单镜像或镜像组的构建器入口；「一个镜像 → 一份往返过的快照」每种语言只写一个函数，两种形态共用。
3. **`EvolutionTests.swift`：十个轴套件**，挂在 `enum EvolutionTestSuite` 下。每个套件只写轴（cache、镜像、可用性平台）和测试，每种输出一对一行测试（`<种类>File` / `<种类>String`）：

   | 套件 | 轴 | 测试 | 取代 |
   |---|---|---|---|
   | `SwiftUIDyldCacheTests` | SwiftUI × 默认三版 | Swift 报告、Swift 接口、pack facade | ABI `DyldCacheTests`、Swift 接口 `DyldCacheTests` |
   | `SwiftUICoreDyldCacheTests` | SwiftUICore × 默认三版 | Swift 接口 | Swift 接口 `SwiftUICoreDyldCacheTests` |
   | `AppKitDyldCacheTests` | AppKit × 默认三版 | ObjC 报告、ObjC 头文件 | ObjC 两组的 `DyldCacheTests` |
   | `SwiftUIArchivedDyldCacheTests` | SwiftUI × 51 份归档，标 macOS 可用性 | Swift 接口 | Swift 接口 `ArchivedDyldCacheTests` |
   | `AppKitArchivedDyldCacheTests` | AppKit × 51 份归档，标 macOS 可用性 | ObjC 报告、ObjC 头文件 | ObjC 两组的 `ArchivedDyldCacheTests` |
   | `SwiftUIImageGroupDyldCacheTests` | SwiftUI + SwiftUICore × 默认三版 | 四种全有 | 四组各自的同名套件 |
   | `SwiftUIImageGroupArchivedDyldCacheTests` | SwiftUI + SwiftUICore × 51 份归档，标可用性 | 四种全有 | 四组各自的同名套件 |
   | `AppKitImageGroupDyldCacheTests` | AppKit + UIFoundation + CollectionViewCore + CoreAutoLayout × 默认三版 | ObjC 报告、ObjC 头文件 | ObjC 两组的同名套件 |
   | `AppKitImageGroupArchivedDyldCacheTests` | 同一组 × 51 份归档，标可用性 | ObjC 报告、ObjC 头文件 | ObjC 两组的同名套件 |
   | `SwiftUICoreSimulatorTests` | SwiftUICore 两个模拟器 runtime 文件（18.5 → 26.5） | Swift 报告 | ABI `SwiftUICoreTests` |

   测试数：5 + 2 + 4 + 2 + 4 + 8 + 8 + 4 + 4 + 2 = 43，与现状相同。可用性平台只影响两种「接口」输出；报告输出和现状一样从不标。

4. **`SwiftInterfaceTestSupport.swift`**：`write(_:forImageGroup:suffix:fileExtension:)` 改收 `[EvolutionImage]`。

**采用的假设**（用户可推翻）：

- 默认三版本轴上 Swift 一侧沿用实际读的 SwiftUI、ObjC 一侧沿用 AppKit，拆成两个轴套件，不借合并之机统一成 AppKit；过时的「AppKit」注释改正。
- 合并只保留现有的「轴 × 输出」组合，不顺手给轴补上别的管线；要补时只是在套件里加一对一行测试。
- 测试名改变（例如 `ABIEvolutionTestSuite.DyldCacheTests/evolutionFile()` → `EvolutionTestSuite.SwiftUIDyldCacheTests/swiftReportFile()`），旧名字不留别名——这是维护者手点的目标，没有脚本按名字调用它们（已 grep 过 `Scripts/` 与 `.github/`）。

### 非目标

- 不合并 diff 套件（`SwiftDiffableInterfaceBuilderTestSuite`）的两版本基类，也不改它读 cache 的方式；`SwiftUICoreSimulatorTests` 继续借用它的 `CrossVersionMachOFileTests`。
- 不动 `SwiftInterfaceBuilderTests.swift`（单镜像接口套件；工作区里有维护者未提交的改动）、MachOSymbols 里的重复，以及其它不属于演进的 IntegrationTests。
- 不改任何库代码、不改 CLI，也不新增 `Package.swift` 依赖。
- 不运行 IntegrationTests；输出比对由维护者手动做。

## 改动地图

| 文件 / 类型 | 动作 | 改什么 | 为什么 | 步骤 |
|---|---|---|---|---|
| `Tests/IntegrationTests/Evolution/EvolutionAxis.swift` · `EvolutionMetadataLanguage` | 新增 | `swift` / `objc`，`isCarried(by:)` 判 `__swift5_*` / `__objc_*` 节 | 取代 `isOnAxis(_:)` 覆写，两种语言的唯一差别收在一处 | 1 |
| 同上 · `EvolutionAvailabilityPlatform` | 新增 | `macOS`，`swiftSpelling` / `objcSpelling` | 两条接口管线拼法不同，轴只声明「标 macOS」 | 1 |
| 同上 · `EvolutionImage` / `EvolutionVersion` / `EvolutionAxis` | 新增 | 镜像、版本、轴三个 `Sendable` 值类型 | 取代嵌套元组，管线只认一种输入 | 1 |
| 同上 · `MultiVersionDyldCacheImageTests` | 新增（自 `ABIEvolutionTests.swift:174-218` 挪来） | 打开 cache、收镜像、按语言算两条轴；`defaultMacOSCachePaths` / `archivedMacOSCachePaths`；`availabilityPlatform` 类属性 | 轴只定义一次，版本清单不再挂在某个套件上 | 1 |
| `Tests/IntegrationTests/Evolution/EvolutionDumpTests.swift` · `EvolutionDumpTests` | 新增 | 协议要求 `evolutionAxis(for:)`；扩展里 `dump(_:to:)`、四条 private 管线、两个快照函数、`preparedObjCIndexer(of:)`、`indexConfiguration` | 取代四个 dump 协议的 16 个入口与 8 个准备函数 | 1 |
| 同上 · `EvolutionDumpKind` / `EvolutionDumpDestination` / `EvolutionDumpOutput` | 新增 | 四种输出、两种去处、一次输出的内容 | 测试体缩成一行 | 1 |
| `Tests/IntegrationTests/SwiftInterface/SwiftInterfaceTestSupport.swift` · `write(_:forImageGroup:suffix:fileExtension:)` | 修改 | 第 1 步加一个收 `[EvolutionImage]` 的重载，第 2 步删掉收元组的旧重载 | 镜像组命名改用新值类型；分两步保证每步都能编 | 1、2 |
| `Tests/IntegrationTests/Evolution/EvolutionTests.swift` · `EvolutionTestSuite` | 新增 | 十个轴套件，43 个一行测试，沿用旧套件里仍成立的注释（11.x 方法名、镜像何时加入组等） | 合并后的套件 | 2 |
| `Tests/IntegrationTests/SwiftDiffing/ABIEvolutionTests.swift` | 删除 | 整个文件 | 被合并 | 2 |
| `Tests/IntegrationTests/SwiftInterface/SwiftEvolutionInterfaceBuilderTests.swift` | 删除 | 整个文件 | 被合并 | 2 |
| `Tests/IntegrationTests/ObjCDiffing/ObjCAPIEvolutionTests.swift` | 删除 | 整个文件（`ObjCDiffing/` 目录随之为空、删除） | 被合并 | 2 |
| `Documentations/Internal/ABIEvolutionDesign.md:235-243` | 修改 | 集成套件的路径与套件名改成新的 | 这段是现行说明，引用了被删的文件 | 3 |
| `Documentations/Internal/ProjectEvolutionLog.md` | 修改 | 落地时追加一节（节号落地时取） | 账本规则 | 3 |
| `Documentations/Evolutions/README.md`、`Documentations/README.md` | 修改 | 登记本提案（现在 `draft`，落地时换编号） | 索引 | 3 |

## 架构图

改了什么（文件与类型）：

```text
Tests/IntegrationTests/
- SwiftDiffing/ABIEvolutionTests.swift
-   protocol ABIEvolutionDumpTests              report: single-image path + image-group path
-   enum ABIEvolutionTestSuite
-     class MultiVersionDyldCacheImageTests     opens caches; isOnAxis = __swift5_*
-     DyldCacheTests, SwiftUIImageGroupDyldCacheTests, SwiftUIImageGroupArchivedDyldCacheTests, SwiftUICoreTests
- SwiftInterface/SwiftEvolutionInterfaceBuilderTests.swift
-   protocol SwiftEvolutionInterfaceDumpTests   interface: single-image path + image-group path
-   enum SwiftEvolutionInterfaceBuilderTestSuite   5 suites; ArchivedDyldCacheTests owns the 51 cache versions
- ObjCDiffing/ObjCAPIEvolutionTests.swift
-   protocol ObjCAPIEvolutionDumpTests          report: single-image path + image-group path
-   enum ObjCAPIEvolutionTestSuite
-     class MultiVersionDyldCacheImageTests : ABIEvolutionTestSuite.MultiVersionDyldCacheImageTests   isOnAxis = __objc_*
-     6 suites
-   protocol ObjCEvolutionInterfaceDumpTests    header: single-image path + image-group path
-   enum ObjCEvolutionInterfaceTestSuite        6 suites
+ Evolution/EvolutionAxis.swift
+   enum EvolutionMetadataLanguage              swift (__swift5_*) | objc (__objc_*)
+   enum EvolutionAvailabilityPlatform          macOS -> "macOS" | "macos"
+   struct EvolutionImage, EvolutionVersion, EvolutionAxis
+   class MultiVersionDyldCacheImageTests       opens caches once; one axis per language
+     static defaultMacOSCachePaths, archivedMacOSCachePaths
+ Evolution/EvolutionDumpTests.swift
+   protocol EvolutionDumpTests                 requires evolutionAxis(for:)
+   enum EvolutionDumpKind                      swiftReport | swiftInterface | objcReport | objcInterface
+   dump(_:to:) -> one private pipeline per kind
+ Evolution/EvolutionTests.swift
+   enum EvolutionTestSuite                     10 axis suites, 43 one-line tests
~ SwiftInterface/SwiftInterfaceTestSupport.swift
~   write(_:forImageGroup:) takes [EvolutionImage]
```

套件之间的引用（改前互相借轴，改后只认基类）：

```text
before                                              after
ObjCEvolutionInterfaceTestSuite.*                   EvolutionTestSuite.*Tests
  └─> ObjCAPIEvolutionTestSuite.*  (axes)             └─> MultiVersionDyldCacheImageTests
        └─> ABIEvolutionTestSuite.MultiVersion…             ├── defaultMacOSCachePaths
        └─> SwiftEvolutionInterfaceBuilderTestSuite         └── archivedMacOSCachePaths
              .ArchivedDyldCacheTests.cachePaths      EvolutionTestSuite.SwiftUICoreSimulatorTests
ABIEvolutionTestSuite.SwiftUIImageGroupArchived…        └─> SwiftDiffableInterfaceBuilderTestSuite
  └─> SwiftEvolutionInterfaceBuilderTestSuite                 .CrossVersionMachOFileTests (unchanged)
        .ArchivedDyldCacheTests.cachePaths
```

一次测试的调用链：

```text
@Test swiftReportFile()
└── dump(.swiftReport, to: .file)                          EvolutionDumpTests
    ├── evolutionAxis(for: .swift)                         stored per language at init
    ├── swiftReport(over: axis)
    │   ├── measuringPreparation
    │   │   └── swiftSnapshotDocument(of:label:)           every image of every version
    │   ├── axis.comparesImageGroups
    │   │   ? ABIEvolutionBuilder.evolution(ofImageGroups:versions:)
    │   │   : ABIEvolutionBuilder.evolution(of: documents)  (+ ABIDiffer cross-check when N == 2)
    │   └── EvolutionDumpOutput(suffix: "Evolution", text, "txt", json)
    └── .file    -> write(text, forImageGroup: newest.images, …) + write(json, …, "json")
        .console -> printResult(text)
```

## 详细设计

### `EvolutionAxis.swift`

```swift
import Foundation
import Testing
import MachOKit
import SwiftSectionFixtureSupport
import SwiftSectionTestingSupport

/// The metadata an evolution pipeline reads, and so which images join
/// its axis: an image without it has nothing to index.
enum EvolutionMetadataLanguage: Sendable {
    /// `__swift5_*` sections. AppKit kept its Swift API in
    /// `libswiftAppKit.dylib` until macOS 14, so a Swift AppKit axis
    /// reaching further back starts at 14.0.
    case swift
    /// `__objc_*` sections, which AppKit carries in every cache.
    case objc

    func isCarried(by machOFile: MachOFile) -> Bool {
        let sectionNamePrefix = switch self {
        case .swift: "__swift5_"
        case .objc: "__objc_"
        }
        return machOFile.sections.contains { $0.sectionName.hasPrefix(sectionNamePrefix) }
    }
}

/// The platform an evolution interface spells availability for, each
/// pipeline in its own spelling — what `--emit-available --platform` passes.
enum EvolutionAvailabilityPlatform: Sendable {
    case macOS

    /// `@available(macOS, …)`.
    var swiftSpelling: String { "macOS" }
    /// `API_AVAILABLE(macos(…))`.
    var objcSpelling: String { "macos" }
}

struct EvolutionImage: Sendable {
    let imageName: String
    let machOFile: MachOFile
}

struct EvolutionVersion: Sendable {
    let label: String
    /// The primary image first.
    let images: [EvolutionImage]

    var primaryImage: EvolutionImage { images[0] }
}

/// One ordered series of versions (oldest first), as one pipeline reads it.
struct EvolutionAxis: Sendable {
    let versions: [EvolutionVersion]
    /// Whether every version is a group of images (evolution proposal
    /// `image-group-evolution`), which picks the builders' image-group
    /// entry points: a group of one still reads differently from one image.
    let comparesImageGroups: Bool
    /// Set when every label is a version number, so the interfaces can
    /// spell each lifecycle one attribute or macro expresses.
    let availabilityPlatform: EvolutionAvailabilityPlatform?
}

@TestActor
class MultiVersionDyldCacheImageTests: Sendable {
    /// Retained: the extracted files resolve cross-image references
    /// through them while indexing.
    let caches: [FullDyldCache]
    private let axesByLanguage: [EvolutionMetadataLanguage: EvolutionAxis]

    /// Oldest first; each cache's `versionLabel` labels it on the axis.
    class var cachePaths: [DyldSharedCachePath] { defaultMacOSCachePaths }
    class var cacheImageName: MachOImageName { .SwiftUI }
    /// The images whose declarations make up one version, the primary
    /// image first; by default the primary image alone.
    class var cacheImageNames: [MachOImageName] { [cacheImageName] }
    class var availabilityPlatform: EvolutionAvailabilityPlatform? { nil }

    static var defaultMacOSCachePaths: [DyldSharedCachePath] { [.macOS_15_5, .macOS_26_5_2, .macOS_27_0] }
    /// One archived cache per macOS minor on the volume, 11.0.1 → 27.0,
    /// 11.0.1 and 12.0.1 labeled 11.0 and 12.0 (AppleDB offers no 11.0 or
    /// 12.0 image; an SDK's attributes name 11.0 and 12.0).
    static var archivedMacOSCachePaths: [DyldSharedCachePath] { … the 51 versions as today … }

    init() async throws {
        // Every cache holding the primary image is opened whole (as
        // `--dyld-shared-cache` opens it) and kept, with every listed image
        // it holds; each language's axis then keeps the images carrying its
        // metadata and drops a version whose primary image does not.
    }

    nonisolated func evolutionAxis(for language: EvolutionMetadataLanguage) -> EvolutionAxis {
        axesByLanguage[language]!   // both languages are computed at init
    }
}
```

`axesByLanguage` 在 `init` 里算好、以 `let` 存下：类属性（`cacheImageNames`、`availabilityPlatform`）是 `@TestActor` 隔离的，`nonisolated` 的协议实现读不到它们，读一个 `Sendable` 的 `let` 则可以。实现时若字典的强制解包不合适，改成两个 `let`（`swiftAxis`、`objcAxis`）加一个 `switch`。

### `EvolutionDumpTests.swift`

```swift
enum EvolutionDumpKind: Sendable {
    /// `swift-section evolution`: `-Evolution.txt` and `.json`.
    case swiftReport
    /// `swift-section evolution --interface`: `-EvolutionInterface.swiftinterface`.
    case swiftInterface
    /// `swift-section objc evolution`: `-ObjCEvolution.txt` and `.json`.
    case objcReport
    /// `swift-section objc evolution --interface`: `-ObjCEvolutionInterface.h`.
    case objcInterface

    var language: EvolutionMetadataLanguage {
        switch self {
        case .swiftReport, .swiftInterface: .swift
        case .objcReport, .objcInterface: .objc
        }
    }
}

enum EvolutionDumpDestination: Sendable {
    case console
    case file
}

struct EvolutionDumpOutput {
    let suffix: String
    let text: String
    let textFileExtension: String
    /// The machine-readable form a report also writes; `nil` for an interface.
    let json: String?
}

protocol EvolutionDumpTests: SwiftInterfaceDumpTests {
    func evolutionAxis(for language: EvolutionMetadataLanguage) -> EvolutionAxis
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension EvolutionDumpTests {
    var indexConfiguration: SwiftDeclarationIndexConfiguration {
        .init(showCImportedTypes: false)
    }

    /// Runs one pipeline over this suite's axis for its language and prints
    /// the text, or writes the text (and a report's JSON) named after the
    /// newest version's images.
    func dump(_ kind: EvolutionDumpKind, to destination: EvolutionDumpDestination) async throws {
        let axis = evolutionAxis(for: kind.language)
        let output = switch kind {
        case .swiftReport: try await swiftReport(over: axis)
        case .swiftInterface: try await swiftInterface(over: axis)
        case .objcReport: try await objcReport(over: axis)
        case .objcInterface: try await objcInterface(over: axis)
        }
        switch destination {
        case .console:
            printResult(output.text)
        case .file:
            guard let newestVersion = axis.versions.last else { return }
            try write(output.text, forImageGroup: newestVersion.images, suffix: output.suffix, fileExtension: output.textFileExtension)
            if let json = output.json {
                try write(json, forImageGroup: newestVersion.images, suffix: output.suffix, fileExtension: "json")
            }
        }
    }

    private func swiftReport(over axis: EvolutionAxis) async throws -> EvolutionDumpOutput
    private func swiftInterface(over axis: EvolutionAxis) async throws -> EvolutionDumpOutput
    private func objcReport(over axis: EvolutionAxis) async throws -> EvolutionDumpOutput
    private func objcInterface(over axis: EvolutionAxis) async throws -> EvolutionDumpOutput

    /// One image indexed and frozen, round-tripped through the persisted
    /// form: what the evolution consumes is what a saved baseline decodes to.
    private func swiftSnapshotDocument(of image: EvolutionImage, label: String) async throws -> ABISnapshotDocument
    private func objcSnapshotDocument(of image: EvolutionImage, label: String) async throws -> ObjCAPISnapshotDocument
}
```

各管线内部与现状逐条对应：

- `swiftReport`：`measuringPreparation` 里对每个版本的每个镜像取 `swiftSnapshotDocument`；`comparesImageGroups` 时把每组配成 `ABIImageSnapshot(imageName:snapshot:)` 交给 `evolution(ofImageGroups:versions:)`、版本描述只带标签，否则把每版唯一的文档交给 `evolution(of:)`，两版本时追加 `ABIDiffer` 对照行。JSON 用同一个 `ABIEvolution` 编码（现状单镜像路径把它算了两遍，结果相同）。
- `swiftInterface`：按开关选 `AnySwiftEvolutionInterfaceBuilder` 的 `imageGroups:` 或 `versions:` 构造器，平台传 `axis.availabilityPlatform?.swiftSpelling`；`measuringPreparation { try await builder.prepare() }`；正文 = `printAnnotatedInterface().string` 加 `// ABI-breaking on this axis:` 行；扩展名 `swiftinterface`，无 JSON。
- `objcReport`：同 `swiftReport`，换成 `ObjCAPIImageSnapshot`、`ObjCAPIVersionDescriptor`、`ObjCAPIEvolutionBuilder`、`ObjCAPIDiffer`、`ObjCAPIJSON`；对照行写 `API-breaking`。
- `objcInterface`：`measuringPreparation` 里逐版本 `addVersion(images:version:)` 或 `addVersion(indexer:machO:version:)`；`build(availabilityPlatform: axis.availabilityPlatform?.objcSpelling)`；正文加 `// API-breaking on this axis:` 行；扩展名 `h`，无 JSON。

### `EvolutionTests.swift`（一个套件的样子）

```swift
enum EvolutionTestSuite {
    /// SwiftUI together with SwiftUICore across every archived macOS cache:
    /// SwiftUI alone until 14.8, SwiftUICore joining it in 15.0 — where an
    /// evolution of SwiftUI alone reads every declaration moved into
    /// SwiftUICore as removed.
    final class SwiftUIImageGroupArchivedDyldCacheTests: MultiVersionDyldCacheImageTests, nonisolated EvolutionDumpTests, @unchecked Sendable {
        override class var cachePaths: [DyldSharedCachePath] { archivedMacOSCachePaths }
        override class var cacheImageNames: [MachOImageName] { [.SwiftUI, .SwiftUICore] }
        override class var availabilityPlatform: EvolutionAvailabilityPlatform? { .macOS }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func swiftReportFile() async throws { try await dump(.swiftReport, to: .file) }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func swiftReportString() async throws { try await dump(.swiftReport, to: .console) }

        // swiftInterface / objcReport / objcInterface: one pair each, the same shape
    }

    /// SwiftUICore across two simulator runtimes (iOS 18.5 → 26.5): the
    /// N == 2 case, whose printed pairwise cross-check must agree with the
    /// two-sided differ.
    final class SwiftUICoreSimulatorTests: SwiftDiffableInterfaceBuilderTestSuite.CrossVersionMachOFileTests, nonisolated EvolutionDumpTests, @unchecked Sendable {
        override class var oldFileName: MachOFileName { .iOS_18_5_Simulator_SwiftUICore }
        override class var newFileName: MachOFileName { .iOS_26_5_Simulator_SwiftUICore }

        nonisolated func evolutionAxis(for language: EvolutionMetadataLanguage) -> EvolutionAxis {
            EvolutionAxis(
                versions: [
                    EvolutionVersion(label: "18.5", images: [EvolutionImage(imageName: "SwiftUICore", machOFile: oldMachOFile)]),
                    EvolutionVersion(label: "26.5", images: [EvolutionImage(imageName: "SwiftUICore", machOFile: newMachOFile)]),
                ],
                comparesImageGroups: false,
                availabilityPlatform: nil
            )
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func swiftReportFile() async throws { try await dump(.swiftReport, to: .file) }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func swiftReportString() async throws { try await dump(.swiftReport, to: .console) }
    }
}
```

`SwiftUIDyldCacheTests` 另保留 `swiftInterfaceStringViaPackFacade`（`@available(macOS 14.0, …)`）：从 `evolutionAxis(for: .swift).versions` 取三个主镜像交给 `SwiftEvolutionInterfaceBuilder(configuration:versions:_:_:labels:)`，照旧不包 `measuringPreparation`（现状注释说明了原因：`@TestActor` 上的测试把隔离的闭包交出去会触发 region isolation 检查）。

### 与现状的行为差异

- **测试名**全部改变，套件从四个 enum 合到 `EvolutionTestSuite` 一个下。
- **空轴**：现状的 file 入口在轴上一个版本都没有时静默返回，string 入口抛 `fewerThanTwoVersions`；合并后两种都抛。只在 cache 卷没挂载、镜像全不在时出现，抛错更容易看出问题。
- **保留的 cache**：现状只留「主镜像在这条语言的轴上」的 cache，合并后留「有主镜像」的 cache（一个实例要同时服务两种语言）。在这十条轴上结果相同：SwiftUI 在每份归档 cache 里都有 Swift 元数据，AppKit 轴只跑 ObjC 管线、而 AppKit 在每份 cache 里都有 ObjC 元数据。
- **输出内容与文件名**不变（依据见前期调研第 2、3 条）；JSON 里的 `createdAt` 每次运行本来就不同。

## 替代方案考量

- **参数化测试**：每个轴一个 `@Test(arguments: EvolutionDumpKind.allCases)`。代码最短，但一点就跑全部管线，51 版归档轴要几个小时，也没法在跑之前单独挑一种输出。用户选了显式测试。
- **所有轴都走镜像组路径**（单镜像当作一个镜像的组）：能再删掉每条管线里的开关，但 `evolution(ofImageGroups:)` 给版本描述写 `imageNames`、不带 provenance，报告与 JSON 会变，和 CLI 单镜像的输出也不一致。否。
- **把默认三版本轴统一成 AppKit**（注释原本这么写）：Swift 一侧会从 SwiftUI 换成 AppKit，输出变了，维护者手里正在比的结果也就对不上。保留现状、改注释。
- **轴做成值、套件按轴参数化**：同参数化测试的问题，而且 Xcode 里看不到按轴分开的套件。否。
- **只抽公共函数、保留四个 enum**：能去掉管线里的重复，但轴的四重定义和互相引用还在，没解决用户点名的「Swift 和 ObjC 各有一套」。否。

## 影响

### 源码兼容性（source compatibility）

纯测试改动，不涉及任何公开 API：IntegrationTests 不是 product，没有调用方。

### ABI 兼容性（条件项）

不适用 —— 本库以 SPM 源码分发，使用方每次重新编译；本提案也只改测试目标。

### 下游影响

本仓库只有 IntegrationTests 目标受影响。下游仓库（RuntimeViewer、MachOKitUI 等）不依赖 IntegrationTests，无影响。

### 文档与示例

`Documentations/Internal/ABIEvolutionDesign.md:235-243` 引用了被删的 `ABIEvolutionTests.swift` 与 `ABIEvolutionTestSuite.DyldCacheTests`，改成新路径与套件名。账本、任务报告与已落地提案里的旧套件名是历史记录，不改。

## API 演进与废弃策略

不适用 —— 没有公开 API 变化；旧测试名直接删除，不留别名（理由见「采用的假设」）。

## 落地步骤

验证一律在 Ultra 上做（本机是公司那台，不编大工程）：`queued-build swift build --build-tests`，scratch 用 `/Volumes/DerivedData/Agents.noindex/claude/SwiftPM/MachOSwiftSection`，默认 Xcode 编一遍，再用 `DEVELOPER_DIR=…/Xcode-26.6.0.app`（CI 的版本）编一遍。不运行 IntegrationTests。

1. **新骨架与四条管线** —— 改动地图里 `EvolutionAxis.swift` 全部、`EvolutionDumpTests.swift` 全部、`SwiftInterfaceTestSupport.swift` 的新重载。旧的三个文件还在，与新代码并存，名字不冲突（旧基类嵌在 `ABIEvolutionTestSuite` 里）。
   - 行为：`evolutionAxisForSwiftDropsVersionsWhosePrimaryImageHasNoSwiftSection`
   - 行为：`evolutionAxisForObjCKeepsEveryCacheHoldingAppKit`
   - 行为：`imageGroupAxisKeepsAnImageOnlyWhereItsCacheCarriesTheMetadata`
   - 行为：`singleImageAxisUsesTheSingleImageBuilderEntryPoints`
   - 行为：`reportWritesTextAndJSONNamedAfterTheNewestVersionsImages`
   - 行为：`interfaceSpellsAvailabilityInItsOwnLanguagesSpelling`
   - 本步只编译，测试目标能编过即可。
2. **十个轴套件取代旧文件** —— `EvolutionTests.swift`；删除三个旧文件与空的 `ObjCDiffing/` 目录；删除 `write(_:forImageGroup:)` 收元组的旧重载。
   - 行为：`everyAxisPipelinePairOfTheOldSuitesHasOneTestNow`（43 个，逐一对照「提议方案」的表）
   - 行为：`noSuiteReadsAnotherSuitesClassProperties`
   - 行为：`archivedAxesTakeTheCacheListFromTheBaseClass`
   - 两个 Xcode 版本各编一遍。
3. **文档** —— `ABIEvolutionDesign.md`、账本一节、两个索引；提案状态与决策日志随代码同批提交。
   - 维护者比对：挑 `SwiftUIImageGroupDyldCacheTests`（四种输出都有、只开三份 cache）前后各跑一次 file 测试，`diff` 两次的输出（JSON 忽略 `createdAt`）。结果记进决策日志。

**收尾时必须判断两件事**（判断结果写进决策日志，不允许沉默跳过）：

- **要不要配套专题文章** —— 预计不需要：这是维护者手检目标的内部整理，用法写在新文件的文档注释里。
- **有没有引入新术语** —— 「版本轴」在旧注释里就在用；落地时查术语表，没有就判断是否值得登记。

## 决策日志

| 日期 | 变更 | 说明 |
|------|------|------|
| 2026-11-26 | Created as Draft | 用户要求把 IntegrationTests 里重复的演进测试抽出来，Swift 与 ObjC 各有一套套件，统一成一套。澄清一轮：范围只做演进（不顺带合并 diff 基类与 MachOSymbols 的重复）；每种输出保留一对显式测试，不用参数化测试；按规则写轻量档提案。 |
| 2026-11-26 | Accepted | 用户看过简报后批准，开始实现。 |
