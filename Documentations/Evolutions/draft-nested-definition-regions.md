# Draft - 在父定义的打印结果里标出嵌套子定义的边界

- **状态**: Accepted
- **创建日期**: 2026-10-01
- **最后更新**: 2026-10-01
- **所属愿景**: 无
- **关联提案**: [0056-visibility-regions](0056-visibility-regions.md)（同一手法：区域编码在原子的 `identifier` 里，冻结后分离成一张表）；RuntimeViewer 的 `draft-find-navigator` §1.1 方案 D（使用方）；swift-semantic-string 的设计记录 `docs/VisibilityRegions.md`
- **实现分支 / PR**: 待定（起草于 `feature/runtime-viewer/find-navigator`）
- **配套文档**: 无

## 摘要

RuntimeViewer 建 Find 语料时，嵌套类型会被打印两遍：父类型的打印里内联了一遍，嵌套类型作为自己的对象又单独打印一遍。它的计时探针量出这部分在 Foundation 和 SwiftUI 上都占打印时间约四成（Foundation 只打顶层 2.23 s、全打 3.72 s；SwiftUI 31.15 s 对 51.95 s），超过它的提案定的 20% 门槛，所以改走方案 D：子对象不再单独打印主体，而是从父对象的打印结果里切出属于自己的那一段，去掉一级缩进后直接用。今天切不出来：`NestedDeclaration` 把子定义的原子摊平进父定义，不留边界。本提案让打印器在一个新开关下，给每个内联打印的嵌套子定义标上边界和身份（手法同可见性区域），并承诺、用测试钉住「同一个定义内联打印和单独打印，除缩进外逐字节相同」。

## 方案

### 改动位置

- **swift-semantic-string**（新功能，另一个仓库）：在 `Sources/Semantic/Visibility/VisibilityRegion.swift` 旁边加一个 `DefinitionRegion` 组件，把一个身份字符串编码进内容里每个原子的 `identifier`，用与 `VisibilityTag` 不同的分隔符，两种标记可以叠在同一个原子上；冻结后用一个分离函数（与 `VisibilityRegionTable.swift:59` 的 `separatingVisibilityRegions()` 同形）读回成一张表，记录每个区域的身份、UTF-8 范围和嵌套关系，并还原原子原来的 `identifier`。再加两个通用操作：把冻结字符串连同它的可见性区域表切到某个区域；按行去掉开头 N 级缩进（每级 4 个空格），span 与区域表跟着平移。
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
