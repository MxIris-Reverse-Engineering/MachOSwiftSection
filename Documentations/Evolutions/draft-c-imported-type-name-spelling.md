# Draft - C 导入类型的名字统一成 Swift 名，并能切换回 C 名

- **状态**: In Progress
- **作者**: JH
- **创建日期**: 2026-11-24
- **最后更新**: 2026-11-24
- **所属愿景**: 无
- **关联提案**: [`draft-swift-type-indexing-package`](draft-swift-type-indexing-package.md)（`__C` 类型名按 SDK 解析，本提案叠在它上面）；RuntimeViewer 的 0064（注释结构由打印器标出、引擎分离后随 interface 下发，本提案照这条路传名字）
- **实现分支 / PR**: 两个仓库都是 `feature/c-imported-type-name-spelling`（worktree `.worktrees/MachOSwiftSection-CImportedTypeNameSpelling`、`.worktrees/RuntimeViewer-CImportedTypeNameSpelling`），叠在 `feature/swift-type-indexing-package` 上
- **配套文档**: 待定 —— 落地时登记实现说明 / 使用指南的链接
- **网页版**: 同目录同名的 `.html`
- **涉及仓库**: MachOSwiftSection（本仓库，打印器与 `swift-section`）、RuntimeViewer（生成选项、内容区的行尾提示）。这是跨仓库的唯一提案，RuntimeViewer 的提案索引登记为 cross-repository draft

## 摘要

Swift interface 里，从 C 导入、被改了名的类型（`NS_SWIFT_NAME`、typedef、CF 的 `Ref` 去尾）现在**声明行印 Swift 名、其余地方印 C 名**：`struct AnyWeakAttribute { var _details: __C.AGWeakAttribute.__Unnamed_struct__details }`，紧跟着 `extension __C.AGWeakAttribute: Swift.Hashable {}`。原因是声明行取类型描述符里的名字，而引用处取 mangled 名，Swift 给 Clang 声明做 mangling 时一律用 C 名。描述符的导入信息（import info）里两个名字本来都存着，不需要 SDK。

本提案让打印器多一个拼写选项 `CImportedTypeNameSpelling`：

- **默认 `.swiftName`**：声明、成员类型、扩展头全部用 Swift 名。查不到所属模块时写裸名（`extension AnyWeakAttribute: Swift.Hashable {}`），查得到时照旧写成 `模块.Swift名`。
- **`.cName`**：一律按 mangled 的样子印（声明 `struct AGWeakAttribute`，引用 `__C.AGWeakAttribute`）。

同时修掉扩展头不经类型名解析器的问题：SDK 类型的成员已经解析成 `CoreFoundation.CGRect`，扩展头却还是 `__C.CGRect`。

RuntimeViewer 把这个选项做成全局生成选项（Generation Options › Imported Type Names: Swift / C）。用 SourceEditor 显示时，改了名的 C 类型在声明行末尾带一条 Xcode 式的行尾标注（`Imported from C as AGWeakAttribute`），点开后用里面的按钮切换。

## 动机

**现象**（RuntimeViewer 显示 AttributeGraph 的 `AGWeakAttribute`，2026-11-24）：

```swift
struct AnyWeakAttribute {
    struct __Unnamed_struct__details {
        var identifier: __C.AGAttribute
        var seed: Swift.UInt32
    }
    var _details: __C.AGWeakAttribute.__Unnamed_struct__details
}

extension __C.AGWeakAttribute: Swift.Hashable {}
extension __C.AGWeakAttribute: Swift.CustomStringConvertible {}
extension __C.AGWeakAttribute: Swift.Equatable {}
```

同一个类型在一屏里有两个名字，扩展头看上去像是给另一个类型加的遵循。`swift-section 0.24.0 interface --show-c-imported-types` 打 AttributeGraph 得到的完全一样，还有 `struct AnyAttribute` 对 `__C.AGAttribute` 这一对（前期调研 1）。

**`swift-type-indexing-package` 解决不了这个**：它的改名只在模块解析成功时才生效（前期调研 5），而 AttributeGraph 这样的私有框架在 SDK 里没有模块，`__C.` 照旧。而且就算 SDK 类型解析成功了，扩展头也不经解析器（前期调研 6），`extension __C.CGRect` 与 `CoreFoundation.CGRect` 的成员并排出现。

**现在的声明行也会误导**：用 `NS_SWIFT_NAME(NSAttributedString.Key)` 导入成成员的 typedef，描述符里只存叶子名 `Key`（前期调研 3），于是声明行印成 `struct Key`，看不出是 `NSAttributedString.Key`。

用户还要能看 C 名：逆向时对照头文件、符号、IDA 里的名字都是 C 名。所以统一之后要能切回去，并且在界面上告诉读者这个类型有另一个名字。

## 前期调研

1. **复现**：本机（macOS 27.2）`swift-section 0.24.0 interface --uses-system-dyld-shared-cache --cache-image-name AttributeGraph --show-c-imported-types` 打出 `struct AnyAttribute { let rawValue: Swift.UInt32 }`、`struct AnyWeakAttribute { … var _details: __C.AGWeakAttribute.__Unnamed_struct__details }`，以及 `struct WeakAttribute<A> { var base: __C.AGWeakAttribute }`。`dump` 则把声明也印成 `struct __C.AGWeakAttribute`（它按 mangled 身份打印）。
2. **两套名字从哪来**：
   - 声明行：`SwiftDeclarationPrinter+Headers.swift:47/56/73` 把 `descriptor.name(in:)` 交给 `renderUnboundTypeName`（`:118`），最终 `renderLeafName` 写 `TypeDeclaration(kind, bareName)`（`:137-146`）。
   - 引用处（成员类型、扩展头）来自 mangled 名。Swift 对 Clang 声明一律按 Clang 名 mangling（`swift/lib/AST/ASTMangler.cpp` 的 `tryAppendClangName`）。`SymbolicDemangler.cImportedTypeIdentity`（`Sources/Analysis/SwiftInspection/SymbolicDemangler.swift:982`）正是把描述符换算成这个 mangled 身份的反方向映射：名字取 ABI 名，C typedef 改成 `typeAlias`，相关实体（related entity）包一层。
3. **描述符里存的是什么**：IRGen 的 `computeIdentity`（`swift/lib/IRGen/GenMeta.cpp:1568`）写 `UserFacingName = Type->getName()`，即 Swift 名的**叶子**；Clang 声明的名字不同时，在名字后面追加 `N<ABI 名>`（`TypeImportInfo`，`Sources/ABI/MachOSwiftSection/Models/Type/TypeImportInfo.swift`；`abiName` 只在两者不同时存在）。扫描本机 shared cache 全部子文件里「名字\0N<ABI 名>\0」的序列：

   | 描述符的名字 | ABI 名 | 份数 | 说明 |
   |---|---|---|---|
   | `AnyAttribute` | `AGAttribute` | 9 | `NS_SWIFT_NAME` 改名，顶层 |
   | `AnyWeakAttribute` | `AGWeakAttribute` | 4 | 同上 |
   | `CGColor` | `CGColorRef` | 142 | CF 类型去 `Ref` |
   | `Decimal` | `NSDecimal` | 47 | 顶层改名 |
   | `Key` | `NSAttributedStringKey` | 158 | 导入成 `NSAttributedString.Key`，**只剩叶子** |
   | `Name` | `NSNotificationName` | 68 | 导入成 `NSNotification.Name`，只剩叶子 |

   结论：对顶层改名，描述符的名字就是 Swift 名；对导入成成员的类型，描述符只给叶子，父类型丢了，而且从描述符本身分不出这两种情况。
4. **父上下文**：`IRGenModule::getAddrOfParentContextDescriptor`（`swift/lib/IRGen/GenDecl.cpp:885`）对 Clang 导入的名义类型一律挂到 `__C`（`ClangImporterContext`）下，只有真正嵌在 C 结构体里的类型（`__Unnamed_struct__details`）才以结构体为父。这一条同样说明「导入成成员」的父路径不在二进制里。
5. **现有改名的条件**：`TypeNodePrintable.printType`（`Sources/Output/SwiftPrinting/NodePrintables/TypeNodePrintable.swift:170-262`）只在 `resolvedModuleName(of:siblingIdentifier:)`（`NodePrintable.swift:179`）把 `__C` 解析成真实模块之后，才问 `CImportedNameResolving.swiftName(forCName:category:)` 改标识符。注释写明这样做是为了避免 `__C.CFString` 这种一半 C 一半 Swift 的写法。所以模块查不到时，标识符永远是 C 名。
6. **扩展头不经解析器**（读代码得出，未实测）：`renderExtendedTypeName`（`SwiftDeclarationPrinter+Headers.swift:743`）调用同步的 `ExtensionName.print(usesModuleSelectors:)`（`Sources/Declaration/SwiftDeclaration/Model/Names/ExtensionName.swift:15`），只用 `DemangleOptions` 拼字符串，不碰异步的类型名解析器。调用方有四处：`SwiftDeclarationPrinter.swift:688`、`+ObjCProtocols.swift:168`、`+ObjCImportedDefinitions.swift:101` 与 `:265`。所以即便 `swift-type-indexing` 解析成功，扩展头仍是 `__C.`。
7. **可用的 API**：`machO.swift.typeContextDescriptors`（`Sources/ABI/MachOSwiftSection/MachOFile+Swift.swift:54`、`MachOImage+Swift.swift:54`）、`isCImportedContextDescriptor(in:)`（`ContextDescriptorProtocol.swift:47`）、`typeImportInfo(in:)`（`TypeContextDescriptorProtocol.swift:70`）、`SymbolicDemangler.demangleContext(for:in:)`（`SymbolicDemangler.swift:342`，产出 mangled 身份节点）。打印器已有按需建一次、之后复用的状态写法（`memoizedRawLayoutBuiltinStorage`，`SwiftDeclarationPrinter.swift:115`）。
8. **标注区域只有 kind 和内容**：swift-semantic-string 的 `AnnotationRegion`（`Sources/Semantic/AnnotationRegions/AnnotationRegion.swift:37`）没有属性字段。本仓库已有把名字编进 kind 字符串的先例：`AnnotationRegion.Kind.attachedMacroTrackedProperty(_:named:)`（`Sources/Output/SwiftPrinting/AnnotationRegionKind+AttachedMacro.swift`）。
9. **`swift-section` 的接口参数**：`Sources/Executables/swift-section/Commands/InterfaceCommand.swift`（`--resolve-c-module-names` 在 `:34`）与 `Sources/Commands/SwiftSectionKit/Swift/InterfaceRequest.swift`。插件 skill 在 `AgentPlugins/swift-section/skills/swift-section-cli/SKILL.md`（§8 讲 `--resolve-c-module-names`），两份插件清单都是 `0.27.0`。
10. **RuntimeViewer 现状**（`next`，含尚未推送的类型索引功能）：
    - 生成选项存在 `appDefaults.options`，内容区在 `appDefaults.$options` 变化时重新取接口（`RuntimeViewerAppCore/Content/ContentTextViewModel.swift`，`interfaceStream` 的 `combineLatest`）；`ViewModel.currentMergedGenerationOptions`（`RuntimeViewerAppCore/Base/ViewModel.swift:51`）与它同样合并内部开关，让缓存键对齐。
    - `SwiftGenerationOptions.resolvesImportedTypeNames`（`RuntimeViewerCore/Interfaces/SwiftGenerationOptions.swift:98`，`@Default(true)`）；面板的「Resolve Imported Type Names」在 `GenerationOptionsViewController.swift:64`；面板已有 `.enumOption`（`Member Sort Order` 就是），枚举写法照 `SwiftGenerationOptions.MemberSortOrder`。
    - 注释结构与宏展开都是「打印器标区域 → 引擎 `separatingAnnotationRegions()` → `RuntimeObjectInterface` 带一个可选字段」（`commentStructure`、`macroExpansions`，`RuntimeObjectInterface.swift:22/33`；`RuntimeObjectInterface+AnnotationRegions.swift`）。
    - `RuntimeSwiftSection.updateConfiguration(for:)`（`RuntimeSwiftSection.swift:1900`）在 `resolvesImportedTypeNames` 开着时请求类型索引，配置有变化就清掉接口缓存。
    - Bridge 是一个 Objective-C 协议 `SourceEditorBridging`（`RuntimeViewerSourceEditorBridge/SourceEditorBridging.swift`），点击回调走 `SourceEditorBridgingNavigationDelegate`；行内展开（`showInlineExpansion`）是「随 interface 传数据、由 bridge 放进编辑器」的先例。Bridge 从未用过行尾标注。
    - 命令行插件 skill `AgentPlugins/runtime-viewer/skills/runtime-viewer-cli/SKILL.md:165-172` 讲了 `__C.` 名的解析；插件版本 `1.4.0` 是类型索引功能抬的，还没发布。
11. **复刻版 SourceEditor 的行尾标注**（`Mx-Iris/SourceEditor` tag `27.2.0-alpha.2`，RuntimeViewer 钉的版本）：
    - 公开入口 `SourceEditorView.insertLineAnnotation(_:)`、`removeAllLineAnnotations()`、`lineAnnotations`（`SourceEditor/macOS/SourceEditorView.swift:967-989`）；`SourceEditorLineAnnotation.init(category:message:lineIdentifier:…:revealAction:…)`（`SourceEditor/Annotations/LineAnnotations/SourceEditorLineAnnotation.swift:134`）；`SourceEditorLineAnnotationCategory`（同文件 `:7`）；动作 `SourceEditorLineAnnotation.Action`（`SourceEditorLineAnnotationAction.swift`，`DisplayStyle` 有 `inline` / `lineItem` / `dropdown`）。
    - **横幅本身不带按钮**：点横幅时 `SourceEditorLineAnnotationManager.handleLeftMouseUpEvent`（`SourceEditorLineAnnotationManager.swift:960-977`）弹出 Xcode 那种下拉框，动作按钮在下拉框里；右键横幅弹出的菜单里只有 `revealAction` 这一项（`SourceEditorLineAnnotationView.swift:788-800`）。`SourceEditorLineAnnotationInteractionDelegate`（`SourceEditorLineAnnotationDropdownPresentation.swift:39`）没有「点了横幅」的回调。所以「点一下就切换」要么走两步（点横幅、再点下拉里的按钮），要么用右键菜单，要么去改复刻版框架。

## 提议方案

### MachOSwiftSection

1. **拼写选项**：`SwiftDeclarationPrintConfiguration.cImportedTypeNameSpelling: CImportedTypeNameSpelling`，默认 `.swiftName`。
2. **本镜像的名字表**：打印器第一次需要时，从本镜像所有 C 导入的类型描述符建一张表，以 mangled 身份为键、描述符的名字为值，**只收可信的条目**：
   - 有 ABI 名，且与描述符的名字不同；
   - 不是相关实体（`__C_Synthesized` 里的错误码结构体之类）；
   - ABI 名**不以**描述符的名字结尾——导入成成员的类型（`NSAttributedStringKey` → `Key`）都长这样，描述符给的只是叶子，宁可不改名。代价是 `NSDecimal` → `Decimal` 这类顶层改名也被挡掉（前期调研 3），它们照旧印 C 名，有 SDK 时由类型索引补上。
3. **`.swiftName` 下一个 `__C` 引用怎么印**（按顺序取第一个成立的）：
   1. 注册了的解析器把模块解析出来了 → 照旧写成 `模块.Swift拼写`（`swift-type-indexing-package` 的路径，不变）；
   2. 名字表里有它 → **只写 Swift 名，不写模块**（`AnyWeakAttribute`，用户定的）；
   3. 都没有 → 照旧 `__C.ABI名`。

   嵌在 C 类型里的类型，父类型那一段按同样的规则印（`AnyWeakAttribute.__Unnamed_struct__details`）。
4. **`.cName`**：引用一律按 mangled 的样子印 `__C.ABI名`，**打印时不问任何解析器**——模块也不解析，因为 `UIKit.UICellConfigurationState` 会和同名的 Swift 结构体混淆，这正是 `swift-type-indexing-package` 起因里的例子。只有打开了标注（第 7 条）时，声明名会去问解析器要标注里那个 Swift 名，打印出来的文字不变。
5. **声明行与引用走同一套规则**：C 导入类型的声明名，在 `.cName` 下是 ABI 名；在 `.swiftName` 下依次取解析器给的 Swift 拼写（可以带点号，`struct NSAttributedString.Key`）、名字表里的名字、ABI 名。不可信的条目因此从 `struct Key` 变成 `struct NSAttributedStringKey`。
6. **扩展头改走异步的类型打印路径**：只改扩展类型根在 `__C` / `__C_Synthesized` 的扩展，用打印器同一套解析与拼写印出名字，仍包成同一种 `TypeDeclaration`。其余扩展一个字节都不变。
7. **标注**：`SwiftDeclarationPrintConfiguration.marksCImportedTypeNames`（默认关）打开时，两种拼写不同的 C 导入类型的声明名外面包一个 `AnnotationRegion`，kind 里带着两个名字。文本不变，分离之后与不标注时逐字节相同。
8. **`swift-section interface --c-imported-type-name-spelling swift-name|c-name`**，默认 `swift-name`。

### RuntimeViewer

1. **生成选项**：`SwiftGenerationOptions.cImportedTypeNameSpelling`（`@Default(.swiftName)`，旧设置读出来是 Swift 名）。Generation Options 面板的 Swift 一组加一行 `Imported Type Names: Swift | C`。它与「Resolve Imported Type Names」各管各的：后者决定要不要用 SDK 解析模块，在 C 名模式下不起作用，也不再为它建类型索引。
2. **内部标注开关**：`GenerationOptions.marksCImportedTypeNames`，不出现在面板里，存下来的值永远是默认的 false。内容区只在 SourceEditor 可用时把它打开，`currentMergedGenerationOptions` 照同样的规则合并。
3. **接口带回名字**：`RuntimeObjectInterface.cImportedTypeNames: [RuntimeInterfaceCImportedTypeName]?`，每条是声明名在文本里的 UTF-8 范围和两个名字。从分离出的标注区域里取，与宏展开在同一处；注释结构不认这种 kind。
4. **行尾标注**：bridge 新增 `showLineAnnotations(_:)` 与一个代理回调。内容区每次 `setSource` 之后，给每个改了名的声明放一条：
   - Swift 名模式：`Imported from C as AGWeakAttribute`，动作 `Show C Names`；
   - C 名模式：`Imported to Swift as AnyWeakAttribute`，动作 `Show Swift Names`。

   点横幅弹出下拉框，用里面的按钮切换；右键横幅的菜单里也有同一个动作（`revealAction`）。切换就是翻转全局的生成选项，所有内容区一起重新取接口。
5. **其余出口跟着选项走**：MCP、App 充当 host 时的命令行、导出读的都是 `appDefaults.options`，与其他生成选项一样；独立运行的命令行 host 用默认的 Swift 名。Find 语料始终用 Swift 名打印。

### 交互：两次点击

用户选的样式里，按钮直接画在横幅上；复刻版框架的横幅没有按钮（前期调研 11）。用户批准按 Xcode 原生的两步做：点横幅弹出下拉框，用里面的按钮切换；右键横幅的菜单里也有同一个动作。不改 `Mx-Iris/SourceEditor`。

### 非目标

- **不推断导入成成员的类型的父路径**：描述符只给叶子（`Key`），没有 SDK 就保持 C 名，不按前缀去猜 `NSAttributedString.Key`。
- **相关实体不改**：`__C_Synthesized` 里的类型（`CKError` 之类）照旧打印。
- **只在声明行放提示**：引用处（`var base: AnyWeakAttribute`）不放，一屏里可能有几十个引用，提示会太吵。
- **侧栏、路径栏、Find 结果里的对象名不跟着切换**：它们来自索引，不重新打印。Find 语料始终是 Swift 名，搜 C 名搜不到改了名的引用。
- **`dump`、`diff`、`snapshot` 的键不变**：ABI diff 按 mangled 身份对比（`Sources/Output/SwiftDiffing/Keying.swift`），只有 `diff --interface` 的渲染会跟着新的默认拼写变。
- **NSTextView 显示路径与 iOS 版不放提示**：两处都没有行尾标注；iOS 版也没有生成选项界面，只能用默认的 Swift 名。
- **命令行工具不加对应参数**：它读 App 的生成选项，独立 host 用默认值。

## 改动地图

| 仓库 · 文件 / 类型 | 动作 | 改什么 | 为什么 | 步骤 |
|---|---|---|---|---|
| MSS · `Sources/Output/SwiftPrinting/CImportedTypeNameSpelling.swift` · `CImportedTypeNameSpelling` | 新增 | `.swiftName` / `.cName` 两种拼写 | 拼写选项的类型 | 1 |
| MSS · `Sources/Output/SwiftPrinting/SwiftDeclarationPrintConfiguration.swift` | 修改 | 加 `cImportedTypeNameSpelling`（默认 `.swiftName`）与 `marksCImportedTypeNames`（默认 false） | 打印配置 | 1 |
| MSS · `Sources/Output/SwiftPrinting/CImportedTypeSwiftNameTable.swift` · `CImportedTypeSwiftNameTable` | 新增 | 从 `typeContextDescriptors` 建「mangled 身份 → 描述符名字」的表，`trustsUserFacingName(_:importInfo:)` 是可信规则 | 描述符里现成的 Swift 名 | 1 |
| MSS · `Sources/Output/SwiftPrinting/SwiftDeclarationPrinter.swift` | 修改 | 按需建一次名字表并复用（照 `memoizedRawLayoutBuiltinStorage`）；回答节点打印器对名字表的查询；扩展头调用改成 `await` | 打印器持有名字表 | 1、2 |
| MSS · `Sources/Output/SwiftPrinting/NodePrintables/TypeNodePrintable.swift` · `printType(_:)` | 修改 | `__C` 引用按方案第 3、4 条的规则印 | 统一引用处的拼写 | 2 |
| MSS · `Sources/Output/SwiftPrinting/NodePrintables/NodePrintable.swift` · `resolvedModuleName(of:siblingIdentifier:)` | 修改 | `.cName` 下不问解析器 | C 名模式等于 mangled 拼写 | 2 |
| MSS · 节点打印器的 delegate 协议（与 `swiftName(forCName:category:)` 同处） | 修改 | 加一个内部查询：按 mangled 身份取名字表里的 Swift 名 | 名字表不是可注册的解析器，是打印器自带的 | 2 |
| MSS · `Sources/Output/SwiftPrinting/SwiftDeclarationPrinter+Headers.swift` · `renderTypeDeclarationHeader`、`renderExtendedTypeName` | 修改 | 声明名按同一套规则取；标注开着时包区域；扩展头根在 `__C` 时走异步类型打印 | 声明、扩展与成员一致 | 2、3 |
| MSS · `SwiftDeclarationPrinter.swift:688`、`+ObjCProtocols.swift:168`、`+ObjCImportedDefinitions.swift:101/265` | 修改 | 调用 `await renderExtendedTypeName` | 签名变成 async | 2 |
| MSS · `Sources/Output/SwiftPrinting/AnnotationRegionKind+CImportedTypeName.swift` | 新增 | `CImportedTypeNames`（两个名字）、`AnnotationRegion.Kind.cImportedTypeName(_:)` 与解析回来的 `cImportedTypeNames` | 把两个名字交给宿主 | 3 |
| MSS · `Sources/Commands/SwiftSectionKit/Swift/InterfaceRequest.swift`、`Sources/Executables/swift-section/Commands/InterfaceCommand.swift` | 修改 | `--c-imported-type-name-spelling swift-name\|c-name` | 命令行能切回 C 名 | 3 |
| MSS · `Tests/SwiftInterfaceTests/CImportedTypeNameSpellingTests.swift` | 新增 | 第 1–3 步的行为 | 回归 | 1–3 |
| MSS · 受新默认拼写影响的快照 / baseline 测试 | 修改 | 只更新改了名的 C 类型那几行 | 默认输出变了 | 2 |
| MSS · `README.md` 的 swift-section 一节、`AgentPlugins/swift-section/skills/swift-section-cli/SKILL.md`（§4 参数表、§8、§9）、两份插件清单 | 修改 | 新参数与新默认拼写；插件版本 `0.27.0` → `0.28.0` | 文档与插件随代码 | 3 |
| MSS · `Documentations/Evolutions/README.md` | 修改 | 登记本草案 | 索引 | 0 |
| RV · `RuntimeViewerCore/Sources/RuntimeViewerCore/Interfaces/SwiftGenerationOptions.swift` | 修改 | `CImportedTypeNameSpelling` 枚举与 `cImportedTypeNameSpelling`（`@Default(.swiftName)`） | 用户选项 | 4 |
| RV · `…/Interfaces/RuntimeObjectInterface+GenerationOptions.swift` | 修改 | `marksCImportedTypeNames`（`@Default(false)`） | 只有内容区要提示 | 4 |
| RV · `…/Interfaces/SwiftDeclarationPrintConfiguration+GenerationOptions.swift` | 修改 | 把拼写映射进打印配置；**不**进 `applySwitches(of:)`，Find 语料保持 Swift 名 | 显示跟着选项，语料不跟 | 4 |
| RV · `…/Interfaces/RuntimeInterfaceCImportedTypeName.swift` | 新增 | 声明名的 UTF-8 范围与两个名字 | 接口带回提示所需的数据 | 4 |
| RV · `…/Interfaces/RuntimeObjectInterface.swift`、`RuntimeObjectInterface+AnnotationRegions.swift`、`RuntimeInterfaceCommentStructure+AnnotationRegions.swift` | 修改 | 加可选字段 `cImportedTypeNames`；分离时取出；注释结构忽略这种 kind | 照宏展开的路 | 4 |
| RV · `…/Sections/Swift/RuntimeSwiftSection.swift` · `updateConfiguration` | 修改 | 设 `marksCImportedTypeNames`；`.cName` 下不请求类型索引 | C 名用不到索引 | 4 |
| RV · `RuntimeViewerUsingAppKit/RuntimeViewerSourceEditorBridge/SourceEditorBridging.swift` | 修改 | `SourceEditorBridgingLineAnnotation`、`showLineAnnotations(_:)`、代理的 `sourceEditorBridge(_:didPerformActionOfLineAnnotationWithIdentifier:)` | bridge 接口 | 5 |
| RV · `…/RuntimeViewerSourceEditorBridge/SourceEditorBridge.swift`（或新的 `LineAnnotationController.swift`） | 修改 / 新增 | `setSource` 清掉旧标注；插入 `SourceEditorLineAnnotation`（类别、图标、颜色、动作、`revealAction`）；动作回调代理 | 接上框架的行尾标注 | 5 |
| RV · `RuntimeViewerUsingAppKit/RuntimeViewerSourceEditorBridgeTests/LineAnnotationTests.swift` | 新增 | 第 5 步的行为 | 回归 | 5 |
| RV · `RuntimeViewerPackages/Sources/RuntimeViewerAppCore/Content/ContentInterface.swift` | 修改 | 加提示的值（UTF-16 范围、消息、动作标题），按当前拼写生成文字 | AppCore 描述、AppUI / App 只画 | 6 |
| RV · `…/RuntimeViewerAppCore/Content/ContentTextViewModel.swift` | 修改 | 合并 `marksCImportedTypeNames`；新输入 `cImportedTypeNameSpellingToggled`，翻转 `appDefaults.options` 里的拼写 | 切换即改全局选项 | 6 |
| RV · `…/RuntimeViewerAppCore/Base/ViewModel.swift` · `currentMergedGenerationOptions` | 修改 | 同样合并 `marksCImportedTypeNames` | 缓存键与内容区对齐 | 6 |
| RV · `RuntimeViewerUsingAppKit/RuntimeViewerUsingAppKit/Content/ContentSourceEditorViewController.swift` | 修改 | `setSource` 之后 `showLineAnnotations`；代理回调进 relay | 接上 ViewModel | 6 |
| RV · `RuntimeViewerUsingAppKit/RuntimeViewerUsingAppKit/Generation Options/GenerationOptionsViewController.swift` | 修改 | `.enumOption(title: "Imported Type Names", labels: ["Swift", "C"], …)` | 面板入口 | 6 |
| RV · `RuntimeViewerCore/Tests/…`、`RuntimeViewerPackages/Tests/RuntimeViewerAppCoreTests/…` | 新增 | 第 4、6 步的行为 | 回归 | 4、6 |
| RV · `AgentPlugins/runtime-viewer/skills/runtime-viewer-cli/SKILL.md`、两份插件清单 | 修改 | 「Imported types」一段补上描述符的 Swift 名与 C 名选项；`1.4.0` 已发布就抬到 `1.4.1`，没发布就留在 `1.4.0` | 输出变了 | 7 |
| RV · `RuntimeViewerCore/Package.swift` 与锁文件 | 修改 | 抬 MSS 的 pin | 取上游的改动 | 7 |
| RV · `Documentations/Evolutions/README.md` | 修改 | cross-repository draft 一行 | 索引 | 0 |

## 架构图

**改了什么**：

```text
MachOSwiftSection
  Sources/Output/SwiftPrinting/
+   CImportedTypeNameSpelling              .swiftName (default) | .cName
+   CImportedTypeSwiftNameTable            mangled identity -> descriptor's Swift name (trusted entries only)
+   AnnotationRegion.Kind.cImportedTypeName(_:)  carries both names when marking is on
~   SwiftDeclarationPrintConfiguration     + cImportedTypeNameSpelling, + marksCImportedTypeNames
~   SwiftDeclarationPrinter                + memoized name table (machO.swift.typeContextDescriptors)
~   TypeNodePrintable.printType            spelling rules for __C references
~   NodePrintable.resolvedModuleName       .cName asks no resolver
~   +Headers.renderTypeDeclarationHeader   declared name by the same rules; region when marked
~   +Headers.renderExtendedTypeName        async; C-imported extended types through the type printer
  Sources/Executables/swift-section/
~   interface --c-imported-type-name-spelling swift-name|c-name

RuntimeViewer
  RuntimeViewerCore/Interfaces/
~   SwiftGenerationOptions                 + cImportedTypeNameSpelling (@Default .swiftName)
~   GenerationOptions                      + marksCImportedTypeNames (internal, stored false)
+   RuntimeInterfaceCImportedTypeName      declared name's UTF-8 range + both names
~   RuntimeObjectInterface                 + cImportedTypeNames
  RuntimeViewerSourceEditorBridge/
+   SourceEditorBridgingLineAnnotation
~   SourceEditorBridging                   + showLineAnnotations(_:)
~   SourceEditorBridgingNavigationDelegate + didPerformActionOfLineAnnotationWithIdentifier
  RuntimeViewerAppCore/Content/
~   ContentInterface, ContentTextViewModel + notes, + spelling toggle input
  RuntimeViewerUsingAppKit/
~   ContentSourceEditorViewController      line annotations, toggle relay
~   GenerationOptionsViewController        + "Imported Type Names: Swift | C"
```

**一个 `__C` 引用怎么印**：

```text
printType(reference rooted in __C)
├─ spelling == .cName                       -> "__C." + ABI name       (no resolver asked)
└─ spelling == .swiftName
   ├─ a resolver resolves the module        -> Module + Swift spelling (existing path)
   ├─ name table has a trusted entry        -> bare Swift name          AnyWeakAttribute
   └─ otherwise                             -> "__C." + ABI name        __C.NSAttributedStringKey

declared name of a C-imported descriptor
├─ .cName                                   -> ABI name                 AGWeakAttribute
└─ .swiftName                               -> resolver's spelling ?? trusted name ?? ABI name
```

**点「Show C Names」之后**：

```text
click "Show C Names" in the line annotation's dropdown
  -> SourceEditorBridge: SourceEditorLineAnnotation.Action
  -> navigationDelegate.sourceEditorBridge(_:didPerformActionOfLineAnnotationWithIdentifier:)
  -> ContentSourceEditorViewController: cImportedTypeNameSpellingToggledRelay
  -> ContentTextViewModel: appDefaults.options.swiftInterfaceOptions.cImportedTypeNameSpelling = .cName
  -> appDefaults.$options: every content pane refetches
  -> RuntimeEngine.interface(for:options:)                          (service process)
       -> RuntimeSwiftSection.updateConfiguration                   printer config changed: cache cleared
       -> SwiftDeclarationPrinter prints with .cName, marks declared names
       -> separatingAnnotationRegions() -> RuntimeObjectInterface.cImportedTypeNames
  -> ContentSourceEditorViewController.setSource + showLineAnnotations
       "Imported to Swift as AnyWeakAttribute"  [Show Swift Names]
```

## 详细设计

### MachOSwiftSection 的公开 API

```swift
/// How a print spells the types a mangling places in the Clang importer's modules (`__C`,
/// `__C_Synthesized`): imported C structs, enums, typedefs, CF types and Objective-C classes.
public enum CImportedTypeNameSpelling: String, Sendable, Hashable, CaseIterable {
    /// The name Swift code uses. A type whose module a registered resolver finds prints under
    /// it (`CoreFoundation.CGRect`); a type the image's own descriptors rename prints under that
    /// name alone (`AnyWeakAttribute`); any other keeps its mangled spelling (`__C.AGFoo`).
    case swiftName
    /// The C declaration's own name, exactly as the mangling spells it: `__C.AGWeakAttribute`
    /// in a reference, `AGWeakAttribute` on its declaration. No resolver is asked.
    case cName
}

public struct SwiftDeclarationPrintConfiguration {
    // …
    /// How imported C and Objective-C type names are spelled. `.swiftName` by default.
    public var cImportedTypeNameSpelling: CImportedTypeNameSpelling = .swiftName

    /// Marks the declared name of every C-imported type whose two spellings differ with a
    /// `cImportedTypeName` annotation region carrying both. Off by default; separating the
    /// regions gives exactly the print with it off.
    public var marksCImportedTypeNames: Bool = false
}

/// The two names of a C-imported type: what Swift code calls it and what its C declaration is called.
public struct CImportedTypeNames: Sendable, Hashable {
    /// `AnyWeakAttribute`; dotted when a resolver spells a type imported as a member
    /// (`NSAttributedString.Key`).
    public let swiftName: String
    /// `AGWeakAttribute`.
    public let cName: String

    public init(swiftName: String, cName: String)
}

extension AnnotationRegion.Kind {
    /// The declared name of a C-imported type whose Swift and C names differ, marked when
    /// `SwiftDeclarationPrintConfiguration.marksCImportedTypeNames` is on. The region's text is the
    /// spelling printed; the kind carries both. Not a comment.
    public static func cImportedTypeName(_ names: CImportedTypeNames) -> Self

    /// The names a `cImportedTypeName` kind carries; nil for any other kind.
    public var cImportedTypeNames: CImportedTypeNames? { get }
}
```

kind 的编码是 `"cImportedTypeName|" + swiftName + "|" + cName`。`|` 不会出现在 Swift 或 C 的名字里，点号可以照常出现在 Swift 名里。解析只认这个前缀，并且要求恰好三段、两个名字都不为空。原先设计用 U+001F，实现时发现 swift-semantic-string 拒绝 kind 里的任何控制字符（它自己的标记就是控制字符，`AnnotationTag.validate`），改成了 `|`。

### 名字表（模块内部）

```swift
/// The Swift names the image's own C-imported type descriptors give, keyed by the identity a
/// mangling spells — `SymbolicDemangler.demangleContext(for:in:)` of the descriptor.
struct CImportedTypeSwiftNameTable: Sendable {
    static let empty = Self(entries: [:])

    init(typeContextDescriptors: [TypeContextDescriptorWrapper], in context: some ReadingContext)

    /// The trusted Swift name of the C-imported type `identity` names, or nil.
    func swiftName(forIdentity identity: Node) -> String?

    /// Whether a descriptor's user-facing name is the type's whole Swift name. A type imported as
    /// a member (`NS_SWIFT_NAME(NSAttributedString.Key)`) keeps only its leaf (`Key`) in the
    /// descriptor, and its ABI name ends with that leaf; such a name is not trusted.
    static func trustsUserFacingName(_ userFacingName: String, importInfo: TypeImportInfo) -> Bool {
        guard let abiName = importInfo.abiName, abiName != userFacingName, !importInfo.isRelatedEntity else { return false }
        return !abiName.hasSuffix(userFacingName)
    }
}
```

- 键是 mangled 身份节点的**结构**（照 `ExtensionName` 的结构化 `Hashable`），所以 C typedef 的 `typeAlias` 种类、嵌套 C 类型的父路径都对得上。
- 只遍历 `isCImportedContextDescriptor(in:) == true` 的描述符，读名字和 `typeImportInfo(in:)`，不建声明模型。表放在打印器里，第一次打印 `__C` 引用或 C 导入声明时才建；打印配置怎么变都不重建，因为表只取决于镜像。
- 读描述符出错的条目直接跳过（表少一条只会退回 C 名），不报 degradation。

### 打印规则的落点

- `printType(_:)`：`contextNode.kind == .module` 且模块是 `__C` / `__C_Synthesized` 时：
  - `.cName`：写原模块名与标识符，不调 `resolvedModuleName` 的解析分支，也不问 `swiftName(forCName:category:)`。
  - `.swiftName`：先走现有路径；模块没解析出来、但名字表对整个 `name` 节点有答案时，**不写模块与分隔符**，把 Swift 名写成标识符（语义仍是这个类型的 `printIdentifier` 上下文，RuntimeViewer 的跳转不受影响）。
  - 嵌套类型的父段经 `printName(contextNode, asPrefixContext:)` 递归回到 `printType`，自然套用同一规则。
- `printModuleSelector(ofNestedType:)`：父段是改了名的裸名时，不写模块选择器（与第 2 条的「不写模块」一致）。
- `renderTypeDeclarationHeader`：描述符是 C 导入的（`isCImportedContextDescriptor`）时，按方案第 5 条算出名字，替换现在的 `descriptor.name(in:)`。解析器那一路用描述符的 ABI 名去问：`moduleName(forTypeName:)` 加 `swiftName(forCName:category:)`，分类取 `CImportedTypeNameCategory(nodeKind:)`，与引用处的查询相同，所以声明与引用必然一致。`displayParentName == true`（`dump` 风格）那条路不变。
- `renderExtendedTypeName` 改成 `async`：`extensionName.node` 根在 `__C` / `__C_Synthesized` 时，打印走 `typeDemangleResolver.resolve(for:)`，再 `.replacingTypeNameOrOtherToTypeDeclaration()`（`renderUnboundTypeName` 现成的写法）；位置命名的局部类型那条分支与其余扩展保持原样。

### RuntimeViewer 的类型

```swift
extension SwiftGenerationOptions {
    public enum CImportedTypeNameSpelling: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
        case swiftName
        case cName
    }
}

// SwiftGenerationOptions
/// How imported C and Objective-C types are spelled: under their Swift name (`AnyWeakAttribute`,
/// `UIKit.UITraitCollection`), or as the binary mangles them (`__C.AGWeakAttribute`). With `.cName`,
/// `resolvesImportedTypeNames` does nothing. Swift names in settings saved before it existed.
@Default(CImportedTypeNameSpelling.swiftName)
public var cImportedTypeNameSpelling: CImportedTypeNameSpelling

// RuntimeObjectInterface.GenerationOptions
/// Asks the Swift printer to mark the declared names of renamed C-imported types, which the
/// interface then carries as `cImportedTypeNames`. Only the content pane sets it, and only where
/// SourceEditor runs; stored values are always the default.
@Default(false)
public var marksCImportedTypeNames: Bool

/// A declared C-imported type whose Swift and C names differ.
public struct RuntimeInterfaceCImportedTypeName: Codable, Sendable, Hashable {
    /// Where the declared name is in the interface's text, in UTF-8 offsets, as the comment
    /// structure counts them.
    public let nameUTF8Range: Range<Int>
    public let swiftName: String
    public let cName: String
}

// RuntimeObjectInterface
/// The renamed C-imported types this interface declares, when the request marked them; nil
/// otherwise, and from a peer built before them.
public let cImportedTypeNames: [RuntimeInterfaceCImportedTypeName]?
```

线上兼容：旧版对端不认这两个选项，按自己的 MachOSwiftSection 打印，不带 `cImportedTypeNames`，内容区就没有提示；新版对端收到旧版请求时取默认值。

### Bridge

```swift
/// A note at the end of a line, with one action — Xcode's issue annotation, used here for a
/// C-imported type's other name. A class, because `SourceEditorBridging` is an Objective-C protocol.
@objc(RuntimeViewerSourceEditorBridgingLineAnnotation)
public final class SourceEditorBridgingLineAnnotation: NSObject {
    /// The UTF-16 range in the current source the note is about; it sits at the end of the
    /// range's first line.
    public let characterRange: NSRange
    public let message: String
    /// The title of the action, in the dropdown the note opens and in its contextual menu.
    public let actionTitle: String
    /// Handed back when the action is performed.
    public let identifier: String

    public init(characterRange: NSRange, message: String, actionTitle: String, identifier: String)
}

// SourceEditorBridging
/// Replaces the line annotations shown on the current source. `setSource` removes them all,
/// so call this after it, with ranges of that source.
func showLineAnnotations(_ annotations: [SourceEditorBridgingLineAnnotation])

// SourceEditorBridgingNavigationDelegate
/// The action of the line annotation shown under `identifier` was performed.
func sourceEditorBridge(_ bridge: SourceEditorBridging, didPerformActionOfLineAnnotationWithIdentifier identifier: String)
```

- 实现照复刻版 tag `27.2.0-alpha.2` 的源码：`lineIdentifier` 取 `dataSource.identifierForLine(_:)`；`SourceEditorLineAnnotation` 的动作用 `Action(message:displayStyle:…)` 放进 `actions`，`revealAction` 用同一个标题，右键菜单里就有这一项；`allowsMinimization: false`、`isDraggable: false`、不画滚动条标记。
- **类别是我们自己的**：Xcode 的 issue 与 note 类别在 IDESourceEditor 里，不在复刻范围，所以外观是我们的取舍，不是复刻 Xcode：`identifier` 为 `RuntimeViewer.note`，图标 `info.circle.fill`，`annotationColor` 为 `.systemGray`，整行淡灰（`systemGray` 的 8%），不标范围、不进滚动条、不能拖动、不能最小化，`defaultViewState: .inline`。框架会怎么用这些值，读自复刻版 tag 上的源码：带标注的行按 `lineHighlightColor` 整行着色（`SourceEditorLineAnnotationManager.lineHighlightForLineIdentifier`），点横幅弹出聚合下拉框，标注那一行右侧为每个 `.inline` / `.dropdown` 动作画一个按钮、按钮文字是 `buttonMessage`（`SourceEditorLineAnnotationAggregatedDropdown`、`DropdownAnnotationView`），右键横幅的菜单只有 `revealAction`。
- `setSource` 在换数据源之前 `removeAllLineAnnotations()`，与行内展开同一个理由：标注挂在旧数据源的行标识上。
- 实现在 `SourceEditorBridge.swift` 末尾的一个扩展里：`sourceEditorView` 是 `private`，另起文件访问不到。
- 框架里缺的东西（比如横幅上的按钮）属于 `Mx-Iris/SourceEditor` 的改动，不在 bridge 里绕。

### AppCore 与 App

- `ContentInterface` 加 `cImportedTypeNameNotes: [ContentTextViewModel.CImportedTypeNameNote]`，每条是 UTF-16 范围、消息和动作标题，由 `ContentTextViewModel.cImportedTypeNameNotes(of:)` 按取接口时的拼写生成（`FetchedInterface` 带着 `cImportedTypeNames` 与 `cImportedTypeNameSpelling`）：
  - `.swiftName`：`Imported from C as <cName>` / `Show C Names`；
  - `.cName`：`Imported to Swift as <swiftName>` / `Show Swift Names`。

  文字放在 AppCore，因为它是「描述值」（RuntimeViewerPackages 的 `Sources/AGENTS.md`）。
- 内部标注开关照 `marksAttachedMacros` 的写法：`Settings.Editor.showsCImportedTypeNameNotes`（SourceEditor 可用即为真），`ContentTextViewModel` 取接口时与 `currentMergedGenerationOptions` 都合并进去。
- `ContentTextViewModel.Input` 加 `cImportedTypeNameSpellingToggled: Signal<Void>`（`@Init(default: .empty())`，NSTextView 与 iOS 的调用点不用改），在主线程把 `appDefaults.options.swiftInterfaceOptions.cImportedTypeNameSpelling` 换成另一个值。之后所有内容区都经 `appDefaults.$options` 重新取接口，不需要单独通知。
- `ContentSourceEditorViewController`：每次 `setSource` 之后 `bridge.showLineAnnotations(...)`，identifier 用提示的序号；代理回调直接 `accept` 到 relay（不管是哪一条，都是同一个全局切换）。
- 面板：`.enumOption(title: "Imported Type Names", labels: ["Swift", "C"], keyPath: \.swiftInterfaceOptions.cImportedTypeNameSpelling)`，放在「Resolve Imported Type Names」上面。

## 替代方案考量

- **模块未知时写 `__C.AnyWeakAttribute`**：保留「C 导入、模块未知」的信号，但与声明行 `struct AnyWeakAttribute` 仍不一致，而且是打印器以前特意避开的半翻译写法（前期调研 5）。用户选了裸名。
- **按 C 名统一（声明行也印 `AGWeakAttribute`）作为默认**：与 mangled 一致，但读的是 Swift interface，Swift 名更贴合。C 名作为可切换的另一种拼写保留。
- **按前缀推断成员导入的父类型**（`NSAttributedStringKey` → `NSAttributedString.Key`）：二进制里没有父路径（前期调研 3、4），按前缀切分会把 `NSDecimal` 切成 `NS.Decimal` 这种错误结果。`swift-type-indexing-package` 已经否定过只靠二进制推断改名。
- **提示做成类型名后面的胶囊标签**：要打印器多输出一段注释，复制与导出会带上它，还要给标签加点击处理。用户选了行尾标注。
- **只切换当前编辑栏**：要在 ViewModel 里另存一份不进设置的状态，接口缓存键也要多一维；用户选了全局生成选项。
- **把拼写和 `resolvesImportedTypeNames` 合成一个三档枚举**：类型索引功能还在验收、设置项已经写好，合并就要改它的设置与测试；两个开关各管各的更简单，C 名模式下后者不起作用即可。

## 影响

### 源码兼容性（source compatibility）

- **纯新增**：`CImportedTypeNameSpelling`、`CImportedTypeNames`、两个配置属性、`AnnotationRegion.Kind.cImportedTypeName(_:)` / `cImportedTypeNames`。
- `renderExtendedTypeName` 是 `package`，改成 `async` 只影响本包的四个调用点。
- **输出有变化**（不是编译期破坏）：默认拼写下，改了名的 C 类型的引用与扩展头变成 Swift 名；不可信条目的声明行从叶子名变成 C 名（`struct Key` → `struct NSAttributedStringKey`、`struct Decimal` → `struct NSDecimal`）；SDK 类型的扩展头在注册了解析器时变成 `模块.名字`。依赖输出文本的下游测试要更新期望值；要旧的 C 名可以设 `.cName`，但声明行会变成 C 名，与以前的「声明 Swift、引用 C」不完全相同——那种混合正是要去掉的。

### ABI 兼容性（条件项）

不适用 —— 本库以 SPM 源码分发，使用方每次重新编译。

### 下游影响

- **本仓库**：`SwiftInterface`（`SwiftInterfaceBuilder` 用同一个打印器）、`SwiftDiffing` 的 `--interface` 渲染、`swift-section interface` 的默认输出跟着变；ABI diff 的键不变。
- **MachOKitUI、SymbolViewer**：经打印器显示 Swift interface，输出变化同上，不需要改代码。
- **RuntimeViewer**（本提案的另一半）：
  - **用户可见**：用 SourceEditor 显示时，改了名的 C 类型的声明行末尾多一条灰色的行尾标注；Generation Options 多一行 `Imported Type Names`；默认接口里这些类型统一成 Swift 名；MCP、App 充当 host 时的命令行与导出跟着选项；Find 结果始终是 Swift 名。
  - **可发现性**：提示默认就在（只要 SourceEditor 可用），面板里有同名开关；不加首次引导。
  - **数据与配置兼容**：`appDefaults.options` 里没有这个键时取 `.swiftName`；`marksCImportedTypeNames` 存下来永远是 false。不需要迁移。
  - **平台**：提示只在 macOS 的 SourceEditor 路径；NSTextView 路径与 iOS 版只有默认的 Swift 名。
  - **发布**：不涉及权限、entitlement、公证与 Sparkle。
  - **派生数据**：Find 语料的打印变了，但代码变化本身会改变产出者身份（`Documentations/DerivedData.md`），旧语料自然失效，不必改 variant。
- **顺序约束**：两边都叠在 `swift-type-indexing-package` 上（它的改动还在两个仓库的本地 `next` 上、没推送）。本提案要等它先收尾，或者在它的功能分支之上开分支，落地时再变基。

### 文档与示例

- 本仓库 `README.md` 的 swift-section 一节与 `AgentPlugins/swift-section/skills/swift-section-cli/SKILL.md`：§4 参数表加 `--c-imported-type-name-spelling`；§8 说明默认的 Swift 名不依赖 `--resolve-c-module-names`；§9「看起来像 bug 其实不是」加一条：导入成成员的类型没有 SDK 时保持 C 名。两份插件清单抬到 `0.28.0`。
- RuntimeViewer 的命令行插件 skill（「Imported types print under their module and Swift name」那一段）补上描述符的 Swift 名与 C 名选项。
- 术语：落地时判断要不要在两边的术语表登记「C 导入类型名拼写」。

## API 演进与废弃策略

- 没有被替代的旧 API，不需要废弃期。
- 默认输出变化按 minor 版本发布，在 release note 里写明「C 导入类型默认按 Swift 名打印，要旧的 C 名请设 `.cName` / `--c-imported-type-name-spelling c-name`」。
- `CImportedTypeNameSpelling` 用 enum：只有两种拼写，调用方需要穷举（RuntimeViewer 的映射、命令行参数）。以后真要加第三种，就是一次有意的源码破坏，到时再评估。

## 落地步骤

已完成的步骤标 ✅。测试名是实际写成的；MachOSwiftSection 的测试在 `Tests/SwiftInterfaceTests/CImportedTypeNameSpellingTests.swift`，用测试里现场编译的桥接头 fixture（`swift_name` 改名的结构体与 `swift_wrapper` typedef、匿名嵌套结构体、导入成成员的 `ProbeOwner.Key`），照 `CImportedTypeConformanceInterfaceTests` 的做法，不依赖系统镜像。

0. ✅ **登记草案** —— 两边的提案索引；提案随两个功能分支的第一个提交走。
1. ✅ **名字表与可信规则** —— MSS 的 `CImportedTypeNameSpelling.swift`、配置两个属性、`CImportedTypeSwiftNameTable.swift`、打印器按需建表
   - 行为：`trustsUserFacingNameWhenABINameDiffers`（`AnyWeakAttribute` / `AGWeakAttribute`、`AnyAttribute` / `AGAttribute`、`CGColor` / `CGColorRef`、`__UIPointerShape` / `UIPointerShape`）
   - 行为：`refusesLeafNameOfTypeImportedAsMember`（`Key` / `NSAttributedStringKey`、`Name` / `NSNotificationName`、`Decimal` / `NSDecimal`）
   - 行为：`refusesRelatedEntityName`、`refusesNameWithoutABIName`
   - 行为：`nameTableReadsTheFixturesDescriptors`（fixture 的 `AnyFooThing`、`AnyFooIdentifier` 各对一条，`Key` 与匿名结构体没有）
2. ✅ **打印规则** —— MSS 的 `printType`、`resolvedModuleName`、delegate 查询、声明头、扩展头与四个调用点
   - 行为：`swiftSpellingPrintsBareSwiftNameWhenModuleIsUnknown`（`var _details: AnyFooThing.__Unnamed_struct__details`、`extension AnyFooThing: … Swift.Equatable`，全文不出现 C 名）
   - 行为：`untrustedDeclaredNamePrintsCName`（`struct ProbeOwnerKey`，没有 `struct Key`）
   - 行为：`swiftSpellingKeepsModuleThatResolverFinds`（替身解析器：找到模块、没给 Swift 名时取描述符的名字 `ProbeModule.AnyFooThing`；给了 `ProbeOwner.Key` 时声明 `struct ProbeOwner.Key`、引用与扩展头 `ProbeModule.ProbeOwner.Key`）
   - 行为：`extensionHeaderSpellsLikeMemberTypes`
   - 行为：`cSpellingPrintsMangledNamesAndAsksNoResolver`（声明 `struct AGFooThing`、扩展 `extension __C.AGFooThing`，替身解析器被问 0 次）
   - 原计划的 `nonCImportedExtensionHeadersAreByteIdentical` 与 `abiDiffKeysAreUnchanged` 不单独写：两者由 MachOSwiftSection 的全量测试覆盖（快照与 diff 测试照旧通过），见决策日志。
3. ✅ **标注与命令行** —— MSS 的 `AnnotationRegionKind+CImportedTypeName.swift`、声明头包区域、`InterfaceRequest` 与 `InterfaceCommand`、README 与插件 skill（插件 `0.28.0`）
   - 行为：`markedDeclaredNameCarriesBothSpellings`（分离后的文本与不标注时逐字节相同）
   - 行为：`markedCSpellingCarriesTheSameNames`
   - 行为：`sameSpellingsAreNotMarked`
   - 行为：`regionKindRoundTripsDottedSwiftName`
   - 行为：`interfaceCImportedTypeNameSpelling`（`SwiftSectionCommandTests`：默认 `swift-name`，`c-name` 映射到 `.cName`，拒绝 `cName` 这种拼法）
   - MSS 功能分支已推送；RuntimeViewer 临时按分支钉（`RuntimeViewerCore/Package.swift` 的 TEMPORARY 注释）。
4. ✅ **RuntimeViewer Core** —— 两个选项、`RuntimeInterfaceCImportedTypeName`、接口字段、分离、`updateConfiguration`、打印配置映射
   - 行为（`CImportedTypeNameSpellingEngineTests`，对系统的 AttributeGraph）：`spellingDefaultsToSwiftNameInOlderPayload`、`spellingRawValuesAreStable`、`corpusPrintsSwiftNamesWhateverTheSpelling`、`swiftSpellingIsUniform`、`cSpellingIsUniform`、`interfaceCarriesCImportedTypeNamesWhenMarked`、`commentStructureIgnoresCImportedTypeNameRegions`
   - 行为（`SwiftSectionPrinterConfigurationTests`）：`changedSpellingReconfiguresOnce`（打印器只重配一次，接口缓存随之清掉）
   - 原计划的 `cNameSpellingRequestsNoTypeIndex` 不写：测试进程不打开类型索引（`RuntimeTypeNames.enableInThisProcess()` 只在服务进程调用），无从观察，代码是 `updateConfiguration(for:)` 里一行条件。`marksCImportedTypeNamesIsNeverStoredTrue` 改由第 6 步的 `togglingFlipsStoredSpelling` 一并断言。
5. **Bridge 的行尾标注** —— `SourceEditorBridging.swift`、`SourceEditorBridge.swift`、`LineAnnotationTests.swift`
   - 行为：`lineAnnotationSitsOnFirstLineOfItsRange`、`showingAgainReplaces`、`setSourceRemovesLineAnnotations`、`performingActionNotifiesDelegateWithIdentifier`、`contextualMenuOffersTheSameAction`
6. **AppCore 与 App** —— `ContentInterface`、`ContentTextViewModel`、`ViewModel.currentMergedGenerationOptions`、`ContentSourceEditorViewController`、面板
   - 行为（`CImportedTypeNameNoteTests`）：`notesNameCDeclarationUnderSwiftSpelling`、`notesNameSwiftTypeUnderCSpelling`、`noteRangeIsInUTF16`、`noNamesNoNotes`、`togglingFlipsStoredSpelling`
   - 原计划的 `mergedOptionsMarkCImportedTypeNamesWhereSourceEditorRuns` 不写：取决于 `SourceEditorFrameworks.availability`，包级测试里框架不在，写出来只是重复实现。
   - 编完用 SourceEditor 打开 AttributeGraph 的 `AnyWeakAttribute`，人工看一次提示与切换（交给用户目视）。
7. **收尾** —— RuntimeViewer 插件 skill（版本 `1.4.0` 是类型索引功能抬的、还没发布，不再抬）、抬 MSS pin、重解析五个锁文件、两边索引与本提案状态

**收尾时必须判断两件事**（判断结果写进决策日志，不允许沉默跳过）：

- **要不要配套专题文章** —— 可信规则与「为什么导入成成员的类型不改名」是下次维护最容易踩的，倾向写进 `Documentations/Internal/` 的一篇实现说明，或并入现有的类型名解析说明。
- **有没有引入新术语** —— 「C 导入类型名拼写」「可信的描述符名字」是否登记术语表。

## 决策日志

| 日期 | 变更 | 说明 |
|------|------|------|
| 2026-11-24 | Created as Draft | RuntimeViewer 显示 AttributeGraph 的 `AGWeakAttribute` 时，声明行是 Swift 名，扩展头与成员类型是 C 名；用户要求统一，并在 SourceEditor 里给一个能点击切换 Swift 名 / C 名的提示。 |
| 2026-11-24 | 提示用 Xcode 式的行尾标注 | 用户在「行尾标注」和「类型名后的胶囊标签」之间选了前者：不改接口文本，复制与导出不受影响。 |
| 2026-11-24 | 模块未知时写裸名 | 用户选了 `AnyWeakAttribute`，不选 `__C.AnyWeakAttribute`：与声明行完全一致。 |
| 2026-11-24 | 切换是全局生成选项 | 用户选了全局：存进设置、所有窗口一起变、面板里有同名开关，不做只管当前编辑栏的临时状态。 |
| 2026-11-24 | 提案放在 MachOSwiftSection | 照 RuntimeViewer 索引里两篇 cross-repository draft 的做法，跨仓库的唯一提案由最底层的仓库维护。 |
| 2026-11-24 | 导入成成员的类型不用描述符的名字 | 实测 shared cache：`NSAttributedStringKey` 的描述符只存 `Key`、`NSNotificationName` 只存 `Name`，二进制里没有父路径；ABI 名以描述符名字结尾的一律不信，代价是 `NSDecimal` → `Decimal` 这类也退回 C 名。 |
| 2026-11-24 | C 名模式等于 mangled 拼写 | 不解析模块：`UIKit.UICellConfigurationState` 会与同名 Swift 结构体混淆。 |
| 2026-11-24 | 扩展头一并修 | 扩展头不经解析器（读代码得出），和本提案改的是同一条路径；只改根在 `__C` 的扩展，其余逐字节不变。 |
| 2026-11-24 | 两次点击待用户确认 | 复刻版框架的横幅没有按钮，点横幅弹下拉框、按钮在下拉框里；先按原生两步加右键菜单做，要一次点击就得改 `Mx-Iris/SourceEditor`。 |
| 2026-11-24 | Accepted | 用户批准，开始实现。 |
| 2026-11-24 | 交互定为两次点击 | 用户确认按 Xcode 原生的两步做（横幅 → 下拉里的按钮，右键菜单也有），不改复刻版框架。 |
| 2026-11-24 | 两边都从远端的 `feature/swift-type-indexing-package` 切 | 远端比两边本地 `next` 多了验收时的修复（宏的配色、文档）；提案随功能分支的第一个提交走，因为两边本地 `next` 都有未推送的合并，不往 `next` 上单独提交提案。 |
| 2026-11-24 | In Progress | 第 1–4 步做完：MachOSwiftSection 的打印器、命令行与文档，RuntimeViewer Core。 |
| 2026-11-24 | kind 的分隔符改成 `\|` | 原设计的 U+001F 被 swift-semantic-string 拒绝：它不允许 kind 里出现任何控制字符（`AnnotationTag.validate`），它自己的标记就是控制字符。 |
| 2026-11-24 | C 名模式在标注时才问解析器 | C 名模式的声明名原先也去问解析器（为了标注里的 Swift 名），`cSpellingPrintsMangledNamesAndAsksNoResolver` 抓到了。改为只在 `marksCImportedTypeNames` 打开时问，打印的文字不受影响，RuntimeViewer 在 C 名模式下的提示仍能写出 SDK 给的 Swift 名。 |
| 2026-11-24 | MSS 测试用现场编译的 fixture | 原计划读系统 shared cache 的 AttributeGraph 与 SwiftUICore；改用 `CImportedTypeConformanceInterfaceTests` 那种测试里现场编译的桥接头 dylib，三种形状（顶层改名、`swift_wrapper` typedef 改名、导入成成员）都能精确构造，也不随系统版本变。RuntimeViewer Core 的引擎测试仍用系统的 AttributeGraph，那是报告的现场。 |
| 2026-11-24 | 两条行为测试并入全量与别的测试 | `nonCImportedExtensionHeadersAreByteIdentical`、`abiDiffKeysAreUnchanged` 由 MachOSwiftSection 全量测试覆盖；`marksCImportedTypeNamesIsNeverStoredTrue` 并入 `togglingFlipsStoredSpelling`；`cNameSpellingRequestsNoTypeIndex` 与 `mergedOptionsMarkCImportedTypeNamesWhereSourceEditorRuns` 在测试进程里无从观察（类型索引只在服务进程打开，SourceEditor 框架只在 App 里），不写。 |
| 2026-11-24 | 行尾标注的外观是我们自己的类别 | Xcode 的 issue 与 note 类别在 IDESourceEditor 里，不在复刻范围；取灰色、`info.circle.fill`、整行 8% 的淡灰，交给用户目视验收时再调。 |
