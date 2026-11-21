# Draft - 长类型拆行：放不下的类型按括号结构拆成多行

- **状态**: Accepted
- **作者**: JH
- **创建日期**: 2026-11-21
- **最后更新**: 2026-11-21
- **所属愿景**: 无
- **关联提案**: 无
- **实现分支 / PR**: `feature/multiline-type-formatting`
- **配套文档**: 待定 —— 落地时登记实现说明 / 使用指南的链接
- **网页版**: 同目录同名的 `.html`

## 摘要

新增一个公开的格式化值类型 `MultilineTypeFormatting`（`SwiftDeclarationRendering`），把已经打印好的 Swift 源码（`SemanticString`）里放不下的类型按括号拆成多行：一个类型一行放得下就不动；放不下时，整个类型照 [TypeAliasFormatter](https://github.com/OpenSwiftUIProject/TypeAliasFormatter) 的结构规则拆开——有两个及以上参数的泛型参数列表每个参数一行，单参数泛型、元组、函数类型与声明的参数列表、`[…]` 集合语法糖只在里面有拆开的部分时才拆。它只插入换行和缩进，文字、semantic type、identifier 和各种 region 原样保留。`swift-section dump` / `interface` 新增 `--multiline-types` 与 `--maximum-line-width`，`InterfaceRequest` / `DumpRequest` 新增同名字段；默认关闭，关闭时输出逐字节不变。RuntimeViewer 在拿到一个定义的完整打印之后调用一次即可，打印器本身一行不改。

## 动机

SwiftUI 视图的 `Body`、modifier 链、`TupleView` 之类的类型在二进制里是完整展开的泛型树，打印出来是一整行。RuntimeViewer 里打开 Preferences.app 的 `SettingsApp.SettingsNavigationSplitView`，`extension … : SwiftUI.View` 里的 `typealias Body = SwiftUI.ModifiedContent<SwiftUI.ModifiedContent<…` 一行有几千个字符，编辑器软换行成几十行，`<` 和 `>` 挤在一起，看不出哪个参数属于哪一层。dump 与 CLI 的 interface 输出同样如此，同类问题也出现在任何带长泛型的成员签名、`where` 子句和关联类型 witness 上。

这类类型只能靠拆行看懂层级。社区里已有专门的工具（TypeAliasFormatter：粘贴一个 typealias，按括号结构排版），说明这个需求是真实存在的；但它工作在纯文本上，复制出来、粘进去、再对照回来，丢掉了 RuntimeViewer 的语法着色、跳转链接与各种 region。本提案把同样的排版放进库里，直接作用在打印结果上。

## 前期调研

- **类型由两套打印器拼成 `SemanticString`。** interface 走本仓库的 `SwiftPrinting`（`TypeNodePrinter` 等，`Sources/Output/SwiftPrinting/NodePrinter/TypeNodePrinter.swift:8`），泛型参数列表由 `printBoundGenericNoSugar` 写出（`Sources/Output/SwiftPrinting/NodePrintables/BoundGenericNodePrintable.swift:66`：`printChildren(typeList, prefix: "<", suffix: ">", separator: ", ")`）；dump 走上游 swift-demangling 的 `NodePrinter`，经 `DemangleResolver.options`（`Sources/Output/SwiftDeclarationRendering/DemangleResolver.swift:31`）。两边写括号和逗号都用不带 context 的 `write(_:)`，`SemanticString` 把它记成 `.standard` 类型的独立 atom（`swift-semantic-string/Sources/Semantic/SemanticString+Conformances.swift:32`），而类型名、模块名、关键字、声明名、注释各有自己的 semantic type。
- **`typealias Body` 这一行是怎么拼出来的。** `renderMergedAssociatedTypeRecords`（`Sources/Output/SwiftPrinting/SwiftDeclarationPrinter+Headers.swift:305`）依次写 `Indent`、`typealias`、名字、`=`，再把 `resolver.resolve(for:)` 打印出的整个类型接在同一行（`:318`–`:326`）。成员签名里的类型则由 `FunctionNodePrinter` / `VariableNodePrinter` 在打印整条声明时递归写出，没有单独的「一个类型」的 `SemanticString`。
- **region 编码在 atom 的 `identifier` 上。** `AnnotationRegion`、`VisibilityRegion`、`DefinitionRegion` 都不占文字，而是把标记写进每个 atom 的 `identifier`，冻结后再分离出来（`swift-semantic-string/Sources/Semantic/AnnotationRegions/AnnotationRegion.swift` 的类型注释）；同一种 region 中间夹进一个不带编码的 atom，会被读成两个。所以插入的换行与缩进 atom 必须沿用相邻 atom 的 `identifier`。
- **嵌套定义的契约只允许缩进随层级变化。** `marksNestedDefinitions` 承诺：父定义打印里深度为 `d` 的子定义，取出后 `removingIndentation(levels: d + 1)`，等于子定义单独打印的结果（`Sources/Output/SwiftPrinting/SwiftDeclarationPrintConfiguration.swift:198`–`:236`）。`removingIndentation` 按字节从每个非空行开头删 `levels * 4` 个空格（`swift-semantic-string/Sources/Semantic/Frozen/FrozenSemanticString+Indentation.swift:28`–`:61`）。因此拆不拆一行，不能取决于这一行缩进了多深——否则同一个子定义在父定义里和单独打印时会拆得不一样。
- **运算符名在 dump 里是带 `<` 的 `.standard` atom。** 上游 `NodePrinter` 把 `infixOperator` 写成 `"\(name) infix"`（`swift-demangling/Sources/Demangling/Node/Printer/NodePrinter.swift:499`），`static func < infix(…)` 里的 `<` 和泛型括号同为 `.standard`。扫描器必须容忍括号不配对的行，而不是猜。
- **宿主是怎么拿到一个定义的。** RuntimeViewer 把一个运行时对象的所有打印（`printTypeDefinition`、`printExtensionDefinition`、`printProtocolDefinition`）拼进一个 `newInterfaceString`，再缓存成 `RuntimeObjectInterface`（RuntimeViewer `RuntimeViewerCore/Sources/RuntimeViewerCore/Core/RuntimeSwiftSection.swift:284`–`:364`），且它已经依赖 `SwiftDeclarationRendering` product（同仓库 `RuntimeViewerCore/Package.swift:178`）。SwiftSectionKit 里 interface 在 `InterfaceRequest.run` 拿到 `builder.printRoot()` 的整份结果（`Sources/Commands/SwiftSectionKit/Swift/InterfaceRequest.swift:225`），dump 在 `DumpSession.dump` 一次处理一个顶层声明（`Sources/Commands/SwiftSectionKit/Swift/DumpRequest.swift:513`–`:530`）。三处都是「打印完、交出去之前」的唯一出口。
- **TypeAliasFormatter 的规则。** 它的 `Renderer`（`Packages/TypeAliasFormatterCore/Sources/TypeAliasFormatterCore/TypeAliasFormatter.swift`）：`<` 有两个及以上参数时一律展开、每个参数一行；只有一个参数时保持一行，除非某个参数已是多行；`(` 与 `[` 只在某个元素是多行时展开；`->` 不算括号；反引号里的内容不解析；另有 `expandSingleArguments` 选项把单参数泛型也展开。它不看行宽，任何输入都整个排版。该仓库没有 license 文件，本提案只借用规则，不复制代码。
- **用户选定的规则。** 本次澄清提问里比较过三种：纯按行宽逐层决定、完全照 TypeAliasFormatter、两者结合。选定两者结合：放得下的类型不动（`Swift.Result<Swift.Int, Swift.Error>` 这类短类型不会在每个签名里被拆成四行），放不下的类型整个按结构规则拆（同一个类型无论嵌在第几层，拆出来的形状都一样）。适用于所有出现类型的位置，元组与函数类型的括号一起处理。

## 提议方案

在 `SwiftDeclarationRendering` 里加一个纯函数式的格式化值类型：

```swift
let formatting = MultilineTypeFormatting(maximumLineWidth: 100)
let formatted = formatting.format(printedDefinition)
```

它逐行处理输入，规则如下：

1. **一行的内容宽度不超过 `maximumLineWidth` 就原样保留。** 内容宽度是这一行的字符数减去行首缩进——缩进不计入，所以拆不拆与嵌套深度无关，嵌套定义的契约自然成立。
2. **超宽的行解析成括号树。** 只在 `.standard` 类型的 atom 里找括号；类型名、模块名、关键字、声明名、注释等其它 atom 整体当作文字。字符串字面量、反引号标识符、`//` 之后的内容是文字；`->` 不是括号。括号不配对（例如 dump 里的运算符声明）就整行原样保留。
3. **找出放不下的类型。** 不在其它泛型参数列表里面的泛型参数列表，算作一个类型的最外层；它的 `>` 落在第 `maximumLineWidth` 列之后，这个类型就算放不下。只有泛型参数列表会触发拆行；行之所以超宽是因为别的东西（一长串参数、行尾注释），这一行不动。
4. **放不下的类型按结构规则拆。** 在这个类型内部：有两个及以上参数的泛型参数列表一律每个参数一行；单参数的泛型参数列表、元组、函数类型的参数列表、`[…]` 集合语法糖，只在某个元素已是多行时才拆。
5. **外层括号跟着拆。** 类型之外的括号——函数声明的参数列表、enum case 的 payload、元组、泛型参数子句（紧跟在声明名后面的 `<…>`）、attribute 的参数——只在某个元素已是多行时才拆，否则保持一行。泛型参数子句因此不会仅仅因为有两个参数就被拆开。
6. **拆开的列表这样排。** 开括号留在原行末尾；每个参数另起一行，缩进为这一行的行首缩进加 4 个空格乘以嵌套层数；参数之间的 `, ` 变成 `,`；闭括号另起一行，缩进回到上一层。

截图里那个 `Body` 的开头一段，按默认宽度格式化后是这样：

```swift
extension SettingsApp.SettingsNavigationSplitView: SwiftUI.View {
    typealias Body = SwiftUI.ModifiedContent<
        SwiftUI.ModifiedContent<
            SwiftUI.SceneBridgeReader<
                SwiftUI.SubscriptionView<
                    Combine.PassthroughSubject<
                        Any,
                        Swift.Never
                    >,
                    SwiftUI.NavigationSplitView<
                        SwiftUI.ModifiedContent<
                            SettingsApp.SettingsSidebarList,
                            SwiftUI.ToolbarRemovingModifier
                        >,
                        SettingsApp.SettingsSecondaryColumn
                    >
                >
            >,
            SwiftUI._EnvironmentKeyWritingModifier<Swift.Bool>
        >,
        SwiftUI.OnTestViewModifier
    >
}
```

同一个文件里放得下的类型不受影响：

```swift
var result: Swift.Result<Swift.Int, Swift.Error>
var selection: SwiftUI.Binding<Swift.Set<Swift.String>>
```

函数签名里有一个类型放不下时，参数列表随之拆开，其余参数保持一行：

```swift
func update(
    model: Swift.Result<Swift.Int, Swift.Error>,
    content: SwiftUI.ModifiedContent<
        SwiftUI.TupleView<…>,
        SwiftUI._EnvironmentKeyWritingModifier<Swift.Bool>
    >
) -> Swift.Bool
```

接入点只有调用方的出口：`InterfaceRequest` 与 `DumpRequest` 各加一个 `multilineTypeFormatting: MultilineTypeFormatting?` 字段（默认 `nil`），在交出产物前调用一次；CLI 的 `dump` 与 `interface` 加 `--multiline-types` 与 `--maximum-line-width <columns>`。RuntimeViewer 在 `RuntimeSwiftSection` 缓存 `RuntimeObjectInterface` 之前调用一次（下游后续改动，不在本提案的实现范围内）。打印器、`SwiftDeclarationPrintConfiguration` 与 `DeclarationRenderConfiguration` 都不改。

### 非目标

- **不改打印器。** `SwiftPrinting`、`SwiftDump`、上游 swift-demangling 与 swift-semantic-string 一行不动；默认关闭时所有输出逐字节不变，fixture baseline 与渲染 A/B 不受影响。
- **diff、evolution、snapshot 不接。** diff 与 evolution 的输出按行标记增删，拆行会让一个声明的标记散到多行；snapshot 是 JSON。这三个请求不加字段。
- **ObjC 输出不接。** `swift-section objc …` 打印的是 Objective-C 头文件，没有本提案要拆的 Swift 泛型。
- **不单独拆长参数列表。** 一个函数声明有十个短参数而超宽，本提案不拆它；参数列表只在某个参数的类型被拆开时随之拆开。按行宽拆参数列表是另一个功能。
- **不做 TypeAliasFormatter 的其它能力。** 单参数泛型也展开的 `expandSingleArguments`、2 / 8 空格或 Tab 缩进、类型树的图形视图都不做；`MultilineTypeFormatting` 是 struct，以后要加选项时加带默认值的属性即可。
- **不解决 SwiftUI modifier 链缩进很深的问题。** `ModifiedContent<ModifiedContent<…>, M>` 是向左嵌套的，二十多层 modifier 拆开后第一个参数会缩进二十多层。把这种链压平成一层需要按语义改写类型，不属于排版。
- **RuntimeViewer 的设置界面与接入不在本提案里实现。** 本提案只交付库与 CLI；RuntimeViewer 的开关、调用与缓存失效由它自己的改动完成。

## 改动地图

| 文件 / 类型 | 动作 | 改什么 | 为什么 | 步骤 |
|---|---|---|---|---|
| `Sources/Output/SwiftDeclarationRendering/MultilineTypeFormatting.swift` · `MultilineTypeFormatting` | 新增 | 公开 struct：`maximumLineWidth`、`init(maximumLineWidth:)`、`format(_:)`；`format` 逐行调用下面三块 | dump 与 interface 共用的位置，RuntimeViewer 已依赖这个 product | 1 |
| `Sources/Output/SwiftDeclarationRendering/MultilineTypeFormatting+Lines.swift` · `MultilineTypeFormatting.Line`（internal） | 新增 | 把 atom 序列按 `\n` 切成行（切开的 atom 保留 type 与 identifier）、算行首缩进与内容宽度、把处理后的行拼回去 | 规则 1：宽度不超的行不解析，直接复制 | 1 |
| `Sources/Output/SwiftDeclarationRendering/MultilineTypeFormatting+BracketTree.swift` · `MultilineTypeFormatting.BracketTree`（internal） | 新增 | 把一行解析成括号树：只扫 `.standard` atom，字符串、反引号、`//`、`->` 当文字；括号种类分为泛型参数列表、泛型参数子句、圆括号、方括号；不配对返回 `nil` | 规则 2 | 2 |
| `Sources/Output/SwiftDeclarationRendering/MultilineTypeFormatting+Layout.swift` · `MultilineTypeFormatting.Layout`（internal） | 新增 | 判定放不下的类型、自下而上决定哪些列表拆开、按规则 6 生成 atom（插入的换行与缩进沿用相邻括号或逗号 atom 的 identifier） | 规则 3–6 | 3 |
| `Tests/SwiftDeclarationRenderingTests/MultilineTypeFormattingTests.swift` | 新增 | 行切分、解析、排版的单元测试，输入用手工拼的 `SemanticString`，形状与两套打印器的输出一致 | 每步的行为清单 | 1–3 |
| `Tests/SwiftDeclarationRenderingTests/MultilineTypeFormattingPreservationTests.swift` | 新增 | 保持性测试：semantic type 与 identifier 不变、去掉插入的换行能还原原文、幂等、与缩进可交换、region 读回不变 | 规则 6 的「只加换行和缩进」承诺 | 4 |
| `Tests/SwiftInterfaceTests/MultilineTypeFormattingNestedDefinitionTests.swift` | 新增 | 打开 `marksNestedDefinitions` 打印 SymbolTestsCore 里带嵌套类型的定义，格式化父定义后取出的子定义等于子定义单独打印后格式化 | 嵌套定义契约在格式化后仍成立 | 4 |
| `Sources/Commands/SwiftSectionKit/Swift/InterfaceRequest.swift` · `InterfaceRequest` | 修改 | 新字段 `multilineTypeFormatting`（init 参数默认 `nil`），`run` 里 `printRoot()` 之后、写文件或交给 output 之前调用 | interface 的唯一出口 | 5 |
| `Sources/Commands/SwiftSectionKit/Swift/DumpRequest.swift` · `DumpRequest`、`DumpSession` | 修改 | 新字段 `multilineTypeFormatting`；`DumpSession.dump` 拿到 `dumpedDeclaration` 后调用 | dump 的唯一出口，一次一个顶层声明 | 5 |
| `Tests/SwiftSectionKitTests/MultilineTypeFormattingRequestTests.swift` | 新增 | 两个请求打开与关闭字段时的输出 | 接入正确、关闭时不变 | 5 |
| `Sources/Executables/swift-section/Commands/InterfaceCommand.swift`、`DumpCommand.swift` | 修改 | `--multiline-types` flag、`--maximum-line-width <columns>` option；`validate()` 拒绝单独给宽度和非正数宽度；`makeRequest()` 映射 | CLI 是 SwiftSectionKit 的包装 | 6 |
| `Tests/SwiftSectionCommandTests/MultilineTypesFlagTests.swift` | 新增 | flag 映射到请求、校验错误的退出码 64 | CLI 两侧都要有测试 | 6 |
| `AgentPlugins/swift-section/skills/swift-section-cli/SKILL.md` | 修改 | 写明两个新 flag 与默认宽度 | CLI 改动要同批更新这份 skill | 6 |
| `Documentations/SwiftSectionKit.md`、`Documentations/Internal/Modules/SwiftSectionKit.md` | 修改 | 两个请求的新字段 | 调用方指南与模块参考 | 7 |
| `CLAUDE.md` | 修改 | SwiftDeclarationRendering 一条补一句它还提供 `MultilineTypeFormatting` | 模块清单与代码同步 | 7 |
| `Documentations/Internal/ProjectEvolutionLog.md`、`Documentations/Glossary.md`、`Documentations/README.md`、`Documentations/Evolutions/README.md` | 修改 | 账本一节、术语 multiline type formatting / long type、索引 | 文档纪律 | 7 |

## 架构图

改了什么：

```text
SwiftDeclarationRendering
+ ├── MultilineTypeFormatting.swift              public struct, format(_:)
+ ├── MultilineTypeFormatting+Lines.swift        split atoms into lines, width gate
+ ├── MultilineTypeFormatting+BracketTree.swift  parse one line into a bracket tree
+ └── MultilineTypeFormatting+Layout.swift       decide breaks, emit atoms
SwiftSectionKit
~ ├── Swift/InterfaceRequest.swift               + multilineTypeFormatting, applied after printRoot()
~ └── Swift/DumpRequest.swift                    + multilineTypeFormatting, applied per declaration in DumpSession
swift-section
~ ├── Commands/InterfaceCommand.swift            + --multiline-types, --maximum-line-width
~ └── Commands/DumpCommand.swift                 + --multiline-types, --maximum-line-width
SwiftPrinting, SwiftDump, swift-demangling, swift-semantic-string    (unchanged)
```

数据流：

```text
SwiftDeclarationPrinter / Dumpable          (unchanged: one line per declaration)
        │ SemanticString
        ▼
+ MultilineTypeFormatting.format(_:)        (only when the caller opts in)
        │ SemanticString: same text, types, identifiers, regions; long types broken
        ▼
InterfaceRequest / DumpSession  ──►  SwiftSectionOutput / file
RuntimeSwiftSection (RuntimeViewer, follow-up)  ──►  RuntimeObjectInterface cache
```

`format(_:)` 内部：

```text
format(source)
└── for each line (atoms split at "\n" keep type + identifier)
    ├── content width (minus leading indentation) <= maximumLineWidth ──► copy unchanged
    └── BracketTree(line)          (.standard atoms only; strings, backticks, "//", "->" are text)
        ├── nil (unbalanced) ──► copy unchanged
        └── Layout
            ├── outermost generic argument list whose ">" lies past the width ──► long type
            ├── inside a long type: generic argument list with >= 2 arguments ──► break
            ├── any list with a multi-line element ──► break        (bottom-up)
            └── emit "<" "\n" indent(L + 4k) element "," "\n" … "\n" indent(L + 4(k - 1)) ">"
```

## 详细设计

### 公开 API

```swift
/// Lays the long types of printed Swift source out over several lines.
///
/// A type that runs past `maximumLineWidth` is broken at its brackets: every
/// generic argument list with two or more arguments puts each argument on a
/// line of its own, and a single-argument generic list, a tuple, a parameter
/// list or collection sugar breaks only when one of its elements spans
/// several lines. A type that fits, and every line that fits, stays as
/// printed.
///
/// Formatting only adds line breaks and indentation, and drops the space of
/// each `, ` between broken elements: the text otherwise, every component's
/// semantic type and identifier, and so every visibility, definition and
/// annotation region, stay as they were.
public struct MultilineTypeFormatting: Hashable, Sendable {
    /// The widest a line's content may be, in characters. A line's own
    /// indentation does not count, so a declaration breaks the same way at
    /// any nesting depth.
    public var maximumLineWidth: Int

    /// - Precondition: `maximumLineWidth > 0`.
    public init(maximumLineWidth: Int = 100)

    /// `source` with its long types laid out over several lines.
    public func format(_ source: SemanticString) -> SemanticString
}
```

`SwiftSectionKit`：

```swift
extension InterfaceRequest {
    /// Lays long types out over several lines; `nil` prints every type on one line.
    public var multilineTypeFormatting: MultilineTypeFormatting? { get set }
}

extension DumpRequest {
    public var multilineTypeFormatting: MultilineTypeFormatting? { get set }
}
```

两个请求的 memberwise `init` 各加一个参数 `multilineTypeFormatting: MultilineTypeFormatting? = nil`，放在 `commentTransformers` 之前，与现有的带默认值参数同列。

CLI（`dump` 与 `interface` 相同）：

```text
--multiline-types              Break a type that runs past the line width over several lines, at its brackets.
--maximum-line-width <columns> The widest a line may be, not counting its indentation, before
                               --multiline-types breaks its types. (default: 100)
```

`validate()`：给了 `--maximum-line-width` 却没给 `--multiline-types`，或宽度不是正数，抛 `ValidationError`（退出码 64）。

### 行与宽度

- `format` 先把 `source.components` 按 `\n` 切成行。一个 atom 内含 `\n` 时在 `\n` 处切开，各段保留原 atom 的 `type` 与 `identifier`；`\n` 本身单独成段，原样输出。
- 行首缩进是这一行开头连续空格的个数 `L`（跨 atom 计）。内容宽度是这一行的 `Character` 数减去 `L`。
- 内容宽度不超过 `maximumLineWidth` 的行，其 atom 原样复制，不做任何解析。绝大多数行走这条路，`format` 的开销主要是一次按行扫描。
- 行之间互不影响：括号跨行的输入（例如已经格式化过的输出）里，每一行单独看都不配对，因此原样保留——这正是 `format` 幂等的原因。

### 括号树

```swift
extension MultilineTypeFormatting {
    enum BracketKind {
        case genericArguments       // "<" after anything but a declaration name
        case genericParameters      // "<" right after a declaration name
        case parentheses            // "(": tuples, function types, parameter lists, attribute arguments
        case squareBrackets         // "[": array and dictionary sugar
    }

    indirect enum BracketTreeNode {
        /// A run of a line's characters that is not a bracket, located by atom index and range.
        case text(AtomRun)
        /// A bracketed list: the opening and closing brackets' locations and the elements between the commas.
        case list(kind: BracketKind, opening: AtomPosition, closing: AtomPosition, separators: [AtomPosition], elements: [[BracketTreeNode]])
    }
}
```

- 只有 `.standard` atom 参与扫描；其它 semantic type 的 atom 整体是一个 `text`。这样类型名、声明名（包括 interface 里的运算符名）、注释里的括号都不会被当成结构。
- 在 `.standard` atom 里：`"` 开始一个字符串字面量，到未转义的 `"` 结束；反引号同理；`//` 之后到行末都是文字；`-` 紧跟 `>` 是箭头，不关闭任何列表；`<`、`(`、`[` 开列表，`>`、`)`、`]` 必须关闭同种列表；深度大于 0 时的 `,` 分隔元素。
- `<` 前面（跳过空白）的 atom 的 semantic type 是 `.type(_, .declaration)`、`.function(.declaration)` 或 `.member(.declaration)` 时，这个列表是 `genericParameters`；否则是 `genericArguments`。
- 关闭括号与种类不符、或行末仍有未关闭的列表，返回 `nil`，整行原样保留。dump 里的 `static func < infix(…)` 就走这条路。

### 排版

- **放不下的类型。** 只看「不在任何 `genericArguments` 里面」的 `genericArguments` 列表：它的闭括号 `>` 的内容列号（相对行首缩进，从 1 数）大于 `maximumLineWidth`，就把它标为长类型的根。列号按这一行原样打印时的位置算。
- **决定拆哪些列表**，自下而上：
  - 长类型根及其内部的 `genericArguments`，元素数不少于 2 时拆。
  - 任何列表，有元素是多行时拆（元素多行 = 元素里有被拆的列表）。
  - 其余不拆。长类型根之外的 `genericArguments` 内部不会有被拆的列表，因此整体保持一行。
- **生成 atom。** 对每个要拆的列表，嵌套层数 `k` 是它自身加上包住它的被拆列表的个数：
  - 开括号 atom 原样输出，后面插入 `\n` 与 `L + 4k` 个空格的缩进 atom；
  - 每个元素去掉首尾空白后输出；
  - 元素之间的分隔：原来的 `, `（或 `,`）atom 换成只含 `,` 的 atom（type 与 identifier 不变），后面插入 `\n` 与缩进；
  - 闭括号前插入 `\n` 与 `L + 4(k − 1)` 个空格；
  - 插入的 atom 都是 `.standard`，`identifier` 取它前面那个括号或逗号 atom 的 `identifier`。括号若和别的字符在同一个 atom 里，就在括号处切开，各段保留原 type 与 identifier。
- 一个列表为空（`()`）时从不拆。

### 保持性

以下性质是公开承诺，各有测试：

1. 内容宽度不超的行逐 atom 不变。
2. 去掉插入的换行与缩进、把被改的 `,` 还原成 `, `，得到与输入相同的文字。
3. 每个原有字符所在 atom 的 semantic type 与 identifier 不变；冻结后各种 region 分离出来与格式化前相同（位置随文字平移）。
4. 幂等：`format(format(x)) == format(x)`。
5. 与缩进可交换：把输入每个非空行多缩进 4 个空格再格式化，等于先格式化再多缩进 4 个空格。由此，格式化后的父定义里取出的嵌套定义，等于嵌套定义单独打印再格式化。

## 替代方案考量

- **纯按行宽、逐层决定（Wadler / Oppen 式的 group）。** 每个括号列表一行放得下就不拆。否：同一个类型嵌在不同深度时排版不同；短的多参数泛型时拆时不拆，读者没法靠形状认出结构。用户在澄清提问里否掉了。
- **完全照 TypeAliasFormatter，不看行宽。** 否：适用于所有类型位置后，每个 `Swift.Result<Swift.Int, Swift.Error>`、`Swift.Dictionary<…>` 都会被拆成多行，整份 interface 变长数倍。用户在澄清提问里否掉了。
- **在打印器里拆：打印泛型参数时直接写换行或「可断点」标记。** 否：类型来自两套打印器（本仓库的 `SwiftPrinting` 与上游 swift-demangling 的 `NodePrinter`），要改两处并给上游的 `NodePrinterTarget` 加要求——这个协议刻意不给默认实现，加一条要求就要上游发版、所有 target 都改；打印器按节点身份 memoize 的片段会带上依赖列号的排版决定；嵌套定义契约要求的「只有缩进随层级变化」也得在递归里处处维护。
- **做成 `SwiftDeclarationPrintConfiguration` 的选项，由每个公开打印入口在返回前格式化。** 否：公开入口有二十来个且互相调用（嵌套类型会再次进入 `printTypeDefinition`），要么重复格式化，要么把每个入口拆成「公开入口 + 内部实现」；dump 的 `DeclarationRenderConfiguration` 还得另接一遍。三个真正的调用方（两个请求、RuntimeViewer）都只有一个出口，在出口调用一次更简单。
- **在纯文本上格式化（照搬 TypeAliasFormatter 的做法）。** 否：会丢掉 semantic type、identifier 与 region，RuntimeViewer 的着色、跳转与嵌套定义拆分都依赖它们。
- **扫描所有 atom 的所有字符。** 否：interface 里运算符名、私有类型名 `(Visitor in $…)` 等 atom 也含括号；只扫 `.standard` atom，再对不配对的行放弃，误判面最小。

## 影响

### 源码兼容性（source compatibility）

纯新增。`MultilineTypeFormatting` 是新类型；`InterfaceRequest` 与 `DumpRequest` 的新字段和 init 参数都有默认值 `nil`，现有调用点不受影响；CLI 新增的两个参数不改变任何已有参数的含义与默认输出。

### ABI 兼容性（条件项）

不适用 —— 本库以 SPM 源码分发，使用方每次重新编译。

### 下游影响

- 本仓库：`SwiftDeclarationRendering` 加文件；`SwiftSectionKit` 与 `swift-section` 加字段与参数。打印器、索引、ABI 层不动。
- **RuntimeViewer**：要用这个功能，需要在设置里加一个开关（可附宽度），在 `RuntimeSwiftSection` 生成 `RuntimeObjectInterface` 之前（`RuntimeSwiftSection.swift:364`）调用 `format`，并在开关变化时清掉 `interfaceByObject` 缓存。它已依赖 `SwiftDeclarationRendering`，不必改依赖声明。这是 RuntimeViewer 自己的后续改动。
- MachOKitUI、SymbolViewer：不受影响。

### 文档与示例

- `AgentPlugins/swift-section/skills/swift-section-cli/SKILL.md`：两个新 flag。
- `Documentations/SwiftSectionKit.md`（调用方指南）与 `Documentations/Internal/Modules/SwiftSectionKit.md`：新字段。
- `CLAUDE.md` 的模块清单：SwiftDeclarationRendering 一条。
- 发版时 `Changelogs/<version>.md` 写一条。

## API 演进与废弃策略

- 不替代任何旧 API，没有废弃。
- 以后要加 TypeAliasFormatter 的「单参数泛型也展开」、其它缩进宽度等选项时，给 `MultilineTypeFormatting` 加带默认值的存储属性，现有调用点不变；不把它改成 enum。
- 不需要 semver major 跃迁。

## 落地步骤

1. **骨架：类型、行切分与宽度闸门** —— 改动地图第 1、2、5 行
   - 行为：`emptySourceIsUnchanged`
   - 行为：`linesWithinWidthAreUnchangedAtomForAtom`
   - 行为：`contentWidthIgnoresLeadingIndentation`
   - 行为：`atomsContainingLineBreaksAreSplitKeepingTypeAndIdentifier`
   - 行为：`nonPositiveWidthIsAPreconditionFailure`（exit test）
2. **括号树** —— 改动地图第 3、5 行
   - 行为：`genericArgumentListsNestInsideParenthesesAndBrackets`
   - 行为：`angleBracketAfterDeclarationNameIsGenericParameterClause`
   - 行为：`arrowIsNotAClosingBracket`
   - 行为：`bracketsInsideStringLiteralsAreText`
   - 行为：`bracketsInsideBackticksAreText`
   - 行为：`bracketsAfterLineCommentAreText`
   - 行为：`bracketsInNonStandardAtomsAreText`（类型名、声明名、注释 atom）
   - 行为：`unbalancedLineIsLeftUnchanged`
   - 行为：`operatorDeclarationFromDumpIsLeftUnchanged`（`static func < infix(…)`）
3. **排版与生成** —— 改动地图第 4、5 行
   - 行为：`multiArgumentGenericBreaksOneArgumentPerLine`
   - 行为：`singleArgumentGenericStaysInlineUnlessItsArgumentBreaks`
   - 行为：`tupleBreaksOnlyWhenAnElementBreaks`
   - 行为：`functionTypeParametersBreakOnlyWhenAParameterBreaks`
   - 行为：`collectionSugarBreaksOnlyWhenAnElementBreaks`
   - 行为：`typeThatFitsStaysOnOneLineInAnOverlongLine`
   - 行为：`overlongLineWithoutLongTypeIsUnchanged`（十个短参数、行尾长注释）
   - 行为：`declarationParameterListBreaksWhenAParameterTypeBreaks`
   - 行为：`genericParameterClauseDoesNotBreakForHavingTwoParameters`
   - 行为：`continuationLinesIndentFromTheLineIndentation`
   - 行为：`separatorLosesItsSpaceWhenBroken`
   - 行为：`swiftUIBodyIsLaidOutByStructure`（本提案「提议方案」一节的例子）
4. **保持性与嵌套定义契约** —— 改动地图第 6、7 行
   - 行为：`formattingKeepsSemanticTypesAndIdentifiers`
   - 行为：`removingInsertedBreaksRestoresTheOriginalText`
   - 行为：`formattingIsIdempotent`
   - 行为：`formattingCommutesWithIndentation`
   - 行为：`annotationAndVisibilityRegionsReadBackUnchanged`
   - 行为：`nestedDefinitionTakenOutOfFormattedParentEqualsFormattedChildPrint`
5. **SwiftSectionKit 接入** —— 改动地图第 8、9、10 行
   - 行为：`interfaceRequestFormatsLongTypesWhenAsked`
   - 行为：`dumpRequestFormatsEachDeclarationWhenAsked`
   - 行为：`requestsWithoutFormattingPrintAsBefore`
   - 行为：`interfaceWrittenToFileIsFormattedToo`
6. **CLI 与 agent 插件** —— 改动地图第 11、12、13 行
   - 行为：`multilineTypesFlagMapsOntoTheRequest`
   - 行为：`maximumLineWidthMapsOntoTheRequest`
   - 行为：`maximumLineWidthWithoutMultilineTypesIsAUsageError`
   - 行为：`nonPositiveMaximumLineWidthIsAUsageError`
   - 行为：插件 skill 里出现的每个 flag 都存在于对应子命令的 `--help`
7. **文档** —— 改动地图第 14、15、16 行
   - 行为：文档索引、账本、术语表、模块清单与代码一致

验证：每步 `swift build` 通过、本步新测试通过；收尾跑 `swift test --skip IntegrationTests` 全量。打印器不改、默认关闭，渲染 A/B 不适用（照 `SystemFrameworkRenderingVerification.md` 的判据，它针对改动打印、索引或读取器的重构），但会对一份真实 SwiftUI interface 打开格式化，记录 `format` 的耗时与输出行数，作为性能与效果的留档。

**收尾时必须判断两件事**（判断结果写进决策日志，不允许沉默跳过）：

- **要不要配套专题文章** —— 规则 1–6 与保持性承诺若在实现中出现代码看不出来的取舍（例如列号的算法、region 编码在切分 atom 时的处理），写一篇 `Documentations/Internal/MultilineTypeFormatting.md` 实现说明，登记到头部的「配套文档」。
- **有没有引入新术语** —— 预计引入 multiline type formatting、long type（放不下的类型）两条，登记进 `Documentations/Glossary.md`。

## 决策日志

| 日期 | 变更 | 说明 |
|------|------|------|
| 2026-11-21 | Created as Draft | RuntimeViewer 里 SwiftUI 视图的 `typealias Body` 印成一行几千个字符，看不出泛型的层级，需要像展开括号一样按层拆行。 |
| 2026-11-21 | 规则选定 | 澄清提问后用户选定：一行放得下的类型不动，放不下的类型整个按 TypeAliasFormatter 的结构规则拆；适用于所有出现类型的位置；元组与函数类型的括号同样处理。纯按行宽和完全照 TypeAliasFormatter 两种都被否掉，理由见「替代方案考量」。 |
| 2026-11-21 | 接入方式 | 做成调用方在出口调用一次的纯格式化函数，不改打印器、不加打印配置项：两套打印器、互相调用的公开入口与嵌套定义契约都让「在打印器里拆」代价过高。 |
| 2026-11-21 | 宽度不计缩进 | 内容宽度减去行首缩进，使同一个声明在任何嵌套深度都拆得一样，`marksNestedDefinitions` 的契约不受影响。 |
| 2026-11-21 | Accepted | 用户批准，开始实现。功能分支 `feature/multiline-type-formatting`，从 `next` 切出。 |
