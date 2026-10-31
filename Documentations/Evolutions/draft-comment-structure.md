# Draft - 注释结构标记：打印器给每条注释标出种类和各段角色

- **状态**: In Progress
- **创建日期**: 2026-10-31
- **最后更新**: 2026-10-31
- **所属愿景**: 无
- **关联提案**: [0068-nested-definition-regions](0068-nested-definition-regions.md) 与 [0056-visibility-regions](0056-visibility-regions.md)（同一手法：标记写在原子的 `identifier` 里，冻结后分离成一张表）；RuntimeViewer 的 `draft-source-editor-comment-annotations`（使用方：SourceEditor 面板把注释画成标签，字段偏移树与枚举布局可折叠）；swift-semantic-string 新增的注释区域组件（载体，设计中）；MachOObjCSection 的同名开关（ObjC 一侧，同一套约定）
- **实现分支 / PR**: 本库 `feature/comment-structure`（worktree `.worktrees/MachOSwiftSection-CommentStructure`）；swift-semantic-string 的注释区域组件已落进它的 `next`（`2698750`），未发版
- **配套文档**: [术语表](../Glossary.md)的「comment structure」条目；[`Internal/Modules/SwiftInterface.md`](../Internal/Modules/SwiftInterface.md) 的「注释结构标记」一段

## 摘要

RuntimeViewer 要在 SourceEditor 面板里把 interface 的注释画成圆角标签（不显示 `// `、`/* */` 和标点，标签名与数值分色），把字段偏移树做成可折叠的大纲，把枚举布局的摘要和逐 case 说明拆成标签并可折叠。用户在 RuntimeViewer 会话里定了：注释的结构由生成器输出，RuntimeViewer 不解析注释文本。今天做不到，因为每条注释在 `SemanticString` 里只是一个 `.comment` 原子，枚举逐 case 的说明甚至是一个多行原子，种类、段、树的层级都没有留下。本提案给 `SwiftDeclarationPrintConfiguration` 加一个默认关的开关 `marksCommentStructure`：打开时，打印器把输出的每一条注释包进 swift-semantic-string 新增的注释区域（`AnnotationRegion`），标出它的种类（本库在 `AnnotationRegion.Kind` 上扩展的一组常量）和每一段的角色（marker、label、value……），字段偏移树与枚举布局用区域的嵌套表达层级；关着时输出与今天逐原子相同。

## 方案

### 改动位置

- **swift-semantic-string**（另一个仓库，由它的会话设计，草图见下文「依赖」）：`AnnotationRegion`（带一个 kind 的区域）、`AnnotationSegment`（带一个角色的段）、`AnnotatedAtom`（「不打标记时的一个原子」拆成几片打印，分离时并回一个 span）。标记写在原子的 `identifier` 上，不改文本；`separatingAnnotationRegions()` 分离出干净文本和一张表（区域的 kind、UTF-8 范围、深度、直接外层区域，段的角色、范围与所在区域）。
- **MachOSwiftSection**：
  - `SwiftDeclarationPrintConfiguration`（`SwiftDeclarationPrintConfiguration.swift:149` 起，与 `marksOptionalContent`、`marksNestedDefinitions` 并列）加 `public var marksCommentStructure: Bool = false`。
  - `DeclarationRenderConfiguration`（`DeclarationRenderConfiguration.swift:54`）加一个 package 级的同名属性，只由打印器在 `renderModelFields`（`SwiftDeclarationPrinter+Headers.swift:392`）里设置。
  - 在 `AnnotationRegion.Kind` 上扩展 Swift 的种类（公开），新增 `StructuredComment`（package，一条注释的种类与段），都放在 `Sources/Output/SwiftDeclarationRendering/`。
  - interface 路径上全部注释输出点改为经 `StructuredComment` 输出，逐处见下表「出处」一列。
  - `EnumLayoutCalculator.LayoutResult.summaryDescription`（`EnumLayoutCalculator.swift:295`）改为由策略名和一组事实拼出，文字不变，标记时用同一组事实分段。
  - `bodyAfterNestedDefinitions`（`SwiftDeclarationPrinter+VisibilityRegions.swift:78`）判断 body 末尾的换行时改为认 `BreakLine` 原子，理由见「依赖」。
- **不动**：dump 的输出（`SwiftDump` 的各个 Dumper、`DumpRequest`）；diff 与 evolution 渲染器自己的注释（`EvolutionMarking.swift`）；CLI 的选项与输出；开关关着时的全部输出。

### 开关与契约

1. **关着**：dump 与 interface 的输出与今天逐原子相同——文本、原子、span、identifier 都不变，一个原子都不多拆。
2. **打开**：把打印结果冻结，用 `separatingAnnotationRegions()` 分离出注释表之后，得到的冻结串与关着时完全相同——文本、span、identifier 逐个相等。为了标出段，一条注释会拆成几个 `.comment` 原子，但拆开的片都在一个 `AnnotatedAtom` 里，分离时并回原来的一个 span；装了 transformer 的注释不拆。RuntimeViewer 能接受的底线更宽：文本与每个字节的语义类型、identifier 相同，span 边界可以不同。万一 swift-semantic-string 最终不提供 `AnnotatedAtom`，契约退到这条底线。
3. **不漏标**：interface 路径上每一个 `.comment` 字节都落在某个注释区域里。测试用这一条找漏掉的输出点。
4. **与另外两种标记组合**：与 `marksOptionalContent` 一起打开时，按任一配置投影后再分离，得到的注释表与「用该配置打印、只开本开关」得到的相同；与 `marksNestedDefinitions` 一起打开时，嵌套定义那段切出、去缩进后分离出的注释表，与单独打印它得到的相同。

### 种类

种类是 `AnnotationRegion.Kind` 的静态成员，原始字符串与成员名相同；`note` 由 swift-semantic-string 自带，其余由本库扩展。清单以 RuntimeViewer 转来的起点清单为底，按实际输出补全：

| kind | 例 | 出处 |
|---|---|---|
| `memberAddress` | `// Address: 0x135DC`、`// Address (getter): 0x135DC`、`// Address (destructor): 0x…` | `SemanticComponents.swift:30` 的 `AddressComment`，用在 `SwiftDeclarationPrinter.swift:752`、`:755`、`:803`、`:806`、`:853`、`:899`、`:929` |
| `vtableOffset` | `// VTable offset: 12`、`// VTable offset (setter): 13` | `SemanticComponents.swift:57`（`SwiftDeclarationPrinter.swift:850`、`:896`、`:926`）；存储属性的访问器走 `DeclarationRenderConfiguration.swift:266`（`SwiftDeclarationPrinter+Headers.swift:490`） |
| `pwtOffset` | `// PWT offset: 0x18` | `SemanticComponents.swift:7` 前缀为 `PWT offset` 时（协议成员）；`SwiftDeclarationPrinter.swift:465`（被剥掉符号的协议需求） |
| `fieldOffset` | `// Field offset: 0x8` | `DeclarationRenderConfiguration.swift:213`（两个布局后端的存储字段）；`SemanticComponents.swift:7` 前缀为 `Field offset` 时；`SwiftDeclarationPrinter+ObjCImplementation.swift:15`（`@objc @implementation` 的 ivar） |
| `fieldOffsetUnknown` | `// Field offset: unknown (generic parameter not substituted)` | `DeclarationRenderConfiguration.swift:229` |
| `fieldLayoutNode` | `// │   ├── _countAndFlagsBits (Swift.UInt64): 0x8` | `DeclarationRenderConfiguration.swift:239`，两棵树的递归在 `StaticFieldLayoutBackend.swift:189` 与 `RuntimeFieldLayoutBackend.swift:250` |
| `typeLayout` | `// Type Layout: (size: 16, stride: 16, alignment: 8, extraInhabitantCount: 2147483647)`；进程内路径上元组类型的字段是一个多行块 | `DeclarationRenderConfiguration.swift:352`（文件路径）、`MetadataWrapper+Dump.swift:9`（进程内路径） |
| `typeLayoutElement` | 元组块里一个元素的 `// Type: …` 与 `// Layout: (…)` 两行 | `MetadataWrapper+Dump.swift:15` |
| `enumLayoutSummary` | `/* Tagged Multi-Payload (tag bytes after the payload area) — cases: 3 (2 payload + 1 empty); tag values used: 3; tag bits: 8; tag region: offsets 24..<25 (8 bits); leftover extra inhabitants for an outer enum: 253 */` | `DeclarationRenderConfiguration.swift:332` |
| `enumLayoutCase` | `/* Enum Layout */` 加这个 case 的整个说明块 | `StaticFieldLayoutBackend.swift:225`、`RuntimeFieldLayoutBackend.swift:178`，说明块是 `DeclarationRenderConfiguration.swift:308` |
| `enumLayoutCaseHeader` | `// Case 1 (0x01) `withPair` — payload case #1` | 同上，说明块的第一行 |
| `enumLayoutCaseEncoding` | `//   encoding: tag byte(s) after the payload area = 1; …` | 同上 |
| `enumLayoutCaseNote` | `//   note: the exact bytes depend on …` | 同上，只在离线路径解不出 extra inhabitant 的具体字节时出现 |
| `enumLayoutCaseFixedBytes` | `//   fixed bytes: byte[0x18] = 0x1 (0b00000001)` | 同上 |
| `enumLayoutCaseByte` | `//       offset 0x18 = 0x01 (0b00000001)`，每个字节一行 | 同上 |
| `exportStatus` | `// not exported` | `SemanticComponents.swift:96`（成员）、`DeclarationRenderConfiguration.swift:203`（存储属性，`SwiftDeclarationPrinter+Headers.swift:507`）、`SwiftDeclarationPrinter.swift:953`（全局声明） |
| `protocolExtensionDefault` | `// protocol-extension default` | `SwiftDeclarationPrinter.swift:861`、`:904`、`:934` |
| `privateDeclarationSource` | `// EnabledKey is declared in Enabled.swift of module SwiftUICore` | `SwiftDeclarationPrinter.swift:292`、`:447`、`:534`、`:843`、`:879`、`:918`，`SwiftInterfaceBuilder.swift:186`、`:202`；文字由 `PrivateDeclarationSourceFiles.swift:81` 拼出 |
| `conditionalWitness` | `// Body is picked at run time by an availability check (SE-0360):` 加它下面的分支行 | `SwiftDeclarationPrinter+Headers.swift:316` |
| `conditionalWitnessBranch` | `//   macOS 26.0 or later: some SwiftUI.View`，每个分支一行 | 同上 |
| `strippedSymbolicRequirement` | `// Kind: Method, isAsync: false, isInstance: true` | `StrippedSymbolicRequirement.swift:52` |
| `note` | 其余说明性注释，见下 | 见下 |

归为 `note` 的：局部类型的上下文（`SwiftDeclarationPrinter.swift:281`）、`@_rawLayout` 来自 builtin 描述符的说明（`:335`）、推断出的 `@objc @implementation` 证据（`:610`，行内注释）、由后备存储合成的包装属性（`SwiftDeclarationPrinter+Headers.swift:532`）、没有名字的枚举元素（`SwiftDeclarationPrinter+Members.swift:81`、`:131`）、`/* type not recoverable */`（`SwiftDeclarationPrinter+ObjCImplementation.swift:67`）、类型还原不出的 ivar（`:108`）、ObjC 协议的三种说明（`SwiftDeclarationPrinter+ObjCProtocols.swift:95`、`:98`、`:103`）、interface 文件头的每一行（`InterfaceHeader.swift:233`）。

起点清单里的 `spareBits`、`deletedMethodSlot`、`ambiguousAttribution` 不进对外清单：interface 路径不输出它们。`SwiftDeclarationPrintConfiguration` 没有 spare-bit 选项（`renderModelFields` 建的渲染配置里 `printSpareBitAnalysis` 恒为 `false`），另两种只由 `ClassDumper` 输出。它们的 helper 也改走 `StructuredComment`（见「实现」），种类先定为 package 级，等哪天 dump 也要标记时再公开。

### 段

角色沿用三方约定：`marker`（注释符号）、`label`、`qualifier`、`separator`、`key`、`value`、`name`、`type`、`treePrefix`、`text`。两条通用规则：

- 续行里注释符号后面用来对齐的空格算进 marker（`//   `、`//       `）。RuntimeViewer 隐藏 marker 后按区域的层级自己排版，不靠这些空格。
- 代码缩进、换行不属于任何段。多行块内部的代码缩进与换行在块区域之内、行区域之外。

各种类的段（`·` 分隔，引号里是原文，空格照原样）：

```
memberAddress / vtableOffset / pwtOffset / fieldOffset
    marker "// " · label "Address" · separator ": " · value "0x135DC"
    带访问器：marker "// " · label "Address" · separator " (" · qualifier "getter" · separator "): " · value "0x135DC"
    vtableOffset 的 label 是 "VTable offset"、value 是十进制槽号；pwtOffset、fieldOffset 的 label 是 "PWT offset"、"Field offset"

fieldOffsetUnknown
    marker "// " · label "Field offset" · separator ": " · value "unknown" · separator " (" · text "generic parameter not substituted" · separator ")"

fieldLayoutNode
    marker "// " · treePrefix "│   ├── " · name "_countAndFlagsBits" · separator " (" · type "Swift.UInt64" · separator "): " · value "0x8"
    没有类型名时：… name "_value" · separator ": " · value "0x8"

typeLayout
    marker "// " · label "Type Layout" · separator ": (" · key "size" · separator ": " · value "16" · separator ", " · key "stride" · … · separator ")"
    元组块：
        "/* Type Layout */"        marker "/* " · label "Type Layout" · marker " */"
        "// Type: Swift.Int"       marker "// " · label "Type" · separator ": " · type "Swift.Int"
        "// Layout: (…)"           同 typeLayout，label "Layout"
        "// Total: "               marker "// " · label "Total" · separator ": "

enumLayoutSummary
    marker "/* " · label "Tagged Multi-Payload (tag bytes after the payload area)" · separator " — "
    · key "cases" · separator ": " · value "3 (2 payload + 1 empty)" · separator "; " · key "tag values used" · … · marker " */"

enumLayoutCase
    "/* Enum Layout */"            marker "/* " · label "Enum Layout" · marker " */"
    Header      marker "// " · label "Case" · separator " " · value "1" · separator " (" · value "0x01" · separator ") `"
                · name "withPair" · separator "` — " · key "payload case" · separator " #" · value "1"
                没有声明名时 value "0x01" 后面是 separator ") — "；单载荷枚举的载荷 case 只有 key "payload case"
    Encoding    marker "//   " · label "encoding" · separator ": " · text "tag byte(s) after the payload area = 1; …"
    Note        marker "//   " · label "note" · separator ": " · text "…"
    FixedBytes  marker "//   " · label "fixed bytes" · separator ": " · value "byte[0x18] = 0x1 (0b00000001)"
                每个连续字节段一个 value，之间 separator ", "；"none — …"、"not computed" 这几种说法是 text
    Byte        marker "//       " · label "offset" · separator " " · key "0x18" · separator " = " · value "0x01" · separator " (" · value "0b00000001" · separator ")"
                只固定部分位的字节："offset 0x00: fixed bits 0b11000000 = 0b10000000 (the other bits hold payload storage)" →
                … key "0x00" · separator ": " · label "fixed bits" · separator " " · value "0b11000000" · separator " = " · value "0b10000000"
                · separator " (" · text "the other bits hold payload storage" · separator ")"

exportStatus / protocolExtensionDefault
    marker "// " · label "not exported"（或 "protocol-extension default"）

privateDeclarationSource
    marker "// " · name "EnabledKey" · separator " " · text "is declared in" · separator " " · value "Enabled.swift" · separator " " · text "of module" · separator " " · name "SwiftUICore"
    没有名字时以 text "Declared in" 开头；文件名没恢复出来时 text "is declared in a source file whose name could not be recovered"
    · separator " (" · key "private discriminator" · separator " " · value "_…" · separator ")"；编译器合成的文件是 text "is declared in the file the compiler synthesized for" · separator " " · value 文件名

conditionalWitness
    第一行      marker "// " · name "Body" · separator " " · text "is picked at run time by an availability check (SE-0360)" · separator ":"
    Branch      marker "//   " · qualifier "macOS 26.0 or later" · separator ":   "（冒号加对齐用的空格） · type "some SwiftUI.View"；无条件的分支 qualifier 是 "always"

strippedSymbolicRequirement
    marker "// " · key "Kind" · separator ": " · value "Method" · separator ", " · key "isAsync" · separator ": " · value "false" · …

note
    marker "// " · text "…"；行内注释是 marker "/* " · text "…" · marker " */"
```

### 结构

- **字段偏移树**：`fieldOffset` 区域覆盖 `// Field offset: 0x8` 那一行和它下面整棵树；每个 `fieldLayoutNode` 区域覆盖它自己那一行和它全部后代的行。所以只看嵌套就知道每个节点的深度、所在行和子树的末行，不用猜后面的同级区域算不算它的孩子。展开偏移树在自己的可见性区域里（`printExpandedFieldOffsets`），投影掉以后根区域只剩自己那一行。
- **枚举**：`enumLayoutSummary` 在类型的 case 之前，每条事实拆成 key / value 段。`enumLayoutCase` 覆盖 `/* Enum Layout */` 与这个 case 的全部说明行，每行一个子区域：`enumLayoutCaseHeader`、`enumLayoutCaseEncoding`、`enumLayoutCaseNote`、`enumLayoutCaseFixedBytes`，以及每个字节一个 `enumLayoutCaseByte`。载荷 case 前面的 `// Type Layout: …` 是独立的 `typeLayout` 区域，两块之间的空行不属于任何区域。
- **元组的 Type Layout**（只在进程内路径）：`typeLayout` 区域覆盖整块，每个元素一个 `typeLayoutElement` 子区域，`// Total: ` 与它下面那行属于整块、不另设区域。
- **条件 witness**：`conditionalWitness` 区域覆盖说明行与全部分支行，每个分支一个 `conditionalWitnessBranch` 子区域。
- 其余种类各占一行，一条注释一个区域。
- 表里报出的区域范围从第一段开始、到最后一段结束：行首的缩进与行尾的换行不算在内，多行区域内部的缩进与换行算在内。这由 swift-semantic-string 在分离时保证：它裁掉区域首尾那些不属于任何段、每个字节都是空白的原子或片，段从不裁。需要这一条，是因为字段偏移树的根区域在根那一行与树之间必须包住根自己的换行，而树所在的可见性区域一个原子都不能挪——挪了，标记模式下那个换行字节的可见性标记就与不开时不同——所以投影掉树以后，根区域以换行结尾，裁剪后就只剩根那一行。也因此，现有 helper 输出的「缩进 + 注释 + 换行」可以整个包进区域，不必重排原子。

### 装了 transformer 的注释

`fieldOffsetTransformer`、`vtableOffsetTransformer`、`typeLayoutTransformer`、`expandedFieldOffsetTransformer`、`enumLayoutTransformer`、`enumLayoutCaseTransformer` 的闭包返回任意 `SemanticString`，打印器不知道里面怎么分段。开关打开时，闭包的输出整个包进该种类的区域，它的原子全部记为 `text` 段，不再细分，也没有子区域——枚举 case 块只剩 `enumLayoutCase` 一层，RuntimeViewer 折叠到块的第一行。字段偏移树的嵌套不受影响：递归在打印器里，每一行闭包的输出照样包进 `fieldLayoutNode` 区域。

`applyTransformers(_:)` 装上的库自带模板也一样处理。按占位符标出代入的值要另做一套带段的模板渲染（每个模块的 `transform` 改成按占位符逐段输出，枚举 case 模板还要处理条件行与自动补行），而且打印器拿到的只是闭包，还得先知道它来自哪个模板模块，留给后续提案。

### 实现

- **种类常量**：公开地扩展在 `AnnotationRegion.Kind`（swift-semantic-string 的 struct 加静态成员）上。种类会随新注释增加，宿主遇到不认识的种类按 `note` 处理即可。MachOObjCSection 在同一个类型上扩展它自己的六个，两份清单互不重叠；两边都要用的种类放进 swift-semantic-string，免得 RuntimeViewer 同时 import 两个库时出现同名的静态成员。
- **`StructuredComment`**：一条注释的段（角色加文字），种类在加区域时由调用点给出——一个区域的种类未必只属于一行注释（字段偏移的根区域包着整棵树，枚举 case 的区域包着标题行与说明块）。不标记时渲染成一个 `.comment` 原子，文字是各段拼接，与今天的原子相同；标记时渲染成 `AnnotationRegion(kind) { AnnotatedAtom(type: .comment) { AnnotationSegment(role) { 文字 } … } }`，每段一片，分离时并回那一个原子。每处输出点只描述一次文字，两种渲染都从它来，两边不会写走样。关着时每条注释比今天多建一个段数组，第 5 步的性能对比量这部分开销，量出来不可忽略再改成直接拼字符串。一条注释无论拆成几个原子都仍是容器里的一个元素：`Rows`、`MemberList` 一个元素一行，拆散了成员前的注释会各占一行。
- **例外是枚举逐 case 的说明块**：关着时仍走 `EnumCaseProjection.description(indent:prefix:)`（`Transformer+EnumLayoutProjection.swift:86`，它是公开 API，模板引擎与 dump 共用），打开时由同一组 `Transformer.SwiftEnumLayout.CaseInput` 字段按行组装。两边一致靠契约测试覆盖 fixture 里的每个枚举，另用合成的投影做单元测试：只固定部分位的字节、离线解不出的 extra inhabitant、单载荷、没有声明名的 case。
- **dump 不标记**：`DeclarationRenderConfiguration` 里的共享 helper 都改走 `StructuredComment`（包括只有 dump 用的 `memberAddressComment`、`deletedMethodSlotComment`、`ambiguousAttributionComment`、`spareBitAnalysisComment`、`privateDeclarationSourceFileComments`），但它们的开关只由打印器设置，dump 建的配置从不设，所以 dump 输出不变、也不带标记。
- **防漏标**：一个源码扫描测试，在 interface 路径的模块（`SwiftDeclarationRendering`、`SwiftPrinting`、`SwiftInterface`、`SwiftDeclaration`）里，除 `StructuredComment` 自身外不许再直接构造 `Comment(`、`InlineComment(`、`MultipleLineComment(` 或类型为 `.comment` 的原子；`EvolutionMarking.swift` 进白名单。仓库里已有同类扫描（`ReaderKindCastScanTests`、`CommandLineStreamWriteScanTests`）。

### 依赖 swift-semantic-string

API 以它的会话定稿为准。它的草图（swift-semantic-string 的 next worktree 里 `docs/AnnotationRegions.md`，未提交）已满足本库提的要求：

- 区域可以嵌套（同 kind 也行），原样保留内容的元素结构（同 `DefinitionRegion`），起止可以落在一个 `AnnotatedAtom` 内部；相邻的两个同 kind 区域读回为两个。
- 边界不靠编号：每层区域在每个原子上记一个只取决于区域自身内容的阶段（锚点之前、锚点、锚点之后），所以去缩进、投影、切出定义区域都改不动它。0068 的「内联与单独打印逐个相同」、「标记模式投影到某个配置再分离 = 用该配置打印再分离」都成立，`content(ofDefinitionRegion:)` 与 `removingIndentation(levels:)` 不用改。
- 区域包住带 identifier 的原子时，原 identifier 留在最里层，分离时原样还原。
- 段的十种角色定义在 swift-semantic-string（`AnnotationSegment.Role`），两个生产方共用。

本库后来补提的几条，它也已确认：

- 表里报出的区域范围裁掉首尾那些不属于任何段、每个字节都是空格、制表符或换行的原子或片（见「结构」）。判断以原子为单位，被冻结切成几片的长原子按整个原子判断；只含这种原子的区域不进表。只看原子自身的字节，所以去缩进与投影都改变不了结果。
- `AnnotatedAtom` 的输出可以再被外层的可见性、定义、注释区域包住，由外层给每一片加同一个标记，`marksOptionalContent` 下照常并回一个 span。
- 不在 `AnnotatedAtom` 里的段可以包住任意原子：不同语义类型、带 identifier、带可见性或定义标记都行，只是段里不能再有段或注释区域。transformer 闭包的输出因此可以整个包成一个 `text` 段；哪天宿主自己也用注释区域标它的输出，就只包区域、不加段。
- 内容为空的段、区域、`AnnotatedAtom` 什么都不记，不 trap。

草图里的「一次扫描的模板代入函数」本库第一版不用，它已从提案里删掉。它列出的已知限制「分离之前看到的是拆开的片」，本库打印路径上按原子判断的有两处。`DeclarationBlock` 看最后一个原子的末字节，片拼起来末字节不变，不受影响。`bodyAfterNestedDefinitions`（`SwiftDeclarationPrinter+VisibilityRegions.swift:78`）判断最后一个原子是不是 `"\n"`，而枚举块拆开后最后一片正是 `"\n"`；今天块后面总跟着 case 声明，块不会是 body 的最后一项，但这条前提不该靠顺序维持。这处判断改为「最后一个原子是 `BreakLine`」：字符串是 `"\n"` 且类型是 `.standard`。拆出的片类型是 `.comment`，不会被认错；不开标记时没有哪个 `.comment` 原子恰好是 `"\n"`，行为不变。

本库依赖的下限随它发版抬高（今天是 0.5.0）。

### 落地步骤

1. **单一来源**（不依赖 swift-semantic-string；已完成）：新增 `StructuredComment`，这一步只有不标记的渲染。角色先用 package 级的过渡类型 `StructuredComment.Role`，成员名与 swift-semantic-string 草图里的 `AnnotationSegment.Role` 相同，段写成 `.label("Address")`，以后换类型时调用点不用动。interface 路径的全部注释输出点与 `DeclarationRenderConfiguration` 的共享 helper 改走它，`summaryDescription` 改为由事实拼出，加上源码扫描测试。这一步还没有开关，输出必须逐字节不变：全量测试与基线逐条一致，另用单元测试钉住每种注释的文字与段。
2. **接上 swift-semantic-string**（已完成）：依赖暂时指向它的 `next` 分支；删掉过渡类型，角色改用 `AnnotationSegment.Role`，种类常量公开地扩展在 `AnnotationRegion.Kind` 上。
3. **开关与标记渲染**（已完成）：`marksCommentStructure`、`StructuredComment` 的标记渲染、枚举 case 块的分段组装、字段偏移树与枚举与元组与条件 witness 的区域结构、transformer 闭包的包装、`bodyAfterNestedDefinitions` 的判断。
4. **测试**（已完成，与第 3 步同一个提交）：契约测试、结构测试、少见种类所在套件里的断言、单元测试。
5. **文档与完整验证**：模块文档、术语表、演进账本与 AGENTS.md 的规则行；全量测试、渲染 A/B、性能对比；依赖下限随 swift-semantic-string 发版抬高。

### 验证

- **契约测试**（SwiftInterfaceTests，新套件）：SymbolTestsCore，进程内与文件两种读取方式，四种配置——全部注释选项打开的默认渲染；再开 `marksOptionalContent` 并挂 opaque 解析器，逐个投影核对契约第 4 条前半；装上 `applyTransformers(_:)` 的全部模板；再开 `marksNestedDefinitions`，核对契约第 4 条后半。每种配置都核对契约第 2、3 条。
- **结构测试**：在 SymbolTestsCore 上断言具体形状——带 `String` 字段的结构体（树的嵌套、每个节点覆盖的行），多载荷枚举（摘要的 key / value，case 块的五种子区域与字节行的段），类的 getter / setter 地址与 vtable 槽（qualifier），`fieldOffsetUnknown`，`exportStatus`，进程内路径上的元组 Type Layout 块。
- **少见的种类**：条件 witness、ObjC 相关的说明、局部类型、`@_rawLayout`、合成的包装属性、没有名字的枚举元素、私有声明来源、被剥掉符号的协议需求，各自的套件已经现场编译了能产生它们的 fixture；在这些套件里加上契约第 2、3 条的断言（共用一个 helper），不改 SymbolTestsCore（改它会牵动全部基线）。
- **单元测试**：`StructuredComment` 不标记时的文字与今天逐字相同（按种类列表驱动）；枚举 case 块的分段组装与 `description(indent:prefix:)` 逐字相同（合成投影）。
- **开关关着**：现有快照测试与全量测试原样通过；渲染 A/B 逐字节一致（AGENTS.md 规定的大改后必跑项：每处注释的构造都换了写法）。
- **性能**：Ultra 上对 SwiftUI 生成打开全部注释选项的 interface，开关关着，改动前后各量一次 `time -l` 的 instructions retired。
- swift-semantic-string 的组件、分离与组合由它自己的测试覆盖。

### 没有询问就采用的假设

- 只标单版本打印（`SwiftDeclarationPrinter` 与 `SwiftInterfaceBuilder.printRoot`）；dump、diff、evolution 的注释不标。
- 装了 transformer 的注释整条记为一个 `text` 段，按占位符分段留给后续提案。
- 区域第一版不带属性：RuntimeViewer 第一版不用，需要的文字都在段里。
- 每条注释的文字只写在 `StructuredComment` 一处，关着时由各段拼接，所以改动会经过默认输出路径，靠渲染 A/B 证明逐字节不变；只有枚举逐 case 块保留原实现、另写分段组装。
- 不加 CLI 选项：CLI 只输出文本，注释表没有落点。
- 实现等 swift-semantic-string 的组件在分支上可用后开始，开发期用本地兄弟依赖（`USING_LOCAL_DEPENDENCIES=1`）。

### 顺带发现

interface 路径从不使用 `SwiftDeclarationPrintConfiguration.memberAddressTransformer`：成员地址由 `AddressComment`（`SemanticComponents.swift:30`）输出，它没有 transformer 参数，`renderModelFields` 建渲染配置时也没把这个闭包传下去。所以 RuntimeViewer 设置里的成员地址模板对 interface 不起作用；那个闭包的输入只有偏移，接上了也会丢掉 `(getter)` 这类标注。与本提案无关，另行处理。

thunk 读取器不解析两个分支各自直接加载一个类型的可用性条件 witness。`if #available(macOS 26, *) { return 1 } else { return "one" }` 这样的 `some` 结果，编译器（Swift 6.3 与 6.4，`-O` 与 `-Onone` 都一样）把 thunk 编成一次 `__isPlatformVersionAtLeast` 调用加一条 `csel`，在 `$sSiN` 与 `$sSSN` 两个地址之间选，没有分支；读取器只认分支，这个 witness 就打印成 `typealias Body = accessor function at …`，也不出 SE-0360 那条注释。两个分支都要调用取 metadata 的函数时（`[1]` 与 `["one": 1]`）thunk 有分支，读得出来。与本提案无关，另行处理。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-10-31 | Created as Draft | RuntimeViewer 要在 SourceEditor 面板把注释画成标签，字段偏移树与枚举布局可折叠；用户在 RuntimeViewer 会话里定了由生成器输出注释的结构、RuntimeViewer 不解析注释文本。RuntimeViewer 会话把本仓库这一份转了过来，连同三方共用的约定草案（载体在 swift-semantic-string，ObjC 一侧由 MachOObjCSection 做）。只起草，用户批准之前不写实现。 |
| 2026-10-31 | 开关命名 `marksCommentStructure`，与 MachOObjCSection 同名 | 与 `marksOptionalContent`、`marksNestedDefinitions` 用同一个动词。ObjC 一侧放在 `ObjCInterfaceBuilder` 的构造参数上。 |
| 2026-10-31 | 契约按 RuntimeViewer 的修订：文本与每个字节的语义类型、identifier 相同，span 边界可以不同 | 冻结时一个原子一个 span，相邻原子从不合并（swift-semantic-string 的 `FrozenSemanticString+Freezing.swift:25`），拆段必然多出 span。已请 swift-semantic-string 在能便宜做到时把同一原子的片并回一个 span，做到了测试就按完全相等断言。 |
| 2026-10-31 | `spareBits`、`deletedMethodSlot`、`ambiguousAttribution` 不进对外清单；补上 `typeLayoutElement`、`conditionalWitness`、`conditionalWitnessBranch`、`strippedSymbolicRequirement` | 前三种 interface 路径不输出；后四种是实际输出里有结构、起点清单没列到的注释。 |
| 2026-10-31 | 区域第一版不带属性 | RuntimeViewer 第一版不用；名字、类型、偏移都已是段。 |
| 2026-10-31 | RuntimeViewer 确认照用本提案的种类清单与段的切法 | 它的画法：认不出的 kind 按 `note` 画；藏起 marker 与 separator（separator 里的空格留作间距）；treePrefix 画成透明，在 `├── ` 那格画展开三角；`fieldOffset` 与 `fieldLayoutNode` 区域的末尾就是折叠的终点；枚举 Header 的两个 value 按「序号」与「序号的十六进制」显示，不当 tag 值。`memberAddressTransformer` 在 interface 路径不生效与本提案无关，RuntimeViewer 这条线不依赖它。 |
| 2026-10-31 | 采用 swift-semantic-string 的 API 草图（`AnnotationRegion` / `AnnotationSegment` / `AnnotatedAtom`）；种类改为扩展 `AnnotationRegion.Kind`，不另建 `SwiftCommentKind` | 两个生产方与 RuntimeViewer 用同一个类型。ObjC 一侧也改为扩展它，两份清单互不重叠，共用的种类放进 swift-semantic-string。 |
| 2026-10-31 | 契约第 2 条恢复为完全相等 | 拆开的片都在 `AnnotatedAtom` 里，分离时并回原来的一个 span。RuntimeViewer 放宽后的条件留作底线。 |
| 2026-10-31 | 请 swift-semantic-string 裁掉区域首尾的空白原子；它提议的模板代入函数第一版不用 | 前者让字段偏移树不必重排原子，标记模式下换行字节的可见性标记也就不变。后者要先解决「打印器怎么知道闭包来自哪个库自带模板」，留给后续提案。 |
| 2026-10-31 | swift-semantic-string 接受裁剪，确认组合、闭包输出成段、空段静默丢弃三点；`bodyAfterNestedDefinitions` 的判断改为认 `BreakLine` 原子 | 它的草稿已同步更新（仍待它的用户批准）。判断加上类型条件后，开标记时不再依赖「枚举块不会是 body 最后一项」这条前提；不开标记时行为不变。 |
| 2026-10-31 | 落地步骤拆成五步，第 1 步不依赖 swift-semantic-string | 它的组件还只是草图，要等它的用户批准后才实现。第 1 步（注释文字的单一来源）只动默认输出的构造方式，能单独构建与验证，先做；第 2 步起等它的组件在分支上可用。 |
| 2026-10-31 | 用户批准，开始实现 | 状态改为 Accepted。 |
| 2026-10-31 | In Progress；第 1 步落地，与原方案有四处出入 | 一，第 1 步不建种类的过渡类型：一个区域的种类未必只属于一行注释（字段偏移的根区域包着整棵树，枚举 case 的区域包着标题行与说明块），所以种类在第 3 步加区域时由调用点给出，`StructuredComment` 只记段。二，关着时每条注释多建一个段数组，没有做成「关着直接拼字符串」；开销留给第 5 步的性能对比，量出来不可忽略再改。三，返回字符串的现有接口都保留原签名，改为由段拼出：公开的 `ConditionalWitnessComment.lines`，package 级的 `PrivateDeclarationSourceFileComments.line` / `lines` 与 `conditionalWitnessCommentLines`（dump 与测试在用）；打印器改用新增的结构化形式。四，续行的注释符号写成两个相邻的 marker 段（`// ` 与对齐用的空格），说明性注释开头的空格同样归 marker；第 3 步标记时把相邻的同角色段并成一段，表里仍是一个 `//   `。另外两个新套件 `StructuredCommentTests`、`CommentConstructionScanTests` 进了 CI 的筛选清单，AGENTS.md 的打印器一节加了一行规则。 |
| 2026-10-31 | 第 2 步：开发期依赖 swift-semantic-string 的 `next` 分支，只换这一个依赖 | 它的组件已落进 `next`（`2698750`），还没发版。不用 `USING_LOCAL_DEPENDENCIES=1`：那会把 MachOKit、MachOObjCSection 等兄弟库也一起换成它们 `next` 上未发版的内容，测试与 A/B 就不再只差本提案的改动。`Package.swift` 里 `Semantic` 的远端要求暂时写成 `branch: "next"`，落地前改回它发版后的版本号；解析结果只有这一项与基线不同。 |
| 2026-10-31 | 第 3、4 步落地，合成一个提交；与原方案有四处出入 | 第 3 步没有自己的测试，而且它让 `StructuredComment` 自己的文件构造 `.comment` 原子（`AnnotatedAtom(type: .comment, …)`），源码扫描测试要同时放行这些文件，单独提交的话中间那个提交的测试是红的。一，契约第 4 条后半（与 `marksNestedDefinitions` 组合）放进 `NestedDefinitionRegionContractTests` 新增的一个变体，并比较分离出的注释表，不在新套件里重复它切区域、去缩进的那套比较；新套件 `CommentStructureContractTests` 管第 2、3 条与第 4 条前半，另加整个 interface 的 `printRoot`（含文件头）。二，条件 witness 没有现成的现场编译 fixture（唯一的 SE-0360 测试读宿主 cache 里的 SwiftUI），新加套件 `ConditionalWitnessCommentStructureTests` 现场编一个小 dylib；两个分支返回 `[1]` 与 `["one": 1]`，原因见「顺带发现」。三，判漏标的覆盖检查只看非空白的注释字节，与区域首尾裁掉空白的规则一致。四，整个 import `Semantic` 的测试文件里，它的 `Error` 组件会遮住 `Swift.Error`，这些文件改为按名字只 import 用到的类型。三个新套件进了 CI 的筛选清单；条件 witness 那个 fixture 用 Xcode 26.6（Swift 6.3）编出来同样读得出两个分支。 |
