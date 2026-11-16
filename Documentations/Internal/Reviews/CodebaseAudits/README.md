# 代码库体检账本

由 `audit-codebase` 维护。每轮体检先读它决定范围，跑完再更新。各轮报告与本文件同目录（`CodebaseAudit<YYYYMMDD>.md`），由下面的「运行记录」索引。

## 模块表

「最近深审」写「从未（改动集审过 …）」的模块，只审过那一轮改动集里的改动与所在函数，没有整模块深审过；轮转时按「从未」对待。

| 模块 | 路径 | 源码行数 | 最近深审 | 深审时的提交 | 未结的严重问题 |
|------|------|---------|---------|-------------|---------------|
| CrossReferenceAnalysis | `Sources/Analysis/CrossReferenceAnalysis/` | 4,483 | 2026-11-16 | `1ba927ad` | 0 |
| ARM64InstructionDecoding | `Sources/Support/ARM64InstructionDecoding/` | 279 | 2026-11-16 | `1ba927ad` | 0 |
| SwiftObjCInterop | `Sources/Analysis/SwiftObjCInterop/` | 7,073 | 2026-11-16 | `1ba927ad` | 0 |
| SwiftThunkAnalysis | `Sources/Analysis/SwiftThunkAnalysis/` | 3,629 | 从未（改动集审过 2026-11-16） | — | 0 |
| SwiftInspection | `Sources/Analysis/SwiftInspection/` | 6,316 | 从未（改动集审过 2026-11-16） | — | 0 |
| SwiftLayout | `Sources/Analysis/SwiftLayout/` | 4,704 | 从未（改动集审过 2026-11-16） | — | 0 |
| SwiftDeclaration | `Sources/Declaration/SwiftDeclaration/` | 6,631 | 从未（改动集审过 2026-11-16） | — | 0 |
| SwiftIndexing | `Sources/Declaration/SwiftIndexing/` | 2,509 | 从未（改动集审过 2026-11-16） | — | 0 |
| SwiftSpecialization | `Sources/Declaration/SwiftSpecialization/` | 4,883 | 从未（改动集审过 2026-11-16） | — | 0 |
| SwiftPrivateDiscriminators | `Sources/Declaration/SwiftPrivateDiscriminators/` | 828（不含生成文件） | 从未（改动集审过 2026-11-16） | — | 0 |
| SwiftAttributeInference | `Sources/Declaration/SwiftAttributeInference/` | 191 | 从未 | — | — |
| TypeIndexing | `Sources/Declaration/TypeIndexing/` | 1,311 | 从未 | — | — |
| SwiftPrinting | `Sources/Output/SwiftPrinting/` | 7,543 | 从未（改动集审过 2026-11-16） | — | 0 |
| SwiftDeclarationRendering | `Sources/Output/SwiftDeclarationRendering/` | 6,580 | 从未（改动集审过 2026-11-16） | — | 0 |
| SwiftDump | `Sources/Output/SwiftDump/` | 3,323 | 从未（改动集审过 2026-11-16） | — | 0 |
| SwiftInterface | `Sources/Output/SwiftInterface/` | 4,065 | 从未（改动集审过 2026-11-16） | — | 0 |
| SwiftDiffing | `Sources/Output/SwiftDiffing/` | 3,698 | 从未（改动集审过 2026-11-16） | — | 0 |
| SwiftOutputTransformer | `Sources/Output/SwiftOutputTransformer/` | 1,527 | 从未 | — | — |
| SwiftSectionKit | `Sources/Commands/SwiftSectionKit/` | 3,155 | 从未（改动集审过 2026-11-16） | — | 0 |
| swift-section | `Sources/Executables/swift-section/` | 2,242 | 从未（改动集审过 2026-11-16） | — | 0 |
| reader-benchmark | `Sources/Executables/reader-benchmark/` | 285 | 从未（改动集审过 2026-11-16） | — | 0 |
| baseline-generator | `Sources/Executables/baseline-generator/` | 33 | 从未 | — | — |
| MachOSwiftSection | `Sources/ABI/MachOSwiftSection/` | 10,453 | 从未（改动集审过 2026-11-16） | — | 0 |
| MachOSwiftSectionC | `Sources/ABI/MachOSwiftSectionC/` | 588 | 从未 | — | — |
| MachOSymbols | `Sources/MachO/MachOSymbols/` | 3,207 | 从未（改动集审过 2026-11-16） | — | 0 |
| MachODependencies | `Sources/MachO/MachODependencies/` | 1,156 | 从未（改动集审过 2026-11-16） | — | 0 |
| MachOReading | `Sources/MachO/MachOReading/` | 1,416 | 从未（改动集审过 2026-11-16） | — | 0 |
| MachOResolving | `Sources/MachO/MachOResolving/` | 431 | 从未（改动集审过 2026-11-16） | — | 0 |
| MachOPointers | `Sources/MachO/MachOPointers/` | 809 | 从未 | — | — |
| MachOCaches | `Sources/MachO/MachOCaches/` | 675 | 从未 | — | — |
| MachOBase、MachOFoundation | `Sources/MachO/MachOBase/`、`Sources/MachO/MachOFoundation/` | 13 | 从未 | — | — |
| Utilities | `Sources/Support/Utilities/` | 507 | 从未（改动集审过 2026-11-16） | — | 0 |
| MachOMacros | `Sources/Support/MachOMacros/` | 452 | 从未（改动集审过 2026-11-16） | — | 0 |
| MachOFixtureSupport | `Sources/TestSupport/MachOFixtureSupport/` | 17,324 | 从未 | — | — |
| MachOTestingSupport | `Sources/TestSupport/MachOTestingSupport/` | 5,829 | 从未（改动集只做过结构与冗余审查 2026-11-16） | — | — |
| MachOTestingSupportC | `Sources/TestSupport/MachOTestingSupportC/` | 18 | 从未 | — | — |
| RegenerateBaselinesPlugin | `Plugins/RegenerateBaselinesPlugin/` | 81 | 从未 | — | — |

**不审**：

- `Sources/Declaration/SwiftPrivateDiscriminators/PrivateDiscriminatorSourceFiles+KnownFileNames.swift`（`Scripts/GenerateKnownSwiftSourceFileNames.sh` 生成，2,027 行）。
- `Tests/`（25 个测试目标，约 8.3 万行；含 `Tests/Projects/` 下的 fixture 源码，它们为了制造特定的二进制形态而刻意写得古怪）：只作为核对发现时的证据读，不轮转深审。要纳入轮转，在这里改写并给它们加行。
- `Scripts/`（A/B 验证用的 Python 脚本，不是构建目标）、`AgentPlugins/`（agent 插件的文档）、`Documentations/`。

## 规则检查式

在仓库根目录运行；全部带 `-g '*.swift' Sources Plugins`，并排除 `PrivateDiscriminatorSourceFiles+KnownFileNames.swift`（`| grep -v KnownFileNames | wc -l`）。计数包含注释与字符串里的命中，只用来看趋势；每条命中算不算违规由各轮报告判断。

| 规则 | 来源 | 检查式（`rg -nP`） | 2026-11-16 |
|------|------|--------|-----------|
| 不用 `print` 打日志 | 全局指令「编码风格」；项目 `CLAUDE.md`「writing a log statement」 | `'(?<![.\w])(?<!func )print\('` | 27 |
| 不直接用 `os.Logger` / `os_log` / `OSSignposter` | 同上 | `'\bos_log\(\|\bLogger\(\|OSSignposter\(\|\bos_signpost\('` | 1 |
| 不用 `FileHandle.standardError/Output.write` | 项目 `CLAUDE.md`「writing a log statement」 | `'FileHandle\.standard(Error\|Output)\.write'` | 3 |
| 节点工厂调用数（`demangleAsNode` / `Node.create`，信号） | 项目 `CLAUDE.md`「touching the demangler…」 | `'\bdemangleAsNode\(\|\bNode\.create\('` | 36 |
| 批量路径不裸调 `NodeReference(interning:)`（信号） | 同上 | `'NodeReference\(interning:'` | 7 |
| 不强转读取器类型 | 项目 `CLAUDE.md`「whether a reader is a MachOImage or a MachOFile」 | `'\b(as[?!]?\|is)\s+MachO(Image\|File)\b\|\bas[?!]?\s+MachOContext<'` | 0 |
| 不用单字母泛型参数（存量见裁决 A82） | 全局指令「编码风格」 | `'\b(func\|init\|struct\|class\|enum\|protocol\|actor\|typealias\|subscript)\b[^\n{]*<\s*[A-Z][0-9]?\s*(:\|,\|>)'` | 86 |
| 不用单字母局部变量 | 全局指令「编码风格」 | `'\b(let\|var)\s+[a-z]\s*[=:]\|\bfor\s+(case\s+let\s+)?[a-z]\s+in\b'` | 29 |
| 不用 `FullDyldCache.host` | 项目 `CLAUDE.md`「MachODependencies」一段 | `'FullDyldCache\.host(?!\w)'` | 0 |
| 运行时 metatype 不裸用 `_mangledTypeName` | 项目 `CLAUDE.md`「touching the demangler…」 | `'_mangledTypeName\('` | 1 |
| 不用 `first(of: .privateDeclName)` 读鉴别符（信号） | 同上 | `'first\(of: \.privateDeclName\)'` | 2 |
| `NodeReference` 作键要用 `StructuralNodeReferenceKey`（信号） | 同上 | `'\[\s*NodeReference\s*:\|Set<NodeReference>\|Dictionary<NodeReference'` | 1 |
| 包装过的入口里不起 `Task {}` | 项目 `CLAUDE.md`「async code」 | `'(?<![\w.])Task\s*(\(\|\{)\|Task\.detached'` | 1 |
| 按镜像缓存不用手写锁（信号） | 项目 `CLAUDE.md`「per-image or per-file cache」 | `'NSLock\(\)\|NSRecursiveLock\(\)\|OSAllocatedUnfairLock\|os_unfair_lock\|Mutex<\|pthread_mutex_t'` | 43 |
| 废弃转发器数量（提案 0057，0.25.0 前删） | 项目 `CLAUDE.md`「descriptor wrapper…」 | `'@available\(\*,\s*deprecated'` | 356 |
| 不把模块限定名当文本写进输出（信号） | 项目 `CLAUDE.md`「declaration model…printer path」 | `'"Swift\.[A-Z]\w*"'` | 83 |
| 注释走 `StructuredComment` 工厂（只数四个模块） | 同上 | `'(?<![\w.])(Inline)?Comment\('`，路径换成 `Sources/Output/SwiftDeclarationRendering Sources/Output/SwiftPrinting Sources/Output/SwiftInterface Sources/Declaration/SwiftDeclaration` | 0 |
| 库不响应内存压力 | 项目 `CLAUDE.md`「per-image or per-file cache」 | `'makeMemoryPressureSource'` | 0 |
| 不注释掉日志调用点 | 全局指令「编码风格」 | `'^\s*//\s*#(log\|signpost)'` | 0 |
| 无 `#if false` / `#if 0` | 体检死代码信号 | `'^\s*#if\s+(false\|0)\b'` | 0 |

表里的 `\|` 是 Markdown 转义，复制到命令行时写成 `|`。只保留最近 6 轮的计数列。规则改了就新增一行；旧行保留到计数归零或规则作废，作废时在「规则」栏注明。

## 运行记录

| 日期 | 分支 | 提交 | 范围 | 严重 bug | 结构类 | 报告 |
|------|------|------|------|---------|--------|------|
| 2026-11-16 | `next` | `1ba927ad` | 首次体检：改动集（自 `42cbf5d4`，2026-10-17 起 443 个文件）；改动集已覆盖大半模块，未轮转 | 9（2 待确认）；同日全部修掉；验证修复时另发现 1 条（卡死），随后也修掉 | 13 | [CodebaseAudit20261116.md](CodebaseAudit20261116.md) |
