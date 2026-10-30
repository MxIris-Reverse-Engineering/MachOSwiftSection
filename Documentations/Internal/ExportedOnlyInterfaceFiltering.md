# Interface 只打印导出声明（`--exported-only`）的实现说明

> 配套提案见 [0016](../Evolutions/0016-exported-only-interface.md)。
> 本文记录**实际落地的实现**、与提案的差异，以及当前覆盖范围与已知降级。面向维护者。
> 它是 [InterfaceHeaderAndExportStatusAnnotations.md](InterfaceHeaderAndExportStatusAnnotations.md)（提案 0008，`// not exported` 标注）的续篇：标注回答「这个成员导出了吗」，本文的过滤回答「只看导出的东西是什么样」。

## 背景与目标

`SwiftDeclarationPrintConfiguration.printExportedDeclarationsOnly`（CLI `swift-section interface --exported-only`）打开后，
interface 只输出镜像导出的声明。「导出」始终是 **export trie 的事实**，不是访问级别推断——`internal` / `private` 在二进制里不可恢复
（roadmap L-16），而 `-enable-testing` 构建的 `internal` 与 `@usableFromInline` 类型确实导出，过滤后它们照样在。
边界：只做 interface 路径；`dump` 的三个 Dumper 不在范围内。

## 关键设计决策

**过滤在打印期，不在索引期。** 用户选定。索引出的模型保持完整，RuntimeViewer 浏览、ABI diff / snapshot / evolution
全部不受影响；代价是打印器多了一组判定入口。（注意区分**动作**与**事实**：删不删仍然只发生在打印期，
但「类型 / 协议导出与否」这个事实本身自提案 `exported-declaration-flag` 起在索引期算好、存在模型上——见下文「这两腿住在声明模型上」。）索引期过滤本可顺带给 diff 一个「只比对导出面」的能力，但要在
`DefinitionBuilder` 和四个 extension 桶上做更深的手术，且提案 0008 的标注本来就是打印期的事实——两者同层最自然。

**绝不靠猜删东西。** 每个判定都是三态：`false` 才删，`true` 与 `nil` 都保留。`nil` 覆盖「镜像没有导出信息」「成员没有 join 上任何符号」
「重整名不可信」「宿主没装 `ExportFilterScope`」全部情形。这和标注的「绝不靠猜打标」是同一条原则的两面，
也是 `filteredOutputCarriesNoAnnotation` 这个结构性不变量成立的原因：过滤的删除条件**就是**标注的发射条件，两个 flag 同开输出零标注。

**类型 / 协议判据：先反查描述符 offset 处的符号，重整名只做兜底。** 提案原定按 `TypeName.node` 重整出 `_$s…Mn` / `…Mp`
查 trie。第一版这么做，fixture 当场暴露一个真实误删：`extension GenericRequirementTest where T: RawRepresentable { public struct RawRepresentableNestedStruct {} }`
——编译器给嵌套在**带约束扩展**里的类型 mangle 的上下文只含扩展自己的 requirement（`…VAASYRzrlE28RawRepresentableNestedStructVMn`），
而模型的名字节点带着类型的完整签名（interface 头部印出 `where A: RawRepresentable, A: ProtocolTest` 两条），重整结果与真实符号不等，
trie 查不到就成了假阴性，一个导出类型被删掉。因此裁决分两腿：

1. `symbolIndexStore.symbols(for: descriptor.offset)` 取**描述符所在位置**的符号（按 `Mn` / `Mp` 后缀挑），拿编译器自己的拼法查导出位图。
   导出描述符必有 trie 行、未 strip 的镜像对未导出描述符也有本地 symtab 行，所以这一腿几乎总能答。
2. 只有描述符处没有任何符号（strip 过的镜像里的未导出类型）才用重整名查 trie——trie 在 symtab 被 strip 后依然完整，
   一次 miss 就是真阴性。但**含 `.extension` 上下文的名字拒绝兜底**（返回 `nil` → 保留）：那正是第 1 腿存在的理由。

**这两腿住在声明模型上，不在打印器里**（提案 `exported-declaration-flag`）。`TypeDefinition.exportStatus` /
`ProtocolDefinition.exportStatus`（`SwiftDeclaration` 的 `ExportStatus` 枚举：`exported` / `notExported` /
`imageHasNoExportInformation` / `descriptorSymbolNameUnresolvable`，后来又加了 `declarationHasNoSymbol` 与 `declarationIsCImported`）在定义构造时一次算好，`prepare()` 返回时整张表就都有值——
裁决只要描述符 offset 与名字节点，不碰 `index(in:)` 的产物。宿主（RuntimeViewer 的类型列表）因此能逐行标注而不必持有 machO，
打印器的 `exportVerdict(forTypeDefinition:/forProtocolDefinition:)` 退化为 `exportStatus.isExported` 的转发（签名不变，仍是 `Bool?`），
`installExportFilterScope` 只筛 `isDefinitelyNotExported`——`printRoot()` 原先那趟全镜像重算随之消失。
枚举把原本压在 `nil` 里的两个原因分开了：`imageHasNoExportInformation` 是**镜像级**的（没有 export trie，任何声明都无从判断），
`descriptorSymbolNameUnresolvable` 是**声明级**的（trie 正常，只是这一条的名字重整不可信）。
实测四个真实镜像（dyld shared cache 与 iOS 18.5 模拟器的 SwiftUICore、进程内 libswiftCore、`SymbolTestsCore`）共 8171 条类型 / 协议声明
**全部走第 1 腿**、无一落到这两个 case，裁决总耗时占 `prepare()` 的 0.15% 以内——所以它是无条件填充，没有配置开关。

**C 导入类型不裁决**（提案 [draft-exported-only-marking-mode](../Evolutions/draft-exported-only-marking-mode.md)）。`__C.CGSize` 一类类型在本镜像里的描述符
是本镜像自己生成的一份副本：编译器给 Clang 声明的是非唯一链接（`swift/lib/SIL/IR/SIL.cpp` 的 `getDeclLinkage` 对 Clang 声明返回
`PublicNonUnique`），每个用到它的模块各自生成一份、谁都不导出——fixture 里 `_$sSo11CMTimeFlagsVMn` 就是 private external。
把它读成「未导出」，开了 `--show-c-imported-types` 的 `--exported-only` 会删掉 C 类型本身，而且因为它进了 `ExportFilterScope`，
本镜像给它写的公开扩展与 conformance（SwiftUI 的 `extension CGSize: VectorArithmetic`）也跟着被删。所以裁决在源头改为
`declarationIsCImported`：`ExportStatus.resolve` 先看描述符的模块是不是 `__C` / `__C_Synthesized`（`isCImportedContextDescriptor`），
是就不查 trie。它不给结论，于是 C 类型本身保留、不进 scope，扩展照常按成员裁决；宿主读 `exportStatus` 的其他地方（RuntimeViewer 侧栏的
「Not Exported」）一起正确。`ExportedOnlyLibraryEvolutionFixtureTests.cImportedTypeIsNotRuledOnAndItsPublicExtensionsAreKept`
（即时编译的模块扩展 `CGPoint`）与 `ExportStatusTests.cImportedTypeIsNotRuledOn`（`CMTimeFlags`）钉住它；修复前前者的四条断言全红。

**扩展的判据要靠索引器的表，符号推不出「本镜像内」。** 扩展没有自己的描述符符号，能判的只有「被扩展类型 / 遵循协议是不是本镜像内未导出声明」。
「本镜像内」不能从符号存储推断——strip 过的镜像里一个未导出的类型**一个符号都没有**，用 `typeInfo` / `containsSymbol` 判会把被删私有类型的
conformance 扩展全部漏下来。所以 `SwiftInterfaceBuilder.printRoot()` 在开关打开时从 `indexer.allTypeDefinitions` /
`allProtocolDefinitions` 算出 `ExportFilterScope`（本镜像内未导出的 `TypeName` / `ProtocolName` 集合，结构哈希，跨 store 也能匹配）
装到打印器上；`ExtensionName` 经 `TypeName(node:kind:)` / `ProtocolName(node:)` 转换后查集合，`conformingProtocolName` 再查一次协议集合。
不必再查 conformance 描述符 `…Mc`：fixture 上 44 个未导出 `Mc` 全都涉及私有类型或协议，一个 conformance 的导出性就是它两方的导出性。

**空扩展：普通扩展删，conformance 扩展留 `{}`。** 成员全被过滤后的 `extension Foo {}` 是噪音；但 `extension Foo: Equatable {}`
本身就是声明——合成的 `==` witness 不可静态调用（0008 故意不豁免 witness），删掉 witness 后剩下的正是 `.swiftinterface` 对合成 conformance 的印法。
「空」按过滤后的实际内容算（成员、嵌套类型 / 协议、关联类型记录），原本就空的普通扩展桶（如 `where A: ~Copyable {}`）也一并消失。

**三个打印入口拆成「过滤壳 + builder 体」。** `@SemanticStringBuilder` 函数里不能 early return，所以 `printTypeDefinition` /
`printProtocolDefinition` / `printExtensionDefinition` 变成普通函数做判定，原体改名为 `printIncluded…`。被过滤的定义返回空 `SemanticString`，
`BlockList` / `NestedDeclaration` 对空项整体跳过，不会留下孤零零的换行——这是为什么输出里没有 `\n\n\n`。
**事件契约**：被过滤的定义在 start 事件之前就返回，不发任何 print 事件（它没被打印）；被**清空**的普通扩展例外——空不空要先
`index(in:)` 才知道，而索引必须在 start 事件之后（否则失败事件无 start 可配对，见 `printProtocolDefinition` 的注释），
所以它发一对 start / completed 包住空结果。

**字段循环先筛后印，保留原始下标。** `renderModelFields` 的字段记录与布局注释都按原始位置取（`fieldRecords[safe:]`、
`storedFieldComments(forFieldAtIndex:)`），而尾部换行跟着「最后一个实际渲染的字段」走。所以先把 `fields.enumerated()` 筛成
`renderedFields`（每项带原始下标与可见条件），再逐项打印——`fieldIndex` 取原始下标，尾部换行放在循环之后、条件是「任一字段可见」。枚举 case 没有符号，永远不筛。

## 标记模式

提案 [draft-exported-only-marking-mode](../Evolutions/draft-exported-only-marking-mode.md)。标记模式（`marksOptionalContent`，提案 0056）
把受选项控制的内容全部打出、标上可见条件，宿主按选项投影；RuntimeViewer 的 Find 语料就是这样打印的。导出过滤原本不在其中，
开着这个选项 Find 照样搜得到被删的成员。现在 `SwiftVisibilityOption.printExportedDeclarationsOnly`（`swift.printExportedDeclarationsOnly`）
也是一个可见性选项，`isVisibilityOptionEnabled` 认它：

- **判定照旧，动作改为标记。** `isExcludedByExportFilter` 一族在开关打开**或**标记模式下都会裁决（`evaluatesExportFilter`），标记模式不看开关本身的取值。
  每个原本「不输出」的地方改问 `exportFilterVisibility(excluded:)`：保留的内容 `.always`；过滤掉的内容普通打印时 `nil`（略过），
  标记模式下是 `.disabled("swift.printExportedDeclarationsOnly")`——只在开关关着时可见。覆盖三个打印入口、被清空的普通扩展、
  成员循环、存储属性、`printRoot` 的两个全局块与 ObjC category conformance 块。已经打好的 `SemanticString` 用 `visible(under:)`
  （`markAtoms(from:visibleUnder:)` 的包装）补标，不改文本与元素边界；要保留元素结构的一组内容（全局块一项的注释行与声明）包 `VisibilityRegion`。
- **scope 照旧要装。** `printRoot()` 在标记模式下也装 `ExportFilterScope`；逐个定义打印的宿主（RuntimeViewer）给语料打印器也要装。
- **分隔符交给容器，闭合换行除外。** `MemberList`、`BlockList`、`NestedDeclaration` 会把成员的条件带到自己打的换行与分隔符上，
  conformance 扩展被清空后照样投影成 `{}`。管不到的是 `DeclarationBlock` 闭合 `}` 前的换行：它按**全量打印**的 body 最后一个字节决定补不补
  （swift-semantic-string 的设计记录把这列为已知例外）。body 留着嵌套类型、之后的声明全被过滤时（`public enum Namespace { public struct Member {}; static func internalHelper() }`），
  全量打印以成员列表的换行结尾、块不补换行，投影到开关打开就只剩嵌套类型的 `}`，印成 `}}`。所以标记模式下，类型与扩展 body 里嵌套定义之后的部分
  （`bodyAfterNestedDefinitions(of:content:)`）在「其中每个声明都被过滤」（`excludesEveryDeclarationAfterNestedDefinitions(of:)`：
  存储属性与成员全被过滤，且没有枚举 case、`deinit`、关联类型记录、ObjC ivar）时去掉最后那个换行，让块自己补一个条件为「body 任一部分可见」的换行。
  开关关着时它顶替被去掉的那个；开着时嵌套定义在就补、body 全空就不补（`{}`）。协议 body 没有嵌套定义，不需要。
- **事件**：标记模式下被过滤的定义也打印了，所以照常派发 start / completed。
- **嵌套定义区域契约的例外**（`marksNestedDefinitions`）：被过滤的定义里嵌着一个**没被过滤**的定义时，父定义的标记打印把整段、连同这个子定义，
  都标成「开关关着才可见」，取出的子定义区域于是比它单独打印多了这个条件：开关关着时两者相同，开着时区域消失、单独打印还在。
  这在现有编码下修不掉——父定义投影到开关打开时必须整段不可见，子定义单独打印时又必须可见，同一段原子带不了两种条件；
  要在「取出区域」时去掉祖先加上的条件，得改 swift-semantic-string 的区域编码。所以写进契约作为例外：宿主遇到「自己的 `exportStatus` 不是
  `isDefinitelyNotExported`、外层某个定义是」的嵌套定义，单独打印它。RuntimeViewer 接入时在 Foundation 碰到一例
  （`LocalePreferences` 没导出、`LocalePreferences.ICUSymbolsAndStrings` 导出了，源码里两者都是 `package`，导出与否看苹果的导出清单），
  它的 Find 语料已按此单独打印。`ExportedOnlyFixture` 用链接器的 `-unexported_symbol` 把 `UnexportedParent` 的类型符号移出导出表造出同样的形态，
  `NestedDefinitionRegionContractTests.exportedOnlyFixtureNestedDefinitionsTakeOutAsTheirOwnPrints` 把这个区域按上述例外严格检查、其余区域照旧按契约检查。

## 模块结构

```
Sources/Output/SwiftPrinting/
├── SwiftDeclarationPrintConfiguration.swift      # printExportedDeclarationsOnly；isEnabled 认 SwiftVisibilityOption.printExportedDeclarationsOnly
├── SwiftDeclarationPrinter+ExportFilter.swift    # ExportFilterScope、installExportFilterScope、类型 / 协议 verdict 的转发、全部 isExcludedByExportFilter 判定、excludesEveryDeclarationAfterNestedDefinitions
├── SwiftDeclarationPrinter+VisibilityRegions.swift # exportFilterVisibility(excluded:)、bodyAfterNestedDefinitions、SemanticString.visible(under:)
├── SwiftDeclarationPrinter.swift                 # 三个入口的过滤壳 + printIncluded… 体；成员循环逐项问可见性；exportFilterScope 存储
└── SwiftDeclarationPrinter+Headers.swift         # renderModelFields 的字段预筛
Sources/Output/SwiftDeclarationRendering/SwiftVisibilityOption.swift # 可见性选项 swift.printExportedDeclarationsOnly
Sources/Declaration/SwiftDeclaration/Components/ExportStatus.swift # 裁决枚举、C 导入类型不裁决、两腿裁决、descriptorSymbolName 重整（提案 exported-declaration-flag）
Sources/Output/SwiftInterface/SwiftInterfaceBuilder.swift # printRoot 装 scope（标记模式也装）；全局块与 ObjC category conformance 块逐项问可见性
Sources/Executables/swift-section/Commands/InterfaceCommand.swift # --exported-only
```

## 核心算法与数据流

`printRoot()` → 开关打开或标记模式下 `installExportFilterScope(types:protocols:)`（只筛各定义已算好的 `exportStatus`）→ `printRootContents()`。
每个判定的结果都经 `exportFilterVisibility(excluded:)` 变成「输出 / 略过 / 标记」三者之一（见上文「标记模式」）：

| 对象 | 判定入口 | 依据 |
|------|----------|------|
| 全局变量 / 函数 | `isExcludedByExportFilter(globalSymbolNames:)` | `exportVerdict(forSymbolNames:)`（0008 的派生形态查询） |
| 类型 / 协议（含嵌套、特化子类型） | 入口壳 → `TypeDefinition/ProtocolDefinition.exportStatus.isDefinitelyNotExported` | 构造期算好的 `ExportStatus`（C 导入类型不裁决 → 描述符 offset 处的符号 → 重整名兜底） |
| 扩展 | 入口壳 → `isExcludedByExportFilter(_ extension)`；索引后 `isEmptiedByExportFilter` | `ExportFilterScope` 集合；过滤后内容是否为空 |
| 成员 | `printMembersByOffset` / `ByCategory` 逐项 | 派生形态查询；`override` / `@objc` 豁免 |
| 存储属性 | `renderModelFields` 预筛 `isExcludedByExportFilter(field:)` | accessor 组的派生形态查询；无 accessor 符号 / `override` / `To` 入口豁免 |
| ObjC category conformance | `SwiftInterfaceBuilder` 的 `isExcludedByExportFilter(_ conformance:)` | 被扩展的本镜像类是否被过滤 |

特化子类型的名字是 bound-generic 节点，verdict 的两腿都落在未绑定描述符上（第 1 腿直接用描述符 offset，第 2 腿剥 bound-generic 壳）。

## 与提案的差异

- **类型级判据加了 offset 反查腿。** 提案决策日志写的是「按名字查 trie 优于 offset 反查」，理由是 strip 后 offset 反查只能答 `nil`；
  实现保留了这个理由（第 2 腿），但把 offset 反查提到第 1 腿——原因是上文的带约束扩展重整名不等价问题，提案写作时未预见。
- 其余与提案一致。

## 验证

- `Tests/SwiftInterfaceTests/ExportedOnlyInterfaceTests.swift`（`SymbolTestsCore`，12 例）：私有类型 / 私有协议及其默认实现扩展 /
  私有类型的 conformance 扩展 / 嵌套私有类型（父级与公开兄弟保留）各一例删除；带约束扩展里的公开嵌套类型保留（回归）；
  未导出成员删而类型留；未导出全局删；`Tj` 导出、`@objc`、`override` 三类保留；清空的 conformance 扩展留 `{}`；
  双 flag 同开零标注；无空行残留；默认输出与从未听说过该开关的 builder 逐字节相同。每条否定断言都先在默认输出上断言其存在。
- `Tests/SwiftInterfaceTests/ExportedOnlyLibraryEvolutionFixtureTests.swift`（8 例，跑在即时编译的 `ExportedOnlyFixture` 上——`Sources/TestSupport/MachOTestingSupport/ExportedOnlyFixture.swift`，`-enable-library-evolution` 且无 `-enable-testing`）：
  `SymbolTestsCore` 因 `ENABLE_TESTABILITY` 导出全部 `internal`，所以 `internal` 形态在这里钉：类型（顶层 + 嵌套）、协议及其默认实现、
  公开类型对内部协议的 conformance 扩展、方法、存储属性（accessor 以本地符号 join 上）、全局；被清空的普通扩展容器整块删、有公开成员的容器保留；枚举 case 保留；C 导入类型 `CGPoint` 本身、本镜像给它写的公开扩展与 conformance 保留。
- `Tests/SwiftSectionCommandTests/ExportedOnlyFlagTests.swift`：flag 解析、默认关、`dump` 无此 flag。
- `Tests/SwiftInterfaceTests/VisibilityRegionProjectionTests.swift`：标记打印按某组配置投影 == 按该配置直接打印（文本、span、identifier），
  每个打印器都装同一个 scope。SymbolTestsCore 进程内覆盖全关、全开与每个选项单开、单关（含 `printExportedDeclarationsOnly`），从文件打印变动四个布局选项；
  `ExportedOnlyFixture`（即时编译，`internal` 不导出）逐个定义与整份 `printRoot()` 各对开关开、关投影一次。
  两个探针确认它们会红：标记模式退回不管导出过滤时三条都红；不去掉 body 末尾的换行时，`Holder` / `FieldHolder` / `Namespace` / `extension Int`
  投影到开关打开都印成 `}}`。
- 落地前在真实框架上跑过一次临时探针（未提交）：本机 macOS 27.2 dyld cache 的 Combine、SwiftUICore、AppKit，每个定义的标记打印按「过滤开 / 关 ×
  地址等注释开 / 关」四组配置投影，848 / 14,086 / 2,879 个定义全部与直接打印一致，其中 615 / 9,919 / 1,503 个有被过滤标记的内容。
- 落地前的人工交叉验证（fixture 全量输出）：默认 3824 行 → 过滤后 2839 行；标注模式下 378 处 `// not exported` 对应的声明在过滤输出里**零残留**；
  过滤输出相对默认输出的新增行只有 conformance 扩展的 `{` → `{}` 改写；无 `\n\n\n`、无 `{\n}`。
- 默认路径零行为改动，不构成 AGENTS.md 意义上的 large refactor，未跑渲染 A/B 脚本；由既有 interface 快照与 `defaultOutputIsUnchanged` 钉住。

## 已知降级

- **外层没导出时，导出了的嵌套类型跟着被删。** 嵌套类型只在外层里面打印，外层被过滤，整段一起没了：`--exported-only` 的输出里没有
  Foundation 的 `LocalePreferences.ICUSymbolsAndStrings`，虽然它的描述符导出了。系统框架的导出表由导出清单决定，不跟访问级别走，
  这种形态真实存在；标记模式下它是嵌套定义区域契约的例外（见上文「标记模式」）。单独打印这个嵌套类型（宿主逐个对象打印时）照常输出。
- **引用不改写。** 过滤按声明进行，导出成员的签名里仍可能引用被删的类型（fixture：`typealias Body = Structs.PrivateProtocolTest`）。
  这与真实二进制里 `some P` 解析到私有类型的情形同构，属于「输出忠实于二进制」的一面。
- **绕过 `printRoot` 的宿主要自己装 scope**，标记打印也一样。RuntimeViewer 的 per-type 导出若不调 `installExportFilterScope`，类型 / 协议 / 成员照常过滤，
  只有扩展这一腿退化为「全部保留」——fail-open，静默；标记打印则不标任何扩展。
- **镜像没有导出信息时什么都不过滤**（三态 `nil`），静默。目前没有能构造这种镜像的 fixture（与 0008 同一个缺口）。
- **被清空的普通扩展仍会派发一对 print 事件**（见上文事件契约），事件消费者会看到一个 start / completed 之间零输出的扩展。

## 延伸阅读

- 配套提案：[0016](../Evolutions/0016-exported-only-interface.md)；标记模式与 C 导入类型：[draft-exported-only-marking-mode](../Evolutions/draft-exported-only-marking-mode.md)
- 前篇：[InterfaceHeaderAndExportStatusAnnotations.md](InterfaceHeaderAndExportStatusAnnotations.md)（导出事实层、派生符号形态、两个豁免的来历）
- 模块参考：[Modules/SwiftInterface.md](Modules/SwiftInterface.md)（`printRoot()` 的段落与 catch 契约）
- 术语：[Glossary.md](../Glossary.md) 的「export status」与「exported-only 过滤」
