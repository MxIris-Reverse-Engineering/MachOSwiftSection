# Draft - MachO 系列库统一 Swift 6 语言模式并开启三项 upcoming feature

- **状态**: In Progress
- **作者**: JH
- **创建日期**: 2026-11-20
- **最后更新**: 2026-11-20
- **所属愿景**: 无
- **关联提案**: 无
- **跨仓库**: 本提案是 MachOKit（fork）、swift-semantic-string、swift-demangling、MachOKitExtensions、MachOObjCSection 与本库共用的唯一提案。MachOKitExtensions 与 MachOObjCSection 的提案索引各加一行 cross-repository 指向这里（落地步骤第 1 步）；另外三个仓库没有提案目录，不加。
- **实现分支 / PR**: 六个仓库都是 `feature/swift6-mode-and-upcoming-features`。MachOKitExtensions 从 `origin/main` 切（它只有 `main`，本地那条没推过的 `next` 不能用），其余五个从各自的 `next` 切。
- **配套文档**: 待定 —— 落地时判断
- **网页版**: 同目录同名的 `.html`

## 摘要

六个 MachO 系列包里有五个已经在 Swift 6 语言模式下编译，complete strict concurrency checking 早已按错误执行；唯一的例外是 MachOKit（fork），它的清单还是 `swift-tools-version: 5.10`。本提案做两件事：把 MachOKit 升到 tools 6.2，让它也进入 Swift 6 语言模式（实测零错误，Sources 里零并发诊断）；然后在六个包的每个 Swift target 上开启 `ExistentialAny`、`MemberImportVisibility`、`InferIsolatedConformances` 三项 upcoming feature（编译器把它们标为 Swift 7 默认开启），开关在每份清单末尾用一个循环统一加，不逐个 target 写。源码改动约 900 处，绝大部分是补 `import` 与补 `any`；非测试 target 用 `swift package migrate` 自动改，测试 target 照诊断清单手改，另有 6 处工具处理不了、要先手工改好。同为 Swift 7 默认的 `NonisolatedNonsendingByDefault`、`InternalImportsByDefault`、`ImmutableWeakCaptures`，以及独立的 `StrictMemorySafety`，量过之后明确不做（见「非目标」）。

## 动机

**MachOKit 是整条栈里唯一不做 complete concurrency checking 的一层，而它被并发读得最狠。** 上层的读取路径会从多个线程同时读 MachOKit：同一份定义可以被任意多个任务并行打印（提案 0066），交叉引用的整 cache 扫描用 28 个线程（`CrossReferenceAnalysis`），MachOKit 自己的测试里也有 `Tests/MachOKitTests/DyldCacheConcurrentReadTests.swift`。fork 里修过一次懒加载缓存的竞态（MachOKit 0.55.102 一带）。今天 MachOKit 新写的全局可变状态、跨线程传的非 Sendable 值，编译器在 Swift 5 模式下一声不吭；另外五个包同样的写法会直接编不过。实测表明这一层其实已经是 Swift 6 干净的（见前期调研），差的只是清单里的模式声明。

**本库清单早就为这几项特性备好了设置，却一直没用上。** `Package.swift:1541` 的 `extension SwiftSetting` 定义了 `existentialAny`、`internalImportsByDefault`、`memberImportVisibility`、`inferIsolatedConformances`、`nonisolatedNonsendingByDefault`、`immutableWeakCaptures` 六个常量，全仓库没有一处引用。

**每个文件依赖哪些模块，今天写在源码里的和实际用到的对不上，模块一搬家就暴露。** 不开 `MemberImportVisibility` 时，只要某个模块被同一进程里任何地方加载过，它给已有类型加的 extension 成员在所有文件里都能用，哪怕文件根本没 import 它。实测本库有 480 处这样的用法（Sources 245、Tests 235）。近一年模块搬了三轮（提案 0055 按层分组、0097 拆层、0098 把三层迁出本库），每轮都要在编译失败之后才补 import。更要紧的是，名字解析结果随「碰巧加载了哪些模块」而变：探针里有两处现在就靠这种可见性才解析成今天的意思（`TypeAttributeInferrer.swift:143` 的 `switch` 只在看得见 `SwiftObjCInterop` 时才是完备的，`ABIDiffer.swift:289` 的 `.enum` 只在看得见 `MachOSwiftSection` 时才是枚举 case 而不是别处 extension 加的同名实例成员）。开了这项特性，每个文件的依赖都写在它自己的 import 里。

**`any` 关键字项目里已经在用，只是没人强制。** `CLAUDE.md` 要求打印路径把 existential 写成 `any P`（提案 0092），MachOKit 的 target 也早就开了 `ExistentialAny`；本库源码里还有 57 处、测试里 41 处没写 `any` 的 existential。开了之后由编译器统一要求。

**`InferIsolatedConformances` 将来会默认开启，现在开的代价最小。** 它决定 global-actor 隔离类型的 conformance 是否自动推断为隔离的。六个包的 Sources 里一处受影响的都没有，只有本库 `Tests/IntegrationTests` 里 33 处（6 个文件）。现在开就是把这 33 处标好，以后不用等到 Swift 7 模式时再回头处理。

## 前期调研

**方法。** 2026-11-20 在 `JHs-Mac-Studio-Ultra`（Xcode 27.2，Swift 6.4.2）上，把六个包的当前提交（MachOKit `af92491`、MachOKitExtensions `249897b`、MachOObjCSection `4796434`、swift-demangling `815fe91`、swift-semantic-string `f14caa4`、本库 `73c9ccb7`）各自 clone 到 `/Volumes/DerivedData/Agents.noindex/claude/Probes/Swift6Migration/`，以每个包为根各编一次 `swift build --build-tests`，依赖都解析远端版本。新特性用 SE-0486 的迁移模式（`-enable-upcoming-feature <名字>:migrate`）开启，只出带 fix-it 的警告、不挡编译，加 `-print-diagnostic-groups` 按诊断组计数，只统计包根目录下的文件。日志与改过的 clone 都还留在那个目录下。

**各包当前的语言模式。** 从 SwiftPM 生成的 PIF 读每个 target 的 `SWIFT_VERSION`：MachOKitExtensions、MachOObjCSection、swift-demangling、swift-semantic-string 与本库的 target 都是 `6`（tools-version 6.x 且没声明 `swiftLanguageModes` 时 SwiftPM 默认 Swift 6），MachOKit 的四个 target 是 `5`。不在本次范围内的 FrameworkToolbox 的 `FoundationToolbox` 也是 `5`。

**编译器认得哪些特性。** `swiftc -print-supported-features` 列出的 upcoming feature 里，`enabled_in: 7` 的有六个：`ExistentialAny`、`InternalImportsByDefault`、`MemberImportVisibility`、`InferIsolatedConformances`、`NonisolatedNonsendingByDefault`、`ImmutableWeakCaptures`；其中 `ExistentialAny`、`MemberImportVisibility`、`InferIsolatedConformances`、`NonisolatedNonsendingByDefault` 四个标了 migratable，可以用迁移模式和 `swift package migrate`。另有可选的 `StrictMemorySafety`（`-strict-memory-safety`），不属于任何语言模式。

**MachOKit 进 Swift 6 模式。** 两次编译：Swift 5 模式加 `-strict-concurrency=complete`，Sources 零并发诊断，Tests 3 条警告（`DyldCacheConcurrentReadTests.swift` 里 2 条 `SendableClosureCaptures`、1 条 `AddPreconcurrencyImport`）；直接 `-swift-version 6`（从构建数据库核实过 MachOKit、MachOArchiveKit、MachOKitReadable、MachOKitTests 四个 target 都拿到了 `-swift-version 6`），全部编过，零错误，只剩同样那 2 条测试警告和 1 条无关的 deprecation 警告。上游 p-x9/MachOKit 的 `main` 同样是 tools 5.10、没开严格并发；fork 比上游多 35 个提交、少 40 个。

**三项要开的特性，各包的改动处数（源码 / 测试）：**

| 包 | `ExistentialAny` | `MemberImportVisibility` | `InferIsolatedConformances` |
|---|---|---|---|
| MachOKit | 已开启（0） | 56 / 0（49 个文件） | 0 / 0 |
| MachOKitExtensions | 1 / 2 | 2 / 3 | 0 / 0 |
| MachOObjCSection | 0 / 2 | 15 / 21 | 0 / 0 |
| swift-demangling | 1 / 0 | 0 / 3 | 0 / 0 |
| swift-semantic-string | 6 / 0 | 0 / 0 | 0 / 0 |
| MachOSwiftSection | 57 / 41（73 个文件） | 245 / 235（373 个文件） | 0 / 33（全在 `IntegrationTests`） |

本库 `MemberImportVisibility` 的 245 处源码里有 189 处在测试基线生成器 `Sources/TestSupport/SwiftSectionFixtureSupport`，真正的库模块只有五十来处。

**量过、决定不做的四项（源码 / 测试）：**

| 特性 | 改动处 | 不做的原因 |
|---|---|---|
| `NonisolatedNonsendingByDefault` | 778 / 347，本库占 729 / 234 | 改的是运行语义：每个 nonisolated async 函数改为在调用方的 actor 上执行。RuntimeViewer 从主线程调用库入口时，解析工作会跑到主线程；保留现状要给上千个函数逐个加 `@concurrent` |
| `InternalImportsByDefault` | 4,124 行 import（约 1,400 个文件） | 没有迁移模式，只能手改；约一半必须保持 `public import`；下游可能因失去传递可见性而编不过 |
| `ImmutableWeakCaptures` | 约 0（全仓库只有本库 4 处 `[weak` 捕获） | 收益近乎为零，单独开不值得占一次提交；随将来的 Swift 7 模式一起处理 |
| `StrictMemorySafety` | 2,440 / 658 | 不属于 Swift 6 或 7；这是一个以 unsafe pointer 为本的二进制解析库，几千处 `unsafe` 标注只会是噪音 |

`InternalImportsByDefault` 的「约一半必须保持 public」是这样量的：在 clone 里把 Sources 的每条 import 改成 `public import`、清单里只给本包 target 开这项特性，再数编译器报的 `UnusedImportAccess`（「public import 没被公开声明用到」）。MachOKit 320 条里 194 条可降为 internal，MachOKitExtensions 232 / 122，MachOObjCSection 320 / 157，swift-demangling 36 / 28，swift-semantic-string 6 / 2，本库 3,210 条里至少 1,513 条（有两个测试支撑文件因探针跳过了 `@testable import` 而没编完）。直接用 `-Xswiftc -enable-upcoming-feature InternalImportsByDefault` 不可行：它会连第三方依赖一起改导入规则，swift-fileio 等先编不过。

**`swift package migrate` 的实际表现（在本库 clone 上试跑）：**

- 非测试 target：在 258 个文件里套用了 300 个 fix-it（diff +304 / −57），然后在改清单那一步失败：本库的 target 写成 `extension Target` 上的静态常量，工具找不到 target（`unable to find target named 'Utilities' in package`），所以清单必须手改。退出码是 1，但源码已经改好。
- 测试 target：一处都不改，显式 `--target <全部测试 target>` 也是 `Applied 0 fix-its`；它构建时不带测试。测试部分只能照 `--build-tests` 的迁移警告手改。
- 构建一失败就一处都不改。`MemberImportVisibility` 的迁移模式并不只出警告：本库有 4 处直接报错，必须先手工补 import，`migrate` 才跑得起来：

  | 位置 | 报错 | 补什么 |
  |---|---|---|
  | `Sources/Declaration/SwiftAttributeInference/TypeAttributeInferrer.swift:143` | `switch must be exhaustive`（枚举 case 看不见） | `import SwiftObjCInterop` |
  | `Sources/Output/SwiftDiffing/ABIDiffer.swift:289` | `instance member 'enum' cannot be used on type 'TypeContextDescriptorWrapper'` | `import MachOSwiftSection` |
  | `Tests/SwiftInterfaceTests/ExtensionContainerUnificationTests.swift:164` | `.values` 落到了 dynamic member lookup | `import OrderedCollections` |
  | `Tests/SwiftIndexingTests/SymbolTestsCoreIntegrationTests.swift:135` | 同上 | `import OrderedCollections` |

- **`migrate` 补的 import 会遮蔽标准库的名字。** swift-semantic-string 公开声明了 `struct Error`（`Sources/Semantic/Components/Error.swift:8`）和 `struct Numeric`，与 `Swift.Error`、`Swift.Numeric` 同名；还有 `Argument`，与 ArgumentParser 的同名。文件一旦直接 `import Semantic`，裸写的 `Error` 就解析成 `Semantic.Error`。`migrate` 给本库 6 个文件加了 `import Semantic`，其中两处因此编不过：`Sources/Commands/SwiftSectionKit/ObjC/ObjCAPIRequests.swift:295` 与 `Sources/Commands/SwiftSectionKit/Swift/ABIEvolutionRequest.swift:180`（`enum …Error: Error` 被当成以 `Semantic.Error` 为 raw type），改成 `Swift.Error` 就好。危险的是不报错的情形：`catch let error as Error`、`is Error` 这类转型照样能编，只是变成永远失败的转型，编译器只给一条警告。
- 补完上面 6 处、`migrate` 跑完、清单里手加开关之后，Sources 全部编过；测试 target 从第一个失败的文件开始逐个报缺 import（`TypeNameRetentionTests.swift` 缺 `MachOKit`、`SymbolicationTests.swift` 缺 `MachOKitExtensions`），与警告清单一致。

**清单里给 C target 加 `swiftSettings` 是无害的。** `InternalImportsByDefault` 那轮探针在六份清单末尾用同一个循环给所有 target 追加了设置，包括 `MachOKitC`、`MachOSwiftSectionC`、`SwiftSymbolsRegistration` 这些 C target，六个包都照常编过。

## 提议方案

1. **MachOKit 进 Swift 6 语言模式。** `Package.swift` 第 1 行改成 `// swift-tools-version: 6.2`（与另外五个兄弟包一致）。tools 6.x 不声明 `swiftLanguageModes` 时默认 Swift 6，不必另写。清单末尾的 `extension SwiftSetting` 里那九项 Swift 6 已经默认开启的 upcoming feature（`ForwardTrailingClosures` 到 `GlobalConcurrency`）在 Swift 6 模式下是空操作，删掉；`SwiftSetting.allCases` 的 `CaseIterable` 扩展随之删除，改用下面的统一开关。`AccessLevelOnImport` 实验特性（只在 debug 开）保留不动，实现时如果编译器提示它多余再删。
2. **六个包的每个 Swift target 统一开启三项特性。** 每份清单在 `let package = Package(...)` 之后加一个循环，给除 `system`、`binary`、`plugin` 以外的所有 target 追加同一组设置；本库沿用 `Package.swift:1541` 已有的常量。test、macro、executable target 都包括在内，`IntegrationTests` 也开（它只编译不运行）。
3. **源码按三类处理。** 先手工改好「前期调研」里那 6 处（4 处补 import、2 处 `Swift.Error`）；再对非测试 target 跑 `swift package migrate --to-feature ExistentialAny,MemberImportVisibility,InferIsolatedConformances`，它在改清单那一步报错是预期的，以它报告的「Applied N fix-its」为准；测试 target 用 `--build-tests` 加三个 `:migrate` 开关构建，照警告逐条手改（补 import、补 `any`、给 `IntegrationTests` 的 conformance 标 `nonisolated`）。最后才加清单里的开关，正式开启后编一遍确认零错误。
4. **每加一条 `import Semantic`，就检查那个文件里裸写的 `Error`、`Numeric`、`Argument`。** 类型位置一律写成 `Swift.Error` / `Swift.Numeric`；`as Error`、`is Error` 之类的转型与 `catch` 模式逐个看。编译器的「cast always fails」警告按错误对待。
5. **从下往上落地，不为此单独发版。** 顺序是 MachOKit、swift-semantic-string、swift-demangling、MachOKitExtensions、MachOObjCSection、本库。这些设置只影响包自身的编译，不改任何公开 API，下游用的仍是已发布的版本，所以各仓库照各自的流程合进集成分支即可，随下一次正常发版带出去。

### 非目标

- 不开 `NonisolatedNonsendingByDefault`、`InternalImportsByDefault`、`ImmutableWeakCaptures`，也不开 `StrictMemorySafety`（原因见「前期调研」的第二张表）。
- 不动 FrameworkToolbox：它不属于 MachO 系列，`FoundationToolbox` 停在 Swift 5 模式与本提案无关。
- 不给 swift-semantic-string 的 `Error`、`Numeric`、`Argument` 改名：那是公开 API 的破坏性改动，下游全都要跟着改。本提案只在调用点写全限定名。
- 不清理现有的 `@unchecked Sendable`（本库 84 处）与 `nonisolated(unsafe)`（本库 37 处）：它们大多是锁保护的状态，部署目标 macOS 10.15 用不了 `Mutex`；它们在 Swift 6 模式下本来就合法。
- 不采用其他 Swift 6 时代的新语言特性（typed throws、`~Copyable`、`Span` 之类），那是逐处设计取舍，不是开关。
- 不把这些改动提给上游 p-x9/MachOKit：开关与补 import 只为我们自己的检查，按「fork 自用改动不提上游」的约定留在 fork。

## 改动地图

| 文件 / 类型 | 动作 | 改什么 | 为什么 | 步骤 |
|---|---|---|---|---|
| MachOSwiftSection `Documentations/Evolutions/draft-swift6-mode-and-upcoming-features.md`、同名 `.html` | 新增 | 本提案与网页版 | 唯一提案 | 1 |
| MachOSwiftSection `Documentations/Evolutions/README.md`、`Documentations/README.md` | 修改 | 登记本提案 | 索引 | 1 |
| MachOKitExtensions、MachOObjCSection `Documentations/Evolutions/README.md` | 修改 | 各加一行 cross-repository 指向本提案 | 跨仓库提案的约定 | 1 |
| MachOKit `Package.swift:1` | 修改 | `swift-tools-version` 5.10 → 6.2 | 进入 Swift 6 语言模式 | 2 |
| MachOKit `Package.swift:76`、`:145–171` · `extension SwiftSetting` | 修改 / 删除 | MachOKit target 不再拼 `SwiftSetting.allCases`；删掉九项 Swift 6 默认特性与 `CaseIterable` 扩展；末尾加统一开关循环 | Swift 6 模式下那九项是空操作；与另外五个包同一写法 | 2 |
| MachOKit `Sources/MachOKit/**`（49 个文件） | 修改 | 补 56 处 import | `MemberImportVisibility` | 2 |
| MachOKit `Tests/MachOKitTests/DyldCacheConcurrentReadTests.swift` | 修改（可选） | 消掉 2 条 `SendableClosureCaptures` 与 1 条 `AddPreconcurrencyImport` 警告 | Swift 6 模式下仍是警告，不挡编译 | 2 |
| swift-semantic-string `Package.swift`（第 94 行之后） | 修改 | 加统一开关循环 | 开启三项特性 | 3 |
| swift-semantic-string `Sources/Semantic/Components/AnyComponent.swift`、`Frozen/FrozenSemanticString+Codable.swift`、`SemanticString+Conformances.swift` | 修改 | 补 6 处 `any` | `ExistentialAny` | 3 |
| swift-demangling `Package.swift`（第 171 行之后） | 修改 | 加统一开关循环 | 开启三项特性 | 3 |
| swift-demangling `Sources/DemanglingTestingSupport/Required.swift` | 修改 | 补 1 处 `any` | `ExistentialAny` | 3 |
| swift-demangling `Tests/DemanglingTests/DefectRegressionTests.swift`、`NodeTests.swift`、`TransientRemangleParityTests.swift` | 修改 | 补 3 处 import | `MemberImportVisibility` | 3 |
| MachOKitExtensions `Package.swift`（第 390 行之后） | 修改 | 加统一开关循环 | 开启三项特性 | 4 |
| MachOKitExtensions `Sources/MachOKitExtensions/RequiredNonOptional.swift`、`String+.swift`，`Sources/MachODependencies/DependencyLoadName.swift` | 修改 | 1 处 `any`、2 处 import | 两项特性 | 4 |
| MachOKitExtensions `Tests/`（5 个文件：`FixupResolutionMemoTests`、`SelfBindResolutionTests`、`CPlusPlusSymbolIndexCensusTests`、`DependencyLoadNameTests`、`SymbolIndexStoreTests`） | 修改 | 2 处 `any`、3 处 import | 两项特性 | 4 |
| MachOObjCSection `Package.swift`（第 421 行之后） | 修改 | 加统一开关循环 | 开启三项特性 | 5 |
| MachOObjCSection `Sources/`（`MachOObjCSection` 9、`ObjCCodeReferences` 3、`ObjCMetadataSource`、`ObjCDeclarationRendering`、`ObjCInterface` 各 1） | 修改 | 补 15 处 import | `MemberImportVisibility` | 5 |
| MachOObjCSection `Tests/`（约 19 个文件） | 修改 | 21 处 import、2 处 `any` | 两项特性 | 5 |
| MachOSwiftSection `Sources/Declaration/SwiftAttributeInference/TypeAttributeInferrer.swift` | 修改 | 加 `import SwiftObjCInterop` | 迁移模式下第 143 行的 `switch` 报不完备 | 6 |
| MachOSwiftSection `Sources/Output/SwiftDiffing/ABIDiffer.swift` | 修改 | 加 `import MachOSwiftSection` | 迁移模式下第 289 行 `.enum` 解析错 | 6 |
| MachOSwiftSection `Sources/Commands/SwiftSectionKit/ObjC/ObjCAPIRequests.swift:295`、`Sources/Commands/SwiftSectionKit/Swift/ABIEvolutionRequest.swift:180` | 修改 | `: Error` → `: Swift.Error` | `migrate` 补的 `import Semantic` 让 `Error` 解析成 `Semantic.Error` | 6 |
| MachOSwiftSection `Sources/**`（约 258 个文件，其中 `SwiftSectionFixtureSupport` 约 176 个） | 修改 | `swift package migrate` 的 300 个 fix-it：import 与 `any` | 两项特性 | 6 |
| MachOSwiftSection `Package.swift:1541–1548` 之后、`:1550` 的 Tuist 块之前 | 修改 | 加统一开关循环，用已有的 `.existentialAny`、`.memberImportVisibility`、`.inferIsolatedConformances` | 开启三项特性；放在 Tuist 块之前，Tuist 改写 target 时设置已经在了 | 6 |
| MachOSwiftSection `Tests/SwiftInterfaceTests/ExtensionContainerUnificationTests.swift`、`Tests/SwiftIndexingTests/SymbolTestsCoreIntegrationTests.swift` | 修改 | 加 `import OrderedCollections` | 迁移模式下 `.values` 解析错 | 7 |
| MachOSwiftSection `Tests/**`（约 180 个文件） | 修改 | 手改约 235 处 import、41 处 `any` | 两项特性；`migrate` 不改测试 | 7 |
| MachOSwiftSection `Tests/IntegrationTests/`（`OpaqueTypeTests`、`ObjCAPIEvolutionTests`、`ABIEvolutionTests`、`SwiftDiffableInterfaceBuilderTests`、`SwiftEvolutionInterfaceBuilderTests`、`SwiftInterfaceBuilderTests`） | 修改 | 33 处 conformance 标 `nonisolated` | `InferIsolatedConformances`，保持现有行为 | 7 |
| MachOSwiftSection `Documentations/Internal/ProjectEvolutionLog.md` | 修改 | 加一节 | 账本 | 9 |

## 架构图

改了什么：每个包的编译设置。

```text
package                  language mode          upcoming features (every Swift target)
-----------------------  ---------------------  ------------------------------------------------------
MachOKit (fork)          - Swift 5 (tools 5.10)  - 9 Swift-6-era features (MachOKit target only)
                         + Swift 6 (tools 6.2)   - ExistentialAny        (MachOKit target only)
                                                 + ExistentialAny, MemberImportVisibility, InferIsolatedConformances
swift-semantic-string      Swift 6 (tools 6.2)   + ExistentialAny, MemberImportVisibility, InferIsolatedConformances
swift-demangling           Swift 6 (tools 6.2)     Lifetimes (experimental, two targets, kept)
                                                 + ExistentialAny, MemberImportVisibility, InferIsolatedConformances
MachOKitExtensions         Swift 6 (tools 6.2)   + ExistentialAny, MemberImportVisibility, InferIsolatedConformances
MachOObjCSection           Swift 6 (tools 6.2)   + ExistentialAny, MemberImportVisibility, InferIsolatedConformances
MachOSwiftSection          Swift 6 (tools 6.3)   + ExistentialAny, MemberImportVisibility, InferIsolatedConformances
                                                   (statics already declared at Package.swift:1541, now used)
```

每份清单里开关的位置：

```text
Package.swift
  let package = Package(name:, platforms:, products:, dependencies:, targets: [...])
+ let upcomingFeatureSettings: [SwiftSetting] = [ExistentialAny, MemberImportVisibility, InferIsolatedConformances]
+ for target in package.targets where type is not system / binary / plugin {
+     target.swiftSettings = (target.swiftSettings ?? []) + upcomingFeatureSettings
+ }
  // MachOSwiftSection only: Tuist block (TUIST_MAPS_LOCAL_PACKAGE_TESTS) stays after the loop
```

迁移流程（每个包相同，本库多一步预修）：

```text
pre-fix sites migrate mode cannot express   (MachOSwiftSection: 4 imports + 2 Swift.Error)
  -> swift package migrate --to-feature ...  (non-test targets; fails at manifest step by design)
  -> swift build --build-tests -Xswiftc -enable-upcoming-feature -Xswiftc <Feature>:migrate
       -> fix every remaining warning under Tests/ by hand
  -> add the loop to Package.swift
  -> swift build --build-tests   (features on, zero errors)  -> swift test
  -> DEVELOPER_DIR=Xcode-26.6 swift build --build-tests      (CI toolchain, Swift 6.3)
```

## 详细设计

**统一开关**（swift-semantic-string、swift-demangling、MachOKitExtensions、MachOObjCSection、MachOKit 写在清单末尾）：

```swift
let upcomingFeatureSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

for target in package.targets where target.type != .system && target.type != .binary && target.type != .plugin {
    target.swiftSettings = (target.swiftSettings ?? []) + upcomingFeatureSettings
}
```

本库写在 `extension SwiftSetting`（`Package.swift:1541`）之后、Tuist 块（`:1550`）之前，用已有常量：

```swift
let upcomingFeatureSettings: [SwiftSetting] = [
    .existentialAny,
    .memberImportVisibility,
    .inferIsolatedConformances,
]

for target in package.targets where target.type != .system && target.type != .binary && target.type != .plugin {
    target.swiftSettings = (target.swiftSettings ?? []) + upcomingFeatureSettings
}
```

`static let` 在 `extension SwiftSetting` 里声明、在顶层代码里引用，清单求值顺序没有问题；另外三个未用的常量（`internalImportsByDefault`、`nonisolatedNonsendingByDefault`、`immutableWeakCaptures`）留着，将来开时直接加进数组。

**MachOKit 清单**改后的相关部分：

```swift
// swift-tools-version: 6.2

// ...
        .target(
            name: "MachOKit",
            dependencies: [
                // unchanged
            ],
            swiftSettings: [
                .enableExperimentalFeature("AccessLevelOnImport", .when(configuration: .debug)),
            ]
        ),
// ...

let upcomingFeatureSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

for target in package.targets where target.type != .system && target.type != .binary && target.type != .plugin {
    target.swiftSettings = (target.swiftSettings ?? []) + upcomingFeatureSettings
}
```

原来的 `extension SwiftSetting { static let forwardTrailingClosures … }` 与 `extension SwiftSetting: @retroactive CaseIterable` 整段删除。循环要放在清单里 `let machOKit = package.targets.first(...)` 那段 binary-parse-support 依赖处理之后或之前都可以，它只追加 `swiftSettings`。

**迁移命令**（以本库为例，在 Ultra 的功能 worktree 里，`queued-build` 前缀照写）：

```bash
queued-build swift package --scratch-path /Volumes/DerivedData/Agents.noindex/claude/SwiftPM/MachOSwiftSection \
    migrate --to-feature ExistentialAny,MemberImportVisibility,InferIsolatedConformances

queued-build swift build --build-tests \
    --scratch-path /Volumes/DerivedData/Agents.noindex/claude/SwiftPM/MachOSwiftSection \
    -Xswiftc -print-diagnostic-groups \
    -Xswiftc -enable-upcoming-feature -Xswiftc ExistentialAny:migrate \
    -Xswiftc -enable-upcoming-feature -Xswiftc MemberImportVisibility:migrate \
    -Xswiftc -enable-upcoming-feature -Xswiftc InferIsolatedConformances:migrate
```

第一条退出码是 1 属正常（改清单失败），看输出里的 `Applied N fix-its in M files`。第二条用来列出测试 target 里剩下的警告。日志带 ANSI 颜色与 OSC 8 超链接，按 `[#组名]` 计数前要先去掉转义；同一条诊断会打印两遍（一行摘要、一行带源码框的），按「文件:行:列 + 文字」去重。

**手改测试的规则**：`MemberImportVisibility` 的警告形如 `import of module 'X' is required`，在文件的 import 区按字母序补 `import X`（文件里已有 `@testable import X` 或 `@_spi(...) import X` 的，不重复加）；`ExistentialAny` 补 `any`；`InferIsolatedConformances` 的警告形如 `conformance of 'T' to 'P' should be marked 'nonisolated'`，照写 `nonisolated P`。补了 `import Semantic` 的文件按「提议方案」第 4 条检查。要是用脚本批量补 import，脚本先给用户看过再跑。

## 替代方案考量

- **MachOKit 保持 tools 5.10，只加 `.enableUpcomingFeature("StrictConcurrency")`。** Swift 5 模式下这只给 complete checking 的警告，不是错误；以后新代码出问题只是多一条警告，达不到另外五个包的约束力。否。
- **MachOKit 保持 tools 5.10，靠 `swiftLanguageVersions: [.version("6")]` 进 Swift 6。** 能少改一行，但 `swiftLanguageVersions` 在 tools 6 已废弃改名，与五个兄弟包写法不一致，跟上游同步时第 1 行的冲突也省不掉（上游以后升 tools-version 照样冲突）。否。
- **逐个 target 写 `swiftSettings:`，或让 `swift package migrate` 改清单。** 本库有 53 个 target，MachOKitExtensions 24 个、MachOObjCSection 19 个，逐个写容易漏，新加的 target 也得记着写；`migrate` 在本库的清单上直接失败。统一循环一处搞定，新 target 自动带上。选循环。
- **四项全开（再加 `NonisolatedNonsendingByDefault` 与 `InternalImportsByDefault`）。** 2026-11-20 的调研结果摆给用户之后，用户选了只开三项低风险的。理由见「前期调研」第二张表。
- **只开 `ExistentialAny` 与 `InferIsolatedConformances`，不开 `MemberImportVisibility`。** 后者是三项里改动最大、坑最多的（4 处迁移模式硬错误、`Semantic.Error` 遮蔽），但它正是动机里「每个文件的依赖写在自己的 import 里」的来源，而且坑都已经在探针里找全并给出了改法。保留。
- **给 swift-semantic-string 的 `Error` 改名，从根上避开遮蔽。** 公开 API 的破坏性改动，下游（本库、RuntimeViewer）都得跟着改，不属于这次的范围。只在调用点写 `Swift.Error`；改名另行考虑。

## 影响

### 源码兼容性（source compatibility）

**纯新增**——六个包都不改任何公开声明的签名。`any` 关键字、补的 import、`Swift.Error` 全限定、`nonisolated` conformance 都不改变声明的类型。MachOKit 换语言模式不改变它的公开 API：它的类型的 Sendable 标注早已写好（Swift 5 模式下就在），全局函数与类型没有 global actor 隔离，Swift 6 模式下推断出的隔离与今天相同。

upcoming feature 只作用于开启它的 target 本身的编译，不传给依赖它的包：下游即使不开这三项，也照样能用这六个包。

### ABI 兼容性（条件项）

不适用 —— 六个包都以 SPM 源码分发，使用方每次重新编译。

### 下游影响

- **本仓库**：所有 target 都开三项特性，包括 `IntegrationTests`（只编译不运行）、`SwiftSectionMacros`（macro target）、`swift-section` 等 executable target。
- **RuntimeViewer、MachOKitUI、SymbolViewer**：它们从源码编这六个包，编的时候用的是各包自己的设置，所以不用改任何代码；RuntimeViewer 的 Tuist workspace 重新生成后带上新设置。它们自己的 target 不受影响。
- **Tuist 开发 workspace**（`./TuistScript.sh`）：Tuist 读 `Package.swift` 求值后的结果，循环加的设置会照常映射过去；最后一步编一遍确认。
- **上游 p-x9/MachOKit**：不提交。fork 的清单第 1 行与 `extension SwiftSetting` 一段与上游不同，以后合上游 tag 时这两处会冲突，按 fork 的写法解决。

### 文档与示例

- 本库 `Documentations/Internal/ProjectEvolutionLog.md` 加一节；两个提案索引登记本提案；MachOKitExtensions、MachOObjCSection 的索引加 cross-repository 行。
- `CLAUDE.md` / `AGENTS.md` 不加条目：开了特性之后，漏写 `any` 或漏 import 会被编译器当场指出，agent 不会默默写错。唯一不报错的是 `Semantic.Error` 遮蔽下的转型，但那会有「cast always fails」警告；落地时再判断是否值得在本库 `CLAUDE.md` 加一句。
- 没有 DocC、README 或示例代码受影响。

## API 演进与废弃策略

- 没有被替代或废弃的 API。
- 不需要 semver major 跃迁；各仓库不必为此单独发版，随下一次正常发版带出。

## 落地步骤

1. **提案进集成分支，跨仓库登记** —— 改动地图第 1–3 行
   - 行为：`proposalIsListedInBothIndexes`、`siblingIndexesPointAtTheProposal`
2. **MachOKit 进 Swift 6 并开三项特性**（fork 的 `.worktrees/MachOKit-Swift6UpcomingFeatures`，从 `next` 切） —— 第 4–7 行
   - 行为：`machOKitTargetsCompileInSwift6Mode`、`machOKitBuildsWithAllThreeUpcomingFeatures`、`machOKitTestsPassSkippingAotCachePrintTests`（已知 5 个环境失败照旧）、`machOKitBuildsWithXcode26_6`
3. **swift-semantic-string 与 swift-demangling 开三项特性** —— 第 8–12 行
   - 行为：`semanticStringBuildsAndTestsWithUpcomingFeatures`、`demanglingBuildsAndTestsWithUpcomingFeatures`、`demanglingLifetimesFeatureStillEnabledInBothTargets`、两者 `buildsWithXcode26_6`
4. **MachOKitExtensions 开三项特性**（从 `origin/main` 切） —— 第 13–15 行
   - 行为：`machOKitExtensionsBuildsAndTestsWithUpcomingFeatures`、`buildsWithXcode26_6`
5. **MachOObjCSection 开三项特性** —— 第 16–18 行
   - 行为：`machOObjCSectionBuildsAndTestsWithUpcomingFeatures`、`buildsWithXcode26_6`
6. **本库 Sources：预修、migrate、开关** —— 第 19–22 行
   - 行为：`preFixedSitesCompileUnderMigrationMode`、`migrateAppliesAllNonTestFixIts`、`noFileImportingSemanticSpellsBareErrorOrNumeric`、`allNonTestTargetsBuildWithUpcomingFeatures`
7. **本库 Tests：手改剩余警告** —— 第 23–25 行
   - 行为：`allTestTargetsBuildWithUpcomingFeatures`（含 `IntegrationTests`）、`noMigrationWarningRemains`
8. **本库全量验证** —— 不改代码
   - 行为：`fullSuitePassesSkippingIntegrationTests`、`fullSuitePassesWithXcode26_6`、`renderingABVerificationIsByteIdentical`（`SystemFrameworkRenderingVerification.md` 的三条腿，对照组为 `next`；补 import 只改名字解析，A/B 用来兜住遮蔽一类不报错的变化）、`tuistWorkspaceGeneratesAndBuilds`、`noCastAlwaysFailsWarning`
9. **落地** —— 第 26 行
   - 行为：六个仓库按各自流程合进集成分支（MachOKitExtensions 推 `main`），本提案取号、状态改 Implemented，账本加一节

构建与测试一律远程在 Ultra 上跑（公司那台不编这些工程），产物目录用 `/Volumes/DerivedData/Agents.noindex/claude/SwiftPM/<包名>`；第 2–5 步的仓库互不依赖，可以并行。

**收尾时必须判断两件事**（判断结果写进决策日志，不允许沉默跳过）：

- **要不要配套专题文章** —— 预计不需要：没有新的调用方契约；「迁移模式的四类坑」已在本提案里写全。落地时再确认。
- **有没有引入新术语** —— 预计没有。

## 决策日志

| 日期 | 变更 | 说明 |
|------|------|------|
| 2026-11-20 | Created as Draft | 用户要求把 MachO 系列库迁到 Swift 6、开启严格并发，并评估开启全部新特性的改动量。实测发现五个包已是 Swift 6 模式，只有 MachOKit 停在 Swift 5 且切换后零错误；Swift 7 默认的六项特性逐项量过之后，用户选定「MachOKit 切 Swift 6 + `ExistentialAny`、`MemberImportVisibility`、`InferIsolatedConformances`」，另外三项与 `StrictMemorySafety` 不做 |
| 2026-11-20 | Accepted | 用户批准，开始实现 |
