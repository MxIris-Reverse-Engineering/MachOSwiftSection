# 使用指南：Tuist 开发 workspace

- **面向**: 在本仓库做日常开发、想让第三方依赖走二进制缓存的人；同时改本库和上游那几个库的人；改 `Package.swift` 的 target、依赖或测试的人（同步规则）
- **对应提案**: [0099-tuist-workspace](../Evolutions/0099-tuist-workspace.md)
- **最后更新**: 2026-11-21

`MachOSwiftSection-Tuist.xcworkspace` 是原生 `MachOSwiftSection.xcworkspace` 之外的第二条路，只供日常开发。它由 `./TuistScript.sh` 用 Tuist 生成：本库照常从源码编，可以跳转、可以编辑；原生 workspace 里放的五个上游库（MachOKit、MachOKitExtensions、MachOObjCSection、swift-demangling、swift-semantic-string）也从源码编；其余 27 个第三方包（swift-dependencies 一族、swift-collections、Capstone、swift-crypto、Yams……）预编进本机的 Tuist 二进制缓存，只编一次。

**`Package.swift` 仍是 target 与依赖的唯一定义。** Tuist 直接读它，把本库转换成 `MachOSwiftSection.xcodeproj`；手写的只有 Tuist 转换不了的那部分（`Tuist/CommandLine/Project.swift`，见下文）。

**发版、CI、`swift build` / `swift test` 和原生 workspace 都不走这里**，Tuist 这边出问题不影响它们。生成的工程文件都已忽略，不提交。

## 第一次使用

```bash
mise install                 # 装 mise.toml 钉的 Tuist（4.210.0，与 RuntimeViewer 相同）
./TuistScript.sh warm        # 解析依赖 → 把第三方依赖编进缓存 → 生成 workspace
open MachOSwiftSection-Tuist.xcworkspace
```

- **锁文件**：脚本每次解析都从本检出根目录的 `Package.resolved`（`swift build` 与原生 workspace 解析出的那份，不提交）开始，所以 Tuist 用的是同样的版本。没有这个文件时 Tuist 解析各清单允许的最新版本，并提示一句；新 worktree 里可以先从集成检出拷一份过来。解析完与它不一致时会列出差异，多半是换了 Xcode：有些包按 Swift 版本选用不同的清单。
- **Xcode**：脚本和 Tuist 都用 `DEVELOPER_DIR` 或 `xcode-select` 选中的那个，打开 workspace 也用同一个。二进制缓存按 Xcode 版本分开，换了 Xcode 要重新 `warm`。
- **缓存省多少**：2026-11-20 在 Ultra（M3 Ultra 28 核，Xcode 27.2）上，清空 DerivedData 后编 `swift-section`（Debug），不走缓存 63 秒，走缓存 46 秒；`warm` 把 70 个第三方 target 编成 xcframework 用了 60 秒。省下的是第三方依赖那部分，本库与上游库照旧从源码编；核心少的机器上没有测过。

## 日常用法

| 要做的事 | 做法 |
|---|---|
| 编辑、构建、运行 CLI | scheme `swift-section` |
| 跑本库的测试 | scheme `MachOSwiftSection Tests`：`Package.swift` 里除 `IntegrationTests` 外的全部测试 target |
| 命令行构建 / 测试 | `./TuistScript.sh build`、`./TuistScript.sh test`，`--` 之后的参数原样交给 `xcodebuild`（例如 `-- -only-testing:SwiftDumpTests`） |
| 增删了源文件 | `./TuistScript.sh generate`（Tuist 转换包时按 glob 展开文件；只改已有文件不用） |
| 改了 `Package.swift`、换了根目录的 `Package.resolved` | `./TuistScript.sh generate`：脚本发现清单或种子锁文件变了，会先重新解析 |
| 第三方依赖升级、换了 Xcode | `./TuistScript.sh warm`（只重编变了的） |
| 同时改上游库 | `./TuistScript.sh generate --local-dependencies`，见下文 |
| 不再用这个 workspace，或要把本检出让给 RuntimeViewer 的本地模式 | `./TuistScript.sh release` |

**别直接跑 `tuist generate` / `tuist install`。** 清单读的环境变量（哪些 target 留作源码、哪些测试进 scheme、要不要映射测试、本地模式的目录）都由脚本算好再传进去；直接跑 Tuist 拿不到它们，也没有下文的占用保护。

**生成出的工程只链接一套配置的缓存。** 默认按 Debug 生成；要在 Xcode 里编 Release，先 `./TuistScript.sh generate --configuration Release`，编完不带参数再 `generate` 回到 Debug。缓存也按配置分开预热（`warm --configuration Release`）。

**让测试少打输出**：同 CI 一样，在命令前加 `MACHO_SWIFT_SECTION_SILENT_TEST=1`（例如 `MACHO_SWIFT_SECTION_SILENT_TEST=1 ./TuistScript.sh test`）。它有两处效果：`Package.swift` 照旧给本库的测试 target 加编译条件 `SILENT_TEST`（手写的 `SwiftSectionCommandTests` 经脚本转成的 `TUIST_SILENT_TEST` 加）；生成的每个测试 scheme 在 TestAction 的环境里设 `MACHO_TESTING_SILENT=1`（`Workspace.swift`），MachOKitExtensions 的 `MachOFixtureSupport` 在测试进程里读它，让测试里的 `.print()` 不出声——这个开关是运行时的环境变量，编译条件到不了 MachOKitExtensions 的模块。变量改了要重新 `generate`（`test`、`build` 每次都会先生成）；在 Xcode 里直接跑这些 scheme 时，也是生成时的设置说了算。

## 用本地检出的上游库

同时改本库和上游库时，Tuist workspace 也能像原生 workspace 的本地依赖那样，直接编它们的本地检出，其余第三方依赖照旧走缓存：

```bash
./TuistScript.sh generate --local-dependencies    # 打开；之后不带参数的命令都沿用
./TuistScript.sh generate --remote-dependencies   # 回到锁文件钉住的版本（默认）
```

- **哪几个库、从哪取**：原生 workspace 的 `container:../<名字>` 成员，现在是上面五个；原生 workspace 加了库，这里自动跟上。默认从检出的上一级目录取，worktree 里就是 `.worktrees/` 下那组链接，所以编的是那组链接指向的检出（比如 `.worktrees/MachOKitExtensions` 指向 MachOKitExtensions 的主检出时，编的就是它当前所在的分支）。打开本地模式时设了 `TUIST_LOCAL_PACKAGE_CHECKOUTS`，就改从它指的目录取：每个库一个子目录，名字与库相同（SwiftPM 按目录名认包，经符号链接也一样按真实目录名认）。
- **效果**：`Tuist/Package.swift` 按路径声明这几个库，顶替依赖图里所有按 URL 声明的同名包。它们从本地源码编，没提交的改动也算；改已有文件后在 Xcode 里直接编就生效。它们的编译警告照常显示。
- **测试**：六个包的测试都进 workspace，每个包一个 scheme（`<包名> Tests`）。做到这一点要每个库的 `Package.swift` 末尾都有那段 `TUIST_MAPS_LOCAL_PACKAGE_TESTS` 适配块（见下一节）；MachOKitExtensions、MachOObjCSection、swift-demangling 已经加了，MachOKit 与 swift-semantic-string 现在用不着。某个库的检出停在加块之前的提交、又有 Tuist 不接受的测试时，脚本会警告并点名那个库，这一次整个 workspace 都不带测试（Tuist 对按路径声明的包只能全映射或全不映射），生成照常进行。上游库自己的测试里有读写死路径的（MachOKit 的 `AotCachePrintTests`、`ArchiveFileTests`，MachOObjCSection 的 `MachOObjCSectionTests` 读 `/Users/JH/Downloads/iOS18.5-SwiftUI`），在没有这些文件的机器上照样失败，与 Tuist 无关。
- **模式会记住**：记在 `Tuist/.local-dependencies`（已忽略），之后不带参数的命令都沿用；每条命令开头都打印当前用的是哪种依赖。两种模式各有一份依赖 checkout，切换后会先重新解析。
- **写进库目录的文件**：Tuist 会在每个按路径声明的包目录里生成 `<包名>.xcodeproj/` 和 `Derived/`。脚本把这两项写进那个仓库的 `info/exclude`（只在本机，不提交），`git status` 里看不到；切回远程模式时删掉 `<包名>.xcodeproj/`，`Derived/` 留着。git 跟踪着 `<包名>.xcodeproj` 的库，脚本直接报错，不让 Tuist 覆盖。

## 与 RuntimeViewer 共用的占用记录

RuntimeViewer 的 Tuist workspace 在它的本地依赖模式下也往这几个检出里生成同名工程，其中也包括本库的检出；而本库的 Tuist workspace 每次都往本检出根目录生成 `MachOSwiftSection.xcodeproj`。两边的设置不同，谁后生成谁就让另一边的 workspace 坏掉，所以两个脚本生成之前都先「占用」检出：

- 被占检出的 git 目录里写 `tuist-generated-project-owner`：占用者检出的路径、在占用者那里释放它的命令、生成进来的工程名。
- 占用者在自己的 `Tuist/.claimed-checkouts`（已忽略）里列出手里的检出，列着才算有效；占用者已经不在或不再列着，记录就是陈旧的，直接接管。
- 另一个检出占着时，命令报错并给出在那边要跑的释放命令：本库是 `./TuistScript.sh release`，RuntimeViewer 是 `./TuistScript.sh generate --remote-dependencies`。RuntimeViewer 旧版脚本写的 `runtimeviewer-tuist-local-dependencies` 记录也认。
- **本库的检出在两种模式下都被自己占着**，本地模式下再加五个上游库。所以要让 RuntimeViewer 的本地模式用这个检出，先在这里 `./TuistScript.sh release`；反过来，RuntimeViewer 的本地模式占着这个检出时，这里的 `generate` 会报错，先在 RuntimeViewer 那边切回远程。

## 测试是怎么映射进来的

Tuist 把按路径声明的包的测试 target 一起转换（`PackageSettings` 的 `includeLocalPackageTestTargets`），但它拒绝两种 SwiftPM 接受的测试：依赖可执行 target 的（本库的 `SwiftSectionCommandTests`、MachOObjCSection 的 `ObjCSectionCommandTests`），和依赖一个不属于任何 product 的普通 target 的（本库的 `SwiftSectionFixtureSupport`、`SwiftSectionTestingSupport`，swift-demangling 的 `DemanglingTestingSupport`）。

- **适配块**：`Package.swift` 末尾那段代码只在 `TUIST_MAPS_LOCAL_PACKAGE_TESTS=1` 时生效——脚本解析依赖时设它——把第一种测试拿掉，给第二种依赖的 target 补一个 library product。平时这个变量不存在，块里什么都不做：`swift package dump-package` 的输出与没有这段代码时逐字节相同。规则是通用的，以后新加的这两种测试不用再改清单。三个上游库的清单末尾是同一段代码，改的时候四处一起改。
- **`SwiftSectionCommandTests` 手写在 `Tuist/CommandLine/Project.swift`**：它 `@testable import swift_section`，也就是可执行 target 自己的模块。那里把 CLI 的源码编成静态 framework `swift_section` 给它用，`swift-section` 工具再编一遍同样的源码，链接时不用绕开 `@main` 的入口。**CLI 的依赖列表是 Tuist 描述里唯一手抄的一份**：`Package.swift` 里 `swift-section` 加了依赖，这里也要加，否则编不过。MachOObjCSection 的 `ObjCSectionCommandTests` 不手写，留在 `swift test` 里跑。
- **只被测试用到的外部依赖要在 `Tuist/Package.swift` 里声明**（现在只有 swift-snapshot-testing），否则 Tuist 报 `… depends on 'X', which is not a configured external dependency`。按 `Package.swift` 里的版本要求加上即可。
- **`IntegrationTests`** 会被转换进来，但不进任何 scheme（`AGENTS.md`：维护者手工查看用的，不跑）。

## 存放位置

`/Volumes/DerivedData` 挂载时，全部放在 `/Volumes/DerivedData/MachOSwiftSection/Tuist/` 下；没挂载时放在仓库里（`Tuist/.build/`、`Tuist/.build-LocalDependencies/`、`DerivedData/Tuist/`，都已忽略）。`TUIST_SCRIPT_ROOT` 可以指定别处。

| 目录 | 内容 |
|---|---|
| `Cache/` | Tuist 的二进制缓存与清单缓存，所有检出共用（按内容寻址） |
| `Dependencies/<checkout>/` | 远程模式的依赖 checkout，每个检出一份；`-LocalDependencies` 后缀的是本地模式那份 |
| `WarmScratch/<checkout>/` | 预热时的临时构建目录，每次预热前清空 |
| `Work/<checkout>/` | `build` / `test` 的 DerivedData 与 `.xcresult`、各包解析后的清单（`Manifests/`）、上次解析依赖用的模式与清单（`InstalledDependencies`） |

`<checkout>` 是检出目录名加路径的短 hash，同名的两个 worktree 不会混用。想从头来：删掉 `Dependencies/<checkout>/` 与 `Work/<checkout>/InstalledDependencies` 后 `install`，删掉 `Cache/` 后 `warm`。

脚本的日志在仓库内的 `Products/Logs/Tuist/`（已忽略）。Tuist 命令的输出原样显示在终端，同时记进日志；`xcodebuild` 的输出只记进日志，失败时终端只显示错误摘要。`test` 结束时打印通过 / 失败 / 跳过的个数，`.xcresult` 的路径在日志开头。

**Agent 运行时**用 `TUIST_SCRIPT_ROOT=/Volumes/DerivedData/Agents.noindex/<agent>/Tuist-MachOSwiftSection`。`install`、`generate`、`release` 不编译，可以直接跑；`warm`、`build`、`test` 要编译，经 `queued-build` 运行，在公司那台 Mac Studio 上按远程构建的规矩放到 Ultra 上跑。

## 已知的坑：清单里那些看着奇怪的写法

都是为了绕开 Tuist 4.210 的行为，改之前先看这里。

- **测试 scheme 关掉了 Main Thread Checker 与 Thread Performance Checker**（`Workspace.swift`，以及脚本生成后补的 `disablePerformanceAntipatternChecker`）：后者往测试进程里插入 `libRPAC.dylib`，改写已加载镜像里的调用，`CrossReferenceAnalysisTests` 里拿进程内读到的 cache 镜像和同一镜像的文件比对的测试就看到一批指向 `libRPAC` 的调用而失败。关掉之后测试进程与 `swift test` 的一样。Tuist 4.210 只往 TestAction 写主线程检查那一项，另一项由脚本在生成后补上，所以别直接跑 `tuist generate`。
- **工具 target 写明 `productName: "swift-section"`**：Tuist 会把 target 名里的 `-` 换成 `_`，不写的话编出来的可执行文件叫 `swift_section`。
- **CLI 的部署版本是 macOS 12.0**（`Tuist/CommandLine/Project.swift`）：Tuist 把 swift-argument-parser 编成它声明的最低版本 macOS 12，10.15 的 `swift-section` import 不了它。
- **测试 target 的部署版本抬到 macOS 14.0**（`Tuist/Package.swift` 的 `testTargetSettings`）：SwiftPM 给测试 target 的部署版本不低于 XCTest 与 Swift Testing 的要求（Xcode 26、27 都是 14.0），包声明的更低也一样；Tuist 照搬包声明的 10.15，`TypeIndexingTests` 于是找不到它测的 macOS 13 API。脚本把所有转换进来的测试 target（含 `IntegrationTests`，免得编整个 workspace 时它编不过）传进 `TUIST_TEST_TARGET_NAMES`。
- **测试 target 与 `swift-section` 链接时带 `-ObjC`**（`Tuist/Package.swift` 的 `testTargetSettings`，`Tuist/CommandLine/Project.swift` 的 `linkFlags`）：SwiftPM 把每个包 target 的目标文件整块链进去；Tuist 编的是静态 framework，链接器只拉被符号引用到的归档成员。没人点名的 protocol conformance 于是丢了，`as?` 静默失败：包装 `MachOImage` / `MachOFile` 的读取器（`MachOReaderWrapper`）两样都不像，`WrappedReaderSymbolTests` 与 `WrappedReaderDemanglingTests` 红了 4 条。Xcode 27 的链接器下 `-ObjC` 会拉进所有定义了 ObjC 类或分类、Swift 类型或 extension 的成员，与 RuntimeViewer 的 Tuist workspace 同一个做法。
- **有加载期 constructor 的 target 被整个 `-force_load`**：`SwiftSymbolsRegistration` 的 constructor 把 Swift 注册成符号语言。它原先是那个 C 文件唯一的内容，又是 `static`，文件里没有全局符号，`-ObjC` 也拉不进来；不加的话 Swift 语言没注册，`SwiftSymbolsTests` 红 281 处，Tuist 编的 `swift-section` 也会把 Swift 符号当成 C。如今这个文件导出了锚点 `swift_symbols_registration_anchor`，`SymbolLanguage+Swift.swift` 调用它，带 `-ObjC` 的链接已经能把它拉进来（MachOObjCSection 的 `MachOObjCSectionC` 同样处理）。脚本仍然保留这条通用规则，作为保险：读清单时找出源码里有 `__attribute__((constructor))` 的 target，沿包内依赖算出哪些测试 target 与可执行 target 会链到它，传进 `TUIST_FORCE_LOADS`，这些链接对那个归档加 `-force_load`。
- **导入了 Testing 的库 target 加上 TestingMacros 插件路径**（`Tuist/Package.swift` 的 `testingSupportSettings`）：`SwiftSectionTestingSupport` 是普通的库 target，却用了 Swift Testing 的 `#require`。SwiftPM 给每个 target 都带上工具链的 TestingMacros 插件，Xcode 只给测试 target 带，于是报 `plugin for module 'TestingMacros' not found`。脚本读清单时找出源码里 `import Testing` 的库 target，传进 `TUIST_TESTING_SUPPORT_TARGET_NAMES`。上游库的也算，两种模式都扫：本地模式下扫它们的本地检出（比如 swift-demangling 的 `DemanglingTestingSupport`），远程模式下扫 Tuist 的依赖 checkout（记在 `Work/<checkout>/Manifests/packages.tsv`，角色 `own-remote`）——MachOKitExtensions 的 `MachOTestingSupport` 用了 `#expect`、`#require`，远程模式下它照样从源码编，只给本地检出补插件路径的话就编不过。
- **手写的 target 设了 `SWIFT_PACKAGE_NAME = MachOSwiftSection`**（`Tuist/CommandLine/Project.swift`）：`SwiftSectionCommandTests` 调用 SwiftSectionKit 的 `package` 方法，只有同一个包的模块看得见；Tuist 给它转换的 target 都设了这个值，手写的也要设。
- **`CAPSTONE_HAS_AARCH64` 手动补上**：Tuist 丢掉只以 trait 为条件的设置；本库开了 swift-capstone 的 `AARCH64` trait，不补的话 Swift 包装编不过，C 库能编过但没有任何架构可用。
- **警告还给按路径声明的包**：Tuist 对所有包都关掉警告，Xcode 只关远程包的；本库（本地模式下还有五个上游库）的 target 经 `TUIST_WARNING_TARGET_NAMES` 把警告要回来。
- **预热要带 `--cache-profile development`**（脚本已经带上）：`tuist cache warm` 不读 `Tuist.swift` 里的默认配置，不传就连本库与上游库也一起缓存。缓存例外按 target 名字匹配所有包，脚本读完清单会警告名字撞上的第三方 target。
- **Tuist 会往 `PrecompiledLibraries/swift-syntax/` 里写 `swift-syntax.xcodeproj`、`Derived/` 与 `.build/`**：它也是按路径声明的包。都已忽略。
