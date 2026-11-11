# Draft - 识别 `@Observable` 宏：interface 默认折叠它的展开

- **状态**: Accepted
- **创建日期**: 2026-11-11
- **最后更新**: 2026-11-11
- **实现分支**: `feature/observable-macro`

## 摘要

用 `@Observable` 写的类，编译后二进制里只剩宏展开的结果：每个被跟踪的属性 `x` 变成 private 的存储字段 `_x` 加一组 computed accessor（getter / setter / `_modify` / init accessor），另外多出存储字段 `_$observationRegistrar`、方法 `access(keyPath:)`、`withMutation(keyPath:_:)`、四个 `shouldNotifyObservers(_:_:)` 重载，以及一个 `extension X: Observation.Observable {}`。interface 今天把这些原样印出来，读起来和源码对不上。本提案让库识别出这样的类：模型上标出它带 `@Observable`（`prepare()` 之后就能读到，宿主可以在类型列表里标出来），interface 默认印成源码的样子（类型上写 `@Observation.Observable`，被跟踪的属性写成普通的 `var x: T`，宏生成的成员与 conformance 不印），打开新开关 `expandsMacros` 则和今天逐字节相同。起因是 RuntimeViewer 要在侧边栏标出这类类型，并让用户在折叠与展开两种形态之间切换。

## 方案

### 改动位置

- 识别规则（新文件）：`Sources/Analysis/SwiftInspection/ObservableMacroRecognition.swift`，只读字段记录，供下面两处调用。
- 模型：新类型 `SwiftAttachedMacro`（`Sources/Declaration/SwiftDeclaration/Model/SwiftAttachedMacro.swift`）；`TypeDefinition.attachedMacros` 在 `TypeDefinition.init(type:in:)`（`Model/Definitions/TypeDefinition.swift:230`）里赋值，specialization 构造的定义沿用泛型定义的值；`TypeDefinition.observableMacroExpansion` 由新的索引步骤 `Indexing/TypeDefinition/TypeDefinition+ObservableMacro.swift` 产出，接在 `TypeDefinition+Indexing.swift:97` 的 `recoverWrappedProperties(in:)` 之后；`ExtensionDefinition.generatingMacro` 在 `SwiftDeclarationIndexer` 建 conformance extension 时（`SwiftDeclarationIndexer.swift:791` 一带）赋值。
- 打印：`SwiftDeclarationPrintConfiguration.expandsMacros`；`SwiftVisibilityOption.expandsMacros`；新文件 `SwiftDeclarationPrinter+ObservableMacro.swift`，照 `SwiftDeclarationPrinter+PropertyWrapperSynthesis.swift` 的做法算一份每次打印用的视图，接进字段块（`SwiftDeclarationPrinter+Headers.swift:471`）、成员块（`SwiftDeclarationPrinter.swift:765`、`:804`）、导出过滤（`SwiftDeclarationPrinter+ExportFilter.swift:218`）、类型头与 extension 的打印。
- dump：`ClassDumper.declaration`（`Sources/Output/SwiftDump/Dumper/ClassDumper.swift:57`）在类头前加 `@Observation.Observable`。
- CLI 与 Kit：`InterfaceRequest.expandsMacros`、`interface --expand-macros`，以及 `AgentPlugins/swift-section` 的 skill。

明确不动的地方：`fields` / `variables` / `functions` 保持二进制里的原样，ABI diff、snapshot、evolution 的记录不变；diff 与 evolution 的 interface 一律印展开形态（它们比较的是 ABI 事实）；property wrapper 的还原不变；不涉及 swift-demangling 与 swift-semantic-string。

### 识别规则

在 Ultra 上用 Swift 6.4.2 编了探针（debug、release、release 加 `strip -x` 三种），规则按实测定：

- 必须是 class，并且有一个名叫 `_$observationRegistrar`、类型正是 `Observation.ObservationRegistrar` 的存储字段。字段记录在剥掉符号之后仍在，所以剥过的二进制同样认得出。
- 有 `_$backingData` 字段的不算：SwiftData 的 `@Model` 也生成同名同类型的 registrar 字段（探针实测），它要另作识别，不在本提案内。
- 不要求有 `Observation.Observable` 的 conformance record：一个 `@Observable` 类继承另一个 `@Observable` 类时，宏不再生成 conformance（实测子类没有这条记录）。

### 被跟踪的属性怎么认

每个存储字段 `_x`（`var`，名字不以 `_$` 开头，没被 property wrapper 还原认领）按下面的证据认作属性 `x` 的存储：

1. 类型里有成员变量 `x`，类型与 `_x` 相同，并且有 setter 或 modify：来源记为 `declaredMember`。
2. `x` 的 accessor 被剥掉了：从 `_x` 合成 `var x: T`，来源记为 `synthesized`，打印时照 property wrapper 合成的先例在上方加一行 note 注释，写明是从存储字段 `_x` 合成的。实测有一条额外证据可用：被跟踪属性的初始值表达式符号挂在 `x` 名下（`variable initialization expression of Model.count`），手写的存储属性挂在自己名下（`… of Model._cache`），并且 public 类的这类符号剥过之后还在。`_x` 自己有初始值表达式符号时，它就是手写的存储属性，不认。
3. 剩下的唯一误判：类是 internal、符号全部剥掉、又有一个用 `@ObservationIgnored` 声明且名字以下划线开头的 `var _y`，它会被读成被跟踪的 `y`。note 注释里写着 `_y`，读者看得到原始字段名。

其余存储的 `var`（`@ObservationIgnored` 声明的）在折叠形态里加上 `@Observation.ObservationIgnored`：不加的话，读者分不出哪些属性被跟踪。`let` 不加，宏本来就不跟踪它。

### 折叠形态长什么样

```swift
@Observation.Observable
class InternalModel {
    var value: Swift.Int
    var optionalText: Swift.String?
    @Observation.ObservationIgnored var cacheHits: Swift.Int
    let constant: Swift.Int

    init()

    deinit
}
```

- 被跟踪的属性印在 `_x` 的位置，也就是源码里的位置；`_x` 的字段偏移与布局注释照旧挂在它上面（那就是它的存储）。
- 不印：`_$observationRegistrar`、`declaredMember` 来源的 computed `x`、宏生成的 `access(keyPath:)`、`withMutation(keyPath:_:)`、`shouldNotifyObservers(_:_:)`，以及宏生成的 `Observation.Observable` conformance（extension 里没有别的内容时整个 extension 不印）。
- 宏与属性名按节点打印，module selector 照常生效（`@Observation::Observable`），不拼字符串。
- `marksOptionalContent` 打开时两种形态都印：折叠的内容在 `.disabled(expandsMacros)` 区域里，展开的内容在 `.enabled(expandsMacros)` 区域里，按任一取值投影都与直接用该取值打印逐字节相同。RuntimeViewer 用这个在两种形态之间切换而不必重印，展开的那部分就是被折叠的成员。

### API

宿主的调用点：

```swift
// 侧边栏：prepare() 之后就能读，不需要先索引这个类型。
if typeDefinition.attachedMacros.contains(.observable) {
    properties.insert(.isObservable)
}

// interface：默认折叠；要看二进制里的展开就打开。
configuration.expandsMacros = true
```

- `public struct SwiftAttachedMacro: Hashable, Sendable`：`static let observable`，带 `name` 与 `moduleName`。用 struct 加静态成员而不用 enum，以后识别 `@Model` 之类不会破坏下游的穷举 `switch`。
- `TypeDefinition.attachedMacros: Set<SwiftAttachedMacro>`：构造时算出，和 `exportStatus` 一样在 `prepare()` 返回时就有。
- `TypeDefinition.observableMacroExpansion: ObservableMacroExpansion?`：`index(in:)` 之后才有，列出被跟踪的属性（`name`、`backingFieldName`、`origin`）、加 `@ObservationIgnored` 的存储属性和宏生成的方法。
- `ExtensionDefinition.generatingMacro: SwiftAttachedMacro?`：这个 extension 是哪个宏生成的；宿主把 extension 当独立对象显示时，凭它在折叠形态里隐藏。
- `SwiftDeclarationPrintConfiguration.expandsMacros: Bool = false`、`SwiftVisibilityOption.expandsMacros`、`InterfaceRequest.expandsMacros`、CLI `interface --expand-macros`。关掉折叠（`expandsMacros = true`）时输出与今天逐字节相同。

### dump

dump 照旧印出二进制里的全部成员，只在类头前加 `@Observation.Observable`，与 `@objc @implementation` 类在 dump 里的写法一致。

### 测试与验证

- 新的现场编译 fixture `ObservableMacroFixture`（照 `ClassesWithoutClassObjectsFixture` 的写法），三个变体：debug、release、release 加 `strip -x`；覆盖 final、open、internal、子类、泛型、带 property wrapper 的类，一个只手写 conformance 的类，以及一个手写出 `_$backingData` 与 registrar 字段、代替 `@Model` 的类。
- 断言：识别结果、每个变体的折叠与展开输出、`marksOptionalContent` 下两种投影与直接打印逐字节相同、dump 类头、CLI 开关、Kit 字段。
- 渲染 A/B：候选侧加 `--expand-macros` 的 interface 应与基线逐字节相同；dump 的差异只能是 `@Observable` 类的类头行，逐条核对。测试与 A/B 都在 Ultra 上跑。

### 发版

RuntimeViewer 的 release 构建按版本解析，要等本库发版。`next` 上 existential-any 用了 swift-demangling 未发布的选项，所以顺序是先发 swift-demangling，再发本库（带上这两项）。

### 落地步骤

每一步单独构建通过、相关测试通过后提交并推送；测试在 Ultra 上跑。

1. [ ] 识别与模型标记：`ObservableMacroRecognition`、`SwiftAttachedMacro`、`TypeDefinition.attachedMacros`（含 specialization 沿用）、`ExtensionDefinition.generatingMacro`；新 fixture `ObservableMacroFixture` 与识别的测试。
2. [ ] 索引期的展开分析：`ObservableMacroExpansion`、`TypeDefinition.observableMacroExpansion`；三个变体下被跟踪属性、来源、`@ObservationIgnored` 属性与生成方法的测试。
3. [ ] interface 折叠：`expandsMacros`、`SwiftVisibilityOption.expandsMacros`、类型头属性、字段块与成员块、导出过滤、conformance extension、`marksOptionalContent` 下的两种形态；输出与投影一致性的测试。
4. [ ] dump 类头的 `@Observation.Observable` 与测试。
5. [ ] `InterfaceRequest.expandsMacros`、`interface --expand-macros`、`AgentPlugins/swift-section` 的 skill，以及两侧的测试。
6. [ ] 文档（模块文档、演进账本、术语表、`AGENTS.md` 与文档索引按需）、全量测试与渲染 A/B。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-11-11 | Created as Draft | RuntimeViewer 要在侧边栏标出 `@Observable` 类，并在 interface 里提供折叠与展开两种形态，请本库识别这个宏 |
| 2026-11-11 | 识别结果在构造时算出，不等 `index(in:)` | RuntimeViewer 的侧边栏在索引任何类型之前就建好，与 `exportStatus` 的情形相同 |
| 2026-11-11 | 有 `_$backingData` 的类不认作 `@Observable` | SwiftData 的 `@Model` 生成同名同类型的 registrar 字段（探针实测） |
| 2026-11-11 | 关掉折叠时输出与今天逐字节相同，类头也不加属性 | 与 `usesExistentialAny`、`usesModuleSelectors` 的先例一致，A/B 能用它做逐字节对照 |
| 2026-11-11 | accessor 被剥掉时也合成被跟踪的属性，上方加 note 注释 | 剥过符号的 App 里 internal 的 view model 是常态；先例是 property wrapper 的合成，note 写明来源字段 |
| 2026-11-11 | interface 默认折叠 | 用户选定：interface 的目标是读起来像源码，要看二进制里的展开就加 `--expand-macros` |
| 2026-11-11 | 用户批准，开始实现；补上落地步骤 | 精简提案原本没有分步，按方案拆成六步，每步能单独构建与验证 |
