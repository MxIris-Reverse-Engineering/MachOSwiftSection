# Draft - Tuist 开发 workspace：第三方依赖走二进制缓存，上游库可切换为本地检出

- **状态**: In Progress
- **作者**: JH
- **创建日期**: 2026-11-20
- **最后更新**: 2026-11-20
- **所属愿景**: 无
- **关联提案**: RuntimeViewer 仓库的 `Documentations/Evolutions/0053-tuist-coexistence.md`（Tuist workspace 与原生工程并存）与 `0082-tuist-local-dependencies.md`（本地依赖模式）。本提案的脚本照它们的做法写，并顺带改 RuntimeViewer 脚本里的占用检查，让两边的本地依赖模式互斥（落地步骤第 5 步）。
- **跨仓库**: 本提案是唯一的一份。另外四个仓库只有配套小改动：MachOKitExtensions、MachOObjCSection、swift-demangling 的 `Package.swift` 末尾各加同一段适配（第 3 步），RuntimeViewer 改 `TuistScript.sh` 与它的使用指南（第 5 步）。它们的提交信息按 slug 指回本提案，各自的文档按各仓库自己的规定同步。
- **实现分支 / PR**: 本库 `feature/tuist-workspace`，从 `next` 切出；另外四个仓库用同名分支，从各自的集成分支切出（MachOKitExtensions 是 `main`，其余是 `next`）。
- **配套文档**: 使用指南 [`Documentations/Internal/TuistDevelopment.md`](../Internal/TuistDevelopment.md)（第 6 步新增）
- **网页版**: 同目录同名的 `.html`

## 摘要

在原生的 `MachOSwiftSection.xcworkspace` 之外，加一条只供日常开发用的 Tuist 路：`./TuistScript.sh` 生成 `MachOSwiftSection-Tuist.xcworkspace`。本库照常从源码编，可以跳转、可以编辑；27 个真正的第三方依赖（swift-dependencies 一族、swift-collections、Capstone、swift-crypto、Yams……）预编进本机的 Tuist 二进制缓存，只编一次。原生 workspace 里放的五个上游库——MachOKit、MachOKitExtensions、MachOObjCSection、swift-demangling、swift-semantic-string——默认按锁文件版本从源码编；加上 `--local-dependencies` 就改用检出旁边（worktree 里就是 `.worktrees/` 下那组链接）的本地检出，没提交的改动也算，`--remote-dependencies` 切回，选过的模式会记住。Tuist workspace 能跑测试：本库 21 个测试 target 由 Tuist 从 `Package.swift` 转换过来，依赖可执行 target 的 `SwiftSectionCommandTests` 在一个小的 Tuist 工程里手写；本地模式下五个上游库的测试也一起进来。做到这一点要在本库和三个上游库的 `Package.swift` 末尾加同一段适配，它只在 Tuist 解析时设下的环境变量下生效，平时的 SwiftPM、Xcode 与 CI 一律不受影响。RuntimeViewer 的本地依赖模式也会往这几个检出里写同名工程，两边的脚本改成共用一份占用记录，一边占着时另一边直接报错。发版、CI、`swift build` / `swift test` 和原生 workspace 都不变。

## 动机

- **第三方依赖在每个干净的 DerivedData 里都要重编一遍。** 本库的依赖闭包里有 27 个与本仓库开发无关的包（`tuist install` 实测解析出的清单见「前期调研」）：Capstone 的 C 库、swift-crypto、swift-collections、pointfree 的 swift-dependencies 一族、MetaCodable 与 MemberwiseInit 两个宏包、Yams、SourceKitD、swift-apinotes……原生 workspace 走 Xcode 自带的 SwiftPM 集成，每换一个 DerivedData（新 worktree、清缓存、换 Xcode）就全部从源码编一次。Tuist 的二进制缓存按内容寻址，同一台机器、同一个 Xcode 下只编一次。RuntimeViewer 用同样的做法量过：完整 App 从空 DerivedData 构建，不用缓存 504 秒，走缓存 155 秒。本库的数字还没量，第 4 步量。
- **原生 workspace 切换本地上游库的方式太粗。** 今天的切换靠 `USING_LOCAL_DEPENDENCIES=1` 加兄弟目录是否存在（`Package.swift:42` 起的 `package(local:remote:)`）：这个变量要进到 Xcode 的启动环境里才生效；对所有声明了本地路径的依赖一刀切，连 workspace 里没有列出的 swift-capstone（`Package.swift:275`，`../swift-capstone` 在 `.worktrees/` 下有链接）也会被换成本地；切换后要等 Xcode 重新解析。Tuist 这边由 `Tuist/Package.swift` 按路径逐个声明要本地化的库，SwiftPM 让根包的路径依赖顶替图里所有同名声明，名单就是 workspace 的成员，切换只发生在命令行上。
- **RuntimeViewer 的本地依赖模式已经在往本仓库的检出里写工程，而没有任何东西拦着另一方。** 它在每个按路径声明的包目录里生成 `<包名>.xcodeproj` 与 `Derived/`。2026-11-20 实测：RuntimeViewer 的集成 worktree 正占着本库的集成 worktree（本 worktree 的 git 目录里 `runtimeviewer-tuist-local-dependencies` 记着 `/Volumes/Repositories/Private/Org/MxIris-Reverse-Engineering/RuntimeViewer/.worktrees/RuntimeViewer`），本 worktree 根目录那份被忽略的 `MachOSwiftSection.xcodeproj` 就是它生成的。本库自己的 Tuist 也会在同一位置生成同名工程，两边的 `PackageSettings` 不同（配置名、警告、测试映射），谁后生成谁就让另一边的 workspace 坏掉。

## 前期调研

### 现状

- **原生 workspace 的成员**（`MachOSwiftSection.xcworkspace/contents.xcworkspacedata`）：`container:../MachOKit`、`container:../MachOObjCSection`、`group:`（本库）、`group:PrecompiledLibraries/swift-syntax`。集成 worktree 里还有一处没提交的改动，又加了 `container:../MachOKitExtensions`、`container:../swift-demangling`、`container:../swift-semantic-string`。「本地依赖」指的就是这五个 `container:../<名字>` 成员。
- **`PrecompiledLibraries/swift-syntax`** 是一个按包身份顶替 swift-syntax 的包，每个 product 是一个 `binaryTarget`（`PrecompiledLibraries/swift-syntax/Package.swift:46` 起，xcframework 从 `MxIris-DeveloperTool/swift-syntax-builder` 的 release 下载）。原生 workspace 靠把它列为成员来顶替；Tuist 这边要在 `Tuist/Package.swift` 里按路径声明它，两种模式都声明。
- **本库 `Package.swift` 的本地依赖开关**：`usingLocalDependencies = envEnable("USING_LOCAL_DEPENDENCIES")`（`Package.swift:42`）；`package(local:remote:)` 在 `#filePath` 含 `/checkouts/`、`/SourcePackages/` 或 `/.build/` 时一律走远程（`Package.swift:49-74`），所以作为别人的远程依赖时不受这个变量影响。
- **可执行 target 与测试**：`swift-section`、`reader-benchmark`、`baseline-generator` 三个可执行 target（`Package.swift:929`、`956`、`972`），一个命令插件 `RegenerateBaselinesPlugin`（`Package.swift:987`），22 个测试 target。`SwiftSectionCommandTests`（`Package.swift:1305`）依赖 `swift-section`，测试文件里是 `@testable import swift_section`（13 个文件），不启动子进程。`SwiftSectionFixtureSupport`、`SwiftSectionTestingSupport`、`SwiftSectionTestingSupportC` 是普通 target，不属于任何 product（`Package.swift` 的 `products:` 只有 20 个库与 `swift-section`）。
- **没有提交的锁文件**：`.gitignore` 有 `*.resolved`，根目录的 `Package.resolved` 是每台机器、每个检出自己解析出来的。
- **RuntimeViewer 的做法**（`RuntimeViewer/TuistScript.sh`，1774 行；`Documentations/Guides/TuistDevelopment.md`）：`Tuist/Package.swift` 按路径声明四个本地包；`Tuist.swift` 的缓存 profile `development` 用 `.onlyExternal`，按名字把本地包与 MachO 那几个库的 target 留作源码；本地依赖模式在 `Tuist/.local-dependencies` 记住目录，两种模式各用一份 `SWIFTPM_BUILD_DIR`；占用记录写在被占检出的 git 目录里（`runtimeviewer-tuist-local-dependencies`，内容是占用者的路径），判断占用是否仍然有效的办法是看占用者的 `Tuist/.local-dependencies` 是否指向这个目录；切回远程时删掉生成进库目录的工程；Tuist 生成的文件经被占仓库的 `info/exclude` 忽略。它的本地模式不映射测试，原因正是下面的第 1 条与第 6 条。RuntimeViewer 钉的 Tuist 是 4.210.0（`mise.toml`），它记下的 Tuist 4.210 的坑（`${inherited}`、`-ObjC`、测试 target 部署版本、trait 宏、`--cache-profile`）大部分只与 App 工程有关，与本提案相关的三条在「详细设计」里逐条说明。

### 实测（2026-11-20，JH's Mac Studio，Xcode 27.2，Tuist 4.210.0）

探针放在 `/Volumes/DerivedData/Agents.noindex/claude/Probes/MachOSwiftSection-Tuist/`：本库 `next` 与五个上游库集成分支的 HEAD 用 `git archive` 导出成副本，`Tuist/Package.swift` 按路径声明本库副本与预编译 swift-syntax，`Tuist/CommandLine/Project.swift` 放 CLI。只跑了 `tuist install` 与 `tuist generate`，没有编译。没碰任何真实检出。

1. **远程模式、打开 `includeLocalPackageTestTargets`**：生成失败。`The test target 'SwiftSectionCommandTests' in the local package 'MachOSwiftSection' depends on the executable target 'swift-section', which Tuist omits when mapping local package dependencies.` 这个选项对所有按路径声明的包一视同仁，没有按 target 排除的参数（`PackageSettings.init` 只有 `includeLocalPackageTestTargets: Bool`，见 Tuist 4.218.1 的 `ProjectDescription.swiftinterface`）。
2. **用环境变量在 `Package.swift` 里摘掉 `SwiftSectionCommandTests`**：开关生效（`tuist install` 的环境能传进依赖清单的 `Context.environment`，而 Tuist 在 install 时就把清单解析结果缓存下来）。下一个错误：`The local package test target 'SwiftDumpTests' depends on 'SnapshotTesting', which is not a configured external dependency.` 只被测试用到的依赖必须在 `Tuist/Package.swift` 里声明。
3. **补上 swift-snapshot-testing**：`Couldn't find target 'SwiftSectionFixtureSupport'`。测试依赖的普通 target 不属于任何 product 时，Tuist 找不到它。
4. **同一开关下给测试依赖的普通 target 补 library product**：生成成功。`MachOSwiftSection.xcodeproj` 有 48 个 target，其中 21 个测试 target（除 `SwiftSectionCommandTests` 外全部，含 `IntegrationTests`）。原生 `MachOSwiftSection.xcworkspace` 没被碰，新生成的是 `MachOSwiftSection-Tuist.xcworkspace`。
5. **在 Tuist 工程里手写 CLI**：`swift-section`（command line tool）、`swift_section`（static framework，同一批源码，模块名就是测试要的 `swift_section`）、`SwiftSectionCommandTests`（unit tests，依赖 `swift_section`）三个 target，都按 `.external(name:)` 依赖包的 product，生成成功。工程放在 `Tuist/CommandLine/` 下也能生成。没编译，链接与 `@testable import` 是否成立待第 2 步在 Ultra 上验证。
6. **本地模式（五个上游库副本按路径声明）**：生成失败。`The test target 'ObjCSectionCommandTests' in the local package 'MachOObjCSection' depends on the executable target 'objc-section'`。换 Tuist 4.218.1 同样失败。
7. **五个上游库副本的 `Package.swift` 末尾都加上同一段通用适配**（见「详细设计」，第 1、3 条的两种形态都按规则处理）：生成成功，六个包的测试全部映射进来：本库 21、MachOKit 1、MachOKitExtensions 9、MachOObjCSection 8、swift-demangling 1、swift-semantic-string 2。再逐个去掉适配：MachOKit 与 swift-semantic-string 不加也能过；swift-demangling 不加时报 `Couldn't find target 'DemanglingTestingSupport'`。**最少要改三个上游库：MachOKitExtensions（`CPlusPlusSymbolsFixture`）、MachOObjCSection（`ObjCSectionCommandTests`）、swift-demangling（`DemanglingTestingSupport`）。**
8. **生成的工程确实写进各包自己的目录**：`Siblings/<名字>/<名字>.xcodeproj` 与 `Derived/`，本库副本根目录也是。这就是与 RuntimeViewer 冲突的地方。
9. **`Tuist.swift` 能读环境变量**：把 `TUIST_SOURCE_TARGET_NAMES=Utilities,SwiftSymbols,MachOSwiftSection` 经 `Environment.sourceTargetNames` 读进缓存 profile，`tuist dump config` 显示 `exceptTargetQueries` 正是这三个名字。缓存例外名单因此可以由脚本从各包清单算出来，不用像 RuntimeViewer 那样手抄、再用 `check` 守着。
10. **`tuist install` 解析出的远程依赖**（远程模式，种子锁文件取自集成 worktree 的 `Package.resolved`）：AssociatedObject、capstone、combine-schedulers、FrameworkToolbox、MetaCodable、Rainbow、SourceKitD、swift-apinotes、swift-argument-parser、swift-asn1、swift-async-algorithms、swift-binary-parse-support、swift-capstone、swift-clocks、swift-collections、swift-concurrency-extras、swift-crypto、swift-dependencies、swift-fileio、swift-fileio-extra、swift-issue-reporting、swift-literal-type-inference、swift-memberwise-init-macro、swift-object-association、swift-objc-dump、swift-snapshot-testing、Yams，加上五个上游库。

### 推测（未验证，落地步骤里验证）

- 测试 target 的部署版本：SwiftPM 给测试 target 的部署版本不低于 XCTest 与 Swift Testing 的要求（macOS 14.0），Tuist 照搬包声明的 10.15，RuntimeViewer 因此在 `Duration`、`timeLimit` 上编不过。本库测试大概率踩同一个坑。
- `-ObjC`：Tuist 把包编成静态库，链接器只拉被符号引用到的成员。本库测试是否依赖按名字在运行时查找的类，没查过。
- `CAPSTONE_HAS_AARCH64`：本库开了 swift-capstone 的 `AARCH64` trait（`Package.swift:291` 的 `capstoneTraits`），Tuist 会丢掉只以 trait 为条件的设置，RuntimeViewer 因此手动补上了这个宏。
- `swift_section` 这个 static framework 里有 `@main`，链进测试 bundle 后会多出一个 `_main` 符号。bundle 不是可执行文件，这应该无害。

## 提议方案

1. **新增 Tuist 描述**，全部是开发用的，不进发版与 CI：
   - `mise.toml` 钉 Tuist 4.210.0，与 RuntimeViewer 相同（探针里用这个版本全部生成成功；4.218.1 的 `tuist install` 在本地模式下失败过一次，没查原因）。
   - `Tuist/Package.swift` 按路径声明本库（`..`）、预编译 swift-syntax、只被测试用到的 swift-snapshot-testing；本地模式下再按路径声明五个上游库。`PackageSettings` 恢复本库（以及本地模式下上游库）target 的警告，补上 Capstone 的 trait 宏，按需给测试 target 抬部署版本、加 `-ObjC`。
   - `Tuist/CommandLine/Project.swift` 是 Tuist 转换不了的那部分：`swift-section` CLI、给测试用的 `swift_section` 模块、`SwiftSectionCommandTests`。
   - `Workspace.swift` 命名 `MachOSwiftSection-Tuist`，每个映射了测试的包一个测试 scheme（不含 `IntegrationTests`）。
   - `Tuist.swift` 的缓存 profile：只缓存外部依赖，例外名单是本库与五个上游库的全部 target，名单由脚本经环境变量传入。两种模式下上游库都从源码编。
2. **`Package.swift` 末尾加一段适配**，只在 `TUIST_MAPS_LOCAL_PACKAGE_TESTS=1` 时生效：摘掉依赖本包可执行 target 的测试，给测试依赖却不属于任何 product 的普通 target 补 library product。同一段代码原样加进 MachOKitExtensions、MachOObjCSection、swift-demangling。规则是通用的，以后谁新加了这两种形态的测试都不用再改清单。
3. **`TuistScript.sh`**：`install`、`generate`、`warm`、`build`、`test`、`release` 六个命令，`--local-dependencies` / `--remote-dependencies` 切换并记住模式，`--configuration Debug|Release`，`--dry-run`。依赖 checkout、二进制缓存、构建产物放 `/Volumes/DerivedData/MachOSwiftSection/Tuist/`，`TUIST_SCRIPT_ROOT` 可改。本地模式开始前先读各上游库的清单，有包会被 Tuist 拒掉测试时整体关掉测试映射并说明是哪个包，而不是让生成失败。
4. **占用记录两边共用**：被占检出的 git 目录里写 `tuist-generated-project-owner`（占用者路径、释放它的命令），占用者在自己的 `Tuist/.claimed-checkouts` 列出手里的检出，列着才算有效。本库的脚本在任何模式下都占着自己的检出（根目录那份工程总要生成），本地模式下再占五个上游库；RuntimeViewer 的脚本改用同一份记录，旧记录仍然认。
5. **文档**：使用指南 `Documentations/Internal/TuistDevelopment.md`，`AGENTS.md` 构建一节加一条，`Documentations/README.md` 登记。

### 非目标

- 不替代原生 workspace、`swift build` / `swift test` 与 CI；发版与 CI 只走原生路径。`Package.swift` 仍是 target 与依赖的唯一定义，Tuist 描述不另抄一份。
- 不做 RuntimeViewer 那种「与原生工程对照」的 `check`，也不重排导航栏：本库没有原生 App 工程可对照，Tuist 直接读 `Package.swift`；唯一手抄的是 CLI 的依赖清单，编不过就会暴露。
- 只做 macOS，只有 Debug 与 Release 两套配置。
- 不映射 `reader-benchmark`、`baseline-generator` 两个维护者工具，也没有 `regen-baselines` 插件，照旧 `swift run` / `swift package`。
- 不跑 `IntegrationTests`：target 会被转换进来，但不进任何 scheme（`AGENTS.md`：它是维护者手工查看用的）。
- 不上传缓存：`Tuist.swift` 不设 `fullHandle`，二进制缓存只在本机。
- MachOKit 与 swift-semantic-string 不改：实测它们现在不需要适配。以后它们新增了那两种形态的测试，脚本会关掉本地模式的测试映射并点名，到时再加同一段适配。
- 不改 `USING_LOCAL_DEPENDENCIES` 机制：原生 workspace 的用法不变；脚本运行时忽略这个变量并提示。

## 改动地图

| 文件 / 类型 | 动作 | 改什么 | 为什么 | 步骤 |
|---|---|---|---|---|
| `mise.toml` | 新增 | `[tools] tuist = "4.210.0"` | 两台机器、两个仓库用同一个 Tuist；RuntimeViewer 记下的坑都是这个版本 | 1 |
| `Tuist/Package.swift` | 新增 | 按路径声明本库、预编译 swift-syntax，按 URL 声明 swift-snapshot-testing；本地模式加五个上游库；`PackageSettings` | Tuist 的依赖图从这里来；路径依赖顶替图里同名的 URL 声明 | 1、2、3 |
| `Tuist/CommandLine/Project.swift` | 新增 | `swift-section`、`swift_section`、`SwiftSectionCommandTests` 三个 target | Tuist 不转换可执行 target，也不接受依赖它的测试（实测第 1、5 条） | 1、2 |
| `Workspace.swift` | 新增 | workspace 名 `MachOSwiftSection-Tuist`，成员 `Tuist/CommandLine`，按包生成测试 scheme | 不与原生 `MachOSwiftSection.xcworkspace` 同名；测试 target 在转换出的工程里，只能由 workspace 的 scheme 引用 | 1、2 |
| `Tuist.swift` | 新增 | 缓存 profile `development`：`.onlyExternal`，例外取 `TUIST_SOURCE_TARGET_NAMES` | 本库与上游库留作源码，其余进缓存；名单由脚本从清单算（实测第 9 条） | 4 |
| `TuistScript.sh` | 新增 | 六个命令、两种依赖模式、存放位置、日志、锁文件种子与比对、占用记录、测试映射的预检 | 直接跑 `tuist` 拿不到正确的环境变量与占用保护 | 1–5 |
| `Package.swift` | 修改 | 文件末尾加 `TUIST_MAPS_LOCAL_PACKAGE_TESTS` 适配块 | 让 Tuist 能映射本库测试（实测第 1–4 条）；变量不设时什么都不变 | 2 |
| `MachOSwiftSection.xcworkspace/contents.xcworkspacedata` | 修改 | 加入 MachOKitExtensions、swift-demangling、swift-semantic-string 三个成员，与集成 worktree 里那处未提交的改动内容相同 | 脚本从这里读本地依赖名单，五个都要在 | 1 |
| `.gitignore` | 修改 | 忽略 `MachOSwiftSection-Tuist.xcworkspace/`、根目录的 `MachOSwiftSection.xcodeproj/` 与 `Derived/`、`Tuist/.build*/`、`Tuist/CommandLine/` 下生成的工程与 `Derived/`、`Tuist/.local-dependencies`、`Tuist/.claimed-checkouts` | 生成物不提交；根目录那两项今天只靠 RuntimeViewer 写进 `info/exclude` 才被忽略 | 1 |
| MachOKitExtensions `Package.swift` | 修改 | 末尾加同一段适配块 | 本地模式下 `CPlusPlusSymbolsFixture` 找不到（实测第 7 条） | 3 |
| MachOObjCSection `Package.swift` | 修改 | 同上 | 本地模式下 `ObjCSectionCommandTests` 被拒（实测第 6 条） | 3 |
| swift-demangling `Package.swift` | 修改 | 同上 | 本地模式下 `DemanglingTestingSupport` 找不到（实测第 7 条） | 3 |
| RuntimeViewer `TuistScript.sh` · `claim_local_checkouts` / `release_local_checkouts` | 修改 | 改用共用的 `tuist-generated-project-owner` 与 `Tuist/.claimed-checkouts`；旧的 `runtimeviewer-tuist-local-dependencies` 照旧认、自己占着的顺手删掉 | 双向互斥：今天它看不见本库的占用 | 5 |
| RuntimeViewer `Documentations/Guides/TuistDevelopment.md` | 修改 | 「写进库目录的文件」「同一时刻只让一个检出用这组库」两段改写成共用的占用记录 | 文档与代码同批 | 5 |
| `Documentations/Internal/TuistDevelopment.md` | 新增 | 使用指南：第一次使用、日常用法、两种模式、占用记录、存放位置、已知的坑 | 维护者要知道怎么用、什么时候要重新 `install` / `generate` | 6 |
| `AGENTS.md` | 修改 | 构建一节加一条：Tuist workspace 是开发用的第二条路，只经脚本运行，agent 设 `TUIST_SCRIPT_ROOT` 并经 `queued-build` | agent 默认会直接跑 `tuist generate`，那样既没有环境变量也没有占用保护 | 6 |
| `Documentations/README.md` | 修改 | Internal 一节登记新指南 | 文档索引 | 6 |
| `Documentations/Evolutions/README.md` | 修改 | 状态表加本提案 | 提案索引 | 创建时、落地时 |
| `Documentations/Internal/ProjectEvolutionLog.md` | 修改 | 落地时加一节 | 演进账本 | 落地时 |

## 架构图

改了什么（文件与生成物）：

```text
MachOSwiftSection/                                  (a checkout)
├── MachOSwiftSection.xcworkspace                   ~ members: + MachOKitExtensions, swift-demangling, swift-semantic-string
├── Package.swift                                   ~ + TUIST_MAPS_LOCAL_PACKAGE_TESTS block at the end
├── + mise.toml                                       tuist 4.210.0
├── + Tuist.swift                                     cache profile "development"
├── + Workspace.swift                                 MachOSwiftSection-Tuist
├── + TuistScript.sh
├── + Tuist/
│   ├── + Package.swift                               the dependency graph Tuist converts
│   └── + CommandLine/Project.swift                   swift-section, swift_section, SwiftSectionCommandTests
└── generated, ignored:
    ├── MachOSwiftSection-Tuist.xcworkspace
    ├── MachOSwiftSection.xcodeproj, Derived/         (converted from ./Package.swift)
    └── Tuist/CommandLine/MachOSwiftSectionCommandLine.xcodeproj

../MachOKitExtensions/Package.swift                 ~ + the same block
../MachOObjCSection/Package.swift                   ~ + the same block
../swift-demangling/Package.swift                   ~ + the same block
RuntimeViewer/TuistScript.sh                        ~ shared claim record
```

生成出的 workspace 里有什么：

```text
MachOSwiftSection-Tuist.xcworkspace
├── Tuist/CommandLine/MachOSwiftSectionCommandLine.xcodeproj   (+ hand-written Tuist targets)
│   ├── swift-section            commandLineTool   sources: Sources/Executables/swift-section/**
│   ├── swift_section            staticFramework   same sources, for @testable import
│   └── SwiftSectionCommandTests unitTests ──► swift_section
│        (all three ──► .external(SwiftSectionKit, MachOFoundation, ArgumentParser, …))
├── MachOSwiftSection.xcodeproj              source, 27 library/macro/C targets + 21 test targets
├── remote mode: checkouts/<upstream>/…      source (cache exception), no tests
├── local mode:  ../<upstream>/<upstream>.xcodeproj   source from the local checkout, + its tests
└── third-party packages                     binary cache after `warm`, source before
```

一条命令怎么走（`./TuistScript.sh generate --local-dependencies`）：

```text
TuistScript.sh generate --local-dependencies
├── check the pinned Tuist (mise.toml), unset USING_LOCAL_DEPENDENCIES
├── read the local package names            MachOSwiftSection.xcworkspace: container:../<name>
├── record the mode                         Tuist/.local-dependencies ← <directory>
├── read the manifests                      swift package dump-package, TUIST_MAPS_LOCAL_PACKAGE_TESTS=1
│   ├── TUIST_SOURCE_TARGET_NAMES           every target of this package and the five upstream ones
│   ├── TUIST_PACKAGE_TEST_TARGETS          <package directory>=<test target>,…;…
│   └── tests rejected by Tuist anywhere?   → TUIST_MAPS_LOCAL_PACKAGE_TESTS=0 + a warning naming the package
├── ensure_dependencies                     SWIFTPM_BUILD_DIR per mode; seed Tuist/Package.resolved; tuist install
├── claim_checkouts                         this checkout + the five upstream checkouts
│   └── another live owner?                 → fail with the owner's release command
└── tuist generate --no-open
```

占用记录（两个仓库的脚本共用）：

```text
<claimed checkout's git dir>/tuist-generated-project-owner
    line 1: /path/to/owner/checkout
    line 2: ./TuistScript.sh release            (MachOSwiftSection)
            ./TuistScript.sh generate --remote-dependencies   (RuntimeViewer)

<owner checkout>/Tuist/.claimed-checkouts       one real path per line

a claim is live ⇔ the owner's .claimed-checkouts lists the claimed checkout's real path
legacy: <git dir>/runtimeviewer-tuist-local-dependencies is live
        ⇔ <owner>/Tuist/.local-dependencies/<package name> is the claimed checkout
```

## 详细设计

### `Package.swift` 的适配块

本库与三个上游库的 `Package.swift` 末尾原样加这一段（探针里五个上游库副本都用它通过了 `swift package dump-package` 与 `tuist generate`）。它读的是 `Context.environment`，平时这个变量不存在，块里什么都不做；作为别人的远程依赖时也一样。

```swift
// The Tuist development workspace (MachOSwiftSection's Documentations/Internal/TuistDevelopment.md)
// maps this package's tests with Tuist, which rejects two shapes SwiftPM accepts: a test that depends
// on an executable target, and a test that depends on a target no product contains. Only while Tuist
// resolves the packages, with TUIST_MAPS_LOCAL_PACKAGE_TESTS=1, the first kind is left out and the
// second kind gets a library product of its own. Nothing changes without the variable.
if Context.environment["TUIST_MAPS_LOCAL_PACKAGE_TESTS"] == "1" {
    let executableTargetNames = Set(package.targets.filter { $0.type == .executable }.map(\.name))
    func dependencyName(_ dependency: Target.Dependency) -> String? {
        switch dependency {
        case .targetItem(let name, _), .byNameItem(let name, _):
            return name
        default:
            return nil
        }
    }
    package.targets.removeAll { target in
        target.type == .test && target.dependencies.contains { dependency in
            dependencyName(dependency).map(executableTargetNames.contains) ?? false
        }
    }
    let productTargetNames = Set(package.products.flatMap { product in (product as? Product.Library)?.targets ?? [] })
    let testDependencyNames = Set(package.targets.filter { $0.type == .test }.flatMap { $0.dependencies.compactMap(dependencyName) })
    package.products += package.targets
        .filter { target in target.type == .regular && testDependencyNames.contains(target.name) && !productTargetNames.contains(target.name) }
        .map { target in Product.library(name: target.name, targets: [target.name]) }
}
```

- 在本库里它摘掉 `SwiftSectionCommandTests`，给 `SwiftSectionFixtureSupport`、`SwiftSectionTestingSupport`（以及测试直接依赖的其余普通 target）补 product。在 MachOObjCSection 里摘掉 `ObjCSectionCommandTests`；在 MachOKitExtensions 与 swift-demangling 里补 `CPlusPlusSymbolsFixture`、`DemanglingTestingSupport` 的 product。
- 被摘掉的测试 Tuist workspace 里就没有了，照旧用 `swift test --filter` 跑；本库的 `SwiftSectionCommandTests` 例外，它在 `Tuist/CommandLine/Project.swift` 里手写（下文）。MachOObjCSection 的 `ObjCSectionCommandTests` 不手写：那要在本库描述另一个仓库的 target，非目标。
- 只看 target 依赖（`targetItem` / `byNameItem`），不看 `productItem`：依赖别的包的可执行 product 的测试，Tuist 怎么处理没有实测，目前四个包里也没有。

### `Tuist/Package.swift`

```swift
// swift-tools-version: 6.2
import Foundation
import PackageDescription

// The dependencies of MachOSwiftSection-Tuist.xcworkspace (Documentations/Internal/TuistDevelopment.md).
// This package is declared by path, so its Package.swift stays the only definition of its targets.
// In the local dependency mode TuistScript.sh names the upstream packages in TUIST_LOCAL_PACKAGE_NAMES
// and their directory in TUIST_LOCAL_PACKAGE_CHECKOUTS; a root's path dependency stands in for every
// declaration of the same package in the graph.
let processEnvironment = ProcessInfo.processInfo.environment
let localPackageCheckoutsDirectory = processEnvironment["TUIST_LOCAL_PACKAGE_CHECKOUTS"] ?? ""
let localPackageNames = (processEnvironment["TUIST_LOCAL_PACKAGE_NAMES"] ?? "").split(separator: ",").map(String.init)
let localPackageDependencies: [PackageDescription.Package.Dependency] = localPackageCheckoutsDirectory.isEmpty
    ? []
    : localPackageNames.map { packageName in .package(path: "\(localPackageCheckoutsDirectory)/\(packageName)") }

#if TUIST
    import ProjectDescription

    func names(_ variable: String) -> [String] {
        (processEnvironment[variable] ?? "").split(separator: ",").map(String.init)
    }

    // Tuist suppresses warnings in every package; Xcode does so for remote packages only.
    let warningSettings: [String: Settings] = Dictionary(
        names("TUIST_WARNING_TARGET_NAMES").map { targetName in
            (targetName, Settings.settings(base: ["SWIFT_SUPPRESS_WARNINGS": "NO", "GCC_WARN_INHIBIT_ALL_WARNINGS": "NO"]))
        },
        uniquingKeysWith: { first, _ in first }
    )

    // Tuist drops a setting whose only condition is a trait; this package enables swift-capstone's
    // AARCH64 trait, which defines CAPSTONE_HAS_AARCH64 that way.
    let restatedTraitDefinitions: [String: Settings] = [
        "Capstone": .settings(base: [
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS": ["$(inherited)", "CAPSTONE_HAS_AARCH64"],
            "GCC_PREPROCESSOR_DEFINITIONS": ["$(inherited)", "CAPSTONE_HAS_AARCH64=1"],
        ]),
        "Ccapstone": .settings(base: [
            "GCC_PREPROCESSOR_DEFINITIONS": ["$(inherited)", "CAPSTONE_HAS_AARCH64=1"],
        ]),
    ]

    // Filled in by step 2 once the tests have been built: the deployment target SwiftPM gives a test
    // target (macOS 14.0) and -ObjC, each only if the build shows it is needed.
    let testTargetSettings: [String: Settings] = [:]

    let packageSettings = PackageSettings(
        targetSettings: warningSettings
            .merging(restatedTraitDefinitions) { $1 }
            .merging(testTargetSettings) { $1 },
        includeLocalPackageTestTargets: processEnvironment["TUIST_MAPS_LOCAL_PACKAGE_TESTS"] == "1"
    )
#endif

let package = Package(
    name: "MachOSwiftSectionTuistDependencies",
    dependencies: [
        .package(path: ".."),
        // Stands in for swift-syntax everywhere, as it does as a member of the native workspace.
        .package(path: "../PrecompiledLibraries/swift-syntax"),
        // Used only by tests, which Tuist needs declared here (MachOSwiftSection's requirement).
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.18.9"),
    ] + localPackageDependencies
)
```

- 包名 `MachOSwiftSectionTuistDependencies`。根包的路径依赖 `..` 的身份是目录名：worktree 叫 `MachOSwiftSection-<用途>` 时身份就变了，而上游库的清单不按 URL 引用本库，所以不受影响；生成的工程名取自 `Package(name:)`，仍是 `MachOSwiftSection.xcodeproj`。
- `TUIST_WARNING_TARGET_NAMES` 是本库全部 target，本地模式下再加五个上游库的全部 target（与原生 workspace 一致：Xcode 只给远程包关警告）。

### `Tuist/CommandLine/Project.swift`

```swift
import ProjectDescription

// What Tuist cannot convert from ../../Package.swift: the swift-section executable, and
// SwiftSectionCommandTests, which imports the executable's module. swift_section compiles the same
// sources as a static framework for that test; the tool compiles them again, so its link needs no
// trick around the @main entry point. The dependency list mirrors Package.swift's swift-section
// target and is the one hand-written copy in the Tuist description.
let commandLineDependencies: [TargetDependency] = [
    .external(name: "SwiftSectionKit"),
    .external(name: "MachOFoundation"),
    .external(name: "SwiftSymbols"),
    .external(name: "SwiftDump"),
    .external(name: "SwiftOutputTransformer"),
    .external(name: "SwiftDeclaration"),
    .external(name: "SwiftIndexing"),
    .external(name: "Semantic"),
    .external(name: "OutputTransformer"),
    .external(name: "ObjCDeclarationRendering"),
    .external(name: "ObjCOutputTransformer"),
    .external(name: "Rainbow"),
    .external(name: "ArgumentParser"),
]

let commandLineSources: SourceFilesList = ["../../Sources/Executables/swift-section/**"]

// MACHO_SWIFT_SECTION_SILENT_TEST=1, which Package.swift turns into SILENT_TEST for its test targets;
// TuistScript.sh passes it on as TUIST_SILENT_TEST, the only form a Tuist manifest can read.
let commandTestSettings: Settings = Environment.silentTest.getBoolean(default: false)
    ? .settings(base: ["SWIFT_ACTIVE_COMPILATION_CONDITIONS": ["$(inherited)", "SILENT_TEST"]])
    : .settings()

let project = Project(
    name: "MachOSwiftSectionCommandLine",
    targets: [
        .target(
            name: "swift-section",
            destinations: .macOS,
            product: .commandLineTool,
            bundleId: "com.machoswiftsection.swift-section",
            deploymentTargets: .macOS("10.15"),
            sources: commandLineSources,
            dependencies: commandLineDependencies
        ),
        .target(
            name: "swift_section",
            destinations: .macOS,
            product: .staticFramework,
            bundleId: "com.machoswiftsection.swift-section.module",
            deploymentTargets: .macOS("10.15"),
            sources: commandLineSources,
            dependencies: commandLineDependencies
        ),
        .target(
            name: "SwiftSectionCommandTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "com.machoswiftsection.SwiftSectionCommandTests",
            deploymentTargets: .macOS("14.0"),
            sources: ["../../Tests/SwiftSectionCommandTests/**"],
            dependencies: [
                .target(name: "swift_section"),
                .external(name: "SwiftDeclarationRendering"),
                .external(name: "SwiftPrinting"),
            ] + commandLineDependencies,
            settings: commandTestSettings
        ),
    ]
)
```

- CLI 的源码编两遍（tool 一遍、framework 一遍）。另一种写法是 tool 不带源码、只链 framework，靠链接器从静态库里取 `_main`；省一遍编译，但能否链接成功依赖链接器怎么处理入口符号，没实测，放进「替代方案」。
- `MACHO_SWIFT_SECTION_SILENT_TEST=1` 在 `Package.swift` 里变成测试 target 的 `SILENT_TEST` 定义：`tuist install` 时设了它，转换出的测试就带上。手写的 `SwiftSectionCommandTests` 也要带：Tuist 的 manifest 只读得到 `TUIST_` 开头的变量，所以脚本把它转成 `TUIST_SILENT_TEST=1`，`Project.swift` 据此给这个 target 加 `SILENT_TEST`。

### `Workspace.swift`

```swift
import ProjectDescription

// "<package directory>=<test target>,<test target>;…" from TuistScript.sh, one entry per package whose
// tests are mapped: this package always (directory "."), the upstream packages in the local mode.
// IntegrationTests is never listed.
let packageTestTargets: [(directory: String, targets: [String])] = Environment.packageTestTargets
    .getString(default: "")
    .split(separator: ";")
    .compactMap { entry in
        let parts = entry.split(separator: "=", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        return (parts[0], parts[1].split(separator: ",").map(String.init))
    }

let workspace = Workspace(
    name: "MachOSwiftSection-Tuist",
    projects: ["Tuist/CommandLine"],
    schemes: packageTestTargets.map { entry in
        let packageName = entry.directory == "." ? "MachOSwiftSection" : (entry.directory as NSString).lastPathComponent
        var testableTargets = entry.targets.map { targetName in
            TestableTarget.testableTarget(target: .project(path: Path(entry.directory), target: targetName))
        }
        if entry.directory == "." {
            testableTargets.append(.testableTarget(target: .project(path: "Tuist/CommandLine", target: "SwiftSectionCommandTests")))
        }
        return .scheme(name: "\(packageName) Tests", testAction: .targets(testableTargets))
    }
)
```

- 上游库的目录是绝对路径；`Path` 接受绝对路径字符串，第 3 步验证。`Workspace.swift` 能否 `import Foundation` 用 `NSString` 没验证，不行就自己切最后一段。
- 测试映射被预检关掉时 `TUIST_PACKAGE_TEST_TARGETS` 为空，只剩各 target 自己的 scheme；`SwiftSectionCommandTests` 仍在 `MachOSwiftSectionCommandLine` 工程里，Tuist 自动生成的 scheme 能跑它。

### `Tuist.swift`

```swift
import ProjectDescription

// Every target of MachOSwiftSection and of the five upstream packages stays source, in both dependency
// modes; every other dependency comes out of the binary cache once warmed. TuistScript.sh reads the
// names from the packages' manifests. No fullHandle: the cache stays on this machine.
let sourceTargetNames = Environment.sourceTargetNames
    .getString(default: "")
    .split(separator: ",")
    .map(String.init)

let tuist = Tuist(
    project: .tuist(
        cacheOptions: .options(
            profiles: .profiles(
                ["development": .profile(.onlyExternal, except: sourceTargetNames.map { .named($0) })],
                default: "development"
            )
        )
    )
)
```

- 上游库在远程模式下也留作源码，理由与 RuntimeViewer 相同：本库经常跟着它们改、频繁挪 pin，放进缓存就要一次次重新预热；它们留作源码也能直接跳进去看。代价是远程模式从空 DerivedData 构建要多编这五个库，第 4 步量出来后若差得多再议。
- 例外按名字匹配所有包的 target。脚本在算名单时检查有没有第三方包的 target 与名单同名，有就警告（同名的会被一起留成源码）。

### `TuistScript.sh`

照 RuntimeViewer 的脚本写，只保留与本库有关的部分。

**命令**：

| 命令 | 做什么 |
|---|---|
| `install` | 从种子锁文件开始解析当前模式的依赖（`tuist install`），结束时与种子比对 pin |
| `generate [--configuration <c>]` | 需要时先 `install`，占用检出，生成 workspace（默认 Debug） |
| `warm [--configuration <c>]` | 带 `--cache-profile development` 把第三方依赖编进缓存，再生成 |
| `build [--configuration <c>]` | 生成后用 `xcodebuild` 编 `swift-section` scheme |
| `test [-- <xcodebuild 参数>]` | 生成后用 `xcodebuild test` 跑 `MachOSwiftSection Tests` scheme，退出码就是 `xcodebuild` 的 |
| `release` | 放弃所有占用：删掉生成进各检出的工程（git 跟踪的不删）、占用记录与 `MachOSwiftSection-Tuist.xcworkspace`；`Derived/` 留着 |

`--local-dependencies` / `--remote-dependencies` 可以跟在任何命令后面，从这条命令起切换模式；`--dry-run` 打印要做的事；`--help` 打印脚本头部的说明。

**环境变量**（脚本设，manifest 读）：

| 变量 | 谁读 | 内容 |
|---|---|---|
| `TUIST_MAPS_LOCAL_PACKAGE_TESTS` | 四个包的 `Package.swift`，`Tuist/Package.swift` | `1`：映射测试；预检不通过时 `0` |
| `TUIST_LOCAL_PACKAGE_CHECKOUTS`、`TUIST_LOCAL_PACKAGE_NAMES` | `Tuist/Package.swift` | 本地模式下上游库所在目录与名字；远程模式不设 |
| `TUIST_SOURCE_TARGET_NAMES` | `Tuist.swift` | 本库与五个上游库的全部 target |
| `TUIST_WARNING_TARGET_NAMES` | `Tuist/Package.swift` | 恢复警告的 target：本库全部，本地模式再加上游库全部 |
| `TUIST_PACKAGE_TEST_TARGETS` | `Workspace.swift` | 每个映射了测试的包的测试 target，不含 `IntegrationTests` |
| `TUIST_SILENT_TEST` | `Tuist/CommandLine/Project.swift` | 用户设了 `MACHO_SWIFT_SECTION_SILENT_TEST=1` 时为 `1` |
| `SWIFTPM_BUILD_DIR` | Tuist | 当前模式的依赖 checkout 目录 |
| `TUIST_XDG_CACHE_HOME`、`TUIST_CACHE_WARM_SCRATCH_DIRECTORY` | Tuist | 二进制缓存与预热的临时目录 |

`USING_LOCAL_DEPENDENCIES` 被设了就提示一句并 `unset`：它会让本库清单自己换上本地兄弟，连 swift-capstone 一起，与 `Tuist/Package.swift` 的名单对不上。

**名单从哪来**：本地依赖的名字读 `MachOSwiftSection.xcworkspace/contents.xcworkspacedata` 里的 `container:../<名字>`（不含 `/` 的那些），workspace 加了库这里自动跟上。target 名单用 `swift package dump-package`（带 `TUIST_MAPS_LOCAL_PACKAGE_TESTS=1`，`--scratch-path` 放在 `Work/<checkout>/Manifests/`）读六个包的清单：本库与本地模式下的上游库读检出里的，远程模式下的上游库读 `install` 之后 `SWIFTPM_BUILD_DIR/checkouts/<名字>` 里的。远程模式下第一次 `install` 之前还没有 checkout，先用空名单装一次再算。

**测试映射的预检**：对每个按路径声明的包，在它的清单 JSON 里找 Tuist 会拒绝的两种形态——测试依赖本包的可执行 target、测试依赖不属于任何 product 的普通 target（实测第 1、3、6 条）。适配块生效时这两种都不该剩下；还剩，说明那个包没有适配块（比如本地检出停在加块之前的提交），这次就整体设 `TUIST_MAPS_LOCAL_PACKAGE_TESTS=0`，警告点名那个包，生成照常进行。只被测试用到的外部依赖（实测第 2 条）预检查不出来，生成时 Tuist 自己会报，指南里写怎么补。

**锁文件**：`Tuist/Package.resolved` 不提交（`*.resolved` 已忽略）。每次 `install` 前用本检出根目录的 `Package.resolved` 当种子（没有就不种，由 Tuist 解析最新版本），结束时逐条比对，不同就警告；swift-syntax（这边是预编译包，没有 pin）与本地模式下的五个库不参与比对。

**依赖模式**：模式记在 `Tuist/.local-dependencies`（内容是上游库所在目录；远程模式下这个文件不存在）。默认目录是检出的上一级，worktree 里就是 `.worktrees/`；打开本地模式时设了 `TUIST_LOCAL_PACKAGE_CHECKOUTS` 就用它。两种模式各用一份依赖 checkout（`Dependencies/<checkout>` 与 `Dependencies/<checkout>-LocalDependencies`），共用 `Tuist/Package.resolved`，所以切换后、或上次解析用的是另一种模式时先重新 `install`（`Work/<checkout>/InstalledDependencies` 记着上次）。切到远程时释放五个上游库的占用。

**存放位置**：`/Volumes/DerivedData` 挂着时全放在 `/Volumes/DerivedData/MachOSwiftSection/Tuist/` 下（`Cache/`、`Dependencies/<checkout>[-LocalDependencies]/`、`WarmScratch/<checkout>/`、`Work/<checkout>/`），`<checkout>` 是目录名加路径的短 hash；没挂载时放在仓库里的 `Tuist/.build/`、`Tuist/.build-LocalDependencies/` 与 `DerivedData/Tuist/`（都已忽略）。`TUIST_SCRIPT_ROOT` 指定别处。`build` / `test` 的 DerivedData 在 `Work/<checkout>/DerivedData`。日志在 `Products/Logs/Tuist/`；Tuist 的输出原样显示并记进日志，`xcodebuild` 的输出只进日志，失败时显示错误摘要。

**占用记录**（与 RuntimeViewer 共用）：

- 被占的检出：它的 git 目录（`git rev-parse --absolute-git-dir`，worktree 各有一份）里的 `tuist-generated-project-owner`，第一行是占用者检出的路径，第二行是在占用者检出里释放它的命令。
- 占用者：自己的 `Tuist/.claimed-checkouts`，每行一个被占检出的真实路径（`pwd -P`）。
- 有效：占用者的 `.claimed-checkouts` 列着这个路径。占用者不在了、或已经不列了，记录就是陈旧的，可以直接覆盖。
- 旧记录 `runtimeviewer-tuist-local-dependencies`：占用者的 `Tuist/.local-dependencies` 加上包名指向这个检出时算有效（RuntimeViewer 今天的规则）。
- 本库的脚本在 `generate` 前占用自己的检出与（本地模式下）五个上游库；遇到别人的有效占用就失败，报出占用者路径与它的释放命令。检出里 git 跟踪着 `<包名>.xcodeproj` 时也失败（Tuist 会覆盖它）。上游库的 `<包名>.xcodeproj/` 与 `Derived/` 写进那个仓库的 `info/exclude`，本库自己的生成物走 `.gitignore`。
- 释放：删掉生成进那个检出的工程、占用记录，并从 `.claimed-checkouts` 里去掉。

**Tuist 版本**：读 `mise.toml` 的版本；有 mise 就 `mise exec -- tuist`，否则用 PATH 里的 `tuist`；版本不对就失败并提示 `mise install`。

**agent 运行**：`TUIST_SCRIPT_ROOT=/Volumes/DerivedData/Agents.noindex/<agent>/Tuist-MachOSwiftSection`，并写成 `queued-build ./TuistScript.sh <命令>`。

### RuntimeViewer 那一侧

- `claim_local_checkouts`：先读共用记录与旧记录，任何一个有效且占用者不是自己就失败，报出占用者与释放命令；然后写共用记录（第二行是 `./TuistScript.sh generate --remote-dependencies`），把路径写进自己的 `Tuist/.claimed-checkouts`，自己的旧记录删掉。
- `release_local_checkouts`：删掉自己的共用记录（以及残留的旧记录），从 `.claimed-checkouts` 里去掉。
- 今天它占着本库的集成 worktree 与五个上游检出（旧记录）。改完后它下一次 `generate` 就把记录换成新的；在那之前，本库的脚本按旧规则认出它的占用。

### 已知要在实现中确认的点

1. `swift_section` 与 `SwiftSectionCommandTests` 能编、能链、`@testable import` 成立（第 2 步）。
2. 本库测试在 Tuist workspace 里要不要抬部署版本到 14.0、要不要 `-ObjC`（第 2 步，只加确实需要的）。
3. `Capstone` 的 trait 宏补上后 `SwiftThunkAnalysis` 能编（第 1 步）。
4. `Workspace.swift` 里按绝对路径引用上游库工程（第 3 步）。
5. 远程与本地两种模式下，Tuist workspace 跑出的测试数与 `swift test --skip IntegrationTests` 一致，失败的与原生路径相同（第 2、3 步，在 Ultra 上）。

## 替代方案考量

- **Tuist 的「把 `Package.swift` 当工程」**（beta，`tuist generate` 直接读根目录的 `Package.swift`）：不用 `Tuist/Package.swift`，可本地 / 远程切换要靠顶替同名包，还是得有一个根清单按路径声明上游库；文档写明它不打算支持 SwiftPM 的全部特性；它很可能按包名生成 `MachOSwiftSection.xcworkspace`，与原生 workspace 同名（推测，没实测）。否。
- **在 `Project.swift` 里手写全部 target**：生成的工程名可以避开 RuntimeViewer 用的 `MachOSwiftSection.xcodeproj`，冲突自然消失；但要把五十来个 target 的依赖关系从 `Package.swift` 再抄一份，必然漂移，还得写一个 `check` 守着。否。
- **Tuist 的 Xcode 原生包集成**（生成的工程里仍用 Xcode 的 SwiftPM 集成）：不往包目录写工程，冲突也消失；但它没有二进制缓存，与原生 workspace 相比什么也没得到。否。
- **本地模式不映射测试**（RuntimeViewer 的做法）：不用改任何上游库；但本库跨仓库改动时用的正是本地模式，那时 Tuist workspace 里跑不了任何测试，本库自己的也跑不了（这个选项对所有路径包一刀切）。用户选了加适配块（决策日志「用户批准，开始实现」）。
- **只针对点名的 target 打补丁**（在本库清单里按名字摘掉 `SwiftSectionCommandTests`、按名字补 product）：探针第一版就是这么做的；但三个上游库各要写一份不同的补丁，以后每加一个这种形态的测试都要回来改。通用规则一段代码四个仓库共用。否。
- **CLI 只链 framework、不带源码**：省一遍 CLI 源码的编译；能否链接成功取决于链接器会不会为入口符号 `_main` 从静态库里取成员，没实测，失败了还得改成给 framework 加 `-entry-point-function-name`。编两遍的写法没有这个风险，CLI 模块也不大。否，可以在第 2 步顺手试一次，成了再换。
- **远程模式下把五个上游库也放进缓存**：远程模式从空 DerivedData 构建会更快；但它们的 pin 动得勤，每次都要重新预热，缓存里旧版本越积越多，也跳不进源码。暂否，第 4 步量出差距后可以重议。
- **只在本库这边检查 RuntimeViewer 的占用**：不用改 RuntimeViewer；但 RuntimeViewer 的本地模式照样会盖掉本库生成的工程。用户选了双向互斥。
- **用 `USING_LOCAL_DEPENDENCIES=1` 实现本地模式**：本库清单自己就会换上本地兄弟；但它对所有带本地路径的依赖一刀切（含 swift-capstone），三个上游库的清单也各有自己的开关，结果取决于每个清单怎么写。按路径逐个声明更精确，与 RuntimeViewer 一致。否。

## 影响

### 源码兼容性（source compatibility）

纯新增。没有任何公开 API 变化。`Package.swift` 的适配块只在 `TUIST_MAPS_LOCAL_PACKAGE_TESTS=1` 时生效，`swift build`、`swift test`、Xcode 的原生 workspace、CI 与下游的 SwiftPM 解析都不会设这个变量；三个上游库同样。

### ABI 兼容性（条件项）

不适用 —— 本库以 SPM 源码分发，使用方每次重新编译。

### 下游影响

- **本仓库内**：没有 target 受影响。`.gitignore` 多了几项生成物，`MachOSwiftSection.xcworkspace` 多了三个成员（它们本来就在集成 worktree 的未提交改动里）。
- **RuntimeViewer**：`TuistScript.sh` 换用共用的占用记录（第 5 步）。它的 Tuist 在本地模式下按路径读本库与三个上游库的清单，但不设 `TUIST_MAPS_LOCAL_PACKAGE_TESTS`，适配块不生效，它生成的工程不变。
- **MachOKitExtensions、MachOObjCSection、swift-demangling**：清单末尾多一段默认不生效的代码，不需要发版——只有本地模式读它们的本地检出时才用到。它们的其他下游（MachOKitUI、SymbolViewer……）不受影响。

### 文档与示例

- 新增使用指南 `Documentations/Internal/TuistDevelopment.md`，登记进 `Documentations/README.md`。
- `AGENTS.md` 构建一节加一条。
- `README.md` 不改：Tuist workspace 只给维护者用。
- RuntimeViewer 的 `Documentations/Guides/TuistDevelopment.md` 改两段（第 5 步）。

## API 演进与废弃策略

无：没有公开 API 变化，不涉及版本号。

## 落地步骤

在 Ultra 上构建与跑测试（本机是 10 核那台），用默认的 Xcode 27.2；第 2、3 步的测试结果另用 Xcode 26.6 的 `swift test` 结果对照。

1. **骨架：远程模式能生成、能编 CLI** —— 改动地图里 `mise.toml`、`Tuist/Package.swift`（不含测试相关）、`Tuist/CommandLine/Project.swift`（只有 `swift-section`）、`Workspace.swift`（无测试 scheme）、`TuistScript.sh`（`install`、`generate`、`build`、`release`，存放位置，锁文件，自己检出的占用）、`.gitignore`、workspace 成员
   - 行为：`generateCreatesTheTuistWorkspaceAndLeavesTheNativeWorkspaceUntouched`
   - 行为：`buildCompilesSwiftSectionFromTheTuistWorkspace`
   - 行为：`generateFailsNamingTheOwnerWhenAnotherCheckoutHoldsThisOne`
   - 行为：`releaseRemovesTheGeneratedProjectsAndTheClaim`
   - 行为：`installWarnsWhenTheResolvedPinsDifferFromTheSeedLockFile`
   - 行为：`usingLocalDependenciesIsIgnoredWithAWarning`
2. **本库的测试** —— `Package.swift` 适配块，`Tuist/Package.swift` 的 swift-snapshot-testing 与测试设置，`Project.swift` 的 `swift_section` 与 `SwiftSectionCommandTests`，`Workspace.swift` 的测试 scheme，脚本的 `test` 命令与清单读取
   - 行为：`theTestSchemeHoldsEveryTestTargetExceptIntegrationTests`
   - 行为：`swiftSectionCommandTestsImportTheCommandModuleAndPass`
   - 行为：`theTuistTestRunMatchesSwiftTestTargetByTarget`
   - 行为：`packageManifestIsUnchangedWithoutTheTuistVariable`（`swift package dump-package` 不带变量时与改动前逐字节相同）
3. **本地模式** —— 三个上游库的适配块（各自的功能分支），`Tuist/Package.swift` 的本地依赖，脚本的模式切换、上游库占用、预检
   - 行为：`localDependenciesBuildTheUpstreamPackagesFromTheirCheckoutsWithUncommittedEdits`
   - 行为：`theModeIsRememberedAndSwitchingResolvesAgain`
   - 行为：`localModeMapsTheTestsOfAllSixPackages`
   - 行为：`anUpstreamCheckoutWithoutTheBlockTurnsTestMappingOffWithAWarning`
   - 行为：`switchingToRemoteReleasesTheUpstreamCheckouts`
4. **二进制缓存** —— `Tuist.swift`，脚本的 `warm` 与 `TUIST_SOURCE_TARGET_NAMES`
   - 行为：`warmCachesEveryThirdPartyPackageAndNoneOfTheSixOwnPackages`
   - 行为：`generateAfterWarmLinksTheCachedBinaries`
   - 行为：`aThirdPartyTargetNamedLikeAnOwnTargetIsReported`
   - 记录：空 DerivedData 下不用缓存与走缓存各编一次 `swift-section` 与测试 scheme 的时间，写进决策日志与指南。
5. **与 RuntimeViewer 互斥** —— RuntimeViewer 的 `TuistScript.sh` 与指南
   - 行为：`runtimeViewerLocalModeFailsWhileMachOSwiftSectionHoldsTheCheckout`
   - 行为：`machOSwiftSectionFailsWhileRuntimeViewerHoldsAnUpstreamCheckout`（新旧两种记录各一次）
   - 行为：`aStaleClaimIsTakenOverSilently`
6. **文档** —— 使用指南、`AGENTS.md`、`Documentations/README.md`

**收尾时必须判断两件事**（判断结果写进决策日志，不允许沉默跳过）：

- **要不要配套专题文章** —— 本提案已定要写使用指南 `Documentations/Internal/TuistDevelopment.md`；实现说明是否另写，收尾时判断。
- **有没有引入新术语** —— 「Tuist 开发 workspace」「本地依赖模式」「占用记录」是否进 `Documentations/Glossary.md`，收尾时判断。

## 决策日志

| 日期 | 变更 | 说明 |
|------|------|------|
| 2026-11-20 | Created as Draft | 用户要一个照 RuntimeViewer 做法建的 Tuist 开发 workspace，依赖可在本地检出与远程版本之间切换，本地依赖就是原生 workspace 里放的那几个上游库。按轻量档处理：新增的开发路径，不改原有的构建、发版与 CI。 |
| 2026-11-20 | 定下三个方向 | 用户选定：提供二进制缓存与 `warm`；Tuist workspace 要能跑测试，先实测再定写法；与 RuntimeViewer 的本地依赖模式双向互斥，为此顺带改 RuntimeViewer 的脚本。 |
| 2026-11-20 | 实测定下测试的写法 | 十项实测见「前期调研」：Tuist 的测试映射对路径包一刀切，会拒绝两种形态的测试；用一段只在 Tuist 解析时生效的清单适配块处理，本库加，三个上游库也要加才能在本地模式下带测试；`SwiftSectionCommandTests` 在 `Tuist/CommandLine/Project.swift` 里手写。三个上游库要不要加，留给用户定。 |
| 2026-11-20 | 用户批准，开始实现 | 用户选定给 MachOKitExtensions、MachOObjCSection、swift-demangling 加适配块，本地模式带测试；状态改 Accepted。实现在本库的 `feature/tuist-workspace`，三个上游库与 RuntimeViewer 各用同名分支。 |
| 2026-11-20 | 清单改由脚本自己读 | 本想直接读 Tuist 缓存的清单索引（`swifterpm/package-info/index.json`），实测设了 `SWIFTPM_BUILD_DIR` 时 Tuist 不产出这份索引，靠它不可靠。改回提案原写法：每次 `install` 之后脚本用 `swift package dump-package`（带 `TUIST_MAPS_LOCAL_PACKAGE_TESTS=1`，8 个并行）读一遍所有包的清单存进 `Work/<checkout>/Manifests/`，名单、预检和同名检查都读它（35 个包）。Python 出错时脚本直接失败，而不是带着空名单生成。 |
| 2026-11-20 | 解析依赖的记号带上清单的 hash | `Work/<checkout>/InstalledDependencies` 除了模式，还记 `Tuist/Package.swift`、`Package.swift`、种子锁文件与（本地模式下）上游库清单的 hash：改了 `Package.swift` 或换了根目录的 `Package.resolved`，下一次 `generate` 自己重新解析，不必记得先跑 `install`。 |
| 2026-11-20 | CLI 的部署版本改为 macOS 12.0 | Ultra 首次构建：Tuist 把 swift-argument-parser 编成它声明的 macOS 12，10.15 的 `swift-section` import 不了它（11 处同一错误，其余全部编过）。 |
| 2026-11-20 | 测试 target 抬到 macOS 14.0（原定「按需」，确认需要） | `TypeIndexingTests` 用的 macOS 13 API 在 10.15 下编不过。脚本把所有转换进来的测试 target（含 `IntegrationTests`）传进新变量 `TUIST_TEST_TARGET_NAMES`。 |
| 2026-11-20 | 手写的 target 设 `SWIFT_PACKAGE_NAME = MachOSwiftSection` | `SwiftSectionCommandTests` 调用 SwiftSectionKit 的 `package` 方法；Tuist 转换的 target 都带这个设置，手写的没有。 |
| 2026-11-20 | 导入 Testing 的库 target 加 TestingMacros 插件路径 | `SwiftSectionTestingSupport` 用了 `#require`，Xcode 只给测试 target 带 TestingMacros 插件。脚本扫描路径包里普通 target 的源码找 `import Testing`，传进新变量 `TUIST_TESTING_SUPPORT_TARGET_NAMES`；本地模式下 swift-demangling 的 `DemanglingTestingSupport` 也会被找到。 |
| 2026-11-20 | `build` / `test` 加 `--scheme` | 本地模式下要跑上游库各自的测试 scheme（`<包名> Tests`）。 |
| 2026-11-20 | MachOKitExtensions 的 `next` 已不需要适配块，仍按决定加上 | 探针用的是它的 `main`（有 `CPlusPlusSymbolsFixture`），`next` 上这个测试支撑 target 已经没有了，块目前不起作用。另：本库 `.worktrees/MachOKitExtensions` 链接指向它的主检出（`main`），不是它的 `next` worktree，所以公司那台上的本地模式编的是 `main`，预检会因为那个 target 关掉测试并点名。 |
| 2026-11-20 | Tuist 往 `PrecompiledLibraries/swift-syntax/` 里写 `.build/` | 它是按路径声明的包，Tuist 在那里下载二进制产物；与它生成的工程一起写进 `.gitignore`。 |
