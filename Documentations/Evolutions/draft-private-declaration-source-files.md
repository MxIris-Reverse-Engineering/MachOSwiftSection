# Draft - dump 与 interface 标出私有声明来自哪个源文件

- **状态**: In Progress
- **创建日期**: 2026-10-25
- **最后更新**: 2026-10-25
- **所属愿景**: 无
- **关联提案**: [0063](0063-private-declarations.md)（名字经过的私有声明与按镜像反推源文件；当时明确不接 `swift-section`）、[0062](0062-local-type-context-names.md)（局部类型声明上方那行注释，本案的注释与它并排）
- **实现分支 / PR**: `feature/private-declaration-source-files`（worktree `.worktrees/MachOSwiftSection-PrivateDeclarationSourceFiles`，基于 `next`）
- **配套文档**: [Modules/SwiftPrivateDiscriminators.md](../Internal/Modules/SwiftPrivateDiscriminators.md)

## 摘要

0063 把「反推 private discriminator 来自哪个源文件」下沉到了本库的 `SwiftPrivateDiscriminators`：discriminator 是 `MD5(模块名 + 源文件名)`，拿候选文件名去撞，128 位摘要对上就是确认。但除了它自己的测试，本库没有任何 target 依赖它，现在只有 RuntimeViewer 的 `Private` 标签在用。`swift-section dump` 只印 discriminator 原文（`(CodingKeys in _B89E435DF71E951D297EEE1ADCD6DDD8)`），interface 连 discriminator 也不印：fixture 里两个文件各声明了一个 `private struct PrivateDoppelganger`，interface 印出来的两个声明头一模一样，读者分不出谁是谁。本案给 dump 和 interface 加一个默认关闭的开关，打开后，凡是名字带来新 discriminator 的声明，上方都加一行注释写出它来自哪个源文件；还原不出的照实说。

## 方案

**改动位置**（明确不动的地方见本节末尾）：

- `Sources/Output/SwiftDeclarationRendering/DeclarationRenderConfiguration.swift:86`：挨着 `staticFieldLayoutProvider` 加一个反推结果的 provider 属性，以及生成这行注释的 helper。provider 的协议和结果类型也放在这个模块。
- `Sources/Declaration/SwiftPrivateDiscriminators/PrivateDiscriminatorSourceFileIndex.swift:29`：`PrivateDiscriminatorSourceFileIndex` 遵循这个协议，并加一个批量入口。
- `Sources/Output/SwiftDump/Dumper/` 下各 dumper 的 `body`（`EnumDumper.swift:142`、`StructDumper.swift:129`、`ClassDumper.swift:220`、`ProtocolDumper.swift:93`、`ProtocolConformanceDumper.swift:61`、`AssociatedTypeDumper.swift:96`）：声明头和成员行的上方。
- `Sources/Output/SwiftPrinting/SwiftDeclarationPrinter.swift`：类型（`:234`，紧跟局部类型那行注释）、协议（`:351`）、扩展（`:458`）的声明头，以及 `printDefinition`（`:618`）里的成员与全局声明。打印器加一个登记 provider 的方法，写法同 `addTypeNameResolver`（`:178`），登记了才打印。
- `Sources/Commands/SwiftSectionKit/Swift/DumpRequest.swift:132`、`InterfaceRequest.swift:188`：请求加字段；开关打开时建 index、批量反推，再交给 dumper 或打印器。`Package.swift:809` 的 `SwiftSectionKit` 加依赖 `SwiftPrivateDiscriminators`。
- `Sources/Executables/swift-section/Commands/DumpCommand.swift:56`、`InterfaceCommand.swift:59`：加 flag。

**输出**。一个声明的名字里有它外层声明没有的 discriminator 时，它上方每个这样的私有声明加一行注释。dump：

```swift
// CodingKeys is declared in Codable.swift
enum SymbolTestsCore.CodableTests.GenericCodableTest.(CodingKeys in _B89E435DF71E951D297EEE1ADCD6DDD8) {
    case element
    case metadata
}
```

interface 里同名的两个私有类型从此能分开：

```swift
// PrivateDoppelganger is declared in PrivateDoppelgangers.swift
struct PrivateDoppelganger {
    var alphaStorage: Swift.Int64

    init(alphaSeed: Swift.Int64)
}
// PrivateDoppelganger is declared in a source file whose name could not be recovered (private discriminator _1282F137F8790A6AF4B7E2738A640142)
struct PrivateDoppelganger {
    var betaStorage: Swift.Int64

    init(betaSeed: Swift.Int64)
}
```

- 两条输出用同一套写法，只在 helper 里实现一次。哈希用的模块名与声明打印的模块不同时补上模块（`// EnabledKey is declared in Enabled.swift of module SwiftUICore`）；编译器合成的文件写成 `declared in the file the compiler synthesized for Foo.swift`；还原不出的写明还原不出并附上 discriminator，因为 interface 别处不印它。
- 「外层声明」指打印时包住它的那个声明。dump 把每个类型、协议、conformance 都平铺在顶层，所以每个私有类型都有自己的一行；成员行只比它所在的类型。interface 里嵌在私有类型里的类型、私有类型的成员都和外层同一个文件，不再重复；公开类型上的 `private func` 会标出它所在的文件，通常就是声明它的那个 extension 所在的文件。
- conformance 的声明头同时看被扩展的类型和协议：遵循一个私有协议的 conformance 只能写在那个协议的文件里。
- 类型引用不标：字段类型、函数签名里出现的私有类型，它的源文件在那个类型自己的声明上方。名字里的 discriminator 照旧，dump 里仍然带，interface 里仍然不带。

**接法**：

- 协议和结果类型放在 `SwiftDeclarationRendering`。dump（`SwiftDump`）和 interface（`SwiftPrinting`）都依赖它；`SwiftPrivateDiscriminators` 依赖 `SwiftIndexing`，而 `SwiftDump` 在 `SwiftDeclaration` 之下、`SwiftPrinting` 与 `SwiftIndexing` 平级，两边都不能直接依赖它。结果类型是新的 `PrivateDeclarationSourceFile`；`PrivateDiscriminatorSourceFiles.SourceFile` 原样不动，index 遵循协议时把一个换成另一个，RuntimeViewer 的源码不用改。
- dump：provider 装在 `DeclarationRenderConfiguration` 上，和 `staticFieldLayoutProvider` 一样由 `DumpRequest` 装；为空就不打印，不另设开关。
- interface：`SwiftDeclarationPrintConfiguration` 不动（它是 `Equatable`，放不进 provider），provider 登记到打印器上。`SwiftInterfaceBuilder` 也不动：`InterfaceRequest` 在 `prepare()` 之后用 `builder.indexer` 建 index，登记到 `builder.printer`。
- dump 没有索引器。开关打开时 `DumpRequest` 另建一个 `SwiftDeclarationIndexer` 并 `prepare()`，只为给 index 读名字；读完 index 就放掉它，这是 0063 已有的行为。不直接从描述符读名字：那样会少掉 extension 的名字这批候选，同一个镜像 dump 和 interface 还原出来的就会不一样。

**一次批量反推**：

- 一个还原不出的 discriminator 要把五步候选全部算完，逐个声明去问的话，每遇到一个新的就整套重来。RuntimeViewer 在 Debug 构建里量过：逐个问时还原不出的每个要 3–4 秒；一次算完整个镜像是 30 秒（SwiftUICore）到 144 秒（SwiftUI）。Release 没有量过。
- 所以打印前先一次求完。index 的批量入口收齐镜像名字（index 本来就要读）和 `SymbolIndexStore` 里成员符号、全局符号的 `privateDeclarations` 里出现的全部 discriminator，交给一次搜索；之后每个声明的查询都只是查表。
- 候选不变，0063「不扩大到符号表的全部标识符」的决定照旧，只是一次要求的 discriminator 变多了。

**开关**：默认关闭，和两条输出现有的注释一样用 `--emit-*` flag：`dump --emit-private-source-files`、`interface --emit-private-source-files`。请求字段是 `DumpRequest.emitsPrivateDeclarationSourceFiles` 和 `InterfaceRequest.emitsPrivateDeclarationSourceFiles`，默认 `false`，源码兼容。

**明确不动**：

- 开关关闭时 dump 与 interface 的输出逐字节不变，也不建 index、不多 `prepare()` 一次。
- 反推算法、候选和已知文件名清单不变，还原率不变。
- RuntimeViewer 不受影响；本案的注释不做成 `SwiftVisibilityOption`，它有自己的 `Private` 标签弹窗。
- snapshot、diff、evolution 和 `objc` 子命令都不动；diff 的声明头本来就带 discriminator。
- demangle 预设不动，interface header 也不加还原统计。

**不在这次范围内**：提高还原率；第 5 步按 discriminator 分开搜索、本可并行，release 量完再决定要不要做；RuntimeViewer 在它的接口视图里接这行注释。

**测试**：

- SwiftSectionKitTests 在 SymbolTestsCore 上打开开关跑 `DumpRequest` 与 `InterfaceRequest`。期望值在代码之外用 `md5 -s` 算出：`Codable.swift` 是 `_B89E…`，`Structs.swift` 是 `_930E…`，`PrivateDoppelgangers.swift` 是 `_82F1…`，`PrivateDoppelgangersSecondFile.swift` 是 `_1282…`。
  - 两个同名的 `PrivateDoppelganger` 各标各的文件。
  - 私有类型的成员和嵌套类型不重复标。
  - `PrivateDoppelgangersSecondFile.swift` 按现有规则大概率拼不出（复数落在名字中间），实现时确认；拼不出就正好覆盖「还原不出」的写法，拼得出就另找一个用例。
- 注释 helper 的单元测试：模块名不同、合成文件、私有声明没有名字、一个名字带两个 discriminator。
- 关闭时不变：现有 dump、interface 快照基线一个都不改；改动碰到每个类型头和成员行的打印路径，落地前再跑一次 A/B 验证。
- CLI：SwiftSectionCommandTests 测两个 flag 映射到请求字段。
- 实数据：release CLI 在 macOS 27 的 SwiftUI、SwiftUICore、Foundation 上打开开关跑 dump 与 interface，记下耗时（与关闭时比）和还原数，写回本提案。

**文档**：同批更新 `Modules/SwiftPrivateDiscriminators.md`（宿主多了 CLI，加上批量入口）、`Modules/SwiftSectionKit.md` 和调用方指南 `Documentations/SwiftSectionKit.md`（两个新字段）、`Modules/SwiftInterface.md`（打印器的登记方法），以及 `AgentPlugins/swift-section` 的 skill（新 flag 和这行注释）；在 ProjectEvolutionLog 记一节。术语表没有新词，「private declaration」已经登记过。

**落地步骤**（每一步单独构建、相关测试通过后提交）：

1. ✅ 接缝：`SwiftDeclarationRendering` 里的协议、结果类型与注释 helper；index 遵循协议、加批量入口（`@_spi(Support)` 的 `recoverSourceFiles(ofEveryDeclarationIn:)`）。测 helper 和批量入口。
2. dump：各 dumper 打注释；`DumpRequest` 的字段、索引器与 index；`dump` 的 flag。测 dump 一侧。
3. interface：打印器的登记方法与各打印点；`InterfaceRequest` 的字段；`interface` 的 flag。测 interface 一侧。
4. 文档、skill、实数据量测与 A/B 验证。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-10-25 | Created as Draft | 用户问 dump 和 interface 会不会输出反推出的文件名。核实两边都不会：`SwiftPrivateDiscriminators` 除自己的测试外没有任何 target 依赖，0063 当时明确不接 `swift-section`；release CLI 在 SymbolTestsCore 上的 dump 有 170 行带 discriminator，一个文件名也没有，interface 连 discriminator 都没有 |
| 2026-10-25 | dump 和 interface 都接 | 未提问自定。沿用「新的识别能力默认两条输出都接」 |
| 2026-10-25 | 默认关闭，用 `--emit-private-source-files` 打开 | 未提问自定。整镜像反推在 Debug 构建里要 30–144 秒，release 未量；两条输出现有的注释也都要显式打开 |
| 2026-10-25 | 写成声明上方的注释，名字里的 discriminator 不替换 | 未提问自定。dump 要留着 discriminator 原文；两条输出新增的事实一律写成注释 |
| 2026-10-25 | 只标带来新 discriminator 的声明 | 未提问自定。私有类型的成员和嵌套类型必然与它同一个文件，逐个重复只是噪音；公开类型上的私有成员才说明它在哪个文件 |
| 2026-10-25 | dump 打开开关时另建索引器读名字 | 未提问自定。直接从描述符读会少掉 extension 的名字这批候选，同一镜像 dump 与 interface 的还原结果会不一样 |
| 2026-10-25 | 打印前一次批量反推 | 未提问自定。逐个声明问，每个还原不出的都要把五步重算一遍 |
| 2026-10-25 | 用户批准（Draft → Accepted），开始实现 | 方案与全部假设照单通过 |
| 2026-10-25 | 结果类型另起一个，`SourceFile` 不下沉 | 实现时发现：RuntimeViewerCore 开了 `MemberImportVisibility`，按 SE-0444 它读 `fileName` 这些成员要 import 声明它们的模块，下沉后留 typealias 也可能逼它多加一行 import；在接缝处换一下类型只多几行 |
| 2026-10-25 | 批量入口取一个索引器，`@_spi(Support)` | 成员符号要从索引器的镜像查，全局声明要读它的定义；index 按索引器建的两个初始化方法本来就是这个 SPI |
