# 0036 - 把 objc-section 并入 swift-section：`swift-section objc` 子命令组

- **状态**: Implemented
- **作者**: JH
- **创建日期**: 2026-09-23
- **最后更新**: 2026-09-23
- **所属愿景**: 无
- **关联提案**: MachOObjCSection 仓库的 0002（objc-section 命令行的来历）、0006（snapshot / diff / evolution）、0007（`--sections` 写法与空结果提示）、0009（objc-section 的发布流水线，本改动落地后退役）；MachOObjCSection 仓库的 [0010](https://github.com/MxIris-Reverse-Engineering/MachOObjCSection/blob/main/Documentations/Evolutions/0010-remove-objc-section-cli.md)（fork 侧的删除，在本改动随 swift-section 发版之后执行）
- **实现分支 / PR**: `feature/objc-subcommands`（worktree `.worktrees/MachOSwiftSection-ObjCSubcommands`，基于 `next`），按本仓库惯例在本地合并进 `next`
- **配套文档**: 使用指南 [ObjCCommandLine.md](../ObjCCommandLine.md) / [ObjCCommandLine_zh.md](../ObjCCommandLine_zh.md)

## 摘要

把 MachOObjCSection（p-x9/MachOObjCSection 的 fork）里的 `objc-section` 命令行原样搬进本仓库，
成为 `swift-section objc` 子命令组：`dump`（默认）/ `interface` / `snapshot` / `diff` / `evolution`，
参数、输出、退出码与 stderr 提示都和 objc-section 0.8.106 一致。只搬命令行，ObjC 的各个库仍留在
fork 里，本仓库本来就依赖它们。搬完之后只剩一个命令行、一个版本号、一条发布流程，Homebrew
用户升级 swift-section 就能拿到 ObjC 命令。fork 那边的 objc-section 等本改动随 swift-section
发版之后再删。

## 动机

**维护一个 fork 的成本。** MachOObjCSection 是上游仓库的 fork，fork 独有的东西越多，每次同步上游
越痛苦。objc-section 命令行，以及为它新加的发布流水线（MachOObjCSection 0009，2026-09-23 刚发出
第一个版本 0.8.106），都是纯 fork 独有的负担。维护者原话：「这个仓库是 fork 的，维护两边很麻烦」。

**两个命令行已经在漂移，每处改动都要做两遍：**

- **cache 读取方式不同。** 本仓库 `next` 上的 643bc61c 把 `MachOFile.load` 从 `DyldCache` 改成了
  `FullDyldCache`，原因是只覆盖主缓存文件的 `DyldCache` 会让落在子缓存里的镜像读到映射范围之外；
  objc-section 的同名函数还是 `DyldCache`。
- **同一个缺陷修了两次。** `dump --sections` 两种自然写法都会读错的问题，objc-section 在
  MachOObjCSection 0007 修了一次，本仓库 `next` 上又修了一次（`DumpSectionsOptionTests`）。
  0007 的提案里已经写明两边的 `MachOOptionGroup` 同源，缺陷是一起抄过去的。
- **三个文件是逐字复制的。** `Architecture`、`MachOOptionGroup`、`SemanticColorScheme` 在两边行为
  完全相同；objc-section 那边的注释甚至写明「与 swift-section 逐字对齐是有意为之」。

**分发不对等。** swift-section 在 homebrew-core 里，版本号由 Homebrew 的机器人自动跟进；objc-section
只有 GitHub Release 上的一个二进制（0.8.106 是唯一的一个）。

## 前期调研

- **本仓库已经依赖 fork。** `Package.swift` 里的 `MachOObjCSection` 依赖要求 `"0.8.105" ..< "0.9.0"`，
  `Package.resolved` 锁在 0.8.105，已经在用 `MachOObjCSection`、`ObjCIndexing`、`ObjCMetadataSource`
  等产品。objc-section 用到的 `ObjCDiffing` 是 0.8.106 才有的，所以下限要升到 0.8.106。
- **共同依赖的版本范围兼容。** 两边锁定的版本：MachOKit 0.52.102 / 0.52.101（fork 要求
  `from: 0.52.101`）、swift-objc-dump 都是 0.8.101、swift-semantic-string 都是 0.3.0、FrameworkToolbox
  0.9.0 / 0.10.0（fork 要求 `from: 0.9.0`）、swift-argument-parser 都是 1.8.2、Rainbow 都是 4.2.1。
- **objc-section 有 20 个源文件**（`Sources/objc-section/`，fork 的 `next` 分支）。放进同一个模块后：
  - **同名冲突**，需要改名：`DumpCommand`、`InterfaceCommand`、`SnapshotCommand`、`DiffCommand`、
    `EvolutionCommand`、`TransformerOptionGroup`、`BundledVersion`。五个命令的 `commandName` 都是显式
    写的，改类型名不影响命令行拼写。
  - **行为相同，可直接合并**：`Architecture`（只差注释）、`SemanticColorScheme`（只差注释）、
    `MachOOptionGroup`（objc-section 多一个诊断用的 `imageDescription` 计算属性）。
  - **扩展方法重复**：`MachOFile.load(…)` 两个重载、`String.withColorHex` / `withColor`、
    `SemanticString.printColorfully(using:)`。`String` 的两个方法实现相同；`MachOFile.load` 只差上面说的
    `DyldCache` / `FullDyldCache`。
- **换成 `FullDyldCache` 预计不改变 ObjC 输出。** 用已发布的 objc-section 0.8.106 实测宿主缓存里的
  Foundation、AppKit、SwiftUI、SwiftUICore、CoreData，`dump --sections classes` 全部正常输出，没有复现
  643bc61c 描述的问题。所以这只是推测会一致，要靠落地步骤 4 的逐字节对比确认。
- **ObjC 快照不记录工具名。** `ObjCAPIProvenance` 只有 `label`、`binaryPath`、`generatorVersion`、
  `createdAt` 四个字段。搬过来之后 `generatorVersion` 会变成 swift-section 的版本号；兼容性由
  `formatVersion`（当前为 1）决定，0.8.106 生成的基线照样能读。
- **帮助文本里写死了两处 `objc-section snapshot`**（`DiffCommand`、`EvolutionCommand` 的参数说明），
  要改成 `swift-section objc snapshot`。
- **Homebrew 配方不用改。** homebrew-core 的 `swift-section.rb` 执行 `swift build --product swift-section`、
  安装这一个二进制，并用 `--generate-completion-script` 生成补全脚本。子命令随二进制一起进去，补全也会
  自动包含 `objc`。
- **CI 只跑白名单里的测试。** `.github/workflows/macOS.yml` 用 `--filter` 列出要跑的测试套件。
  objc-section 的三个测试套件（`ObjCSectionCommandTests`、`ObjCAPICommandParsingTests`、
  `ObjCDumpDiagnosticsTests`）只测参数解析和纯函数，不依赖本机样本，可以加进白名单。
- **必须基于 `next`。** `next` 比 `main` 多 141 个提交，其中有 ObjC 相关的功能和命令行文件的改动
  （`SwiftSection.swift`、`Extensions.swift`、`InferObjCOverridesFlagTests` 等）。
- **下游。** RuntimeViewerCore 把 MachOObjCSection 锁在 `exact: 0.8.104`、MachOSwiftSection 锁在
  `exact: 0.15.2`，本改动不影响它；它将来升级到包含本改动的 swift-section 时，要把 MachOObjCSection
  一并升到 0.8.106 以上（按现在的依赖要求本来也得升到 0.8.105）。MachOKitUI、REAgent、swift-decompiler
  直接依赖 fork 的库，不用命令行，不受影响。

## 提议方案

在 `swift-section` 下挂一个 `objc` 子命令组，把 objc-section 的五个子命令原样放进去：

```bash
swift-section objc dump Foo.framework/Foo              # = objc-section dump
swift-section objc Foo.framework/Foo                   # dump 仍是默认子命令
swift-section objc interface NSString --uses-system-dyld-shared-cache -n Foundation
swift-section objc snapshot <file> --label 26.0 -o baseline.json
swift-section objc diff old.json new.json --fail-on-breaking
swift-section objc evolution v1.json v2.json v3.json --labels 17.0,18.0,26.0
```

- **纯搬迁，行为不变。** 每个子命令的参数拼写、默认值、stdout、stderr 提示和退出码都与
  objc-section 0.8.106 一致。唯一的例外是快照里的 `generatorVersion`，它记录的是生成工具的版本号。
- 源码放进 `Sources/swift-section/ObjC/`，类型统一加 `ObjC` 前缀。三个行为相同的小类型和重复的
  扩展方法各留一份，用本仓库的实现；`MachOOptionGroup` 补上 `imageDescription`。
- 测试搬进 `Tests/SwiftSectionCommandTests/ObjC/`，并加进 macOS CI 的白名单。
- 版本号跟随 `BundledVersion`。本改动不单独发版，发版时机由维护者决定。

### 非目标

- **不统一两边的 transformer。** `swift-section transformer` 仍只列出 Swift 的注释模块；
  `--transformer-config` 仍忽略配置文件里 ObjC 模块的键。两者对 ObjC 生效是可以单独做的后续工作。
- **不给 Swift 命令加 ObjC 输出。** `dump` / `interface` 等现有命令的行为一个字节都不变。
- **不搬 ObjC 的库。** `ObjCInterface`、`ObjCDiffing` 等仍在 fork 里，本仓库继续以包依赖的方式使用。
- **不保留 `objc-section` 这个命令名**：不做别名，也不做软链接。已发布的 0.8.106 二进制可以作为过渡。
- **不在本提案里发版**，也不包括 fork 那边的删除，后者见 fork 侧的提案。

## 详细设计

### 命令树

```swift
// Sources/swift-section/ObjC/ObjCCommand.swift
import ArgumentParser

struct ObjCCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "objc",
        abstract: "Dump Objective-C declarations out of a Mach-O file or dyld shared cache, and diff their API.",
        subcommands: [
            ObjCDumpCommand.self,
            ObjCInterfaceCommand.self,
            ObjCSnapshotCommand.self,
            ObjCDiffCommand.self,
            ObjCEvolutionCommand.self,
        ],
        defaultSubcommand: ObjCDumpCommand.self
    )
}
```

`SwiftSectionCommand.configuration.subcommands` 末尾加上 `ObjCCommand.self`。顶层的默认子命令仍是
Swift 的 `DumpCommand`。

### 文件去向

| objc-section 里的文件 | 去向 |
|---|---|
| `Commands/DumpCommand.swift` 等五个命令 | `ObjC/Commands/ObjCDumpCommand.swift` 等，类型改名为 `ObjCDumpCommand` / `ObjCInterfaceCommand` / `ObjCSnapshotCommand` / `ObjCDiffCommand` / `ObjCEvolutionCommand`，`commandName` 不变 |
| `ObjCSectionCommand.swift` | 由 `ObjCCommand.swift` 取代 |
| `Version.swift` | 删除，改用本仓库的 `BundledVersion` |
| `Models/Architecture.swift`、`Models/SemanticColorScheme.swift` | 删除，用本仓库的同名类型 |
| `Models/MachOOptionGroup.swift` | 删除；本仓库的 `MachOOptionGroup` 补上 `imageDescription` |
| `Models/TransformerOptionGroup.swift` | `ObjC/Models/ObjCTransformerOptionGroup.swift`（类型改名，内容不变） |
| `Models/GenerationOptionGroup.swift` | `ObjC/Models/ObjCGenerationOptionGroup.swift`（类型改名，内容不变） |
| `Models/ObjCSectionKind.swift`、`ObjCSectionKindList.swift` | 原名搬进 `ObjC/Models/` |
| `Models/ObjCSectionCommandError.swift` | 原名搬进 `ObjC/Models/`，删掉与加载器重复的 7 个 case（见下） |
| `Utilities/MachOFile+Load.swift` | 删除，用本仓库 `Extensions.swift` 里的 `MachOFile.load`（`FullDyldCache`），错误类型沿用本仓库的 `SwiftSectionCommandError` |
| `Utilities/SemanticString+Color.swift` | 删除重复的 `String` 扩展与 `printColorfully(using:)`；只有 objc 那边有的 `colorized(using:)` 搬进 `ObjC/Utilities/` |
| `Utilities/ObjCInterfaceSession.swift`、`ObjCSnapshotInputLoader.swift`、`StandardErrorLog.swift` | 原名搬进 `ObjC/Utilities/` |

`MachOFile.load` 抛出的错误从 `ObjCSectionCommandError` 换成 `SwiftSectionCommandError`。已逐条比对：
与加载相关的 7 个 case（`missingFilePath`、`imageNotFound`、`invalidArchitecture` 等），两边的
`description` 文本逐字相同，所以 stderr 不变。`ObjCSectionCommandError` 只保留 ObjC 专有的 3 个 case：
`declarationNotFound`、`malformedCTypeReplacement`、`unknownCType`。

### Package.swift

```swift
static let swift_section = Target.executableTarget(
    name: "swift-section",
    dependencies: [
        // …existing…
        .product(name: "ObjCInterface", package: "MachOObjCSection"),
        .product(name: "ObjCDiffing", package: "MachOObjCSection"),
        .product(name: "ObjCOutputTransformer", package: "MachOObjCSection"),
        .product(name: "ObjCDeclarationRendering", package: "MachOObjCSection"),
        .product(name: "ObjCIndexing", package: "MachOObjCSection"),
        .product(name: "ObjCMetadataSource", package: "MachOObjCSection"),
        .product(.MachOObjCSection),
        .product(name: "ObjCDump", package: "swift-objc-dump"),
    ],
)
```

`MachOObjCSection` 依赖的远程要求改为 `"0.8.106" ..< "0.9.0"`，`Package.resolved` 同步更新。
`SwiftSectionCommandTests` 按搬过来的测试实际 import 的模块补上对应产品。

### 测试

三个套件搬进 `Tests/SwiftSectionCommandTests/ObjC/`：`@testable import objc_section` 改为
`@testable import swift_section`，被测类型换成新名字，断言内容不动。套件的显示名从
`"objc-section …"` 改成 `"swift-section objc …"`。`macOS.yml` 的 `--filter` 白名单加上
`ObjCSectionCommandTests|ObjCAPICommandParsingTests|ObjCDumpDiagnosticsTests`。

## 替代方案考量

- **同一个包里的第二个可执行文件 `objc-section`**：命令名和参数完全不变。**用户否决。**
  发布流程要多编一个二进制、多传一个附件；homebrew-core 的配方只装 `swift-section`，要安装它得另外
  提 PR；版本号还会从 0.8.106 跳到 swift-section 的 0.2x。
- **把 ObjC 的库一起搬过来**：**用户否决，只搬命令行。** 这些库还被 MachOKitUI、REAgent、
  swift-decompiler、RuntimeViewer 直接依赖，搬库是另一个量级的改动。
- **保留 `objc-section` 命令名作为别名**（安装一个软链接，按 `argv[0]` 分派）：否。多一套安装和分发
  逻辑，和「少维护一份」的目的相反；0.8.106 的二进制已经能当过渡。
- **现在就删掉 fork 端**：**用户否决。** 在 swift-section 下次发版之前，会出现两边都拿不到新版
  ObjC 命令的空窗。
- **抽一个两个命令行共用的支撑库**：只有在做成两个可执行文件时才需要；并进同一个模块后直接共用
  类型即可，不适用。

## 影响

### 源码兼容性（source compatibility）

- **库 API：纯新增，而且实际没有变化。** 所有改动都在 `swift-section` 可执行目标内部。对库使用方唯一
  可见的是依赖解析：MachOObjCSection 的下限从 0.8.105 升到 0.8.106。
- **命令行：纯新增。** 新增 `objc` 子命令组；现有子命令的参数与输出不变。

### ABI 兼容性（条件项）

不适用 —— 本库以 SPM 源码分发，使用方每次重新编译。

### 下游影响

- 本仓库内：`swift-section` 可执行目标、`SwiftSectionCommandTests`、`macOS.yml`。
- RuntimeViewer：目前用精确版本锁住两个库，不受影响；以后升级到包含本改动的 swift-section 时，
  MachOObjCSection 的精确版本要一并提到 0.8.106 以上。
- 其余通过版本范围依赖 MachOSwiftSection 的仓库（MachOKitUI、SymbolViewer 等）：SwiftPM 会自动解析到
  0.8.106，不用改。
- MachOObjCSection（fork）：本改动随 swift-section 发版后，按 fork 侧提案删除 objc-section 与它的发布
  流水线。

### 文档与示例

- README 的「swift-section CLI Tool」一节新增 `#### objc - Objective-C Declarations and API Diffing`。
- 新增 `Documentations/ObjCCommandLine.md`（英文）与 `ObjCCommandLine_zh.md`（中文），内容来自 fork 的
  objc-section 使用指南，包括那六条从签名和帮助文本里看不出来的约定。登记进 `Documentations/README.md`
  的 External 一节。
- `AGENTS.md` 的架构一节写明 `swift-section` 可执行目标现在还依赖 MachOObjCSection 的 ObjC 产品。
- 下一个版本的 `Changelogs/<version>.md` 写明迁移对照：`objc-section <子命令>` → `swift-section objc <子命令>`。

## API 演进与废弃策略

- `objc-section` 这个命令名不做过渡别名。fork 上已发布的 0.8.106 Release 保留，作为最后一个独立的
  objc-section 二进制；swift-section 发版时由 changelog 给出迁移对照。
- 库 API 没有被替代或删除的部分，不需要 `@available(*, deprecated)`，也不需要 semver major 跃迁。

## 落地步骤

1. **依赖**：MachOObjCSection 的下限升到 0.8.106，给 `swift-section` 目标和测试目标补上产品依赖。
   构建通过。
2. **源码**：按「文件去向」搬入、改名、去重，改掉帮助文本里的 `objc-section snapshot`，把 `ObjCCommand`
   挂到 `SwiftSectionCommand` 下。构建通过。
3. **测试**：搬入三个套件并加进 CI 白名单。`swift test` 的原始退出码为 0。
4. **逐字节对比**：拿 objc-section 0.8.106（fork 的 Release 二进制）和新的 `swift-section objc`，在同一批
   输入上比对 stdout、stderr 和退出码：
   - 宿主缓存里的 Foundation、AppKit、SwiftUI、SwiftUICore、CoreData 的 `dump` 与若干 `interface`；
   - 一个没有 ObjC 元数据的二进制（空结果提示）和一个非法的 `--sections` 写法（报错文本）；
   - `snapshot` 生成的 JSON，排除 `generatorVersion` 与 `createdAt` 两个字段后比对；
   - `diff` / `evolution` 的文本与 `--json` 输出。
   任何差异都要逐条解释，不能解释的算缺陷。
5. **文档**：README、`ObjCCommandLine.md` 与中文版、`Documentations/README.md`、`AGENTS.md`、
   `ProjectEvolutionLog`。本提案在落地提交里分配编号并改为 Implemented。
6. 提 PR：`feature/objc-subcommands` → `next`。
7. swift-section 带着本改动发版之后，按 fork 侧提案删除 fork 里的 objc-section。

**收尾时必须判断两件事**（判断结果写进决策日志，不允许沉默跳过）：

- **要不要配套专题文章** —— 计划中的 `ObjCCommandLine.md` 就是面向调用方的使用指南（有六条从签名看不出来的
  约定）；实现层面若发现代码里看不出来的决策，另写实现说明。
- **有没有引入新术语** —— 预计没有；落地时确认。

## 决策日志

| 日期 | 变更 | 说明 |
|------|------|------|
| 2026-09-23 | Created as Draft | 用户原话：「我打算去掉objc-section集成到swift-section里面了，这个仓库是fork的，维护两边很麻烦」 |
| 2026-09-23 | 只搬命令行，ObjC 的库留在 fork | 用户选定 |
| 2026-09-23 | 以 `swift-section objc` 子命令组的形式并入，不做第二个可执行文件 | 用户选定；理由见「替代方案考量」第一条 |
| 2026-09-23 | fork 端在 swift-section 带着本改动发版后再删 | 用户选定；避免出现两边都拿不到新版 ObjC 命令的空窗 |
| 2026-09-23 | 纯搬迁、合并重复的小文件（用本仓库的实现）、基于 `next`、版本号跟随 swift-section、文档按本仓库规矩写中英两份、两个仓库各写一份提案、fork 端的删除清单 | 用户确认这七条默认安排 |
| 2026-09-23 | Draft → Accepted → In Progress | 用户批准，并要求做完直接提交推送 |
| 2026-09-23 | 实现偏差：`MachOOptionGroup` 不合并，ObjC 命令保留 `ObjCMachOOptionGroup` | 前期调研比对的是 `main` 上的版本；`next` 上它已带了 Swift 专用的 `--dependency-search-path`（及其校验）。合并会让每个 ObjC 子命令多出一个不起作用的参数，违背「参数不变」，这一条优先于「合并重复文件」。`Architecture`、`SemanticColorScheme` 在 `next` 上仍只差注释，照原计划合并 |
| 2026-09-23 | 实现偏差：`swift-section` 目标只加 5 个 ObjC 产品 | objc-section 的源码实际只 import `ObjCDeclarationRendering`、`ObjCDiffing`、`ObjCIndexing`、`ObjCInterface`、`ObjCOutputTransformer`；详细设计里另列的 `MachOObjCSection`、`ObjCMetadataSource`、`ObjCDump` 不需要 |
| 2026-09-23 | 实现偏差：不更新 `Package.resolved` | 本仓库不跟踪它（`.gitignore` 的 `*.resolved`） |
| 2026-09-23 | 实现偏差：`SemanticString+Color.swift` 整个不搬 | 去掉与本仓库重复的 `printColorfully` 之后，`colorized(using:)` 已没有调用方 |
| 2026-09-23 | 新增一条根命令接线测试 | `SwiftSectionCommand.parseAsRoot(["objc", …])` 必须落到 `ObjCDumpCommand`；根命令漏挂 `ObjCCommand` 时其余测试照样全过 |
| 2026-09-23 | 使用指南只搬命令行用户需要的四条约定 | fork 指南里另两条（RW data 不在泛型接口上、分析 cache 需要 MachOKit 0.52.101+）以及泛型参数、`ObjCMetadataSource` 两节是写给库调用方的，留在 fork 的库指南里（MachOObjCSection 0010） |
| 2026-09-23 | 逐字节对比通过（落地步骤 4） | 以 objc-section 0.8.106 的 Release 二进制为基准：37 个用例加 5 个子命令的 `--help`。stdout 与退出码全部一致；stderr 只差用法提示里的命令名和 snapshot 写出的文件路径；快照 JSON 只差 `generatorVersion` 与 `createdAt`；`diff --help` 只差一处换行。直接读 15.5 / 26.7 cache 文件的输出也一致，`FullDyldCache` 没有改变 ObjC 输出 |
| 2026-09-23 | 收尾判断：配套文档与术语 | 使用指南已写（`ObjCCommandLine.md` / `_zh`），登记在头部；没有需要单独写实现说明的决策（上面的偏差都记在这里和演进账本里）；没有引入新术语 |
| 2026-09-23 | In Progress → Implemented，落地编号 0036 | 合并进 `next` |
