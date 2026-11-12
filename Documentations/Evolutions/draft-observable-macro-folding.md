# Draft - 识别 `@Observable` 宏：interface 默认折叠它的展开

- **状态**: In Progress
- **创建日期**: 2026-11-11
- **最后更新**: 2026-11-12
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

每个存储字段 `_x`（`var`，名字不以 `_$` 开头，没被 property wrapper 还原认领）先排除一种情况：类型里有成员变量 `x`、但类型与 `_x` 不同（`weak` 之类的引用存储先剥掉再比），那 `_x` 存的就不是 `x`。其余的依次看下面的证据，第一条成立的为准；每个被跟踪的属性都记下认定它的证据（`ObservableMacroExpansion.TrackedProperty.Evidence`）：

1. `x` 有 init accessor（`Model.count.init`）：只有被宏挪走存储的属性才有。
2. 镜像里的成员变量 `x` 有 setter 或 `_modify`，类型与 `_x` 相同。
3. `_x` 自己有初始值表达式（`variable initialization expression of Model._cache`）：它是手写的存储属性，不认。
4. 初始值表达式挂在 `x` 名下（`… of Model.count`）：源码把初始值写在 `x` 上，宏只挪走了存储。
5. `_x` 有自己的 accessor 而 `x` 一个都没有：宏的存储与它的 computed 属性要么一起被 vtable 留住，要么一起被剥掉，所以这是手写的存储属性，不认。
6. 都没有：只凭存储字段名认作被跟踪，证据记为 `backingFieldName`。

带本地符号也不能当作「缺了就是没有」：系统框架链接时 dead-strip，没人引用的 init accessor、final 类 internal 属性的 accessor 都会被去掉（SwiftUI 实测，fixture 用 `-dead_strip` 变体复现）。剩下的误判只有一种：用 `@ObservationIgnored` 声明、名字以下划线开头的 `var _y`，镜像里既没有它自己的初始值表达式、也没有它自己的 accessor 时，会被读成被跟踪的 `y`。初始值表达式只在前两条都不成立时才按类型查一次。

成员变量 `x` 在镜像里时来源记为 `declaredMember`，否则记为 `synthesized`：从 `_x` 合成 `var x: T`，打印时照 property wrapper 合成的先例在上方加一行 note 注释，写明是从存储字段 `_x` 合成的。

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

### 宿主的内联展开

RuntimeViewer 要像 Xcode 的 Expand Macro 那样，在 `@Observation.Observable` 那一行下面单独显示宏生成的声明。为此再加两样，打印规则仍只在本库一处：

```swift
// 宏生成的声明成块打印：成员在类型成员的缩进上，extension 在类型自己的缩进上。
let expansion = try await printer.printMacroExpansion(of: .observable, attachedTo: typeDefinition)

// 折叠形态里给宏属性打上定位标记，separatingAnnotationRegions() 读回。
configuration.marksAttachedMacros = true
// region.kind == .attachedMacro(.observable)
```

- `SwiftDeclarationPrinter.printMacroExpansion(of:attachedTo:level:)`：印出 registrar、每个被跟踪属性的存储 `_x`、镜像里还有 accessor 的 computed `x`、`access(keyPath:)`、`withMutation(keyPath:_:)`、镜像里留下的 `shouldNotifyObservers(_:_:)`，最后是 `extension X: Observation.Observable {}`。每条声明带着展开形态里同样的注释，用的是同一套成员打印代码；导出过滤照常生效。类型没带这个宏时印出空串。
- `SwiftDeclarationPrintConfiguration.marksAttachedMacros`：折叠形态里每个宏属性包在 `AnnotationRegion` 里，种类是 `AnnotationRegion.Kind.attachedMacro(_:)`（`attachedMacro.Observation.Observable`），一个宏一个种类，宿主不必读文字就知道是哪个宏。默认关，关着时输出逐字节不变。
- `SwiftDeclarationPrinter.printMacroExpansionParts(of:attachedTo:)`：照 Xcode 展开 attached macro 的位置把展开拆成几块（`MacroExpansionPart`），每块不带自身缩进、首尾不带换行：每个被跟踪属性一块，放在它折叠出的声明下方，先是镜像里 computed 属性的 accessor 块（剥掉了就没有），再是存储 `_x`；registrar 与生成的方法一块，放在类型闭合括号上方；生成的 conformance 一块，放在闭合括号下方。`marksAttachedMacros` 打开时，每个被跟踪属性折叠出的声明包在 `AnnotationRegion.Kind.attachedMacroTrackedProperty(_:named:)` 的区域里，`MacroExpansionPart.anchorKind` 与它相等；闭合括号不另做标记，它是类型 `DefinitionRegion` 的最后一行（或打印的那个定义的最后一行），不必改 swift-semantic-string。

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

1. [x] 识别与模型标记：`ObservableMacroRecognition`、`SwiftAttachedMacro`、`TypeDefinition.attachedMacros`（含 specialization 沿用）、`ExtensionDefinition.generatingMacro`；新 fixture `ObservableMacroFixture` 与识别的测试。
2. [x] 索引期的展开分析：`ObservableMacroExpansion`、`TypeDefinition.observableMacroExpansion`；三个变体下被跟踪属性、来源、`@ObservationIgnored` 属性与生成方法的测试。
3. [x] interface 折叠：`expandsMacros`、`SwiftVisibilityOption.expandsMacros`、类型头属性、字段块与成员块、导出过滤、conformance extension、`marksOptionalContent` 下的两种形态，以及 `printMacroExpansion(of:attachedTo:level:)` 与 `marksAttachedMacros`；输出与投影一致性的测试。
4. [x] dump 类头的 `@Observation.Observable` 与测试。
5. [x] `InterfaceRequest.expandsMacros`、`interface --expand-macros`、`AgentPlugins/swift-section` 的 skill，以及两侧的测试。
6. [x] 文档（模块文档、术语表、`AGENTS.md`、A/B 流程；演进账本一节与文档索引留到正式收尾）、全量测试与渲染 A/B。

### 验证

在 JHs-Mac-Studio-Ultra（macOS 27.2、Xcode 26.6）的沙盒里跑，swift-demangling 用它 `next` 的 8809c1b 作本地兄弟依赖（existential-any 的选项还没发版）。

- 全量测试：2879 个测试、548 个套件，只剩 `FileMappingTests.readersOfOneCacheFileShareOneMapping` 一条；分支起点上跑全量同样只这一条失败，是基线已有的。
- 全量中途暴露并修好的两件事：`TypeDefinition` 实例大小超过提案 0002 的守卫（456 > 448，展开描述改为装箱，回到 440）；fixture 在静态初始化里同步编四个变体，编译期间占住协作线程（改为在独立线程编译、访问器改成 async）。当时把 `BoundedConcurrentMapTests` 的一分钟时限超时也归到它头上，后来查明这条在没有本分支改动的全量里也会超时，见下一条。
- 分块的展开（`printMacroExpansionParts`）加入后再跑全量：2884 个测试，三条失败，都不是本次引入的。`FileMappingTests` 是基线已有的。`BoundedConcurrentMapTests.cancellationStopsSubmittingPendingElements` 的时限超时在 Ultra 上其他会话不含本分支的全量里也出现过（2026-11-11 的两次）。`SharedCacheTests.differentKeysParallelViaAsyncLet` 要两个 detached task 在 30 秒内同时拿到协作线程，而 Ultra 的全量自始至终占满协作线程池，排在前面的测试都要等 800 秒以上才结束。这两条在日志里都是在任何新测试开始之前就已经失败的，分块的代码也只在新测试里执行。
- 渲染 A/B（96 对，基线是分支起点，候选侧加 `--expand-macros` 与 `RV_OPTS` 的 `expandsMacros`）：interface 全部逐字节一致；dump 有 10 对不同，去掉 `@Observation.Observable ` 前缀后都逐字节一致，进程内一侧标出 SwiftUI、SwiftUICore、SwiftData 共 28 个类。A/B 跑在 dead-strip 修复之前的提交上；之后的改动只动折叠形态（A/B 里关着）、只在 `marksAttachedMacros` 打开时才有的标记、新加的分块 API 和测试支持代码，展开形态与 dump 不受影响，没有重跑。
- 真实框架：用修复后的 CLI 渲染 macOS 27.2 的 SwiftUI，`Immersion`、`WindowVisibilityState`、`SearchEnvironmentStorage` 等都折叠对了；剩下印 `@Observation.ObservationIgnored var _x` 的都是手写写法（存储与同名属性类型不同，或同名的是方法）。

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
| 2026-11-11 | 带本地符号的镜像只认 init accessor；剥过符号的镜像依次看导出的 accessor、初始值表达式、存储字段名，每个属性记下证据 | 探针实测 debug 与 release 都保留每个被跟踪属性的 init accessor；手写的 `_y` 在这样的镜像里没有 `y` 的 init accessor，不会误认。只有全剥的 internal 类才需要推断 |
| 2026-11-11 | 加入展开块的打印与宏属性的定位标记 | RuntimeViewer 要做 Xcode 式的内联展开，用户批准把这两项加进本提案；由本库打印，宿主不必再写一遍打印规则 |
| 2026-11-11 | 嵌套类型的宏属性靠 `marksNestedDefinitions` 对应到定义：最内层的 `DefinitionRegion` 就是它的类型，不另加 API | 一次打印会内联嵌套类型，宿主要知道每个属性区域属于哪个定义；类型的属性行本来就印在它自己的定义区域里，复用现成机制比复刻打印顺序可靠 |
| 2026-11-11 | 折叠出的 `var x` 用 computed `x` 的 `final`、导出结论与 accessor 注释（vtable 槽位、地址），字段的偏移与布局注释照旧 | 存储字段 `_x` 是 private，它的 `final` 与导出结论说的是存储，不是属性；`x` 的槽位与代码地址才是宿主要找的入口 |
| 2026-11-11 | `@Observation.Observable` 从 `Observation.Observable` 协议的名字节点打印，`@Observation.ObservationIgnored` 从结构体节点打印；两者都是静态节点 | 打印器按节点身份缓存片段，节点要活过打印；协议节点不会被写上 `any`，属性还能链到同名协议 |
| 2026-11-11 | 展开块一行一条声明、不留空行，交给 `Rows` 组合 | 每条声明自带缩进，`Rows` 按两侧是否可见放换行，标记打印投影后也不会多出空行或首尾换行 |
| 2026-11-11 | 标记打印里，只属于展开形态的声明在「类型体最后一个换行」的判断里算作可能看不见 | 投影到折叠形态加只印导出时，嵌套类型之后可能什么都不剩，闭合括号会粘成 `}}`；与导出过滤用同一个机制处理 |
| 2026-11-11 | dump 只在类头加属性，不加关闭开关；渲染 A/B 的进程内一侧加 `RV_OPTS` 的 `expandsMacros` | dump 以信息最大化为目标，A/B 里它的差异只有类头行，人工核对；interface 有 `--expand-macros`，进程内一侧照样需要能关掉折叠 |
| 2026-11-11 | 证据规则不再按镜像有没有本地符号分流：init accessor、成员的 setter 或 `_modify`、挂在 `x` 名下的初始值表达式在任何镜像里都算，只有 `_x` 自己的初始值表达式、或 `_x` 有 accessor 而 `x` 没有，才把它排除 | 用修好的 CLI 渲染真实 SwiftUI 时发现 `Immersion` 等类没折叠对：SwiftUI 带本地符号，但 dead-strip 去掉了 init accessor，旧规则把 `_amount` 读成手写字段。fixture 加 `-dead_strip` 变体复现，修复前的 CLI 在它上面错得一样 |
| 2026-11-11 | fixture 改在独立线程编译，访问器改成 async | 几个套件同时要 fixture 时，同步编译占住多条协作线程，全量里 `BoundedConcurrentMapTests` 两次超时，分支起点上没有；改后全量通过 |
| 2026-11-11 | 实现完成，待用户看过后收尾 | 文档：模块文档（SwiftDeclaration、SwiftInterface）写实现说明，术语表登记 macro folding，插件 skill 写 CLI 用法；不另写使用指南，CLI 的 `--help` 与 skill 已够；演进账本一节、取号与文档索引留给正式收尾 |
| 2026-11-12 | 加入分块的展开 `printMacroExpansionParts` 与被跟踪属性的定位标记；闭合括号用类型的定义区域定位 | RuntimeViewer 改为 Xcode 式的分散展开，用户批准在正式收尾前加上；给 `DeclarationBlock` 的闭合括号打标记要改 swift-semantic-string 并先发版，类型的定义区域已经给出它的范围 |
| 2026-11-12 | 分块里属性的 accessor 块单独打印，由测试逐行对照展开形态的同一块 | 分块要的是不带声明头的块，变量打印器只会连声明一起印；init accessor 提案正在给展开形态的块加 `init` 一行，对照测试保证分块跟着加，而不是悄悄少一行 |
| 2026-11-12 | 更正 2026-11-11 那一行：`BoundedConcurrentMapTests` 的超时不是 fixture 同步编译造成的，独立线程编译照旧保留 | Ultra 上其他会话不含本分支的全量里这条也超时；同步编译占住协作线程是真问题，但当时「改后全量通过」只是一次运气 |
| 2026-11-12 | 比对 `_x` 与 `x` 的类型照旧用 getter 的符号，不改读 init accessor 的符号 | init accessor 会话发现 getter 被 `@_silgen_name` 钉成旧 mangling 时类型会对不上（SwiftUICore 的 `_GeometryActionModifier2.value` 少了 `@Sendable`）；被跟踪属性的 accessor 由宏生成，加不了这个属性，真实框架的 A/B 里也没遇到；真遇上时只是这个属性不折叠，不会印错 |
| 2026-11-12 | 「关掉折叠时输出逐字节不变」以本提案之前的输出为准 | init accessor 提案（draft-init-accessor-recovery）让展开形态里每个被跟踪属性的 accessor 块多印 `@storageRestrictions(initializes: _x) init` 一行，分块里的块跟着印；那一行是那份提案带来的变化 |
