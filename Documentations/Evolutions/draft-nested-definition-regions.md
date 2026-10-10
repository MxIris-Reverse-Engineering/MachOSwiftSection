# Draft - 在父定义的打印结果里标出嵌套子定义的边界

- **状态**: In Progress
- **创建日期**: 2026-10-01
- **最后更新**: 2026-10-08
- **所属愿景**: 无
- **关联提案**: [0056-visibility-regions](0056-visibility-regions.md)（同一手法：区域编码在原子的 `identifier` 里，冻结后分离成一张表）；RuntimeViewer 的 `draft-find-navigator` §1.1 方案 D（使用方）；swift-semantic-string 的设计记录 `docs/VisibilityRegions.md`
- **实现分支 / PR**: 本库 `feature/runtime-viewer/find-navigator`；swift-semantic-string `feature/definition-regions`
- **配套文档**: swift-semantic-string 的设计记录 `docs/DefinitionRegions.md`；[Glossary.md](../Glossary.md)「nested-definition region」

## 摘要

RuntimeViewer 建 Find 语料时，嵌套类型会被打印两遍：父类型的打印里内联了一遍，嵌套类型作为自己的对象又单独打印一遍。它的计时探针量出这部分在 Foundation 和 SwiftUI 上都占打印时间约四成（Foundation 只打顶层 2.23 s、全打 3.72 s；SwiftUI 31.15 s 对 51.95 s），超过它的提案定的 20% 门槛，所以改走方案 D：子对象不再单独打印主体，而是从父对象的打印结果里切出属于自己的那一段，去掉一级缩进后直接用。今天切不出来：`NestedDeclaration` 把子定义的原子摊平进父定义，不留边界。本提案让打印器在一个新开关下，给每个内联打印的嵌套子定义标上边界和身份（手法同可见性区域），并承诺、用测试钉住「同一个定义内联打印和单独打印，除缩进外逐字节相同」。

## 方案

### 改动位置

- **swift-semantic-string**（新功能，另一个仓库，落在 `Sources/Semantic/DefinitionRegions/` 与 `Frozen/FrozenSemanticString+Indentation.swift`）：`DefinitionRegion` 组件把一个身份字符串编码进内容里每个原子的 `identifier`，编码放在可见性标记里面一层，两种标记可以叠在同一个原子上，两种嵌套顺序得到的原子相同；`separatingDefinitionRegions()`（与 `separatingVisibilityRegions()` 同形，两者可按任意顺序调用）读回成 `DefinitionRegionTable`，记录每个区域的身份、UTF-8 范围、深度和直接外层区域，并还原原子原来的 `identifier`。两个操作：`content(ofDefinitionRegion:)` 在**带标记的**冻结串上切出一个区域，去掉该区域及外层区域的身份、按首次使用顺序重建 identifier 表，结果再做两种分离就得到子定义自己的文本与两张表；`removingIndentation(levels:)` 按行去掉开头 N 级缩进（每级 4 个空格），进到多行原子内部，有一行缩进不够就返回 `nil`。
- **MachOSwiftSection**：
  - `SwiftDeclarationPrintConfiguration` 加开关 `marksNestedDefinitions`（默认 `false`）。关着时输出与今天逐字节相同。
  - `SwiftDeclarationPrinter.swift:289` 与 `:303`（类型里的嵌套类型、嵌套协议）、`:436` 与 `:450`（extension 里的类型、协议）：开关打开时，把每个 `NestedDeclaration` 里那次 `printTypeDefinition` / `printProtocolDefinition` 的结果包进 `DefinitionRegion`。身份用名字节点的 mangled name，即 `mangleAsString(child.typeName.node)` 或 `mangleAsString(child.protocolName.node)`——RuntimeViewer 的 `RuntimeObject.name` 正是这个值，拿到就能对上对象，不需要另建映射。
  - `SwiftDeclarationPrinter.swift:378`：先修一个会破坏下面契约的既有问题。嵌在 extension 里的协议，索引器只给它设 `extensionContext`（`SwiftDeclarationIndexer.swift:651`），`parent` 留空，于是打印时它会在原地、以第 1 级接着打印自己的默认实现扩展，结果落在外层 extension 的大括号里面、顶格（Foundation 的 `extension __C.NSNotificationCenter { protocol AsyncMessage {…} }` 就是这样，生成的 Swift 不合法）。这几行内联时与单独打印时缩进相同，按行去缩进必然对不上。修法见「需要你定的」第 1 条。
- **不动**：单独打印的输出、开关关着时的全部输出、事件、导出过滤、`displayParentName`。

### 契约：内联与单独打印除缩进外逐字节相同

对一个嵌套深度为 d 的定义（直接嵌在顶层定义里时 d = 1），它在父定义里的那段区域按行去掉开头 d 级缩进后，必须与单独打印它（同一 printer 配置、`level` 为 1、`displayParentName` 为 `false`）的冻结结果完全相同：文本、span、`identifier`，以及标记模式下的可见性区域表。空行没有缩进，原样保留。

需要特别处理的地方：

- **多行原子**：enum layout 的逐 case 注释是一个原子、多行，每行自带缩进前缀（`DeclarationRenderConfiguration.swift:281` 的 `caseProjection.description(indent:prefix:)`）。去缩进要进到原子内部逐行做，不能只删独立的缩进原子；这正是把去缩进放进 swift-semantic-string 的原因。
- **transformer**：`EnumLayoutCaseTransformer`、`SpareBitAnalysisTransformer` 等闭包收到 `indentation` 自己决定怎么缩进。契约只覆盖「每行按 `indentation` 加前缀」的 transformer：本库 `OutputTransformer` 的模板都是这样，测试钉住；调用方自己写的任意闭包做不到保证，文档写明。
- **展开字段偏移**：每行用 `Indent(level: baseIndentation)` 单独成原子（`DeclarationRenderConfiguration.swift:210`），按行去缩进天然成立，测试照样覆盖。

### 嵌套与回退

区域可以嵌套：孙定义的区域在子定义的区域里，表里记下父子关系，RuntimeViewer 去缩进时按孙定义自己的深度来。子定义打印失败时，`:289` 等循环的逐子 catch 会把它整个丢掉，于是表里没有它的区域；父定义打印失败则整份都没有。两种情况都由 RuntimeViewer 回退到单独打印，本库不做额外处理。

### 代价

只在开关打开时有：每个内联的嵌套子定义多一次 remangle 和一层原子标记，分离时多扫一遍。RuntimeViewer 换来的是不再单独打印嵌套子定义的主体（约四成打印时间）。

### 验证

- 契约测试：SymbolTestsCore 里每个有嵌套子定义的类型，逐层取出每个子定义的区域，去缩进后与单独打印比较（文本、span、`identifier`、可见性区域表）。配置覆盖：普通打印；标记模式全开（含 enum layout 与展开字段偏移）；`OutputTransformer` 模板全开；进程内与文件两种读取方式。另测区域表的嵌套结构与身份。
- 嵌在 extension 里的协议：先确认 fixture 里有没有；没有就用现场编译的小 fixture 测，不改 SymbolTestsCore（改它会牵动全部基线）。
- 开关关着：渲染 A/B 逐字节一致（AGENTS.md 必跑）；第 1 条修复会改变「嵌在 extension 里的协议」所在 interface 的输出，A/B 里这类差异要逐处核对并在决策日志里列出。
- swift-semantic-string：组件、分离、切片、按行去缩进（含多行原子与空行）的单元测试，走它自己的流程。

### 需要你定的

1. **嵌在 extension 里的协议，默认实现扩展打在哪**（推荐 a）：
   - a. `extensionContext` 不为空的协议不再在原地打印默认实现扩展；顶层 interface 改在 extensions 区块里打印它们（今天这些扩展被标成 `isAttachedToProtocolDefinition`，在 extensions 区块里跳过）。生成的 Swift 变合法，内联与单独打印也一致；RuntimeViewer 按方案 D 本来就把子对象自己的扩展另外接在后面。
   - b. 保留原地打印，只把缩进改对。Swift 里 extension 不能写在另一个 extension 的大括号里，改缩进也还是不合法，不推荐。
2. **开关**（推荐单独的 `marksNestedDefinitions`）：与 `marksOptionalContent` 互不相干，宿主可以只开一个；RuntimeViewer 两个都开。另一种是并进 `marksOptionalContent`，少一个开关但把两件事绑死。
3. **身份**（推荐名字节点的 mangled name）：与 RuntimeViewer 的对象名一致。另一种是描述符偏移，更便宜，但 RuntimeViewer 的对象不带偏移，得另建映射。
4. **切片与去缩进放哪**（推荐 swift-semantic-string）：它是通用的文本操作，要和可见性区域表一起平移，放在定义那张表的库里最不容易错；放在 RuntimeViewer 也行，但它得自己理解两种标记的编码。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-10-01 | Created as Draft | RuntimeViewer 的计时探针量出嵌套对象占打印时间约四成（Release，`72913c3d`；Foundation 只打顶层 2.23 s、全打 3.72 s，SwiftUI 31.15 s 对 51.95 s，libswiftCore 15–22%），超过其提案定的 20% 门槛，指向方案 D。用户在 RuntimeViewer 的会话里对「要让 MachOSwiftSection 那边的会话起草这份上游提案吗？」选了「让它起草提案」；只起草，审过置 `Accepted` 之前不写实现。需求三条由 RuntimeViewer 会话转来：子定义原子的边界标记且可嵌套、内联与单独打印除缩进外逐字节相同并用测试钉住（含 enum layout 多行原子、展开字段偏移、transformer 三种情况）、失败由 RuntimeViewer 回退。 |
| 2026-10-01 | Accepted；四个待定项都按推荐 | 用户在 RuntimeViewer 会话里选定：嵌在 extension 里的协议的默认实现扩展改到顶层 extensions 区块打印；单独开关 `marksNestedDefinitions`；身份用名字节点的 mangled name（RuntimeViewer 核实 `RuntimeSwiftSection.swift:275` 以 `mangleAsString(typeDefinition.typeName.node)` 作 `RuntimeObject.name`，协议在 `:258`、扩展在 `:237`）；切片与去缩进放进 swift-semantic-string。随后在本仓库的会话里直接确认「确认，排在遍历修复之后」：先做 swift-demangling 的节点遍历修复（并行打印的引用计数争用），再实现本提案。 |
| 2026-10-01 | In Progress；库接口改为「在带标记的串上切，切完再分离」 | 方案原写「把冻结字符串连同它的可见性区域表切到某个区域」。实现时改成在带标记的冻结串上切（`content(ofDefinitionRegion:)`），可见性区域表由切出的串自己分离得到：`separatingVisibilityRegions()` 按 identifier 表的顺序给条件编号，切表就得重新编号、合并相邻区域、处理跨切点的区域，等于把分离逻辑重写一遍；切串时按首次使用顺序重建 identifier 表，再分离出的表与单独打印的逐项相同（swift-semantic-string 的 `DefinitionRegionTests` 钉住）。定义区域的编码放在可见性标记里面一层：容器与可见性分离都只看第一个字符认标记，放在外层会让容器把带条件的成员当成无条件的。 |
| 2026-10-01 | 「extension 里的协议」只发生在扩展别的模块的类型时；打印器与 interface 生成器各改一处 | 现场编译的 fixture 显示：协议声明在本模块类型的 extension 里时，编译器把它直接挂在类型上（成为该类型的嵌套协议，本来就打印正确）；只有扩展别的模块的类型（`extension Int { protocol Counter }`）才留下 extension 上下文、没有 `parent`。修法按「需要你定的」第 1 条 a：`SwiftDeclarationPrinter` 只给 `parent` 与 `extensionContext` 都为空的协议原地打印默认实现扩展；`SwiftInterfaceBuilder` 原本只把 `parent != nil` 的协议的扩展放进顶层区块，现在也包括 `extensionContext != nil` 的。`ProtocolInExtensionTests` 先红后绿：修复前三条全部失败（interface 里 `extension Swift.Int.Counter {` 开在 `extension Swift.Int {` 的大括号里；单独打印带着扩展；从 extension 里取出的协议去不掉缩进），修复后通过。 |
| 2026-10-01 | 实现：`marksNestedDefinitions` 与 `SwiftDeclarationPrinter+DefinitionRegions.swift` | 四处嵌套循环都经 `nestedDefinition(named:printing:)`：先打印子定义，开关打开且结果非空时才算 mangled name（`mangleAsString(name.node)`）并包一层区域；名字 remangle 失败或含控制字符（区域身份不能带）就不标，宿主单独打印它。开关关着时代码路径不变。 |
| 2026-10-01 | 验证：契约测试全部通过 | `NestedDefinitionRegionContractTests`（SwiftInterfaceTests）：SymbolTestsCore 里每个有嵌套定义的根类型与 extension（几乎所有类型都嵌在命名空间 enum 里），进程内与文件两种读取方式，各三种配置——只开 `marksNestedDefinitions`；再开 `marksOptionalContent` 并挂 opaque 解析器；全部打印选项打开并装上 `applyTransformers(_:)` 的全部模板。每个区域取出、去缩进后与单独打印比较文本、span、identifier、可见性区域表与内层定义区域表，并核对区域数等于嵌套定义数（防漏标），每种配置都检查了 100 个以上的区域，首次运行即全部通过；另有一条确认开关打开时分离后的文本与不开时逐字节相同。swift-semantic-string 侧全部 432 个测试通过、watchOS `arm64_32` 编译通过。 |
| 2026-10-01 | 全量测试与渲染 A/B 通过；Foundation 上只挪动了两个扩展 | 全量 `swift test --skip IntegrationTests`（沙盒副本，本地兄弟依赖，swift-semantic-string 指向 `feature/definition-regions`）2174 个测试全部通过，原始退出码 0。渲染 A/B：基线是本分支 `ed289fb4` 的 git archive，候选是加上本提案改动的副本，两侧依赖相同、只有 swift-semantic-string 指向不同分支；92 对逐字节一致，iOS 15.5 模拟器的 SwiftUI / WidgetKit 两侧同样崩溃（MachOKit `ExportTrie.init`，见并发打印提案）。A/B 的框架里没有协议声明在别的模块类型的 extension 里，另用两侧 CLI 渲染当前系统 Foundation 的 interface 对比：只有 `NSNotificationCenter.AsyncMessage` 与 `NSNotificationCenter.MainActorMessage` 的两个默认实现扩展，从 `extension __C.NSNotificationCenter { … }` 的大括号里（顶格）挪到了顶层的嵌套协议扩展区块，其余四万多行逐字节相同。 |
| 2026-10-08 | PR #131 review 第 4 条：interface 的嵌套协议默认实现区块读列表之前，先对协议调用 `index(in:)` | 声明在 extension 里的协议，要到后面的 extensions 区块才被打印、被索引；而它的默认实现列表只有在协议自己的索引过程里才完整——library evolution 下，默认实现来自父协议 extension 时，编译器生成一个挂在需求名下的默认 witness，`prepare()` 的符号扫描认不出它，由协议的索引过程兜底补出这个 extension。区块读列表时协议还没索引，列表是空的，打印器又不再在协议后面接它（本提案的改动），于是这个 extension 哪里都不打印；同一个 builder 打印两次，第二次才出现。改前它被打印在外层 extension 的大括号里（位置不合法，但打印了），所以这是本提案引入的回退，只出现在这个窄形状上。索引同步、可重复调用、只跑一次（`DefinitionIndexing`），区块顺序不动。复现测试 `ProtocolInExtensionDefaultWitnessTests`（library evolution 编的 fixture）先红后绿。RuntimeViewer 的 `defaultImplementationExtensionsLeftToPrint(of:)` 也是直接读这个列表，要同样先索引协议（那边改）。根因的另一种修法——让 `prepare()` 认出挂在需求名下的默认 witness——改动大得多，没做 |
| 2026-10-08 | 「哪些协议在声明后面接着打印默认实现扩展」公开为 `ProtocolDefinition.printsDefaultImplementationExtensionsAfterDeclaration`，打印器与 `SwiftInterfaceBuilder` 都改读它 | RuntimeViewer PR #121 审查的第 PR121.27 条：它的 Find 语料与内容区要自己补印打印器不接在协议后面的默认实现扩展，此前只能照抄本提案定下的条件；本提案 2026-10-01 给条件加上 `extensionContext == nil` 时，它那份拷贝就错了，直到它的 74c349c7 跟上。库里也写了两份：打印器一份，`SwiftInterfaceBuilder` 的嵌套协议区块取反一份。现在规则只写在这个属性里（`parent == nil && extensionContext == nil`）：打印器读它，区块读它的反面，宿主也读它；文档注释写明为什么嵌在类型里与声明在别的模块类型的 extension 里的协议不在其列。行为不变：JHs-Mac-Studio、Xcode 27.0、本地兄弟依赖，改动前后 SwiftInterfaceTests、SwiftSectionKitTests 与 SwiftPrintingTests（不含 `EnumCaseRenderingParityTests`）的逐条结果相同，289→290、64、42 个测试全部通过，原始退出码 0，多出的一条是新测试；整模块 interface 快照 `SymbolTestsCoreInterfaceSnapshotTests` 也在其中。`EnumCaseRenderingParityTests` 在这个环境里改动前后都在第一个测试崩溃（SIGSEGV），两侧单独跑结果相同，与本改动无关。`ProtocolInExtensionTests` 的 fixture 加了顶层协议 `Greeter`，新测试断言三种位置的协议这个属性分别为 true / false / false；把属性临时改回只看 `parent == nil`（本提案之前的规则）时，新测试与该套件原有的三条一起失败，说明打印器与区块都只经这个属性。渲染 A/B 没做：只是把已有条件抽成属性，不算 AGENTS.md 说的大型重构 |
