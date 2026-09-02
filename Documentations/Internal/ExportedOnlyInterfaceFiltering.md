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
全部不受影响；代价是打印器多了一组判定入口。索引期过滤本可顺带给 diff 一个「只比对导出面」的能力，但要在
`DefinitionBuilder` 和四个 extension 桶上做更深的手术，且提案 0008 的标注本来就是打印期的事实——两者同层最自然。

**绝不靠猜删东西。** 每个判定都是三态：`false` 才删，`true` 与 `nil` 都保留。`nil` 覆盖「镜像没有导出信息」「成员没有 join 上任何符号」
「重整名不可信」「宿主没装 `ExportFilterScope`」全部情形。这和标注的「绝不靠猜打标」是同一条原则的两面，
也是 `filteredOutputCarriesNoAnnotation` 这个结构性不变量成立的原因：过滤的删除条件**就是**标注的发射条件，两个 flag 同开输出零标注。

**类型 / 协议判据：先反查描述符 offset 处的符号，重整名只做兜底。** 提案原定按 `TypeName.node` 重整出 `_$s…Mn` / `…Mp`
查 trie。第一版这么做，fixture 当场暴露一个真实误删：`extension GenericRequirementTest where T: RawRepresentable { public struct RawRepresentableNestedStruct {} }`
——编译器给嵌套在**带约束扩展**里的类型 mangle 的上下文只含扩展自己的 requirement（`…VAASYRzrlE28RawRepresentableNestedStructVMn`），
而模型的名字节点带着类型的完整签名（interface 头部印出 `where A: RawRepresentable, A: ProtocolTest` 两条），重整结果与真实符号不等，
trie 查不到就成了假阴性，一个导出类型被删掉。因此 `exportVerdict(descriptorOffset:nameNode:…)` 分两腿：

1. `symbolIndexStore.symbols(for: descriptor.offset)` 取**描述符所在位置**的符号（按 `Mn` / `Mp` 后缀挑），拿编译器自己的拼法查导出位图。
   导出描述符必有 trie 行、未 strip 的镜像对未导出描述符也有本地 symtab 行，所以这一腿几乎总能答。
2. 只有描述符处没有任何符号（strip 过的镜像里的未导出类型）才用重整名查 trie——trie 在 symtab 被 strip 后依然完整，
   一次 miss 就是真阴性。但**含 `.extension` 上下文的名字拒绝兜底**（返回 `nil` → 保留）：那正是第 1 腿存在的理由。

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
`storedFieldComments(forFieldAtIndex:)`），而尾部换行跟着「最后一个实际渲染的字段」走。所以先把 `fields.enumerated()` 过滤成
`renderedFields`，再用 `offsetEnumerated()` 遍历——`fieldIndex` 取原始下标，`offset.isEnd` 取渲染序列的末尾。枚举 case 没有符号，永远不筛。

## 模块结构

```
Sources/SwiftPrinting/
├── SwiftDeclarationPrintConfiguration.swift      # printExportedDeclarationsOnly
├── SwiftDeclarationPrinter+ExportFilter.swift    # ExportFilterScope、installExportFilterScope、两级 verdict、全部 isExcludedByExportFilter 判定
├── SwiftDeclarationPrinter.swift                 # 三个入口的过滤壳 + printIncluded… 体；成员循环 where 过滤；exportFilterScope 存储
└── SwiftDeclarationPrinter+Headers.swift         # renderModelFields 的字段预筛
Sources/SwiftInterface/SwiftInterfaceBuilder.swift # printRoot 装 scope；全局块 where 过滤
Sources/swift-section/Commands/InterfaceCommand.swift # --exported-only
```

## 核心算法与数据流

`printRoot()` → 开关打开则 `installExportFilterScope(types:protocols:)`（对每个定义跑一次类型级 verdict）→ `printRootContents()`：

| 对象 | 判定入口 | 依据 |
|------|----------|------|
| 全局变量 / 函数 | `isExcludedByExportFilter(globalSymbolNames:)` | `exportVerdict(forSymbolNames:)`（0008 的派生形态查询） |
| 类型 / 协议（含嵌套、特化子类型） | 入口壳 → `exportVerdict(forTypeDefinition:/forProtocolDefinition:)` | 描述符 offset 处的符号 → 重整名兜底 |
| 扩展 | 入口壳 → `isExcludedByExportFilter(_ extension)`；索引后 `isEmptiedByExportFilter` | `ExportFilterScope` 集合；过滤后内容是否为空 |
| 成员 | `printMembersByOffset` / `ByCategory` 的 `where` | 派生形态查询；`override` / `@objc` 豁免 |
| 存储属性 | `renderModelFields` 预筛 `isExcludedByExportFilter(field:)` | accessor 组的派生形态查询；无 accessor 符号 / `override` / `To` 入口豁免 |

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
- `Tests/SwiftInterfaceTests/ExportedOnlyLibraryEvolutionFixtureTests.swift`（即时编译，`-enable-library-evolution` 且无 `-enable-testing`，7 例）：
  `SymbolTestsCore` 因 `ENABLE_TESTABILITY` 导出全部 `internal`，所以 `internal` 形态在这里钉：类型（顶层 + 嵌套）、协议及其默认实现、
  公开类型对内部协议的 conformance 扩展、方法、存储属性（accessor 以本地符号 join 上）、全局；被清空的普通扩展容器整块删、有公开成员的容器保留；枚举 case 保留。
- `Tests/SwiftSectionCommandTests/ExportedOnlyFlagTests.swift`：flag 解析、默认关、`dump` 无此 flag。
- 落地前的人工交叉验证（fixture 全量输出）：默认 3824 行 → 过滤后 2839 行；标注模式下 378 处 `// not exported` 对应的声明在过滤输出里**零残留**；
  过滤输出相对默认输出的新增行只有 conformance 扩展的 `{` → `{}` 改写；无 `\n\n\n`、无 `{\n}`。
- 默认路径零行为改动，不构成 AGENTS.md 意义上的 large refactor，未跑渲染 A/B 脚本；由既有 interface 快照与 `defaultOutputIsUnchanged` 钉住。

## 已知降级

- **引用不改写。** 过滤按声明进行，导出成员的签名里仍可能引用被删的类型（fixture：`typealias Body = Structs.PrivateProtocolTest`）。
  这与真实二进制里 `some P` 解析到私有类型的情形同构，属于「输出忠实于二进制」的一面。
- **`--show-c-imported-types` 下 C 导入类型会被过滤。** `__C.CMTime` 之类外来描述符的 `Mn` 是本地符号（它们不是本镜像导出的），判定为 `false`。
- **绕过 `printRoot` 的宿主要自己装 scope。** RuntimeViewer 的 per-type 导出若不调 `installExportFilterScope`，类型 / 协议 / 成员照常过滤，
  只有扩展这一腿退化为「全部保留」——fail-open，静默。
- **镜像没有导出信息时什么都不过滤**（三态 `nil`），静默。目前没有能构造这种镜像的 fixture（与 0008 同一个缺口）。
- **被清空的普通扩展仍会派发一对 print 事件**（见上文事件契约），事件消费者会看到一个 start / completed 之间零输出的扩展。

## 延伸阅读

- 配套提案：[0016](../Evolutions/0016-exported-only-interface.md)
- 前篇：[InterfaceHeaderAndExportStatusAnnotations.md](InterfaceHeaderAndExportStatusAnnotations.md)（导出事实层、派生符号形态、两个豁免的来历）
- 模块参考：[Modules/SwiftInterface.md](Modules/SwiftInterface.md)（`printRoot()` 的段落与 catch 契约）
- 术语：[Glossary.md](../Glossary.md) 的「export status」与「exported-only 过滤」
