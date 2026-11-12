# Draft - 还原 SE-0400 的 init accessor

- **状态**: In Progress
- **创建日期**: 2026-11-12
- **最后更新**: 2026-11-12
- **实现分支**: `feature/init-accessor-recovery`（RuntimeViewer 一侧是同名分支，见落地步骤 1）

## 摘要

SE-0400 让 computed property 带一个 `init` accessor：初始化器给这个属性赋值时，由它初始化 `@storageRestrictions(initializes:)` 列出的 stored property。二进制里只留下这个 accessor 的符号（后缀 `vi`），`@storageRestrictions` 的名单和参数名都不留。库今天把这个符号整个丢掉：dump 不列它，interface 只印 `get` / `set`，ABI diff 也看不到它。本提案把 init accessor 当成所属属性的一个 accessor 建进模型：dump 列出它的符号，ABI diff 把它算进 accessor 集合，interface 在 accessor block 里印出 `init`；`initializes:` 的名单按「同名的 `_x`、类型与属性相同」推断，推不出就用注释说明二进制没有记录。起因是 SwiftUICore 导出的 `_GeometryActionModifier2.value.init`：编译器自己的 `.swiftinterface` 把它印成 `@storageRestrictions(initializes: _value) init(initialValue)`，我们的 interface 只有 `{ get set }`；`@Observable` 的展开形态也因此缺了每个被跟踪属性的 init accessor。

## 方案

### 二进制里有什么

调研对照了 Swift 6.4 的编译器源码，并在 Ultra 上用 Swift 6.4.2 编了探针：六种写法，debug、release、debug 加 dead-strip、release 加 dead-strip 四种构建。

- 符号是 `<属性>vi`，例如 `$s7SwiftUI24_GeometryActionModifier2V5valueyxAA0C5ProxyVYbcvi`（`SwiftUI._GeometryActionModifier2.value.init`）。swift-demangling 已经认得（`Node.Kind.initAccessor`），不用改。
- 编译器把 init accessor 的访问级别写死为 `internal`（`lib/AST/AccessRequests.cpp`，理由是它只在本模块里被调用）。只有标了 `@usableFromInline` 的才导出，这也是官方 `.swiftinterface` 印出 init accessor 的唯一情况；macOS 27.2 SDK 的 `.swiftinterface` 里只有 SwiftUICore 一处。其余的都是本地符号：前三种构建里六个都在，release 加 dead-strip 之后只剩导出的那个（初始化器把它内联掉了，再没有引用）。
- `initializes:` 的每一项变成一个 indirect result，`accesses:` 的每一项变成一个 `inout` 参数（`lib/SIL/IR/SILFunctionType.cpp` 的 `getSILFunctionTypeForInitAccessor`）。指针直接指向那块存储，看不出是哪个字段：探针里 `Pair.point.init` 的全部机器码是 `str x2, [x0]; str x3, [x1]; ret`，能数出它初始化两块存储，认不出是 `_x` 和 `_y`。参数名不进 mangling，不写时默认叫 `newValue`。
- 有 `…vi` 符号不等于有 init accessor：SwiftUICore 的 `_GeometryActionModifier.value` 已经改回 stored property，为了兼容旧客户端内联进去的调用，用 `@_silgen_name` 留了一个同名的 mutating 函数。

### 改动位置

1. 模型：`Sources/Declaration/SwiftDeclaration/Model/Kinds/AccessorKind.swift:1` 加 `case initAccessor`，`addressLabel` 为 `init`；`Model/Members/Accessor.swift:36` 之后加 `hasInitAccessor`；`Model/Members/VariableDefinition.swift` 加 `initializedFieldNames: [String]?`，存推断出的名单，`nil` 表示镜像里看不出来。
2. 符号分桶：`Sources/MachO/MachOSymbols/SymbolIndexStore.swift:1164` 把 `.initAccessor` 并进 getter / setter 那一支，进成员桶 `.variable`；`:1938` 的 `isAccessor` 加上它，否则 init accessor 的节点会被当成「没有 accessor」。
3. accessor 种类：`Sources/Declaration/SwiftDeclaration/Extensions/DemanglingNode+AccessorKind.swift:14` 加上映射。不加的话种类落到 `.none`，`isStored`（`Accessor.swift:19`）会把整个属性当成 stored property。
4. 建成员：`Indexing/Building/MemberDefinitionBuilder.swift:50` 把 init accessor 排在同名那一组的最后，`accessors.first` 不变；声明节点照旧取 getter 或 borrow（`:62`），只有 init accessor 的组照旧不建成属性（今天也不建）。
5. 成员顺序：`Model/Members/OrderedMember.swift:22` 的 `minSymbolOffset` 跳过 init accessor，成员顺序和今天一样。
6. 推断：新文件 `Sources/Analysis/SwiftInspection/InitAccessorFieldInference.swift`，放在 dump 和模型都够得着的一层，和 `ObservableMacroRecognition` 同一个位置；`ObservableMacroExpansionRecovery.referencedTypeNode(ofStoredType:)`（剥掉 `weak` / `unowned`，`ObservableMacroExpansionRecovery.swift:157`）挪进来两边共用。新的索引步骤 `Indexing/TypeDefinition/TypeDefinition+InitAccessors.swift`，接在 `TypeDefinition+Indexing.swift:47` 的 `foldStoredPropertyAccessors` 之后、`:88` 收集 `orderedMembers` 之前（后者拷贝成员的值，晚了就写不进去）。
7. interface：`Sources/Output/SwiftPrinting/NodePrinter/AccessorBlockKeywords.swift` 加上 `init` 那一行，`NodePrintables/MemberDeclarationNodePrintable.swift:167` 的 `printAccessorBlock` 把它印在 `get` 之前。推不出时的注释走 `Sources/Output/SwiftDeclarationRendering/StructuredComment+Factories.swift` 里的新工厂 `initAccessorFieldsNotRecorded`，配新的注释种类 `AnnotationRegion.Kind.initAccessorFields`（`AnnotationRegionKind+SwiftComments.swift`），由 `SwiftDeclarationPrinter.renderMember` 印在声明的上一行。
8. dump：`Sources/Output/SwiftDump/Dumper/StructDumper.swift:154` 与 `ClassDumper.swift:471` 一带的成员循环。init accessor 进桶之后自动列出，带地址和导出状态；每一条前面再加一行推断结果。
9. ABI diff：`Sources/Output/SwiftDiffing/MemberRecord.swift:322` 给 `.initAccessor` 一个 token `init`；`ABISnapshotDocument.swift:90` 的格式版本从 12 升到 13，因为带 init accessor 的属性的 `|acc:` 标签变了，旧基线会把它们全报成改动。
10. RuntimeViewer：`RuntimeViewerCore/Sources/RuntimeViewerCore/Sections/Swift/RuntimeSwiftSection.swift:1952` 的 `kindString` 对 `AccessorKind` 穷举 `switch`，要补一行 `case .initAccessor`，和本库合进 `next` 放在同一批，否则它直接编不过。它的注释种类是按字符串比较的 struct，新的注释种类不用改代码，按普通注释的样式显示。

### 明确不动的地方

- `@Observable` 的识别：证据照旧按 kind 查 `symbols(of: .initAccessor)`。按 kind 的索引对每个符号都记一行（`SymbolIndexStore.swift:1035`），进不进成员桶都不影响它；折叠形态整块不印被跟踪属性背后的 computed property，不会出现 accessor block。
- 导出判定：成员的导出结论是「任一 accessor 导出即导出」（`SymbolIndexStore.swift:1445`），加进一个不导出的 init accessor 不改变任何结论，`--exported-only` 也一样。
- 属性的声明节点、名字和类型，property wrapper 的还原。
- `final` 的推断结论不变：它把「有 accessor 符号、却都没有 vtable descriptor」当证据，而 init accessor 从不进 vtable，所以证据里不算它（`TypeDefinition+FinalRecovery.swift` 的两处判据、dump 那条路的 `ClassDumper.storedAccessorFieldNames`）。不排除的话，SwiftUICore 那种兼容函数放在 class 的 stored property 上，会让它单凭这一个符号被判成 `final`。
- `accesses:` 和参数名一律不印；`propertyWrappedFieldInitAccessor`（mangling 里的 `fF`）不在范围内；swift-demangling 不改。

### 推断规则

属性有 init accessor，并且类型里有一个名叫 `_<属性名>`、类型与属性相同（先剥掉 `weak` / `unowned`）的 stored property，`initializedFieldNames` 就是 `["_<属性名>"]`；否则为 `nil`。这条规则对得上 `@Observable` 的展开、SwiftUICore 那一例和手写的 `_x` 写法；对不上探针里的 `Angle`（初始化的是 `degrees`）、`Pair`（一个属性同时初始化 `_x` 和 `_y`）和只写 `accesses:` 的写法。要求类型相同，是因为只看名字会把类型不同的 `_x` 也认进来：SwiftData `@Model` 的 `_name` 是占位类型，它的 init accessor 真正写入的是 `_$backingData`。

### 输出的样子

推得出时，照编译器的写法把属性和 `init` 写在同一行：

```swift
struct FrozenBox<A> {
    var _value: A
    init(value: A)
    var value: A {
        @storageRestrictions(initializes: _value) init
        get
        set
    }
}
```

推不出时只印 `init`，声明上一行用注释说明：

```swift
struct Angle {
    var degrees: Swift.Double
    init(radians: Swift.Double)
    // init accessor: the binary does not record which stored properties it initializes
    var radians: Swift.Double {
        init
        get
        set
    }
}
```

- 带 `…vi` 符号的 stored property（SwiftUICore 那个兼容函数）照旧按 stored property 印，输出和今天完全一样：stored property 只给 accessor 印 vtable 槽注释，init accessor 没有槽。
- 开着成员地址注释时，computed property 和 `@Observable` 折叠形态里的被跟踪属性都多一行 `init` 的地址；`expandsMacros` 的展开形态在每个被跟踪属性的 accessor block 里多出 `@storageRestrictions(initializes: _x) init`。
- dump 在类型的 variable 符号里多列一条 `X.value.init : A`，前面一行写推断结果：推出的名单，或者二进制没有记录。

### 测试与验证

- 新的现编 fixture `InitAccessorFixture`（`Sources/TestSupport/MachOTestingSupport/`），照 `ObservableMacroFixture` 分四个变体：debug、release、release 加 dead-strip、release 加 `strip -x`。源码是探针的六种写法，再加 SwiftUICore 那种兼容函数；编译照它的做法放在协作线程池之外。
- 模型、interface、dump、ABI diff 各一组测试，覆盖推得出、推不出、兼容函数，以及 dead-strip 之后只剩导出的那一个；`ObservableMacroInterfaceTests` 里展开形态的期望补上 `init` 那一行。
- 在 Ultra 上跑全量测试和渲染 A/B（改动碰了索引和打印，按规定必须跑）。差异只允许出现在带 `…vi` 符号的属性上。

### 落地步骤

每一步单独能构建、相关测试能过，做完各提交一次。

1. （已完成）模型与分桶：改动位置 1 到 5 里除 `initializedFieldNames` 以外的部分，ABI diff 的 token 与快照格式 13（改动位置 9），RuntimeViewer 的 `kindString`（改动位置 10，RuntimeViewer 仓库里单独的分支）；新的 `InitAccessorFixture`，以及模型、dump（init accessor 自动列出）、ABI diff 的测试。这一步之后 interface 还不印 `init`，只有成员地址注释多出 `init` 的地址。
2. （已完成）推断：`InitAccessorFieldInference`（连同挪过来的 `referencedTypeNode(ofStoredType:)`）、新的索引步骤与 `initializedFieldNames`，以及模型测试。
3. interface：`init` 那一行、推得出时的 `@storageRestrictions`、推不出时的注释（新工厂与新注释种类）；interface 测试，`ObservableMacroInterfaceTests` 里展开形态的期望。
4. dump：每条 init accessor 前的推断结果，以及 dump 测试。
5. 文档与验证：改动位置之外的文档同步（见下一节最后一条），Ultra 上的全量测试与渲染 A/B。

### 没有询问就采用的假设

- 推得出的名单在 interface 里默认就印，不加开关，也不标「推断」：同名且同类型的证据比只看 selector 名字强得多，所以不照 `--infer-objc-overrides` 默认关掉的做法；证据写在 dump 里。代价是带 `accesses:` 的少见写法会印得不全。
- 推不出时的注释总是印，不设开关；只有带 init accessor 的属性才会有，量很小。
- `init` 一律不带参数名：省略参数名是合法写法，参数名本来也不属于接口。
- 文档同批更新：`Documentations/Internal/Modules/SwiftDeclaration.md`（accessor 种类和新的索引步骤；第 86 行「init accessor 不进成员桶」的说法要改）、`ProjectEvolutionLog.md`、`AgentPlugins/swift-section` 的 skill（输出里多了推断出来的名单）。`@Observable` 提案如果那时还没落地，在它的决策日志里补一行「展开形态多出 `init`」；已经落地就只记在本提案里。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-11-12 | Created as Draft | 调研确认二进制只留 init accessor 的符号、不留 `@storageRestrictions`；用户选定写轻量提案：dump、interface、ABI diff 都认出 init accessor，名单只按同名同类型的 `_x` 推断，推不出就注明 |
| 2026-11-12 | 在 `AccessorKind` 上加 case，不在 `VariableDefinition` 上另挂一个字段 | 和 SE-0507 的 `borrow` / `mutate` 一致；dump 的成员循环、地址注释、ABI diff 都沿着 `accessors` 自动带上它。代价是 RuntimeViewer 的穷举 `switch` 要同批补一行 |
| 2026-11-12 | 不从机器码推 `initializes:` / `accesses:` | 能数出 indirect result 和 `inout` 参数各有几个，但指针直接指向存储，看不出是哪个字段；只有个数印不成合法的 Swift |
| 2026-11-12 | 推断要求类型相同 | 只看名字会把类型不同的 `_x` 也认成被初始化的存储，SwiftData `@Model` 就是这样 |
| 2026-11-12 | 用户批准，开始实现；补上落地步骤 | 原稿只列了改动位置，按能各自构建的顺序拆成五步 |
| 2026-11-12 | `final` 推断不把 init accessor 当证据 | 实现时发现 `final` 的证据门槛是「有任意 accessor 符号」，init accessor 进了 `accessors` 之后会被算进去；它从不经 vtable 派发，什么也证明不了。排除之后所有结论与今天相同 |
| 2026-11-12 | 落地步骤 1、2 完成 | Ultra 上相关的 14 个套件（新增的三组、`ABIDifferTests`、`@Observable` 的各组）80 个测试全过。第一次跑时 init accessor 一个都没进成员桶：分桶之前还有一道 `isMember` 名单（`SymbolIndexStore.swift:1878`），补上之后全绿 |
| 2026-11-12 | 推不出时的注释印在声明上一行，不放在 `init` 行尾 | accessor block 由节点打印器写出，那里没有带注释种类的注释通道；声明上一行是地址、导出状态等成员注释共用的位置，走 `comment(_:as:)` 就能被 `marksCommentStructure` 标出来 |
