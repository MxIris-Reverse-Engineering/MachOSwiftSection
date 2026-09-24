# Specialized Interface Bound Rendering Restoration

恢复 interface 打印路径对「用户驱动特化（specialized）定义」的绑定渲染：头部打印绑定名
（`Box<Int>` 而非 `Box<A> where A: …`），字段类型经特化 metadata 替换（`let value: Int`
而非 `let value: A`）。

## 动机：一次由 leaf 迁移引入的回归

`aa233bc`（"refactor(swift): extract SwiftDeclarationRendering, make SwiftDump a leaf"，
首发 0.12.0-beta.6）把 interface 打印从「实例化 SwiftDump dumper」改为 SwiftPrinting
自渲染（model-driven）。旧路径中特化定义的替换机制全部长在 `TypedDumper` 上
（`boundDumpedMetatype` / `fieldDemangledTypeNode` / `resolveBoundDumpedTypeName`），
随 SwiftDump 变成 leaf 后 interface 路径不再经过它们，于是：

- 头部退化为 unbound 形式——[LeafMigrationPlan.md](LeafMigrationPlan.md) 的
  as-shipped deviations 里承认了这一点（"renders with an **unbound** header … Not
  exercised by tests"）；
- 字段替换实际上也一并丢失——plan 里 "fields still substitute" 的说法与实际不符：
  为字段设计的 `FieldDefinition.substitutedTypeNode` 方案从未落地（`git log -S` 只在
  文档中出现），字段节点始终来自 `FieldRecord.demangledTypeNode(in:)` 的原始字节
  demangle。仍在替换的只有 layout 注释引擎（`RuntimeFieldLayoutBackend`），造成
  「注释正确、正文错误」的反差（RuntimeViewer 用户报告的现象：
  `RawCodable<NSVerticalDirection>` 节点正文仍是 `struct RawCodable<A> where …` +
  `var wrappedValue: A`，而 `// Type Layout` 已是特化布局）。

RuntimeViewer 侧 v2.1.0-beta.1 ~ beta.7（对应上游 ≤ 0.12.0-beta.5）行为正常，
beta.8/beta.9 吃进 0.12.0-beta.6+ 后受影响。

## 方案：把旧机制镜像到 SwiftDump 之外

约束：SwiftPrinting 不允许依赖 SwiftDump（leaf 迁移的核心成果），因此不是「把 dumper
接回来」，而是把替换机制下沉到两条路径共享的 `SwiftDeclarationRendering`：

1. **`BoundDumpedTypeNameRenderer` 下移**（`SwiftDump/Protocols/TypedDumper.swift` →
   `SwiftDeclarationRendering/BoundDumpedTypeNameRenderer.swift`，逐字搬移）。它只依赖
   `DemangleResolver`，本就与 dumper 状态无关；`TypedDumper.resolveBoundDumpedTypeName`
   继续转发到它，dump 路径零变化。既有直测该 enum 的
   `SwiftDumpTests/BoundDumpedTypeNameRendererTests` 已 `import SwiftDeclarationRendering`，
   无需改动。
2. **新增 `SpecializedMetadataNodeSubstitution`**（SwiftDeclarationRendering）——旧
   `TypedDumper` 替换成员的 `MetadataWrapper` 版镜像：
   - `boundTypeNode(for:)`：metadata 指针 bitcast 成 `Any.Type` →
     `_mangledTypeName` → demangle，得到绑定形式的类型节点
     （旧 `boundDumpedMetatype()` + `boundDumpedTypeNode()`）；
   - `substitutedFieldTypeNode(for:metadata:in:)`：
     `RuntimeFunctions.getTypeByMangledNameInContext(_:specializedFrom:in:)` 解析字段
     mangled name → `_mangledTypeName` → demangle（旧 `resolveFieldMetatype` +
     `fieldDemangledTypeNode` 的 specialized 分支；value/class metadata 两个受限实现
     本就相同，收敛为对 wrapper 的 case 分派，与
     `RuntimeFieldLayoutBackend.resolveFieldMetatype` 同型）。
3. **SwiftPrinting 接线**：
   - `printTypeDefinition` 在 `isSpecialized` 时把 `typeDefinition.metadata` 传给
     `renderTypeDeclarationHeader(…, specializedMetadata:)`；有 bound 节点时头部改走
     `BoundDumpedTypeNameRenderer.render`，并跳过泛型签名子句（否则会打出
     `Box<Int><A: Hashable>`）、保留 invertible-protocol 标记与 class 的 superclass
     段——与旧 `StructDumper`/`EnumDumper`/`ClassDumper.declaration` 的 `isBound`
     分支逐一对应；
   - `renderModelFields` 对每条 field record 尝试
     `substitutedFieldTypeNode`，结果经 `printField` / `printEnumCase` 新增的
     `substitutedTypeNode` 覆盖参数生效；`nil`（runtime 解析失败、非
     `MachOImage`、旧 runtime 无 `_mangledTypeName`）逐字段回退 unbound 节点——
     与旧 dumper 完全一致的 best-effort 契约。

### 为什么是 metadata 驱动而不是静态节点替换

特化时的 `typeArgumentNodesByParameter` 理论上可以做纯语法的 τ_0_0 → 实参节点替换
（`GenericArgumentEnvironment` 思路），但 runtime 驱动是重构前的原始行为，且强于
静态替换：`A.RawValue` 这类 `dependentMemberType` 引用由 runtime 按 conformance
witness 解析为最终具体类型，静态替换只能得到 `Int.RawValue` 形式。本次目标是
「恢复重构前逻辑」，故原样镜像 runtime 方案。

## 影响面

- 头部/字段绑定渲染只在 `isSpecialized && metadata != nil` 时激活；普通（未特化）
  定义、diff 渲染器（`renderTypeDeclarationHeader` / `printField` 新参数均有默认值）、
  dump 路径（机制原样保留在 `TypedDumper`，仅 enum 搬家）行为不变。
- 消费方 RuntimeViewer 无需改动：`RuntimeSwiftSection` 一直调用
  `printer.printTypeDefinition(specializedDefinition)`，变化全部发生在库内。

## 测试

`SwiftSpecializationTests.GenericTypeNameSubstitutionEndToEndTests` 新增
"specialized definition prints a bound header and substituted field types"：对
`TestUnconstrainedStruct<A>` 特化到 `Int` 后打印，断言含
`TestUnconstrainedStruct<Swift.Int>` 与 `let a: Swift.Int`、不含 `<A>` 与 `where`——
钉住 leaf 迁移时 "Not exercised by tests" 的缺口。全量回归：SwiftPrintingTests /
SwiftDumpTests / SwiftSpecializationTests / SwiftInterfaceTests / SwiftDiffingTests
全绿。

## 私有类型的运行时名字（2026-09-23）

RuntimeViewer 报告：macOS 26.7 上把 AppKit 的 `WindowPortal<A>` 特化成 `WindowPortal<AppKit.ButtonContent>`，头部打成 `struct .WindowPortal<AppKit.ButtonContent>`。对方随后扫了 AppKit 里全部 102 个能特化的泛型类型，同一个原因有三种表现：

- 名字开头多一个点（16 例），例如 `class ._NSLayerView<CGDrawingLayer>: __C.NSView`。
- 私有的嵌套类型丢掉整条父链：`enum .Phase`，离线名字是 `AppKit.InProcessAnimation.Bridged.Phase`。
- 私有类型当泛型实参时丢模块名：`<AXPocketMode>`，而非私有类型是 `<AppKit.ButtonContent>`。

### 根因

特化后的名字全部来自运行时：`_mangledTypeName` → `swift_getMangledTypeName` → `_swift_buildDemanglingForMetadata`。编译器把每个最外层的 `private` / `fileprivate` 类型挂在一个 anonymous context 描述符下面（`lib/IRGen/GenDecl.cpp` 的 `getAddrOfParentContextDescriptor`："Wrap up private types in an anonymous context for the containing file unit so that the runtime knows they have unstable identity"；RuntimeViewer 会话的探针统计，AppKit 26.7 的 879 个 Swift 类型里有 227 个挂在 anonymous context 下）。运行时拼名字时对 anonymous context 没有更多信息，就用描述符地址充当名字：`AnonymousContext("$<地址>", <父上下文>, TypeList())`（`stdlib/public/runtime/Demangle.cpp` 的 `_buildDemanglingForContext`，注释自称 "unstable mangling"）。

这个节点到了打印器：

- interface 打印器没有它的分支，整棵子树连同里面的 `Module` 都打成空串。`BoundDumpedTypeNameRenderer` 的 `.structure` / `.class` / `.enum` 分支又无条件在父节点后面写 `.`，于是名字开头多一个点。`TypeNodePrintable.printType`（字段类型、泛型实参走这里）只在父节点真的写出内容时才写分隔符，所以那里没有点，但模块和外层类型一起丢了。
- dump 路径用的是 Demangling 自带的打印器：`DemangleOptions.default` 下打成 `Module.(unknown context at $600001234)`，`.interface` 选项下同样打成空。

离线命名从来不会遇到这个节点：`SymbolicDemangler.buildContextDescriptorMangling` 遇到 anonymous context 时，查得到它的符号就还原成 `privateDeclName`（interface 打印器只打名字本身），查不到就跳过、直接用父上下文。dyld shared cache 里没有本地符号，所以 AppKit 这类镜像永远是后者。（2026-09-24 起不再如此：shared cache 保留着 `_symbolic` 符号，离线命名从中还原鉴别符，见下文「私有鉴别符」。）

### 修复

- 新增 `SwiftDeclarationRendering/RuntimeTypeNameDemangling.swift`。`node(forMetatype:)` 是库里把运行时 metatype 变成节点的唯一入口：`_mangledTypeName` → `demangleAsNodeTransient` → 把每个 anonymous context 换成它的父节点（child 1），结果与离线命名在 shared cache 里得到的一致。demangler 对同一个 substitution 的每次 back-reference 返回同一个实例，树其实是 DAG，所以替换过程按对象身份 memoize；不含 anonymous context 的子树原样返回同一个实例。
- 五处调用点全部改走它：`SpecializedMetadataNodeSubstitution`（interface 的头部与字段类型）、`TypedDumper`（dump 的头部与字段类型，原先是逐字重复的一份实现）、`RuntimeFieldLayoutBackend`（布局注释里 `.type` 泛型实参与 pack 元素，此前打出 `(unknown context at $…)`）、`InProcessAccessorFunctionResolution`（进程内求 kind-9 witness）。Sources 里现在只有这个文件直接调用 `_mangledTypeName`，新增的运行时名字来源也必须走它。
- `BoundDumpedTypeNameRenderer`：父节点渲染为空时不再写分隔符，与 `TypeNodePrintable.printType` 同一规则。它兜住的是解析器拼不出来的上下文；extension context 在第二批修好之前就是这种情况，见下文。

为什么不给 interface 打印器加一个 `.anonymousContext` 分支：那样只修了 interface 打印器，dump 与布局注释用的 Demangling 打印器照样打出 `(unknown context at $…)`；而且地址本身没有任何值得打印的信息，在源头去掉比让每个打印器各自忽略更一致。

为什么不自己实现 `_mangledTypeName`：讨论过，可行——ABI 模型能读运行时处理的全部 metadata 种类，`SymbolicDemangler` 能从描述符拼出上下文名。但这等于移植约 700 行 C++（`_swift_buildDemanglingForMetadata`，加上从同型约束反推非 key 泛型参数的 `_gatherWrittenGenericParameters`），之后每个 Swift 版本新增的函数类型标志都要跟进；而对 interface 输出，结果与「保留 `_mangledTypeName` + 去掉 anonymous context」一字不差。留待以后单独立项。

### 私有鉴别符（2026-09-24）

上面「换成父节点」的依据是「与离线命名在 shared cache 里一致」，而离线命名在 shared cache 里拿不到鉴别符的前提并不成立。编译器为每条带 symbolic reference 的 mangled name 生成一个符号（`IRGenMangler::mangleSymbolNameForSymbolicMangling`）：`symbolic `、把每个 5 字节引用写成 `_____` 的名字、再按引用顺序逐个跟上被引用者的完整 context mangling，鉴别符就在后者里——例如 `_symbolic _____ 6AppKit24FontPanelBIUSPopUpButton33_05EA0EB8E781FFE22747790FC22932B1LLC`。这类符号在 shared cache 里保留着。有字段描述符的类型一定有一个：字段描述符里记的自身类型名就是指向它自己的引用。

它挂在 `__swift5_typeref` 里那条 mangled name 上，不在任何描述符上，所以「按匿名上下文的偏移查符号」查不到（AppKit 实测：匿名上下文 19820636、类描述符 19820644，都没有符号；`_symbolic` 符号在 19757510）。`AnonymousContextPrivateDiscriminatorIndex`（`SwiftInspection`）因此走引用：逐个 `_symbolic` 符号解析它标的那条 mangled name，沿直接 context 引用（`0x01`）到达被引用的描述符，父级若是 anonymous context，就记下被引用者名字里 `privateDeclName` 的鉴别符（要求其中的名字与描述符名字一致）。按镜像惰性构建，与 demangle memo 一起驱逐。

两条路径用同一个查询：

- 离线：`SymbolicDemangler` 的 `.anonymous` 分支先查 anonymous descriptor 上的符号，查不到再查这张表，两者都没有才跳过。
- 运行时：`RuntimeTypeNameDemangling` 用 `AnonymousContext` 里的地址查同一张表，查到就把其中的类型改写成 `privateDeclName`，查不到才换成父节点。于是同一个类型从描述符和从运行时得到同一个节点。

interface 打印器不打鉴别符，interface 输出不变；`dump` 与布局注释用的默认 demangle 选项含 `.showPrivateDiscriminators`，系统镜像里的 private 类型、以及运行时来源的 private 泛型实参，开始打出 `(Name in _…)`，与带符号的镜像里按描述符解出的名字一致（用户确认保持一致，而不是在注释里去掉鉴别符）。同名的 private 类型也不再撞名：AppKit 两个文件里各有一个 `TextFieldContentBounds`，以前 interface 按名字合并时丢了一个。以 `mangleAsString(node)` 为键的消费方（RuntimeViewer 的 `RuntimeObject.name`、ABI snapshot 的类型键）对 private 类型的键会变。

### extension context（同日第二批）

类型声明在另一个模块的类型的 extension 里时（`extension NSView { enum Invalidations { … } }`），父上下文是 extension context，名字里是 `Extension(<扩展所在的模块>, <被扩展的类型>, <泛型签名>?)`。离线命名（`SymbolicDemangler`）和运行时的名字都带这个节点，所以它和运行时名字无关，离线 interface 里也一直错：interface 打印器没有它的分支、打成空，每个引用都丢了被扩展的类型——macOS 26.5.2 的 AppKit 导出里写的就是 `Invalidations.Tuple<A1, B1>`，缺 `NSView.`。第一批之后特化头部只是不再带开头的点（`struct Tuple<…>`）；RuntimeViewer 的扫描里有 4 例：`NSView.Invalidating`、`NSView.Invalidations.Tuple`、`NSViewController.ViewLoading`、`NSWindowController.WindowLoading`。

修复：`TypeNodePrintable.printNameInType` 加一个 `.extension` 分支，打印它的 child 1，也就是被扩展的类型——Demangling 自带的打印器也是这么做的，只是前面多一个 textual interface 写不出来的 `(extension in <模块>):`。被扩展的类型走普通的类型引用路径，所以 `__C` 类会按 C 导入模块的解析规则打印，也各自是一段可跳转的类型引用。

放在分派器而不是 `printType` 里，是因为 extension 节点还有第二个入口：`BoundDumpedTypeNameRenderer` 把父上下文单独交给解析器渲染，不经过 `printType`。分派器加分支不会波及别处：成员声明的打印器（函数、变量、下标）只取标识符和类型子节点，从不打印第 0 个子节点（上下文），所以 extension 节点只会以「类型的上下文」身份进来。dump 路径不受影响：它用的 Demangling 打印器本来就打出 `(extension in AppKit):__C.NSView.Invalidations.Display`。

### 测试

- `SwiftSpecializationTests/SpecializedRuntimeTypeNameTests`（6 条，走 RuntimeViewer 用的 `printTypeDefinition`）：私有泛型类型的头部；嵌在普通类型里的私有类型（anonymous context 在链中间）；私有类型作泛型实参，头部与字段各一条；展开字段偏移注释里的私有实参；跨模块 extension 里的类型（第一批断言不再以点开头，第二批改为断言完整头部 `struct Swift.Int.RuntimeNamedExtensionBox<Swift.Int> {`）。
- `MachOSwiftSectionTests/SpecializedDumperFieldTypeTests.specializedPrivateStructDeclarationKeepsItsModule`：dump 路径的头部。
- 第一批修复前以上 7 条全红，症状与报告一致：`struct .RuntimeNamedPrivateBox<Swift.Int> {`、`struct .RuntimeNamedPrivateNestedBox<Swift.Int> {`、`<RuntimeNamedPrivateArgument>`、`element (SwiftSpecializationTests.(unknown context at $110c34ea0).RuntimeNamedPrivateArgument)`、`struct .RuntimeNamedExtensionBox<Swift.Int> {`；修复后全绿。
- 进程内 kind-9 witness 那一处没有专门的测试：在测试镜像里造出「kind-9 引用 + 私有 witness」不现实，它与另外四处共用同一个函数。
- `SwiftInterfaceTests/ExtensionContextTypeNameTests`（第二批，3 条）：即时编译一个 dylib，按 `MachOFile` 生成完整 interface（与 `swift-section interface` 同一路径），断言 `Swift.Int` 的 extension 里的类型、其中的泛型类型、以及 `NSObject` 的 extension 里的类型都经被扩展的类型命名；最后一条断言的是「与同一份 interface 里单独引用 `NSObject` 时的写法一致」，不依赖 `__C` 是否被解析成真实模块。修复前 3 条全红（`NestedInExtension`、`GenericNestedInExtension<Swift.String>`、`NestedInObjCClassExtension`），连同收紧后的特化头部那条共 4 条；修复后全绿。

### 端到端验证

- **第一批，RuntimeViewer 会话**（进程内 RuntimeViewerCore 探针，只换 MachOSwiftSection 的版本）：报告的例子变为 `struct AppKit.WindowPortal<AppKit.ButtonContent> {`。AppKit 102 个能特化的泛型类型的头部里，开头带点的从 20 处降到 0，16 个 anonymous context 的例子都补全了限定名（如 `enum AppKit.InProcessAnimation<AppKit.NSAnimatableColor>.Bridged.Phase {`），4 个 extension context 的例子只去掉了点。打开字段偏移、展开字段偏移、type / enum layout、成员地址全部选项生成的完整 interface 里，含 `(unknown context at $…)` 的文件从 32 个降到 0；74 个文件共 233 行变化，全是一对一替换、没有增删行，其中 226 行只差名字（补限定名、去掉 `(unknown context at $…)`、去掉开头的点），另外 7 行是私有嵌套类型补回父链；偏移、布局数值和地址一个都没变。
- **第二批，本地差分**（基线 `a35daff9` 与候选各编一个 release CLI，共用同一份 `Package.resolved`；输入是当前系统 macOS 26.7 的 dyld shared cache）：AppKit 的 `dump` 逐字节相同（dump 不经过这个打印器）。AppKit / SwiftUI / SwiftUICore 的 `interface` 分别变化 255 / 163 / 734 行，行数不变；逐行检查全部是纯插入——每一行都只是在某个名字前面插入了被扩展的类型，没有删改任何别的字符。插入最多的前缀：AppKit 是 `__C.NSEvent.`（83）、`__C.NSView.`（63）、`__C.NSWorkspace.`（40）、`Foundation.AttributeScopes.`（29）；SwiftUI 是 `SwiftUI.DisplayList.`（32）、`SwiftUI.AccessibilityAttachment.`（31）、`Foundation.AttributedString.`（22）；SwiftUICore 是 `SwiftUI.Material.`（176）、`SwiftUI.Color.`（153）、`SwiftUI.Edge.`（84）。例子：`where B == Invalidations.Tuple<A1, B1>` → `where B == __C.NSView.Invalidations.Tuple<A1, B1>`，`[_Shadow]` → `[__C.CALayer._Shadow]`，`Layer.SDFLayer` → `SwiftUI.Material.Layer.SDFLayer`。被扩展的类型是泛型时按语法糖打印（SwiftUICore 的 `[A].PublicEncoding`），这种写法编译器接受（`typealias Y = [Int].Foo` 能通过类型检查）。没有用 `Scripts/run-rendering-ab-verification.py`：它写死的归档 cache 目录 `macOS/26.6` 已经不存在（卷上现在是 `26.6.2` 与 `26.7`），脚本会静默地只跑 `15.5` 那一条腿，而且它的框架清单里没有 AppKit。
