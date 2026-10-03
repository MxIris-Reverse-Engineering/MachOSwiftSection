# 0058 - 把 swift-section 的功能抽成 SwiftSectionKit 库，CLI 只剩一层包装

- **状态**: Implemented
- **作者**: JH
- **创建日期**: 2026-10-03
- **最后更新**: 2026-10-03
- **所属愿景**: 无
- **关联提案**: [0036](0036-objc-subcommands.md)（`objc` 子命令组并入 swift-section；本提案把它一起抽进库）、[0055](0055-group-sources-by-layer.md)（`Sources/` 按层分组；本提案新增 `Commands/` 一组）
- **实现分支 / PR**: `refactor/swift-section-kit`（worktree `.worktrees/MachOSwiftSection-SwiftSectionKit`，基于 `next`），按本仓库惯例在本地合并进 `next`
- **配套文档**: 使用指南 [SwiftSectionKit.md](../SwiftSectionKit.md) / [SwiftSectionKit_zh.md](../SwiftSectionKit_zh.md)；模块文档 [Modules/SwiftSectionKit.md](../Internal/Modules/SwiftSectionKit.md)

## 摘要

新增一个对外发布的 library product `SwiftSectionKit`，把 `swift-section` 每个子命令真正干活的部分搬进去：加载二进制、组装配置、遍历要输出的内容、写文件、决定输出的先后顺序、算出 diff 有没有破坏性变更。每个子命令对应一个按用途建模的请求类型（`DumpRequest`、`ABIDiffRequest`……），输出交给调用方注入的输出端，测试时换成内存记录器即可断言。`swift-section` 可执行文件只剩一层包装：声明 flag、校验 flag 组合、把 flag 映射成请求、把库的错误翻译回原来的文案、把输出写到 stdout / stderr、决定退出码。范围覆盖全部子命令（含 `objc` 下五个）。输出逐字节保持不变，只有两处有意的偏差（见「两处行为偏差」）。

## 动机

**CLI 的执行逻辑完全没有测试。** `Tests/SwiftSectionCommandTests` 现有 79 个测试，没有一个调用过任何命令的 `run()`（`grep -rn '\.run()'` 结果为 0）。这些测试只验证参数能不能解析（`DumpCommand.parse([...])`），外加两个纯函数（`ObjCDumpCommand.diagnosticNotes(for:)`、`TransformerOptionGroup.buildTransformerConfiguration()`）。下面这些行为今天只能靠手动跑命令来确认：

- `dump` 默认输出全部 section 时吞掉读取失败、显式指定时才报错（`Sources/Executables/swift-section/Commands/DumpCommand.swift:153-281`），以及 `--preferred-binary-order` 的排序规则。
- 写文件和打到终端的细微差别：`interface -o` 写出的文件末尾没有换行，打到终端时有（`InterfaceCommand.swift:204-210`）；`diff` 同样如此，`evolution` 则两边一致（`DiffCommand.swift:212-219`、`EvolutionCommand.swift:103-108`）。
- `interface` 进度行的先后顺序：带 `--emit-header` 时 "Preparing…" 打在建索引之前，否则打在挂完 provider 之后（`InterfaceCommand.swift:120-131`、`192-194`）。
- snapshot 输入的识别与重贴标签（`Utilities/ABISnapshotInputLoader.swift:16-79`）、`--fail-on-breaking` 的退出码（`DiffCommand.swift:144-146`、`EvolutionCommand.swift:110-112`）、annotated interface 的逐行着色规则（`DiffCommand.swift:223-251`、`EvolutionCommand.swift:174-204`）。

**测不了的原因是逻辑和进程缠在一起。** `run()` 里直接 `print` / `fputs` / `FileHandle.write`，直接写文件系统；中途抛 ArgumentParser 的 `ValidationError` 和 `ExitCode`；还把 `Date()` 和 `BundledVersion.value` 盖进输出（`ABISnapshotInputLoader.swift:72-77`），同一输入两次运行的结果都不一样。

**两套命令已经各写各的，开始漂移。** Swift 侧的 `snapshot` 早就因为 `swift-section snapshot … | head` 会让进程 abort，把 `FileHandle.standardOutput.write` 换成了 `fwrite`（`SnapshotCommand.swift:40-49` 的注释）。0036 搬进来的 `objc` 子命令却还在用这个写法（`ObjC/Commands/ObjCSnapshotCommand.swift:37-38`、`ObjC/Utilities/StandardErrorLog.swift:10`）：stderr 被关闭时，`objc` 的任何一条进度行都会让进程 abort。`ABISnapshotInputLoader` 和 `ObjCSnapshotInputLoader` 的嗅探与加载代码几乎逐行相同。输出统一走一个有测试的输出端之后，这类漂移就没有地方藏了。

**做成对外 product，其他宿主也能拿到同一套行为。** 仓库里的 `MCP/swift-section-mcp` 自己重写了一套加载逻辑，已经和 CLI 走岔：它用 `DyldCache` 而不是 `FullDyldCache`（0036 动机里写过，只覆盖主缓存文件的 `DyldCache` 会把落在子缓存里的镜像读到映射范围之外），还按文件名而不是 install name 找 cache 镜像（`MCP/Sources/swift-section-mcp/BinarySession.swift:12-80`）。有了 `SwiftSectionKit`，它以后可以直接复用（本提案不迁移它，见「后续工作」）。

## 前期调研

- **CLI 的构成**：`Sources/Executables/swift-section/` 共 35 个文件、3,476 行。最大的几个是 `DumpCommand.swift`（370 行）、`TransformerOptionGroup.swift`（314 行）、`TransformerCommand.swift`（276 行）、`DiffCommand.swift`（260 行）、`EvolutionCommand.swift`（240 行）、`InterfaceCommand.swift`（212 行）。`objc` 子树约 1,000 行。
- **现有测试**：`DiffCommandValidationTests`、`EvolutionCommandValidationTests`、`HeaderAndExportStatusFlagTests`、`InferObjCOverridesFlagTests`、`DumpSectionsOptionTests`、`ExportedOnlyFlagTests`、`ObjCSectionCommandTests`、`ObjCAPICommandParsingTests` 只测解析与 `validate()`；`TransformerOptionGroupTests` 测模板选项到配置的映射；`ObjCDumpDiagnosticsTests` 测空结果提示的文案。测试目标通过 `@testable import swift_section` 直接依赖可执行目标（`Package.swift:1053-1066`）。
- **每个命令写到哪里**（逐字节保持的依据）：

  | 命令 | stdout | stderr |
  |---|---|---|
  | `dump` | 产物；**每个声明的读取错误**（红色，`DumpCommand.swift:343-345`），带 `-o` 时也照样打到 stdout | 无 |
  | `interface` | **进度行** "Preparing… / Building… / built successfully. / Writing… to X..."（`InterfaceCommand.swift:125`、`193-205`）；不带 `-o` 时产物 | `--resolve-c-module-names` 相关警告（`fputs`）；`ConsoleEventHandler` 的索引事件 |
  | `snapshot` | 产物（`fwrite` + 换行） | 进度行（`fputs`）；索引事件 |
  | `diff` / `evolution` | 产物；`--summary-only` 的结论行 | 进度行（`fputs`）；索引事件（按 old / new 或版本标签分开） |
  | `transformer` | 列表或 JSON | 无 |
  | `objc dump` / `interface` | 产物（`dump` 每个声明后空一行） | 空结果提示、`--verbose` 进度（`FileHandle.standardError.write`） |
  | `objc snapshot` | 产物（`FileHandle.standardOutput.write`） | 进度行（同上） |
  | `objc diff` / `evolution` | 产物 | 进度行（同上） |

  `interface` 进度行混进 stdout 是插件 skill 专门警告过的已知怪癖（`AgentPlugins/swift-section/skills/swift-section-cli/SKILL.md:109-126`）。
- **ArgumentParser 怎么处理 `run()` 抛出的错误**（读 swift-argument-parser 源码 `Sources/ArgumentParser/Usage/MessageInfo.swift:96-118`、`Utilities/Foundation.swift:19-31` 核实）：`ValidationError` 打印报错加用法、退出码 64；`ExitCode` 什么都不打印、按给定码退出；其余错误打印 `LocalizedError.errorDescription`（没有就是 `String(describing:)`）、退出码 1。所以库里的错误一旦换了措辞或类型，CLI 必须翻译回原样。
- **源码扫描会自动覆盖新模块**：`Tests/SwiftInterfaceTests/PrintFailureEventTests.swift:165-280` 禁止库模块写进程流（`print` / `fputs` / `FileHandle.standardOutput` / `FileHandle.standardError`），只豁免 `hostModules = ["swift-section", "MachOTestingSupport"]`，模块名取 `Sources` 下第二层目录。`Sources/Commands/SwiftSectionKit/` 不在豁免名单里，扫描会从机制上保证只有 CLI 层碰 stdout / stderr。
- **请求类型可以做成 `Equatable`**：请求要携带的库类型都已经是值类型且可比较——`Transformer.SwiftConfiguration`（`Sendable, Equatable, Hashable, Codable`）、`ObjCGenerationOptions`（同上）、`ObjCPrimitiveTypePattern`（`Hashable`）、`DependencySearchPath`（`Hashable`）、`SwiftDeclarationMemberSortOrder`（`Hashable`）、`Transformer.Module`（`Hashable`）、`ABISnapshotDocument`（`Equatable`）。这让 CLI 包装层可以用「解析 flag → 生成请求 → 与期望值比较」来测。
- **CI 与版本号**：`.github/workflows/version-check.yml:20` 与 `release.yml:42` 写死了 `Sources/Executables/swift-section/Version.swift`；`release.yml:55-58` 按 product 名 `swift-section` 构建。`macOS.yml:123` 的 `--filter` 白名单只跑点名的套件，`ContinuousIntegrationTestFilterTests` 校验名单里的每个名字都真实存在。
- **A/B 对比脚本的覆盖面**：`Scripts/run-rendering-ab-verification.py:397-444` 对系统框架跑默认参数的 `dump` 与 `interface`，覆盖归档 cache、模拟器 runtime 文件两条 CLI 路径（第三条进程内 `MachOImage` 路径走 `RenderingVerificationTests`，不经过 CLI）。`snapshot` / `diff` / `evolution` / `transformer` / `objc` 与各子命令的 `--help` 都不在它的覆盖范围内。
- **`IgnoreCoding.swift` 没有任何调用方**（`grep -rn IgnoreCoding Sources Tests` 只有定义本身）。
- **`package` 访问级别在本仓库已大量使用**（340 个文件）——只与被否的「仅包内可见」方案有关，见「替代方案考量」。

## 提议方案

```
swift-section（可执行文件）   flag 声明与 --help、validate()、命令行拼写的解释、flag → 请求、
                              错误翻译回原文案、诊断写哪个流、终端着色（Rainbow）、退出码、BundledVersion
    └── SwiftSectionKit（新 product）   每个子命令一个请求类型、Mach-O 加载、snapshot 输入加载、
                                        输出端协议、全部编排逻辑
            └── SwiftInterface、SwiftDump、SwiftDiffing、TypeIndexing、MachOObjCSection 的 ObjC 产品……
```

- **每个子命令一个请求类型**，`run(output:environment:)` 执行。互斥选项用 enum 表达，非法组合在类型上写不出来；例如 `diff` 的输出只能是 change list / summary / JSON / annotated interface 之一。
- **输出端**是调用方注入的 `SwiftSectionOutput`，分三路：产物（`write`）、诊断（`report`）、索引事件 handler（`indexEventHandlers(forInputLabeled:)`）。`dump` 照旧边算边输出，错误与正文的先后顺序不变。
- **诊断 = 级别 + 原文**。级别是 progress / warning / note / error，原文就是 CLI 现在打出来的那句话。产物那一路只放真正的产物。哪一级写哪个流由 CLI 决定：`interface` 的 progress 和 `dump` 的 error 写 stdout，其余写 stderr。两个怪癖因此只留在 CLI 包装层，以后修只改一处。
- **环境**（`SwiftSectionEnvironment`）注入生成器名、版本和当前时间。CLI 传 `swift-section` 和 `BundledVersion.value`，测试传固定值。
- **库不依赖 ArgumentParser 和 Rainbow。** 库里的 enum（`Architecture`、`DumpSection`……）在 CLI 里用 `@retroactive` 补上 `ExpressibleByArgument`。
- **CLI 保留的只有**：flag 声明（`--help` 文本逐字不变）、`validate()`（报错文案不变）、命令行拼写的解释（模板名或字面模板、`--transformer-config` JSON 文件、逗号分隔的列表、`--c-type-replacement` 的 `a=b` 串、demangle 覆盖开关）、flag → 请求的映射、库错误翻译回历史文案、诊断的流路由、着色、退出码。
- **测试**：库这一侧，每个请求对 SymbolTestsCore fixture 端到端跑一遍，再加纯逻辑测试；CLI 这一侧，测 flag → 请求映射、错误翻译、流路由。新套件加进 CI 白名单。

### 两处行为偏差

除这两处外，stdout、stderr、退出码、每个子命令的 `--help` 全部逐字节不变。

1. **写流统一走 `fputs` / `fwrite`。** 只在流已经被关闭时有区别：`objc` 子命令不再因此 abort（Swift 侧本来就是这样）。
2. **参数层面的错误改在打开二进制之前报出。** 命令行拼写现在由 CLI 解释，并且发生在调用库之前。受影响的错误有：输入 flag 的组合错误（缺文件路径、`-n` 与 `-p` 同时给、`--dyld-shared-cache` 缺镜像名）、模板名 / `--transformer-config`、C type 替换串。只写错一处时，报错文案和退出码不变，只是不必等二进制加载完；同时写错二进制路径和这类参数时，现在先报后者；`objc --verbose` 下，C type 替换串的错误前面不再有进度行。实现时又确认了同一原因的三个边角：`interface` 的「--supplementary-apinotes has no effect」警告在加载前发出；`snapshot` 给 snapshot JSON 输入时乱写 `--dyld-shared-cache` 现在报错；`snapshot` 对普通文件给 `-n` / `-p` 时 provenance 不再带上那个被忽略的镜像名（见决策日志）。

### 非目标

- **不改 CLI 行为**，上面两处偏差除外。`interface` 进度行与 `dump` 错误行打到 stdout 的怪癖原样保留。
- **不迁移 MCP server**，见「后续工作」。
- **不给库加 CLI 没有的能力**，例如以进程内 `MachOImage` 为输入、snapshot 输入直接给内存中的 document。`SnapshotSource` 是 enum，为后者留了位置。
- **不动现有 product 的公开 API**，不动 `baseline-generator`。
- **不在本提案里发版**。0.22.0 的发版说明到时补一条新 product。

### 后续工作

- 修掉两个输出怪癖：`interface` 进度行与 `dump` 错误行改到 stderr，同步改插件 skill 第 3 节。届时库里也不再有「写 stdout 的诊断」。
- `MCP/swift-section-mcp` 改用 `SwiftSectionKit` 的 `MachOSource` 加载与各请求。
- 诊断原文里还有 CLI 的 flag 名（例如 "warning: --resolve-c-module-names …"），可以随第一条一起改成中性措辞。

## 详细设计

### 模块与目录

```swift
// Package.swift
static let SwiftSectionKit = Target.target(
    name: "SwiftSectionKit",
    dependencies: [
        .target(.MachOFoundation),
        .target(.SwiftDump),
        .target(.SwiftInspection),
        .target(.SwiftOutputTransformer),
        .target(.SwiftDeclaration),
        .target(.SwiftDeclarationRendering),
        .target(.SwiftIndexing),
        .target(.SwiftPrinting),
        .target(.SwiftDiffing),
        .target(.SwiftInterface),
        .target(.TypeIndexing),
        .product(name: "ObjCDeclarationRendering", package: "MachOObjCSection"),
        .product(name: "ObjCDiffing", package: "MachOObjCSection"),
        .product(name: "ObjCIndexing", package: "MachOObjCSection"),
        .product(name: "ObjCInterface", package: "MachOObjCSection"),
        .product(name: "ObjCMetadataSource", package: "MachOObjCSection"),
        .product(name: "ObjCOutputTransformer", package: "MachOObjCSection"),
        // plus the products its sources import directly (Semantic, MachOKit, …)
    ],
    path: "Sources/Commands/SwiftSectionKit",
)

static let swift_section = Target.executableTarget(
    name: "swift-section",
    dependencies: [
        .target(.SwiftSectionKit),
        // what the wrapper itself names while mapping flags to requests
        .target(.SwiftDump),
        .target(.SwiftOutputTransformer),
        .target(.SwiftIndexing),
        .product(name: "ObjCDeclarationRendering", package: "MachOObjCSection"),
        .product(name: "ObjCOutputTransformer", package: "MachOObjCSection"),
        .product(name: "Rainbow", package: "Rainbow"),
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
    ],
    path: "Sources/Executables/swift-section",
)
```

`products:` 加 `.library(.SwiftSectionKit)`；新增测试目标 `SwiftSectionKitTests`。`Sources/Commands/` 是新的一层分组：这个库是可执行文件背后那一层，放进 `Executables/` 名不副实。

### 输出端

```swift
// Sources/Commands/SwiftSectionKit/Output/SwiftSectionOutput.swift
import Foundation
import Semantic
import SwiftDeclaration

/// Where a request's output goes. `swift-section` writes it to stdout and
/// stderr; a test records it.
///
/// A request that indexes several inputs side by side calls this from several
/// tasks at once, so an implementation must be safe to call concurrently.
public protocol SwiftSectionOutput: Sendable {
    /// One piece of the product, in order. Printed, every piece is followed
    /// by a newline.
    func write(_ product: SwiftSectionProduct)

    /// A progress line, warning, note or per-declaration error.
    func report(_ diagnostic: SwiftSectionDiagnostic)

    /// The indexing-event handlers for one indexed input. `label` names the
    /// input when a request indexes several ("old", "new", a version label),
    /// and is `nil` for a single-input request.
    func indexEventHandlers(forInputLabeled label: String?) -> [any SwiftIndexEvents.Handler]
}

extension SwiftSectionOutput {
    /// No handler: indexing degradations fall to `Dispatcher`'s os_log floor.
    public func indexEventHandlers(forInputLabeled label: String?) -> [any SwiftIndexEvents.Handler] {
        []
    }
}

public enum SwiftSectionProduct: Sendable {
    /// Rendered declarations (`dump`, `interface`, `objc dump`,
    /// `objc interface`), carrying the semantic types a terminal colors by.
    case declarations(SemanticString)
    /// Plain text: reports, JSON, listings.
    case text(String)
    /// An annotated interface, whose lines a terminal colors by annotation.
    case annotatedInterface(String, style: InterfaceAnnotationStyle)
    /// Raw bytes: a snapshot document's JSON.
    case data(Data)
}

public enum InterfaceAnnotationStyle: Sendable, Hashable {
    /// `diff --interface`. A unified diff also has two file-header lines and
    /// `@@` hunk headers.
    case diff(isUnifiedDiff: Bool)
    /// `evolution --interface`: trailing `// [...]` lifecycle annotations and
    /// column-0 legend comments.
    case evolution
}

/// What a terminal colors one annotated line as.
public enum AnnotatedLineKind: Sendable, Hashable {
    case added
    case removed
    case modified
    case header
    case plain
}

extension InterfaceAnnotationStyle {
    /// The rule `swift-section` colors by, public so that every host colors
    /// alike: one kind per line of `text`, split on "\n" keeping empty lines.
    public func lineKinds(of text: String) -> [AnnotatedLineKind]
}

public struct SwiftSectionDiagnostic: Sendable, Hashable {
    public enum Severity: Sendable, Hashable, CaseIterable {
        case progress
        case warning
        case note
        case error
    }

    public var severity: Severity
    /// The line exactly as `swift-section` prints it.
    public var message: String

    public init(severity: Severity, message: String)
}

/// Where the product goes.
public enum ProductDestination: Sendable, Hashable {
    /// To the request's `SwiftSectionOutput`.
    case output
    /// Into this file; the output then receives diagnostics only.
    case file(URL)
}
```

「每块产物后面跟一个换行」这条语义是盘点出来的：现有的每处 stdout 写入都等于「内容 + 换行」。`print(x)` 如此；annotated interface 按行着色后逐行补换行，拼起来恰好也是「全文 + 换行」；`snapshot` 的 `fwrite` 加 `fputs("\n")` 同样如此。写文件时各命令的老规矩（`interface` / `diff` 不补换行、`evolution` 补、`dump` 每块补）由库自己处理，`.file` 目的地下不经过输出端。

### 输入

```swift
public enum Architecture: String, CaseIterable, Sendable, Hashable {
    case x86_64
    case arm64
    case arm64e
}

public enum DyldSharedCacheImage: Sendable, Hashable {
    case name(String)
    case path(String)
}

/// Where a Mach-O image comes from.
public enum MachOSource: Sendable, Hashable {
    /// A thin or fat Mach-O file; `architecture` picks a fat binary's slice.
    case file(path: String, architecture: Architecture?)
    /// One image of the dyld shared cache at `cachePath`.
    case dyldSharedCache(cachePath: String, image: DyldSharedCacheImage)
    /// One image of the running system's dyld shared cache.
    case systemDyldSharedCache(image: DyldSharedCacheImage)
}

extension MachOSource {
    /// The loader every request shares (today's `MachOFile.load`).
    public func load() throws -> MachOFile
}

public enum MachOSourceError: Error, LocalizedError, Sendable, Equatable {
    case fatBinaryRequiresArchitecture(availableArchitectures: [String])
    case architectureNotFound(Architecture)
    case dyldSharedCacheImageNotFound(DyldSharedCacheImage)
    case systemDyldSharedCacheUnavailable
}

/// Where a snapshot comes from.
public enum SnapshotSource: Sendable, Hashable {
    /// A snapshot document (JSON) or a binary, told apart by the file's first
    /// non-whitespace byte, as the command line always has.
    case path(String)
}

public enum SnapshotSourceError: Error, LocalizedError, Sendable, Equatable {
    /// An annotated interface renders from the live models; a snapshot
    /// document carries none.
    case binaryRequired(path: String)
}

/// How `snapshot` / `diff` / `evolution` load a binary input. A snapshot
/// document input ignores it.
public struct BinaryLoadingOptions: Sendable, Hashable {
    public var architecture: Architecture?
    /// When set, every binary input is a dyld shared cache and this image is
    /// extracted from each.
    public var dyldSharedCacheImage: DyldSharedCacheImage?

    public init(architecture: Architecture? = nil, dyldSharedCacheImage: DyldSharedCacheImage? = nil)
}
```

今天的 `SwiftSectionCommandError` 里，缺文件路径、`-n` 与 `-p` 同时给、缺镜像名这三种在 `MachOSource` 上写不出来，留在 CLI，由 flag → `MachOSource` 的映射抛出，文案不变。`failedFetchFromSystemDyldSharedCache` 从来没有被抛出过，删掉。

### 环境

```swift
public struct GeneratorIdentity: Sendable, Hashable {
    public var name: String
    public var version: String

    public init(name: String, version: String)
}

public struct SwiftSectionEnvironment: Sendable {
    /// Stamped into interface headers and snapshot provenance.
    public var generator: GeneratorIdentity
    /// Stamped into snapshot provenance as `createdAt`.
    public var currentDate: @Sendable () -> Date

    public init(generator: GeneratorIdentity, currentDate: @escaping @Sendable () -> Date = { Date() })
}
```

`BundledVersion` 留在 `Sources/Executables/swift-section/Version.swift`，CI 两个 workflow 不用改。版本号标识的是工具而不是库，其他宿主应该盖上自己的名字。

### 请求类型

两个写全的例子：

```swift
public struct DumpRequest: Sendable, Equatable {
    public enum SectionSelection: Sendable, Hashable {
        /// Every section; one the binary does not carry is skipped silently.
        case all
        /// These sections, in this order; one that fails to read is reported.
        case only([DumpSection])
    }

    public enum Ordering: Sendable, Hashable {
        /// Section by section.
        case bySection
        /// Types, protocols and `@objc @implementation` classes interleaved
        /// by their offset in the binary, then conformances, then associated
        /// types.
        case binaryOrder
    }

    public enum FieldOffsetComments: Sendable, Hashable {
        case none
        case flat
        /// Nested struct fields expanded with their absolute offsets.
        case expanded
    }

    public var source: MachOSource
    public var dependencySearchPaths: [DependencySearchPath]
    public var sections: SectionSelection
    public var ordering: Ordering
    public var demangleOptions: DemangleOptions
    public var fieldOffsetComments: FieldOffsetComments
    public var emitsMemberAddresses: Bool
    public var emitsVTableOffsets: Bool
    public var emitsProtocolWitnessTableAddresses: Bool
    public var emitsTypeLayout: Bool
    public var emitsEnumLayout: Bool
    public var emitsExportStatus: Bool
    public var emitsHeader: Bool
    public var commentTransformers: Transformer.SwiftConfiguration?
    public var destination: ProductDestination

    public init(source: MachOSource)

    public func run(output: some SwiftSectionOutput, environment: SwiftSectionEnvironment) async throws
}

public struct ABIDiffRequest: Sendable, Equatable {
    public enum Report: Sendable, Hashable {
        /// The change list followed by the verdict line.
        case changeList
        /// The verdict line alone.
        case summary
        /// The diff with provenance, as JSON.
        case json
        /// The full interface annotated with diff markers; both sides must be
        /// binaries. With `includesBreakingChangeVerdict`, the outcome also
        /// says whether the diff breaks the ABI, at the cost of a change-list
        /// diff on top.
        case annotatedInterface(format: AnnotatedDiffFormat, includesBreakingChangeVerdict: Bool)
    }

    public var old: SnapshotSource
    public var new: SnapshotSource
    public var binaryLoading: BinaryLoadingOptions
    public var report: Report
    public var destination: ProductDestination
    /// How many inputs index at once: `nil` is the processor count, and `1`
    /// indexes the old side before the new one.
    public var maximumConcurrentPreparations: Int?

    public init(old: SnapshotSource, new: SnapshotSource, report: Report)

    public func run(output: some SwiftSectionOutput, environment: SwiftSectionEnvironment) async throws -> ABIDiffOutcome
}

public enum AnnotatedDiffFormat: Sendable, Hashable {
    case inline
    case unified
    case markdownFenced
}

public struct ABIDiffOutcome: Sendable {
    /// `nil` only for an annotated interface requested without the verdict.
    public var diff: ABIDiff?

    public var hasBreakingChange: Bool? {
        diff?.hasBreakingChange
    }
}
```

其余请求：

| 请求 | 对应子命令 | 字段（按用途建模之处加粗） | 返回 |
|---|---|---|---|
| `InterfaceRequest` | `interface` | `source`、`dependencySearchPaths`、`showsCImportedTypes`、`parsesOpaqueReturnTypes`、**`cModuleNameResolution: .disabled / .enabled(supplementaryAPINotesPaths:)`**、**`fieldOffsetComments: .none / .flat / .expanded`**、`emitsMemberAddresses`、`emitsVTableOffsets`、`emitsTypeLayout`、`emitsEnumLayout`、`emitsExportStatus`、`printsExportedDeclarationsOnly`、`memberSortOrder: SwiftDeclarationMemberSortOrder`、`infersObjCOverridesFromSelectorNames`、`emitsHeader`、`commentTransformers`、`destination` | — |
| `ABISnapshotRequest` | `snapshot` | `source: SnapshotSource`、`binaryLoading`、`dependencySearchPaths`（今天只交给 accessor thunk 读取器，索引器不用；照旧）、`label`、`destination` | `ABISnapshotDocument` |
| `ABIEvolutionRequest` | `evolution` | `inputs: [SnapshotSource]`、`labels: [String]?`、`binaryLoading`、**`report: .lineage / .summary / .json / .annotatedInterface`**、`destination`、`maximumConcurrentPreparations` | `ABIEvolutionOutcome`（`evolution`、`hasBreakingChange`） |
| `TransformerTokensRequest` / `TransformerTemplatesRequest` | `transformer tokens` / `templates` | `module: TransformerModule?`（`nil` 列出全部） | — |
| `TransformerConfigurationRequest` | `transformer config` | `configuration: Transformer.SwiftConfiguration`、`destination` | — |
| `ObjCDumpRequest` | `objc dump` | `source`、**`kinds: [ObjCDeclarationKind]?`**（`nil` 为全部，此时空的 kind 不提示）、`nameFilter`、`generation: ObjCGenerationOptions`、`cTypeReplacements: [ObjCPrimitiveTypePattern: String]`、`ivarOffsetComment: Transformer.ObjCIvarOffset?`（给了就隐含打开 ivar offset 注释）、`reportsIndexingProgress`、`imageDescription: String?`、`destination` | — |
| `ObjCInterfaceRequest` | `objc interface` | `declarationName`、`kind: ObjCDeclarationKind?`、`source`、`generation`、`cTypeReplacements`、`ivarOffsetComment`、`reportsIndexingProgress`、`destination` | — |
| `ObjCAPISnapshotRequest` | `objc snapshot` | `source: SnapshotSource`、`binaryLoading`、`label`、`destination`（ObjC 侧没有 `--dependency-search-path`） | `ObjCAPISnapshotDocument` |
| `ObjCAPIDiffRequest` | `objc diff` | `old`、`new`、`binaryLoading`、**`report: .changeList / .summary / .json`**、`destination` | `ObjCAPIDiffOutcome` |
| `ObjCAPIEvolutionRequest` | `objc evolution` | `inputs`、`labels`、`binaryLoading`、**`report: .lineage / .summary / .json`**、`destination` | `ObjCAPIEvolutionOutcome` |

几处说明：

- `DumpSection` 是今天的 `SwiftSection` 改名，`ObjCDeclarationKind` 是 `ObjCSectionKind` 改名。作为公开类型，旧名分别容易和包名、和 section 的概念混淆。rawValue 不变，所以 `--help` 里列出的取值不变。
- `labels` 的个数校验在库里，抛出的仍是 `ABIEvolutionError.labelCountMismatch` / `ObjCAPIEvolutionError.labelCountMismatch`，文案和退出码不变；逗号拆分属于命令行拼写，留在 CLI。
- `objc dump` 提示文案里的镜像名今天取「用户敲的写法」：`-n` → `-p` → 文件路径。`imageDescription` 让 CLI 照旧传这个值；不传时按 `source` 推导。
- `--supplementary-apinotes` 不带 `--resolve-c-module-names` 时，在 `cModuleNameResolution` 上写不出来，所以那条 "has no effect" 警告改由 CLI 发出，原文不变。
- `objc` 的 `diff` / `evolution` 今天逐个加载输入，库里保持不变。

### 错误

库抛出的错误用中性措辞（不提 flag 名）。CLI 在 `run()` 里捕获，翻译回历史文案：

| 库错误 | CLI 打印（不变） |
|---|---|
| `MachOSourceError.fatBinaryRequiresArchitecture` | "The file is a fat (universal) binary. You must specify an architecture using --architecture (-a). …"（退出码 1） |
| `.architectureNotFound` / `.dyldSharedCacheImageNotFound` / `.systemDyldSharedCacheUnavailable` | `invalidArchitecture` / `imageNotFound` / `unsupportedSystemVersionForDyldSharedCache` 的原文（退出码 1） |
| `diff` 里的 `SnapshotSourceError.binaryRequired` | `ValidationError("--interface needs two binaries; snapshot JSON inputs only support the change-list report.")`（退出码 64） |
| `evolution` 里的 `SnapshotSourceError.binaryRequired(path:)` | `ValidationError("--interface needs binaries; snapshot JSON inputs (<path>) only support the lineage report.")`（退出码 64） |

其他错误原样透传：snapshot 解码、写文件、MachOKit 读文件、`labelCountMismatch`，以及 `objc interface` 找不到声明（"No class, protocol, category, struct or union named '…' in this binary."，本来就是中性措辞，库里保留原文）。

诊断不翻译：原文就是 CLI 的措辞，有些含 flag 名（例如 "warning: --supplementary-apinotes path does not exist: …"）。这是选定「诊断 = 级别 + 原文」的直接结果，列在「后续工作」里。

### CLI 包装层长什么样

```swift
// Sources/Executables/swift-section/Commands/DiffCommand.swift (after)
struct DiffCommand: AsyncParsableCommand {
    // every @Argument / @Option / @Flag declaration unchanged

    func validate() throws {
        // unchanged
    }

    /// The library request these flags describe.
    func makeRequest() -> ABIDiffRequest {
        let report: ABIDiffRequest.Report
        if interface {
            report = .annotatedInterface(
                format: (format ?? .inline).annotatedDiffFormat,
                includesBreakingChangeVerdict: failOnBreaking
            )
        } else if json {
            report = .json
        } else if summaryOnly {
            report = .summary
        } else {
            report = .changeList
        }
        // validate() has already required exactly one of -n / -p with --dyld-shared-cache
        let cacheImage: DyldSharedCacheImage? = cacheImageName.map { .name($0) } ?? cacheImagePath.map { .path($0) }
        var request = ABIDiffRequest(old: .path(oldPath), new: .path(newPath), report: report)
        request.binaryLoading = BinaryLoadingOptions(
            architecture: architecture,
            dyldSharedCacheImage: isDyldSharedCache ? cacheImage : nil
        )
        request.destination = outputPath.map { .file(URL(fileURLWithPath: $0)) } ?? .output
        request.maximumConcurrentPreparations = jobs
        return request
    }

    func run() async throws {
        let outcome = try await CommandLineErrorTranslation.translating(for: Self.self) {
            try await makeRequest().run(output: StandardStreamOutput(), environment: .commandLine)
        }
        if failOnBreaking, outcome.hasBreakingChange == true {
            throw ExitCode.failure
        }
    }
}
```

```swift
// Sources/Executables/swift-section/Output/StandardStreamOutput.swift
/// Writes a request's output where `swift-section` has always written it:
/// the product to stdout, diagnostics to stderr, except the severities a
/// command lists in `standardOutputSeverities`.
struct StandardStreamOutput: SwiftSectionOutput {
    var colorScheme: SemanticColorScheme = .none
    /// `interface` prints its progress lines on stdout and `dump` its
    /// per-declaration errors. Both are historical and kept for byte-identical
    /// output; see the proposal's follow-up work.
    var standardOutputSeverities: Set<SwiftSectionDiagnostic.Severity> = []

    func write(_ product: SwiftSectionProduct) {
        // fputs / fwrite to stdout, every piece followed by "\n";
        // declarations colored by colorScheme, annotated lines by lineKinds(of:)
    }

    func report(_ diagnostic: SwiftSectionDiagnostic) {
        // stdout when standardOutputSeverities contains the severity, else stderr;
        // an .error on stdout is red, as dump's error lines are today
    }

    func indexEventHandlers(forInputLabeled label: String?) -> [any SwiftIndexEvents.Handler] {
        [ConsoleEventHandler(label: label)]
    }
}
```

`StandardStreamOutput` 写入的两个 `FILE*` 可以注入，测试拿 `open_memstream` 读回字节。

### 文件去向

| 现在 | 去向 |
|---|---|
| `Commands/*.swift` 与 `ObjC/Commands/*.swift` 的 `run()` 主体 | `SwiftSectionKit/Swift/*Request.swift`、`SwiftSectionKit/ObjC/*Request.swift`；命令文件只留 flag、`validate()`、`makeRequest()`、`run()` 的三五行 |
| `Utilities/Extensions.swift` 的 `MachOFile.load` | `SwiftSectionKit/Inputs/MachOSource.swift` |
| `Utilities/Extensions.swift` 的配色与 `printColorfully` | `swift-section/Output/StandardStreamOutput.swift` |
| `Utilities/ABISnapshotInputLoader.swift`、`ObjC/Utilities/ObjCSnapshotInputLoader.swift` | `SwiftSectionKit/Inputs/`，两份嗅探代码合成一份 |
| `ObjC/Utilities/ObjCInterfaceSession.swift` | `SwiftSectionKit/ObjC/`（internal） |
| `ObjC/Utilities/StandardErrorLog.swift` | 删除，由 `StandardStreamOutput` 取代 |
| `Utilities/IgnoreCoding.swift` | 删除（没有调用方） |
| `ObjCDumpCommand.diagnosticNotes(for:)` 与 `Outcome` | `SwiftSectionKit/ObjC/`，`ObjCDumpDiagnosticsTests` 随之搬进 `SwiftSectionKitTests` |
| `TransformerCommand.swift` 的 `TransformerModuleSelector` 与列表格式化 | `SwiftSectionKit/Swift/`（`TransformerModule` 与三个请求） |
| `Models/Architecture.swift`、`SwiftSection.swift`、`ObjC/Models/ObjCSectionKind.swift` | `SwiftSectionKit`（`Architecture`、`DumpSection`、`ObjCDeclarationKind`），`ExpressibleByArgument` 留在 CLI |
| `Models/*OptionGroup.swift`、`ObjC/Models/*OptionGroup.swift`、`ObjCSectionKindList.swift`、`SemanticColorScheme.swift`、`Version.swift` | 留在 CLI |
| `Models/SwiftSectionCommandError.swift`、`ObjC/Models/ObjCSectionCommandError.swift` | 留在 CLI，只装历史文案（翻译目标、C type 替换串错误）；`declarationNotFound` 移到库 |

`DumpCommand` 里逐类型 dump 的辅助函数标着 `@MainActor`，搬进库时去掉：循环本来就是顺序执行，去掉不影响输出顺序，而且库的入口不该要求调用方在 main actor 上。

### 测试

- **`SwiftSectionKitTests`（新）**：内存记录器 `RecordingOutput` 按调用顺序记下产物和诊断。对 SymbolTestsCore fixture 跑每个请求：
  - `dump`：默认 section 与显式 section 的报错差异、两种排序、`.file` 目的地写出的字节、固定生成器下的 header、注释开关与模板配置生效、`objcImplementationClasses` 为空时的提示。
  - `interface`：带与不带 header 时的 progress 顺序、`.file` 目的地。
  - `snapshot`：返回的 document、固定时间与版本的 provenance、重贴 snapshot JSON 的标签。
  - `diff` / `evolution`：fixture 对自身无变化、snapshot 与二进制混用、四种报告、annotated interface 遇到 snapshot 输入抛 `SnapshotSourceError`、标签个数不符。
  - `transformer` 的三个列表；`objc` 五个请求。
  - 纯逻辑：`MachOSource` 的各个错误路径、`lineKinds(of:)` 的着色分类、合并后的 snapshot 嗅探。
  - fixture 的 `ExclusiveImageAccess` 声明照现有 fixture 套件的做法来。
- **`SwiftSectionCommandTests`（保留并补充）**：现有解析测试不动（类型改名处随改）。新增：每个命令「解析 flag → `makeRequest()` → 与期望请求比较」、错误翻译（库错误 → 历史文案与退出码）、`StandardStreamOutput` 的流路由与换行语义、流已关闭时不 abort。
- **源码扫描**：`PrintFailureEventTests` 不改豁免名单，靠它保证 `SwiftSectionKit` 里没有任何进程流写入。
- **CI**：新套件名加进 `macOS.yml` 的白名单。

### 验收

1. `swift test --skip IntegrationTests` 的原始退出码为 0（全量，不只 CI 子集）。
2. A/B 对比脚本：基准为 `next`，候选为本分支，`dump` 与 `interface` 逐字节一致。
3. 新旧两个二进制逐字节对比 A/B 脚本覆盖不到的部分：根命令与每个子命令的 `--help` 和 `--version`；`snapshot` / `diff` / `evolution` 的各种报告（JSON 去掉 `createdAt` 后比）；`transformer` 三个子命令；`objc` 五个子命令；若干错误路径（文件不存在、胖二进制没给 `-a`、flag 组合错误）。比较 stdout、stderr 和退出码，凡有差异逐条解释，只允许出现「两处行为偏差」里的那两类。这个对比脚本写完先给用户看再跑。
4. `SwiftSectionKit` 能为包声明的每个平台编译（macOS、iOS、tvOS、watchOS、visionOS），因为它现在是对外 product。
5. 插件 skill 里点名的每个 flag 在 `--help` 里都还在（`grep -ohE -- '--[a-z][a-z0-9-]+'`）。CLI 行为不变，skill 本身不用改。

## 替代方案考量

- **仅包内可见的 target（`package` 访问级别，不进 products）**：不新增对外契约，以后要复用再升格。**用户否决**，选择直接做成对外 product。
- **只抽 Swift 侧、`objc` 以后再说**：**用户否决**，要一次性让整个 CLI 层变薄。
- **请求返回完整结果值、CLI 再打印**：测试最直接，但 `dump` 大框架要等全部算完才出第一行，错误与正文的穿插顺序也要另外记录。**用户否决。**
- **请求字段一比一镜像 flag**（`json: Bool`、`summaryOnly: Bool`，校验和报错一起搬进库）：搬迁最省事，但库的 API 带着命令行的味道，非法组合写得出来，程序调用方还会收到提到 `--json` 的报错。**用户否决。**
- **结构化诊断事件**（每种诊断一个带数据的 enum case）：调用方能按数据处理，但 public enum 每加一个 case 对下游都是源码破坏。**用户否决。**
- **输出端照搬两个流**（`standardOutput` / `standardError`）：最简单，但程序调用方拿到的产物里会混进 `interface` 的进度行。**用户否决。**
- **在这次改动里顺手修掉输出怪癖**：重构和行为变化混在一起，A/B 对比就没法当验收证据了。**用户否决**，列为后续工作。
- **不重构，测试时启动编好的可执行文件、抓它的输出**：测试拿不到可靠的二进制路径，每个用例起一个进程很慢，没法注入时间和版本，也给不出程序化 API。不采用。
- **把 `BundledVersion` 搬进库**：要改两个 CI workflow 里写死的路径，而且版本号标识的是工具。不采用。
- **把命令行拼写的解释（模板名、C type 替换串等）也搬进库**：好处是「参数错误先于加载报出」这处偏差不会出现。代价是要么让请求携带未解析的字符串（又回到镜像 flag），要么在公开 API 里带上 CLI 的 option 名作报错文案。不采用，偏差留档在「两处行为偏差」。
- **迁移 MCP server**：**用户选定不在本次范围**，列为后续工作。

## 影响

### 源码兼容性（source compatibility）

- **库 API：纯新增。** 新增 product `SwiftSectionKit`；现有 product 的公开 API 一个都不变。
- **命令行：除「两处行为偏差」外不变。** flag、`--help`、stdout、stderr、退出码保持原样。

### ABI 兼容性（条件项）

不适用 —— 本库以 SPM 源码分发，使用方每次重新编译。

### 下游影响

- 本仓库内：`swift-section` 可执行目标、`SwiftSectionCommandTests`、新增的 `SwiftSectionKit` 与 `SwiftSectionKitTests`、`Package.swift`、`macOS.yml` 的白名单。`release.yml` / `version-check.yml` 不变。
- 下游仓库：没有一个必须改。RuntimeViewer、MachOKitUI、SymbolViewer 不依赖新 product。`MCP/swift-section-mcp` 以后可以改用它（后续工作）。

### 文档与示例

- 新增使用指南 `Documentations/SwiftSectionKit.md`（英文）与 `SwiftSectionKit_zh.md`。调用方要遵守的约定从签名上看不出来，所以要写指南：输出端会被并发调用；每块产物后跟换行的语义；诊断原文是 CLI 措辞；哪些错误该由宿主自己翻译。
- 新增模块文档 `Documentations/Internal/Modules/SwiftSectionKit.md`。
- `AGENTS.md`：模块依赖图加上 `swift-section → SwiftSectionKit`、模块说明加一条、`Sources/` 分组清单加 `Commands/`；再写一条 agent 默认会做错的规矩——命令的新逻辑写进 `SwiftSectionKit`，CLI 只做 flag 映射、错误翻译和流路由。
- README：product 表加一行，并给一段用法示例。
- `Documentations/README.md` 索引、`Evolutions/README.md` 状态表、`ProjectEvolutionLog`。

## API 演进与废弃策略

- 没有被替代的旧 API，不需要 `@available(*, deprecated)`，也不需要 semver major 跃迁。
- 以后给请求加字段一律带默认值，保持源码兼容。`Report` 这类调用方会构造的 enum 加 case，对 `switch` 它们的下游是源码破坏。指南里写明这类 enum 是「供构造的」，不承诺可以穷举 `switch`。

## 落地步骤

每一步都单独构建通过，现有测试保持绿色。

1. **骨架**：`Package.swift` 加 target、product 与测试目标；搬入 `Architecture` / `DumpSection` / `ObjCDeclarationKind`，CLI 补 `@retroactive ExpressibleByArgument`。
2. **地基**：输出端、诊断、环境、`MachOSource` 与 snapshot 输入加载；CLI 侧的 `StandardStreamOutput` 与错误翻译。
3. **逐个搬命令**：`transformer` → `snapshot` → `diff` → `evolution` → `dump` → `interface` → `objc` 五个。每搬一个，构建并跑 `SwiftSectionCommandTests`。
4. **测试**：`SwiftSectionKitTests` 全部套件，CLI 侧的映射、翻译与路由测试；CI 白名单。
5. **验收**：按「验收」一节逐条做，结果记进决策日志。
6. **文档**：按「文档与示例」一节写齐。
7. **落地**：分配编号、状态改为 Implemented、写演进账本，合进 `next`（推送与否由用户定）。

**收尾时必须判断两件事**（判断结果写进决策日志，不允许沉默跳过）：

- **要不要配套专题文章** —— 计划中的使用指南已经满足「有从签名看不出来的调用方契约」这一判据；实现过程中若出现代码里看不出来的决策，另写实现说明或并入模块文档。
- **有没有引入新术语** —— 预计没有；落地时确认。

## 决策日志

| 日期 | 变更 | 说明 |
|------|------|------|
| 2026-10-03 | Created as Draft | 用户原话：「把swift-section CLI的功能抽出来，方便进行测试，CLI层只是一层包装」 |
| 2026-10-03 | 定为完整档（大型重构），三轮澄清提问（最后一轮含收尾确认）后成稿 | — |
| 2026-10-03 | 做成对外发布的 product | 用户选定（推荐的是仅包内可见 + `package` 访问级别） |
| 2026-10-03 | 范围：全部子命令，含 `objc` 五个 | 用户选定 |
| 2026-10-03 | 输出逐字节保持，只统一写流方式；怪癖记为后续 | 用户选定 |
| 2026-10-03 | 输出走注入的输出端，不用返回值 | 用户选定；`dump` 要边算边输出 |
| 2026-10-03 | 模块名 `SwiftSectionKit`，放 `Sources/Commands/` | 用户选定 |
| 2026-10-03 | 公开 API 按用途建模；flag 组合的校验与原报错留在 CLI 的 `validate()` | 用户选定 |
| 2026-10-03 | 测试：每个子命令端到端 + 纯逻辑，新套件进 CI | 用户选定 |
| 2026-10-03 | MCP server 不在本次范围 | 用户选定，列为后续工作 |
| 2026-10-03 | 诊断 = 级别 + CLI 原文 | 用户选定 |
| 2026-10-03 | 版本号留在 CLI、经环境注入；库错误用中性措辞、由 CLI 翻译回原文；退出码由 CLI 决定；索引事件 handler 注入；源码扫描覆盖新模块；删 `IgnoreCoding.swift`；验收方式；文档清单；worktree 与分支 | 我提出，用户确认 |
| 2026-10-03 | 成稿时细化、待评审确认的四处：(1) 命令行拼写的解释留在 CLI，库只收解析好的值，由此带来第二处行为偏差「参数错误先于加载报出」；(2) 预览里的 `failsOnBreakingChange` 改为 `.annotatedInterface(format:includesBreakingChangeVerdict:)`，库只报告结论，退出码由 CLI 定；(3) 诊断原文保留 CLI 措辞（部分含 flag 名），只有抛出的错误用中性措辞；(4) `SwiftSection` / `ObjCSectionKind` 作为公开类型改名为 `DumpSection` / `ObjCDeclarationKind`，`objc dump` 的 `imageDescription` 改为显式字段 | 写详细设计时发现；(1)(3) 是「逐字节保持」与「按用途建模」两条选定碰到一起的结果 |
| 2026-10-03 | Draft → Accepted → In Progress | 用户回复「开工」，批准提案（含上一行四处细化） |
| 2026-10-03 | 实现偏差：`ProductDestination.file(URL)` 改为 `.file(path: String)` | 「Report written to …」这类诊断要逐字复述调用方的拼写；实测 `URL(fileURLWithPath:)` 把 `dir/` 规整成 `dir`、把 `~/x` 展开成家目录路径。写文件时照旧经 `URL(fileURLWithPath:)`，行为不变 |
| 2026-10-03 | 实现偏差：偏差 2 比提案写的多出三个边角，另有一处怪癖随之消失 | 都来自「命令行拼写在调用库之前解释」：`interface` 的「--supplementary-apinotes has no effect」警告在加载前发出（加载失败时也会出现）；`snapshot` 给 snapshot JSON 输入时乱写 `--dyld-shared-cache`（缺镜像名或 `-n` / `-p` 同给）现在报错，以前因为没走到加载而被忽略；`objc --verbose` 下 C type 替换串的错误前不再有进度行。`snapshot` 对普通文件给 `-n` / `-p`（帮助里写明会被忽略）时，provenance 的 `binaryPath` 不再带上那个没用到的镜像名。全部是误用或一条命令行里两处写错的情形，正文「两处行为偏差」已同步 |
| 2026-10-03 | 实现细节：`transformer` 的三个请求 `run(output:)` 不收环境；`ObjCDumpRequest.run` 返回 `Outcome`，`diagnosticNotes(for:)` 公开 | 前者不往产物里盖任何东西；后者让宿主拿到「找到了什么」，测试也直接用它（`ObjCDumpDiagnosticsTests` 从 CLI 测试目标搬到 `SwiftSectionKitTests`） |
| 2026-10-03 | 实现细节：`ExpressibleByArgument` 不加 `@retroactive` | 编译器指出库与可执行文件同包，不算 retroactive conformance |
| 2026-10-03 | 偏差 1 的实测证据 | 旧二进制 `swift-section objc dump --sections unions <fixture> 2>&-` 退出码 134（写 stderr 时 abort），新的是 0。`CommandLineStreamWriteScanTests` 在 `next` 的源码上会命中 `ObjCSnapshotCommand.swift:37-38`、`StandardErrorLog.swift:10` 三处 `FileHandle` 写入和几十处直接 `print`，在本分支上为空——整类挡住，不只修已发现的几处 |
| 2026-10-03 | 测试落地 | `SwiftSectionKitTests` 52 个（`MachOSourceTests`、`InterfaceAnnotationStyleTests`、`TransformerRequestTests`、`ABIRequestTests`、`DumpAndInterfaceRequestTests`、`ObjCRequestTests`，加搬来的 `ObjCDumpDiagnosticsTests`），`SwiftSectionCommandTests` 新增 `CommandRequestMappingTests`、`CommandLineErrorTranslationTests`、`StandardStreamOutputTests`、`CommandLineStreamWriteScanTests`，两个目标合计 151 个，原始退出码 0；新套件全部加进 `macOS.yml` 白名单。`ABIRequestTests` 整个套件共用一份 fixture 的 snapshot 文档，耗时 32 秒 → 17 秒；「模板打开注释种类」改用 member address 模板，避开静态布局引擎（单条 46 秒 → 约 1 秒）。胖二进制测试用 fixture 现场拼单切片胖文件，不依赖宿主 |
| 2026-10-03 | 抽查：`--help` 与 fixture 上的 dump / interface | 根命令与 15 个子命令的 `--help` 新旧逐字节一致；fixture 上 `dump`（默认、带 header 与注释开关）、`interface`（默认、带 header 与 offset 注释）stdout 一致，stderr 只差 `ConsoleEventHandler` 行首时间戳 |
| 2026-10-03 | 验收 1：全量测试 | `swift test --skip IntegrationTests`（Ultra，Xcode 27 / Swift 6.4，`USING_LOCAL_DEPENDENCIES=1`）原始退出码 0：20 批、2240 个测试、422 个套件全部通过，含覆盖新模块的 `PrintFailureEventTests` 源码扫描与 `ContinuousIntegrationTestFilterTests` |
| 2026-10-03 | 验收 2：A/B 对比 | `run-rendering-ab-verification.py --skip-build --skip-image-part`，两侧都是从源码编出的 release 二进制（基准为 `next` 5ec73b2e）：归档 cache 15.5 / 26.6 与模拟器 iOS 15.5 / 16.4 / 17.5 / 18.5 / 26.5，68 对 dump / interface 逐字节一致；iOS 15.5 模拟器的 SwiftUI、WidgetKit 共 4 对两侧同样以信号 5 退出，是 `next` 上原有的问题，脚本按「两侧同败」跳过。MachOImage 一腿不经过 CLI、走的库代码这次没动，跳过 |
| 2026-10-03 | 验收 4：各平台编译 | `SwiftSectionKit` 能为 iOS 15.0、tvOS 15.0、watchOS 9.0（原生构建系统交叉编译）与 visionOS 2.0（Swift Build）编译，新模块零警告。Xcode 27 的 Swift Build 拒绝包声明的 iOS 13.0 下限（只支持 15.0 起），原生构建系统又不认 xros triple，所以平台版本按工具链能接受的取——这是整个包的部署下限问题，与本改动无关，未在此处理 |
| 2026-10-03 | 验收 5：插件 skill 的 flag | skill 与 `references/` 里点名的每个 flag 都出现在新二进制的 `--help` 里；CLI 行为不变，skill 不需要改 |
| 2026-10-03 | 验收 3：新旧二进制逐字节对比 | 用户批准后跑一次性脚本（仓库外，不提交），93 条命令行（覆盖全部子命令的主要 flag、`-o`、各种报告、`objc` 五个子命令、错误路径与每个子命令的 `--help`），比较 stdout、stderr、退出码与 `-o` 写出的文件，抹掉时间戳与 `createdAt`。83 条一致；7 条只差 stderr 上 `[old]` / `[new]` 事件行的先后与「symbol index」计数落在哪一侧——旧二进制自己连跑四次也各不相同（两侧并发索引，谁先建好共享的符号索引不定），加 `--jobs 1` 让两侧按顺序索引后 7 条全部一致；剩下 3 条都属偏差 2：`dump-two-mistakes`（故意写错两处，退出码 1 → 64，先报模板名）、`dump-missing-image-name` 与 `snapshot-cache-without-image`（对不是 cache 的文件加 `--dyld-shared-cache` 又不给镜像名：旧版先打开文件报 `invalidMagic`，新版先报缺镜像名，`snapshot` 也不再先打出「Indexing …」） |
| 2026-10-03 | rebase 到 `next` 9eb05245 | 开工后 `next` 多了一个提交（MachOObjCSection 下限抬到 0.8.108），改的是依赖声明与演进账本，与本改动不重叠，rebase 无冲突 |
| 2026-10-03 | 收尾判断：配套文档与术语 | 使用指南已写（`SwiftSectionKit.md` / `_zh`，输出端契约从协议签名上看不出来，符合写指南的判据），模块文档已写，均登记在头部；实现上的决策都记在本日志与模块文档里，不另写实现说明。没有引入需要登记的新术语：「请求」「输出端」是普通说法，`SwiftSectionKit` 是模块名 |
| 2026-10-03 | In Progress → Implemented，落地编号 0058 | 取 `origin/next`（0057）与 `origin/main`（0054）的最大号加一；同批写演进账本第 77 节，合进 `next` |
