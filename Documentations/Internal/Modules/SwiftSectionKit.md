# SwiftSectionKit 模块（及 swift-section 可执行文件）

> 模块参考文档（module reference），随代码维护。读者：维护者。
> 提案：[0058-swift-section-kit](../../Evolutions/0058-swift-section-kit.md)、[0059-dump-declaration-identity](../../Evolutions/0059-dump-declaration-identity.md)。调用方指南：[SwiftSectionKit.md](../../SwiftSectionKit.md)。

## 模块定位

SwiftSectionKit 是 `swift-section` 每个子命令的库版本：一个子命令对应一个请求类型，`run(output:…)` 执行，产物和诊断交给调用方注入的 `SwiftSectionOutput`。它位于依赖图的最顶层，在 `SwiftInterface`、`SwiftDump`、`SwiftDiffing`、`TypeIndexing` 和 MachOObjCSection 的 ObjC 产品之上；对外是一个 product。

`swift-section` 可执行文件是它的包装层，只做五件事：声明 flag（`--help` 文本就是 flag 声明本身）、`validate()` 里的 flag 组合校验、把 flag 映射成请求（`makeRequest()`）、把库的错误翻译回命令行的历史文案、决定诊断写哪个流以及退出码。**命令的新逻辑一律写进 SwiftSectionKit**，可执行文件里只放「命令行怎么拼写」的东西。

这样分的直接收益是可测：请求是 `Equatable` 的值，输出端可以换成内存记录器，时间与生成器名可以注入，所以每个子命令都能在测试进程里端到端跑完再断言。拆分之前，79 个 CLI 测试没有一个调用过 `run()`。

## 文件 → 子系统对照

| 子系统 | 文件 |
|---|---|
| 1. 输出端 | `Output/SwiftSectionOutput`、`SwiftSectionProduct`（含 `InterfaceAnnotationStyle` / `AnnotatedLineKind`）、`DumpedDeclaration`、`SwiftSectionDiagnostic`、`ProductDestination` |
| 2. 环境 | `Environment/SwiftSectionEnvironment`（含 `GeneratorIdentity`） |
| 3. 输入 | `Inputs/Architecture`、`MachOSource`（含 `DyldSharedCacheImage` / `MachOSourceError`）、`SnapshotSource`（含 `SnapshotSourceError` / `BinaryLoadingOptions`） |
| 4. Swift 侧请求 | `Swift/DumpRequest`（含 `DumpSection` / `FieldOffsetComments`）、`InterfaceRequest`、`ABISnapshotRequest`、`ABIDiffRequest`、`ABIEvolutionRequest`、`TransformerRequests`；共用的 `ABISnapshotLoading`、`DependencySearchPathUsage`、`CommentTransformerApplication` |
| 5. ObjC 侧请求 | `ObjC/ObjCInterfaceSession`（含 `ObjCDeclarationKind`）、`ObjCDumpRequest`、`ObjCInterfaceRequest`（含 `ObjCDeclarationLookupError`）、`ObjCAPIRequests`（snapshot / diff / evolution 与 `ObjCAPISnapshotLoading`） |
| CLI 包装层 | `Sources/Executables/swift-section/`：各命令的 `makeRequest()` + `run()`、`Models/CommandLineSupport`（flag → `MachOSource`、错误翻译、`ExpressibleByArgument`）、`Output/StandardStreamOutput` |

## 1. 输出端

三路分开：`write(_:)` 收产物，`report(_:)` 收诊断，`indexEventHandlers(forInputLabeled:)` 给索引事件的 handler（默认空数组，即落到 `Dispatcher` 的 os_log 地板）。分开是为了宿主永远不用从一串进度行里挑产物。

**换行语义是盘点出来的契约**：现有的每一处 stdout 写入都等于「内容 + 换行」——`print(x)` 如此；annotated interface 按行着色后逐行补换行，拼起来恰好也是「全文 + 换行」；`snapshot` 的 `fwrite` 加 `fputs("\n")` 同样如此。所以 `SwiftSectionProduct` 每一块打印时都跟一个换行，`StandardStreamOutput` 照此写，`RecordingOutput.printedProduct` 照此拼。

**写文件不经过输出端**：`ProductDestination.file(path:)` 时由请求自己写文件，因为各命令写文件的老规矩不一样——`interface` / `diff` / `objc interface` / `transformer config` 写入的文本末尾不补换行，`evolution` 补，`dump` / `objc dump` 每块补。目的地携带路径字符串而不是 `URL`：「Report written to …」这类诊断要逐字复述调用方的拼写，而 `URL(fileURLWithPath:)` 会把 `dir/` 规整成 `dir`、把 `~/x` 展开（实测）。

**诊断 = 级别 + 原文**。原文就是命令行打出来的那句话，有些带 flag 名（"warning: --resolve-c-module-names …"）——这是「输出逐字节保持」的代价。级别决定命令行把它写到哪个流，这张路由表只存在于包装层：`interface` 的 `.progress` 和 `dump` 的 `.error` 写 stdout（历史怪癖，插件 skill 第 3 节专门警告过不要重定向 `interface` 的 stdout），其余写 stderr。以后修这两个怪癖只改两个命令的 `standardOutputSeverities`，库不用动。

**并发**：`diff` / `evolution` 并行索引多个输入，会从多个任务同时调用输出端，所以协议要求 `Sendable` 且实现必须线程安全。`StandardStreamOutput` 的每次写入是一次 `fwrite`（stdio 自带流锁）；测试的 `RecordingOutput` 用锁。

**每块声明是什么**（提案 [0059-dump-declaration-identity](../../Evolutions/0059-dump-declaration-identity.md)）：`dump` 与 `objc dump` 交出顶层声明时走 `write(_:declaring:)`，附一个 `DumpedDeclaration`——Swift 侧是来自哪个 `DumpSection` 加名字，ObjC 侧是 `ObjCDeclarationKind` 加名字。它是协议要求，扩展里的默认实现转给 `write(_:)`，所以 `StandardStreamOutput` 和 `RecordingOutput` 都不实现它，输出与以前逐字节相同；宿主要按声明拆文件时才实现。几条从签名看不出来的事：

- **名字只在 `.output` 目的地才算**，而且在声明本身 dump 成功之后：写文件时产物根本不经过输出端，算了也没人要。算名字失败只置 `name: nil`，不报诊断，否则命令行的 stdout 会多出错误行。
- **conformance 的名字用 `extension` 那一行的完整拼法**（`ProtocolConformance.dumpedTypeName(isFull: true, …)`，`package` 级），不用公开的 `dumpTypeName`。后者按 interface-type 选项打印，会去掉文件级 private 类型的判别符，而类型自己的名字带着它：fixture 里 `AlphaProtocolWitness` 的类型名是 `SymbolTestsCore.(AlphaProtocolWitness in _82F1…)`，用 `dumpTypeName` 拿到的却是 `SymbolTestsCore.AlphaProtocolWitness`，宿主就会把它和它的 conformance 分进两个文件。`filePrivateTypeAndConformanceShareName` 钉住这一点（换成 `dumpTypeName` 的单点变异实测变红）。associated type 用公开的 `dumpTypeName`，它和 `AssociatedTypeDumper` 的 `extension` 行本来就是同一个函数。
- header 和「No @objc @implementation classes recognized」那行注释不是声明，照旧走 `write(_:)`；`objc dump` 每个声明后面那个 `.text("")` 空行也是。
- 代价是每个 Swift 声明多解析一次名字，命令行用不上也要付；落地前用 release 版对大镜像实测了耗时，见提案的决策日志。

## 2. 环境

`SwiftSectionEnvironment` 只装「请求会盖进产物、但不该由它自己去读进程状态」的两样东西：生成器名与版本（interface header、snapshot provenance），以及当前时间（provenance 的 `createdAt`）。CLI 传 `swift-section` 和 `BundledVersion.value`——版本号文件仍在 `Sources/Executables/swift-section/Version.swift`，`version-check.yml` / `release.yml` 写死的路径不用改；测试传固定值，两次运行的字节完全相同。`transformer` 的三个请求不盖任何东西，`run(output:)` 不收环境。

## 3. 输入

`MachOSource` 是全部请求共用的唯一加载器（原 CLI 的 `MachOFile.load`）：文件（胖二进制按 `architecture` 挑切片，瘦二进制忽略它）、指定 cache 文件里的镜像、宿主 cache 里的镜像。cache 一律经 `FullDyldCache` 读（会映射子 cache；只读主 cache 文件的 `DyldCache` 会把落在子 cache 里的镜像读出界，见提案 0036 的动机）。

原 CLI 的 `SwiftSectionCommandError` 里有三种 flag 组合在 `MachOSource` 上写不出来（缺文件路径、`-n` 与 `-p` 同时给、`--dyld-shared-cache` 缺镜像名），它们留在包装层，由 `makeMachOSource(…)` 抛出、文案不变。`failedFetchFromSystemDyldSharedCache` 从来没被抛过，已删除。

`SnapshotSource.path` 是 `snapshot` / `diff` / `evolution` 的输入：snapshot 文档（JSON）或二进制，按文件第一个非空白字节区分（`{` 即文档）。annotated interface 只能吃二进制，`SnapshotSource.requireBinaries` 在加载任何输入之前就逐个检查，出错抛 `SnapshotSourceError.binaryRequired(path:)`。`BinaryLoadingOptions` 只作用于二进制输入：`dyldSharedCacheImage` 一旦给出，每个二进制输入都按 cache 文件处理、从中取同名镜像。

## 4. 请求的设计约定

- **按用途建模**：互斥的选项用 enum 表达，非法组合在类型上写不出来——`ABIDiffRequest.Report` 只能是 change list / summary / JSON / annotated interface 之一，`FieldOffsetComments` 把「expanded 隐含 flat」做成了 `.none / .flat / .expanded`。命令行的 flag 组合校验（`--json and --interface are mutually exclusive`）留在包装层的 `validate()`，原文不动。
- **请求是 `Equatable` 的值**，`run` 的依赖（输出端、环境）是参数而不是字段。包装层的测试靠这一点：解析 flag → `makeRequest()` → 与期望请求比较（`CommandRequestMappingTests`）。
- **库只报告，不退出**：`ABIDiffOutcome.hasBreakingChange` 等结论由包装层对照 `--fail-on-breaking` 决定是否 `throw ExitCode.failure`。`diff --interface` 只在 `includesBreakingChangeVerdict` 时才额外算一遍 change-list diff，和原来「只有 CI 闸门需要它」的取舍一致。
- **命令行拼写留在包装层**：模板名还是字面模板（`TransformerTemplateResolver`）、`--transformer-config` 的 JSON 文件、逗号分隔的 `--labels` / `--sections`、`--c-type-replacement` 的 `a=b`、demangle 的二十多个覆盖开关，都由包装层解释成库的值类型（`Transformer.SwiftConfiguration`、`[ObjCPrimitiveTypePattern: String]`、`DemangleOptions`…）再交给请求。代价见下一节的偏差 2。

## 5. 与拆分前的行为差异（只有两类）

stdout、stderr、退出码、每个子命令的 `--help` 都与拆分前逐字节一致，只有下面两类例外，均有意为之：

1. **写流统一走 `fwrite`**。`objc` 子命令以前经 `FileHandle.standardOutput/standardError.write(_:)` 写，stderr 被关闭时写一行提示就让进程 abort——实测旧二进制 `objc dump --sections unions <fixture> 2>&-` 退出码 134，新的是 0。Swift 侧的 `snapshot` 早就因为同一原因改成了 `fwrite`。`CommandLineStreamWriteScanTests` 用源码扫描把整类写法挡在包装层之外。
2. **参数层面的错误先于打开二进制报出**。命令行拼写在调用库之前解释，所以只写错一处时文案与退出码不变、只是不用等加载；同时写错二进制路径和这类参数时先报后者。同一原因带来的三个边角：`objc --verbose` 下 C type 替换串的错误前不再有进度行；`interface` 的「--supplementary-apinotes has no effect」警告在加载前就发出（加载失败时也会出现）；`snapshot` 给 snapshot JSON 输入同时乱写 `--dyld-shared-cache` 现在会报错（以前因为没走到加载而被忽略）。另有一处随之消失的怪癖：`snapshot` 对普通文件给 `-n` / `-p`（帮助里写着会被忽略）时，provenance 的 `binaryPath` 不再带上那个没用到的镜像名。

## 6. 测试锚点

- `Tests/SwiftSectionKitTests/`：每个请求对 SymbolTestsCore fixture 端到端跑（`ABIRequestTests`、`DumpAndInterfaceRequestTests`、`ObjCRequestTests`、`TransformerRequestTests`），加纯逻辑（`MachOSourceTests` 里的胖二进制是测试现场拼的单切片胖文件，不依赖宿主；`InterfaceAnnotationStyleTests`；从 CLI 搬来的 `ObjCDumpDiagnosticsTests`）。`ABIRequestTests` 整个套件共用一份 fixture 的 snapshot 文档（静态 `Task`），只索引一次。`RecordingOutput` 只实现 `write(_:)`，所以用它的用例同时在测 `write(_:declaring:)` 的默认实现；要看每块声明是什么，用 `DeclarationRecordingOutput`（两个方法都实现，按顺序记下每块产物和它带的声明）。
- `Tests/SwiftSectionCommandTests/`：原有的解析测试；`CommandRequestMappingTests`（flag → 请求）、`CommandLineErrorTranslationTests`（库错误 → 历史文案与退出码）、`StandardStreamOutputTests`（内存流读回字节；`Rainbow.enabled` 与 `outputTarget` 是进程全局量，套件 `.serialized` 并在测试内钉住、用完还原）、`CommandLineStreamWriteScanTests`。
- `PrintFailureEventTests.libraryModulesWriteToNoProcessStream` 的豁免名单只有 `swift-section` 和 `MachOTestingSupport`，`SwiftSectionKit` 自动被扫描：库里出现任何 `print` / `fputs` / `FileHandle.standard*` 都会变红。

## 7. 加一个 flag / 子命令

1. 在请求类型上加字段（带默认值，保持源码兼容），在 `run` 里实现。互斥的就并进已有的 enum。
2. 在命令里加 `@Option` / `@Flag`，在 `makeRequest()` 里映射；需要拒绝的组合写进 `validate()`。
3. 库的新错误用中性措辞；命令行要另一种说法或要 `ValidationError` 的退出码 64，就在 `CommandLineErrorTranslation` 里加一条。
4. 测试两头各一条：库侧对 fixture 断言行为，包装层断言 flag 到字段的映射。
5. 同批改插件 skill（`AgentPlugins/swift-section/skills/swift-section-cli/`）与 README 的 CLI 章节。
