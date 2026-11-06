# MachOSwiftSection 项目地图

- **核对基准**: `1dcc0c08`（`next`，提交于 2026-10-31）——下面每个说法都对照过这个 commit，之后的改动从这里讲起
- **怎么用**: 这一页只讲项目现在长什么样、东西在哪。细节顺着链接去 [模块参考](Modules/README.md)、[术语表](../Glossary.md)、[提案](../Evolutions/README.md)；给 agent 的约定与陷阱在仓库根的 [`AGENTS.md`](../../AGENTS.md)。

## 这是什么

一个 Swift 库加一个命令行工具 `swift-section`：不把二进制加载进进程，直接从 Mach-O 文件或 dyld shared cache 里读出 Swift 和 Objective-C 的类型、协议、遵循、字段布局，再还原成 dump、`.swiftinterface`，或者在两个、多个版本之间做 ABI diff 与 evolution。它自带 demangler（包括 symbolic reference），读取逻辑照着 Swift runtime 自己的实现移植。规模：`Sources/` 972 个文件、约 11.3 万行 Swift；`Tests/` 约 8 万行。

## 产物与进程

| 产物 | 入口 | 是什么 |
|---|---|---|
| 21 个库 product | `Package.swift:1344` | 每层一个，下游按需挑；`SwiftSectionKit` 是「CLI 能做的全部事情」那一个 |
| `swift-section` | `Sources/Executables/swift-section/SwiftSectionCommand.swift:3` | CLI 包装层：只做 flag 映射、错误措辞、输出流路由和退出码，逻辑都在 `SwiftSectionKit` 的 request 里 |
| `baseline-generator`、`regen-baselines` | `Sources/Executables/baseline-generator/BaselineGeneratorMain.swift:5`、`Plugins/RegenerateBaselinesPlugin/RegenerateBaselinesPlugin.swift` | 重新生成 fixture 的 ABI 基线 |
| SymbolTests fixture 工程 | `Tests/Projects/SymbolTests/SymbolTests.xcodeproj` | 编出测试读的 `SymbolTestsCore`；产物不进 git，每台机器自己编 |
| agent 插件 | `AgentPlugins/swift-section/` | 装进 Claude Code 和 Codex，教 agent 用这个 CLI |
| `swift-section-mcp` | `MCP/Sources/swift-section-mcp/` | 独立子包；2026-06-10 之后没动过，现在还能不能编过未核对 |

谁调谁：

```text
swift-section CLI ──► SwiftSectionKit requests ──┐
                                                 ├──► library ──► MachOFile  ──► Mach-O file / dyld shared cache file on disk
RuntimeViewer · MachOKitUI · swift-decompiler ───┘           └──► MachOImage ──► image already loaded in the host process
```

- 两种 reader 共用一套模型：`Sources/ABI/MachOSwiftSection/MachOFile+Swift.swift:14` 和 `Sources/ABI/MachOSwiftSection/MachOImage+Swift.swift:14` 给出同一个 `machO.swift` 入口。
- 只有 `MachOImage` 能调运行时，所以有些事实分两条路得到：字段布局注释在进程内读 live metadata，离线由 SwiftLayout 算（`Sources/Output/SwiftDeclarationRendering/FieldLayoutRenderer.swift:117`）。
- 上游是同组织的兄弟仓库：MachOKit（fork）、MachOKitExtensions、MachOObjCSection、swift-demangling、swift-semantic-string、swift-capstone。兄弟目录存在且设了 `USING_LOCAL_DEPENDENCIES=1` 才用本地副本，否则静默用远端版本（`Package.swift:42`）。

## 模块分层

子节点是父节点的依赖：

```text
swift-section                       CLI wrapper
└─ SwiftSectionKit                  one request per subcommand (+ MachOObjCSection's ObjC* products for `objc`)
   ├─ SwiftDump                     the `dump` output
   ├─ TypeIndexing                  `__C` type → module attribution (macOS only)
   └─ SwiftInterface                orchestrator: single version / diff / evolution
      ├─ SwiftIndexing              image → declaration model
      ├─ SwiftPrinting              declaration model → Swift source (a peer of SwiftIndexing)
      ├─ SwiftSpecialization        generic specialization
      └─ SwiftDiffing               ABI comparison, no Mach-O access
SwiftDeclaration                    the shared declaration model all of the above read and write
└─ SwiftDeclarationRendering        comment engine shared by dump and interface
   ├─ SwiftLayout                   static field offsets and layouts
   └─ SwiftThunkAnalysis            accessor-thunk evaluation, ObjC member tables
SwiftInspection                     runtime-metadata analysis, symbol attribution
└─ MachOSwiftSection                ABI model: the `__swift5_*` sections and their descriptors
   └─ MachOBase                     reading / resolving / pointers
MachOFoundation = MachOBase + MachOSymbols + MachODependencies
```

- 每个 target 的完整依赖在 `Package.swift`（`:336` 起）；每个模块一句话的说明在 `AGENTS.md`。
- `Sources/` 按职责分 9 组目录，新 target 要在 `Package.swift` 里写 `path:`（[提案 0055](../Evolutions/0055-group-sources-by-layer.md)）。分组不等于依赖层次：`Sources/Output/SwiftDeclarationRendering` 反而被 `Sources/Declaration/SwiftDeclaration` 依赖。
- ABI 层自包含：`MachOSwiftSection` 只依赖 `MachOBase`，不碰符号索引和 demangler（`Package.swift:464`），符号归属在 `SwiftInspection` 里做。
- dump 和 interface 是两条独立的打印路径：dump 按 descriptor 逐个打印、不建声明模型，interface 先建模型再打印；两者共用 `SwiftDeclarationRendering` 的注释引擎。

## 关键流程

### `swift-section dump <binary>`

1. `DumpCommand.run()` 把 flag 映射成 `DumpRequest` — `Sources/Executables/swift-section/Commands/DumpCommand.swift:84`（映射在 `:63`）
2. `DumpRequest.run` 装上 thunk reader，加载二进制 — `Sources/Commands/SwiftSectionKit/Swift/DumpRequest.swift:140`
3. `MachOSource.load()` 打开文件，或从 dyld shared cache 里取出那个 image，得到 `MachOFile` — `Sources/Commands/SwiftSectionKit/Inputs/MachOSource.swift:59`
4. 不建声明模型；只有 `--emit-private-source-files` 才另建一个索引器 — `Sources/Commands/SwiftSectionKit/Swift/DumpRequest.swift:190`
5. 按段走：类型、协议、Swift 声明的 `@objc` 协议、遵循、关联类型、`@objc @implementation` 类 — `Sources/Commands/SwiftSectionKit/Swift/DumpRequest.swift:231`
6. 类型列表直接读 `__swift5_types` — `Sources/ABI/MachOSwiftSection/MachOFile+Swift.swift:18`
7. 每个类型交给对应的 dumper，比如 class 交给 `ClassDumper` — `Sources/Output/SwiftDump/Dumpable/Class+Dumpable.swift:10`、`Sources/Output/SwiftDump/Dumper/ClassDumper.swift:13`
8. 结果写进 `SwiftSectionOutput`；CLI 的实现把产品送 stdout、诊断送 stderr — `Sources/Commands/SwiftSectionKit/Output/SwiftSectionOutput.swift:14`、`Sources/Executables/swift-section/Output/StandardStreamOutput.swift:19`

### `swift-section interface <binary>`

1. `InterfaceCommand.run()` 把 flag 映射成 `InterfaceRequest` — `Sources/Executables/swift-section/Commands/InterfaceCommand.swift:103`（映射在 `:78`）
2. 建 `SwiftInterfaceBuilder` — `Sources/Commands/SwiftSectionKit/Swift/InterfaceRequest.swift:180`
3. `prepare()` 交给索引器 — `Sources/Output/SwiftInterface/SwiftInterfaceBuilder.swift:105`、`:125`
4. 索引器在 large-stack executor 上依次建类型、协议、遵循、extension 的定义；类型的字段和成员这时还不填 — `Sources/Declaration/SwiftIndexing/SwiftDeclarationIndexer.swift:273`（四个阶段在 `:502`、`:642`、`:722`、`:897`）
5. `printRoot()` 先算出导出过滤的范围，再按块打印 — `Sources/Output/SwiftInterface/SwiftInterfaceBuilder.swift:141`、`:152`
6. 打印一个类型之前才 `index(in:)`：字段、成员、要跨几种符号才推得出的事实在这一步填上，每个定义只跑一次 — `Sources/Output/SwiftPrinting/SwiftDeclarationPrinter.swift:275`、`Sources/Declaration/SwiftDeclaration/Components/Definitions/TypeDefinition+Indexing.swift:16`
7. 打印器渲染成 `SemanticString`（带语义标注的字符串，宿主据此着色） — `Sources/Output/SwiftPrinting/SwiftDeclarationPrinter.swift:262`
8. 交给输出 — `Sources/Commands/SwiftSectionKit/Swift/InterfaceRequest.swift:207`

### `swift-section evolution <v1> <v2> …`

1. `EvolutionCommand.run()` 把 flag 映射成 `ABIEvolutionRequest` — `Sources/Executables/swift-section/Commands/EvolutionCommand.swift:107`（映射在 `:59`）
2. 默认按 CPU 核数并发处理各个输入 — `Sources/Commands/SwiftSectionKit/Swift/ABIEvolutionRequest.swift:78`、`:88`
3. 输入是 JSON 快照就直接解码，格式版本对不上就报错 — `Sources/Commands/SwiftSectionKit/Swift/ABISnapshotLoading.swift:27`、`Sources/Output/SwiftDiffing/ABISnapshotDocument.swift:94`
4. 输入是二进制就走和 interface 同一个索引器，再把每个定义都 `index(in:)` 一遍、冻结成 `ABISnapshot` — `Sources/Commands/SwiftSectionKit/Swift/ABISnapshotLoading.swift:44`、`Sources/Output/SwiftInterface/SwiftDiffableInterfaceBuilder.swift:58`、`:107`
5. `ABIEvolutionBuilder` 把 N 份快照对齐，每个声明一条 lineage — `Sources/Commands/SwiftSectionKit/Swift/ABIEvolutionRequest.swift:105`、`Sources/Output/SwiftDiffing/ABIEvolutionBuilder.swift:9`
6. `ABIEvolutionReporter` 写出报告 — `Sources/Commands/SwiftSectionKit/Swift/ABIEvolutionRequest.swift:113`、`Sources/Output/SwiftDiffing/ABIEvolutionReporter.swift:30`
7. 带 `--interface` 时改走另一条：合并成一份带演进注释的 interface — `Sources/Commands/SwiftSectionKit/Swift/ABIEvolutionRequest.swift:79`

## 地标

- `Package.swift` — 29 个库 target 的声明与依赖（`:336` 起）、product 清单（`:1344`）；最近三个月改了 80 次，是改得最勤的文件
- `Sources/MachO/MachOSymbols/SymbolIndexStore.swift:17` — 符号索引：每个 image 的符号表解析、demangle、按成员种类分桶
- `Sources/ABI/MachOSwiftSection/MachOFile+Swift.swift:14` — ABI 模型的入口 `machO.swift`
- `Sources/Analysis/SwiftInspection/SymbolicDemangler.swift:31` — 带 symbolic reference 的名字怎么还原成完整的名字
- `Sources/Declaration/SwiftIndexing/SwiftDeclarationIndexer.swift:45` — 从一个 image 建出声明模型
- `Sources/Declaration/SwiftDeclaration/Components/Definitions/TypeDefinition.swift:16` — 一个类型在声明模型里的样子
- `Sources/Output/SwiftPrinting/SwiftDeclarationPrinter.swift:19` — 把声明模型打印成 Swift 源码
- `Sources/Output/SwiftInterface/SwiftInterfaceBuilder.swift:19` — interface 的编排：prepare、导出过滤、按块打印
- `Sources/Commands/SwiftSectionKit/Inputs/MachOSource.swift:15` — 所有 request 共用的唯一加载器
- `Sources/Output/SwiftDiffing/ABISnapshotDocument.swift:77` — 快照格式版本（现在是 10）；改了 key 的写法就要升，旧快照随之读不进

## 术语

完整的项目术语见 [术语表](../Glossary.md)，这里只列读代码前必须知道的十个。

- **image**：一个 Mach-O 二进制单位——一个框架、一个可执行文件，或 dyld shared cache 里的一员。
- **`MachOFile` / `MachOImage`**：两种 reader。前者离线读磁盘上的文件或 cache 文件，后者读当前进程已加载的 image，能调运行时。
- **descriptor**：`__swift5_*` 段里描述类型、协议、遵循的记录，彼此用相对指针相连；`MachOSwiftSection` 就是它们的 Swift 封装。
- **symbolic reference**：mangled name 里直接指向某个 descriptor 的相对指针；普通 demangler 解不开，由 `SymbolicDemangler` 负责。
- **`Node` / `NodeReference`**：demangle 出来的语法树；`NodeReference` 是共享存储里的节点引用，它自带的相等性按所在 store 算，跨 store 比较要用 `StructuralNodeReferenceKey`。
- **materialize**：从 descriptor 读出完整的 wrapper。一次操作最多一次，用局部变量传下去，不缓存回定义上。
- **export status**：一个声明的符号在不在导出表里，`--exported-only` 和 `// not exported` 注释都看它；四种「下不了结论」的情况一律不算未导出。
- **snapshot / lineage**：snapshot 是一个版本冻结下来的 ABI，可以存成 JSON 基线；lineage 是一个声明跨 N 个版本的在场情况与事件。
- **marking mode**：全量打印一遍，把受选项控制的内容标上可见条件，由宿主按当前选项投影；RuntimeViewer 的 Find 用它建语料。
- **stand-in member symbol**：真正的实现符号没了时，用 image 里剩下的别的入口（method descriptor、`@objc` thunk、initializing entry point）造的替身。

## 在做的事

- 0.24.0（2026-10-26）之后合进 `next` 的都还没发版：[提案 0076–0084](../Evolutions/README.md) 和几个修复。下一版按计划删掉废弃的读取接口（[提案 0057](../Evolutions/0057-reading-context-migration.md)），MachOKitUI 和 swift-decompiler 要先迁移（2026-10-26 时还在用，之后未复核）。
- 等批准：[静态布局引擎读取 accessor thunk 背后的字段类型](../Evolutions/draft-static-layout-through-accessor-thunks.md)（2026-09-16 起草，没开始实现）。
- 跨仓库进行中：嵌套坐标字段的精确访问大小，由 swift-decompiler 维护唯一的提案（链接见 [提案索引](../Evolutions/README.md)）。
- 开着的 issue：#137（两个问题都已修在 `next`，等发版）、#139（interface 把手写的 `_x` 字段当成 property wrapper 的 backing storage）、#140（dump 给被删实现的 class 方法印出 `class func static`）、#99（vtable 里的 class 方法印成 `static`）、#83（个别框架生成 interface 失败）。
- 已知没做：image group 演进还没接命令行（[提案 0082](../Evolutions/0082-image-group-evolution.md) 的后续项）；只带上下文 `where` 子句的方法，函数头会多印一个泛型参数表（[演进账本](ProjectEvolutionLog.md)第 118 节记录，未核对）。
- 兄弟仓库待发版：MachOObjCSection 的 `next` 上有重复成员按来源取舍、只打导出声明、ObjC 一侧的注释结构标记；swift-demangling 的 `next` 上有两处修复。
- 文档缺口：[模块参考](Modules/README.md) 还有 13 个模块没写。
- 审查积压：仓库根 `Roadmaps/` 下按日期存着各轮 review 的发现清单。

## 复杂度热点

- **符号索引的几套成员索引**（`Sources/MachO/MachOSymbols/SymbolIndexStore.swift:202`–`:215`）：实现符号、method descriptor、protocol witness、`@objc` thunk 四套成员索引并列，同一个成员可能同时出现在几套里。名字键去掉了 private discriminator，同名的私有类型共用一个桶，所以按单个类型查要用带 node 的重载（`:1334`）。难在哪一套回答哪一种问题，只能从注释和提案里拼出来。
- **`TypeDefinition` 索引的步骤顺序是承重的**（`Sources/Declaration/SwiftDeclaration/Components/Definitions/TypeDefinition+Indexing.swift:22`）：`final` 的还原要读 `applyThunkAttributes` 挂上的 `@objc` 证据，又必须早于 `orderedMembers` 拷贝成员值；wrapped property 的还原要等字段和成员变量都齐。换了顺序照样编译通过，输出却静默变错。
- **dyld shared cache 里的四种偏移口径**（`Sources/Analysis/SwiftThunkAnalysis/Resolution/ThunkAddressSpace.swift:42`）：本库的 offset 是「未滑动的虚拟地址减 shared region 起点」；另外三种（subcache 文件偏移、`MachOFile.fileOffset(of:)`、`FullDyldCache.address(of:)`）看着能用却不对，而且算错时给出的是一个落在邻近 image 里、看起来合理的地址，不报错。
- **泛型参数的层号**（`Sources/Analysis/SwiftInspection/GenericParameterDepthLayout.swift:30`）：一层只算真正声明了参数的上下文，不能数祖先链；opaque type 还要把声明它的函数（debug 构建里还有属性）算进去。八个读取点曾各自数错，现在统一从这里取。
- **ObjC 成员的三档证据**（`Sources/Analysis/SwiftThunkAnalysis/ObjCMembers/ObjCMembers.swift:9`）：IMP 处的 `To` 符号、符号被剥后反汇编 thunk、只按名字推断。第三档只记录、用不用由使用方决定，而且不能写进 `attributes`——紧接着的 `final` 还原会把它当成 `@objc dynamic` 的证据。
