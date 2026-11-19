# 0090 - ObjC 类、category 与协议按 ClangImporter 的规则建成 Swift 声明

- **状态**: Implemented
- **创建日期**: 2026-11-10
- **最后更新**: 2026-11-10
- **关联提案**: [0079-swift-declared-objc-protocols](0079-swift-declared-objc-protocols.md)（Swift 定义的 `@objc` 协议：本提案把它为协议要求移植的命名规则与类型桥接推广到类、category 与任意协议）、[0048-objc-member-selector-recovery](0048-objc-member-selector-recovery.md)（ObjC 成员表：按 selector 把 ObjC 方法联结到 Swift 成员，本提案靠它把 Swift 实现的成员换成真实声明）、[0046-objc-implementation-class-recognition](0046-objc-implementation-class-recognition.md)（识别 `@objc @implementation` 类）；下游是 RuntimeViewer 的提案 0084-objc-generated-interface
- **实现分支 / PR**: `feature/objc-imported-declarations`（自 `next` 切出，已合入 `next`）
- **配套文档**: [Modules/SwiftObjCInterop.md](../Internal/Modules/SwiftObjCInterop.md)（第 6 个子系统与两条契约）、[Modules/SwiftDeclaration.md](../Internal/Modules/SwiftDeclaration.md)「ObjC 声明按 Swift 导入的样子」、[ObjCCommandLine.md](../ObjCCommandLine.md)「The Swift view」

## 摘要

本库只把 Swift 声明打印成 Swift 接口，ObjC 类、category 与协议只有 MachOObjCSection 打出的 ObjC 头文件。RuntimeViewer 要做 Xcode 的 Generated Interface——把一个 ObjC 类显示成 Swift 导入它之后的样子——需要本库给出这种声明。0079 已经为 Swift 定义的 `@objc` 协议移植过 ClangImporter 的命名规则（`omitNeedlessWords`、初始化器、error 约定、subscript）与类型桥接，但只用在协议要求上。本提案把它推广到镜像里任意的 ObjC 类、category 与协议，建成三种新的声明模型，交给 `SwiftDeclarationPrinter` 打印。成员由 Swift 实现时（桥接出去的 Swift 类、`@objc @implementation` 类、Swift 写的 category），经 0048 的 ObjC 成员表联结到那个 Swift 成员，照抄它的真实声明，不再按规则推导。

## 方案

### 三种声明

| ObjC 一侧 | 打印成 | 新模型 |
|---|---|---|
| 类 | `class Name: Superclass, Protocol… { … }` | `ObjCImportedClassDefinition` |
| category | `extension Name: Protocol… { … }`，category 名写进注释 | `ObjCImportedCategoryDefinition` |
| 协议 | `protocol Name: Inherited… { … }`，optional 要求打 `optional` | `ObjCImportedProtocolDefinition` |

- 不打访问级别，推导出的成员也不打 `@objc`：本库打印的 Swift 接口一律不打访问级别，而这里的每个成员本来就是 ObjC 成员。只在编译器从打印出的名字推不回原 selector 时打 `@objc(selector)`。
- 类读的是类自己的方法表、属性表与协议表。dyld cache 会把 category 预先附加到类上（类的表变成「多张表的表」，别的镜像的 category 也在里面，类自己的那张排在本镜像的最后），这些 category 不算类的成员，与头文件里类的 `@interface` 一致。
- 链接器会把同一镜像里给本镜像的类写的 category 并进类自己的表，`__objc_catlist` 里不再有它们。所以 category 声明只出现在给别的镜像的类写的 category 上；Swift 给本镜像的 ObjC 类写的 `extension`、`@objc(Name) @implementation extension` 的成员都是类的成员。
- 协议沿用 0079 的 `ObjCProtocolRequirementBuilder`，加一个参数区分协议是 Swift 还是 ObjC 声明的（`DeclaringLanguage`）：ObjC 声明的协议，属性名照 importer 的属性规则改写，也不去掉 Swift 推导 selector 时插入的 `With`。
- 类名与协议名的换算沿用 0079 的 `ObjCRuntimeNames`：Swift 类按 `_TtC…` demangle，改过运行时名的经 `SwiftClassObjectIndex` 换回 Swift 名。ObjC 声明的类与协议保持 `__C` 下的 ObjC 名，与 mangling 一致；Swift 里改了名的（`NSObject` 协议是 `NSObjectProtocol`，与同模块某个类同名的协议加 `Protocol` 后缀）照本库的惯例交给打印时的类型名提供者，本提案不在模型里改名。
- C struct 与 union 不在本提案内。

### 成员

- **属性**：读属性表的特性串。`R` 打 `{ get }`，否则 `{ get set }`；类属性打 `class var`。所有权只打 Swift 写得出来的：`W` 打 `weak`；`C` 只在属性类型是 Swift 导入成类的类型时打 `@NSCopying`（`NSString`、`NSArray` 这类导入成值类型的不打）；可读写、又不是 `&` / `C` / `W` 的对象属性打 `unowned(unsafe)`；只读属性的特性串不记所有权，什么都不打。`BOOL` 属性有自定义 getter 时 Swift 名取 getter 的名字（`hidden` 打成 `isHidden`，`ImportName.cpp` 的 `isBoolType` 分支）。名字开头的缩写词改小写（`CGPath` 打成 `cgPath`），再照 importer 对属性名做删减：属性类型与所在的类相同时删掉名字里重复的类型名（`NSColor` 的类属性 `blackColor` 打成 `black`），属性类型来自特性串。属性的 getter 与 setter 不再单列成方法，属性排在 getter 在方法表里的位置。
- **方法**：实例方法打 `func`，类方法打 `class func`。名字照 `ObjCImporterNaming`：`init` 家族成初始化器（可空性未知，打 `init!`），`objectAtIndexedSubscript:` 等四个 selector 成 subscript。error 约定只认 selector 里名为 `error` 的那一段（或以 `AndReturnError`、`WithError` 结尾的基名）：编码里的 `^@` 也可能是 `NSDictionary **`，`initWithRTF:documentAttributes:` 不能打成 `init(rtf:)`。
- **工厂方法**（`+colorWithRed:green:blue:alpha:`）：importer 只在返回 `instancetype` 时才把它转成 `convenience init(red:green:blue:alpha:)`，而类的方法编码只记 `@`，看不出来。见下文「没问就定的假设」。
- importer 不导入的 selector 不打：`.cxx_construct`、`.cxx_destruct`、`dealloc`，以及 ARC 下禁用的 `retain`、`release`、`autorelease`、`retainCount`。

### 类型从哪来

参数与返回值的类型按下面的顺序取，取到即止：

1. **联结上的 Swift 成员**（见「与 Swift 合并」）：精确，含可空性。
2. **类采纳的协议**（含协议的继承链）里同一 selector 的扩展类型编码：带类名与 block 签名（`@"NSString"`、`@?<v@?@"NSError">`）。clang 在每个引用某协议的镜像里都放一份它的 `protocol_t`，所以本镜像里就有。参数个数与 selector 的冒号数对不上的编码不用，退回方法表自己的编码；两者都对不上的方法不打，免得把名字配给错的类型。
3. **属性的特性串**（`T@"NSString"`）：给这个属性的 getter 与 setter。
4. **都没有**：`id` 与不知道类名的 `@` 打 `Any`；对象一律 `T!`，这正是 importer 对没有可空性标注的声明的做法。

第 4 档推出的名字会走偏：importer 靠参数的类名删掉多余的词，而类的方法编码只记 `@`。例如 `convertPoint:fromView:` 的第二个参数丢了类名 `NSView`，推出 `convert(_:fromView:)`，Swift 里的真名是 `convert(_:from:)`。所以推导出的成员沿用 0079 的做法：编译器从打印出的 Swift 名推出的 selector 与实际不同时，打 `@objc(selector)` 钉住原 selector。

### 与 Swift 合并

打印器打印每个成员之前，先在实现这个类或 category 的 Swift 定义里找回答同一 selector 的成员：用 0048 记在每个 Swift 成员上的 `objcMember`（selector 与是否类方法），属性先按 getter、再按 setter 找，工厂方法按类方法找。找到就打印那个 Swift 成员的声明，找不到的才按上面的规则推导。证据先认 IMP 处的 `To` 符号与反汇编 thunk 找到的调用目标；这两档都没有时，也认只按名字的第三档（0048 只给覆写算这一档）：参与配对的定义就是实现这个类的那些，类方法表里的方法总有一个成员实现，名字对得上的就是它。配对在打印时做，模型里的成员不记来源。三种情形：

- **桥接出去的 Swift 类**（class data 的 Swift 位为 1）：类声明来自 Swift 的 `TypeDefinition`，与 Swift 一侧的 interface 相同。同一模块里 extension 的成员在 mangling 里就记成类自己的成员，已经在类里；本镜像里另外的 extension（带约束的、遵循协议的）跟在类后面打印。方法表里没有 Swift 成员回答的方法另列在一个 `extension` 里，按规则推导并注明。
- **`@objc @implementation` 类**：类头（父类、协议）来自 ObjC 记录，成员来自 `@implementation` extension 里配上的成员。这些 Swift 名就是编译器导入头文件时得到的名字，所以这种类的输出与 Xcode 的 Generated Interface 一致。
- **Swift 给 ObjC 类写的 extension**（`extension NSView { @objc func … }`、`@objc(Name) @implementation extension`）：类在本镜像里时，链接器已把它编成的 category 并进类的表，成员就打在类里；类在别的镜像里时是一个 category 声明。两种都从本镜像那个 `extension __C.NSView` 里配成员。

### API 形状

照 0079 的 `ObjCProtocolDefinition` 与 `printObjCProtocolDefinition(_:level:)`：模型放 SwiftDeclaration，由 `SwiftDeclarationIndexer` 按名字现建（ObjC 类动辄上千个，不随索引一次建完；镜像里的类与 category 记录按镜像缓存），第一次打印时索引自己，打印器打印。category 按 MachOObjCSection 的 `uniqueName` 取，与 `ObjCInterfaceBuilder.categoryInterface(uniqueName:)` 一致。

```swift
// 最简单：一个纯 ObjC 类
if let definition = indexer.objcImportedClassDefinition(named: "NSView") {
    let interface = try await printer.printObjCImportedClassDefinition(definition)
}

// 常见：桥接出去的 Swift 类，成员自动换成 Swift 声明，不需要调用方做什么
let contentView = indexer.objcImportedClassDefinition(named: "_TtC8MyModule11ContentView")

// category 与协议
let category = indexer.objcImportedCategoryDefinition(uniqueName: categoryUniqueName)
let dataSource = indexer.objcImportedProtocolDefinition(named: "NSTableViewDataSource")

// 镜像里有哪些
let classNames = indexer.objcImportedClassRuntimeNames
let categoryNames = indexer.objcImportedCategoryUniqueNames
```

成员模型 `ObjCImportedMemberDefinition` 照 `ObjCProtocolRequirementDefinition` 的形状：`kind`（方法、初始化器、工厂初始化器、属性、subscript）、`node`、`selector`、`setterSelector`、`isClassMember`、`ownership`、`hasExplicitSelector`、`typeEncoding`。协议要求直接用 `ObjCProtocolRequirementDefinition`，不另建类型。类定义带上 Swift 一侧：`swiftClassDefinition`（桥接出去的 Swift 类）与 `swiftExtensions`（本镜像里这个类的 Swift extension），category 定义带 `swiftExtensions`。

`swift-section objc interface` 加一个 `--swift` 开关（SwiftSectionKit 里是 `ObjCInterfaceRequest.printsSwiftImport`），打印这种 Swift 声明而不是 ObjC 头文件；类、category 与协议才有，struct 与 union 没有。

### 落地步骤

1. **准确率测量**（已完成，结果见下一节）：以 macOS 27.2 的 AppKit 为样本，从 SDK 取每个公开 ObjC 成员的 Swift 名（它的 USR 带 selector，例如 `c:objc(cs)NSView(im)convertPoint:fromView:`），再用已有的 `ObjCImporterNaming` 只凭运行时元数据推导，统计一致的比例，并按原因归类。
2. 三种模型、属性与方法的规则、类型的四档来源（已完成）。
3. 与 Swift 合并（已完成）。
4. 打印器与 `swift-section` 开关（已完成）。
5. 测试（已完成）：命名规则的期望值取自 SDK 里真正的 ClangImporter 给出的名字（第一步测量用的同一批 AppKit 成员），不再另跑 `swift-synthesize-interface`；记录读取与成员构建对进程内的 AppKit 测；与 Swift 合并、打印对 `@objc @implementation` 夹具测（纯 ObjC 类、`@implementation` 类、桥接出去的 Swift 类、Swift 声明的 `@objc` 协议，以及单独发布的 dylib 里给 `NSObject` 写的 category）。

### 第一步的测量结果

2026-11-10 在 Mac Studio Ultra（macOS 27.2，Xcode 27.2 27B52）上测。SDK 一侧用 `swift-symbolgraph-extract` 导出 AppKit 的符号图（连同 `AppKit@Foundation` 扩展图），以其中每个 ObjC 成员 USR 里的 selector 与它的 Swift 名为准；运行时一侧把 AppKit 载入进程，只读运行时的方法表与属性表，不发消息、不触发 `+initialize`。测量程序在临时分支 `probe/objc-importer-naming-accuracy`（`Sources/Executables/objc-importer-naming-probe`），不合并；逐个成员的结果表留在 Ultra 的 `/Volumes/DerivedData/Agents.noindex/claude/Probes/ObjCImporterNamingAccuracy/AppKit.tsv`。

比对了 6,937 个成员，另有 422 个在运行时找不到（实现在别的镜像，或只在头文件里声明）。每个方法按三种类型信息推导：只用运行时编码（对象都只是 `@`）、再加类采纳的协议里同一 selector 的扩展编码（协议成员用协议自己的扩展编码）、把 `@` 换成 SDK 声明的类型（类型信息能达到的上限）。

| 类别 | 个数 | 只用运行时编码 | 加协议的扩展编码 | 换成 SDK 的类型 |
|---|---|---|---|---|
| 实例方法 | 2,508 | 66.4 % | 66.7 % | 80.9 % |
| 类方法 | 177 | 53.7 % | 54.2 % | 67.2 % |
| 初始化器 | 428 | 56.3 % | 56.3 % | 58.2 % |
| 属性 | 2,726 | 94.5 % | 94.5 % | 94.5 % |
| 协议方法 | 1,023 | 76.7 % | 92.4 % | 91.6 % |
| 协议属性 | 75 | 100 % | 100 % | 100 % |
| 合计 | 6,937 | 78.4 % | 80.8 % | 86.3 % |

加上协议的扩展编码之后仍有 1,331 个对不上，其中 639 个只差参数标签。按 SDK 能说明的原因归类，一个成员可以属于几类：

- 换上 SDK 的类型就对（参数或返回值的类名丢了）：415。
- API notes 改过名：343。只按成员所在的类查，实际更多：父类的改名也管到子类重新声明的同一方法。例如 `NSResponder` 在 API notes 里把 `tryToPerform:with:` 定为 `tryToPerform(_:with:)`，`NSApplication.h` 重新声明了这个方法，于是 `NSApplication` 的这个方法也叫这个名字；推导出的 `try(toPerform:with:)` 正是 Swift 3 时代 API notes 里的旧名。
- 工厂方法被导入成初始化器：165。
- 属性名被 importer 缩短（`blackColor` 成 `black`）：117。
- 头文件里有 `NS_SWIFT_NAME`（文本搜索，只作参考）：49。
- 以上都不是：283。其中 113 个带整型参数，多半是枚举或选项集的类型名丢了（参数类型是 `NSEventMask` 时，`matchingMask:` 会被删成 `matching:`）；18 个带集合参数，元素类型丢了（`NSSet<NSIndexPath *>` 让 `…AtIndexPaths:` 删成 `…At:`）。

另外两处是移植本身的缺口：26 个属性只差开头缩写词的大小写（`CGPath` 对 `cgPath`），20 个方法把 `^@` 当成了 error 参数（`initWithRTF:documentAttributes:` 推成 `init(rtf:)`）。

对方案的影响：

1. 协议的扩展编码最关键（协议方法从 76.7 % 升到 92.4 %），照计划用。类方法借采纳协议的编码只多对了 7 个，因为这一档便宜、命中时又精确，仍然保留。
2. 「成员」一节补上三条：属性名开头的缩写词改小写、照 importer 删减属性名、error 约定只认名为 `error` 的那一段。工厂方法照原假设按 `instancetype` 推测，正好覆盖那 165 个。四条做完，估计合计能到 85 % 左右。
3. 剩下的差异靠运行时信息补不上：API notes 与 `NS_SWIFT_NAME`、枚举与选项集的类型名、集合的元素类型、由可空性推出的默认参数（`orderFrontStandardAboutPanelWithOptions:` 的 `With` 就是因为参数有默认值才被删掉），以及参数名（importer 不拆参数名为 `sender` 的方法）。这些只有查 SDK 才能拿到，照原假设留给以后的提案；推导出的名字照方案用 `@objc(selector)` 钉住原 selector。

### 没问就定的假设

- 工厂方法：选择子开头能与类名末尾对上（`matchFactoryAsInitName` 的规则）、返回对象的类方法，按返回 `instancetype` 处理，打成 `convenience init`。不逐个注明是推测：成员列表开头的注释已经说明这些名字是按 importer 的规则推出的。
- 不打 `async` 版本：importer 会给带 completion handler 的方法另打一个 `async` 版本，但类的方法编码里 block 没有签名，推不出结果类型。与 0079 一致，只打 completion handler 形式。
- 公开 API 不查 SDK：经 SourceKit 读 SDK 头文件能给公开 API 换上精确的名字，但要装 Xcode、只能在 macOS 上用，留作以后的提案。
- 发版：新增公开 API，随下一个小版本发布；RuntimeViewer 抬 pin 后接入。

## 后续项

- `objc interface --swift` 接上 `--resolve-c-module-names` 的类型名提供者：`NSObject` 协议才会打成 `NSObjectProtocol`，`CF…Ref` 才会去掉 `Ref`。
- 类型名提供者补上 ClangImporter 的一条规则：与同一模块里别的实体重名的协议加 `Protocol`（`NSAccessibilityElementProtocol` 这类）。TypeDatabase 现在只认 API notes 与 CF 规则，Swift 一侧的接口也受影响。
- `TypeDefinition.extensions` 从来没有人填：填上，或者删掉。
- 剥掉本地符号的镜像（dyld cache 里的 AppKit）中，`@objc @implementation` 类没有 Swift 符号的成员仍按规则推导，例如 `NSGlassEffectView` 的 `init(frame:)`。
- 查 SDK 拿精确名字（API notes、`NS_SWIFT_NAME`、枚举与选项集的类型名、可空性），带 completion handler 的方法的 `async` 版本，C struct 与 union 的 Swift 视图：都留给以后的提案。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-11-10 | Created as Draft | RuntimeViewer 要做 Xcode 的 Generated Interface，把 ObjC 对象显示成 Swift 接口；由 Swift 实现的类要与 Swift 一侧的信息合在一起 |
| 2026-11-10 | 在本库扩展已有的 ClangImporter 移植，不在运行时调用编译器 | 用户选定。纯 Swift，离线文件、iOS 与命令行都能用；调用 `swift-synthesize-interface` 要装 Xcode、每次几秒，而且输入缺的信息一样缺 |
| 2026-11-10 | 按轻量档写精简提案，与 RuntimeViewer 的草案各管一个仓库 | 用户选定；准确率测量放进落地第一步 |
| 2026-11-10 | 用户批准，开始实现；先做落地第一步的准确率测量，测量程序写完给用户看过再跑 | 用户批准时指定的顺序；按全局规则，自己写的脚本先给用户看 |
| 2026-11-10 | 第一步完成：只凭运行时元数据，AppKit 的公开成员有 80.8 % 与 SDK 的 Swift 名一致；「成员」一节补三条规则（属性缩写词小写、属性名删减、error 约定只认 `error` 段），状态改 In Progress | 用户看过测量程序后批准在 Ultra 上运行；三条都是移植的缺口，测量里分别对应 26、117、20 个成员。其余差异要 SDK 才能补，按原假设留给以后的提案 |
| 2026-11-10 | 用户批准接着实现第二到第五步，在 Ultra 上构建与测试，做完在本地合进 `next` | 用户选定 |
| 2026-11-10 | 类只读自己的表，不读 dyld cache 预先附加的 category | 起初读全部表，NSColor 打出了别的镜像的 category 成员与协议；头文件里类的 `@interface` 也只有类自己的成员 |
| 2026-11-10 | category 声明只覆盖给别的镜像的类写的 category；给本镜像的类写的 Swift extension 与 `@implementation` category 的成员打在类里 | 夹具实测：链接器把同镜像的 category 全部并进类的表，`__objc_catlist` 整段不存在，事后分不出哪些成员来自 category |
| 2026-11-10 | 不打访问级别，推导出的成员不打 `@objc`；原方案的 `open` / `public` / `@objc optional` 不用 | 本库的 Swift 接口一律不打访问级别；成员本来就是 ObjC 成员，`@objc` 只在要钉住 selector 时有信息量 |
| 2026-11-10 | 所有权只打 Swift 写得出来的：只读属性什么都不打，`@NSCopying` 只给导入成类的类型 | 只读属性的特性串不记所有权，按原规则会打出 `unowned(unsafe)`；`copy` 的 `NSString` 在 Swift 里是 `String`，`@NSCopying` 写不上去 |
| 2026-11-10 | 与 Swift 合并在打印器里做，成员模型不记 `Origin`；只按名字的第三档在前两档都没有时也认 | Swift 成员已经有自己的模型，再存一份是重复；参与配对的定义就是实现这个类的那些，第三档的成员只能是实现那个 selector 的成员。不认它时，thunk 被优化掉的覆写会按规则再打一遍 |
| 2026-11-10 | 协议要求复用 `ObjCProtocolRequirementBuilder`，加 `DeclaringLanguage` 区分 Swift 与 ObjC 声明的协议 | 两者只差属性名的规则与是否去掉 Swift 插入的 `With`，不值得另建一套 |
| 2026-11-10 | `Protocol` 后缀不在模型里做，节点保持 `__C` 下的 ObjC 名 | 本库的节点与 mangling 一致，Swift 里改了名的 `__C` 名由打印时的类型名提供者（`--resolve-c-module-names`）改写；`objc interface --swift` 还没接它，留作后续 |
| 2026-11-10 | 第五步不另跑 `swift-synthesize-interface`，命名规则的期望值取自 SDK 里 importer 给出的名字 | 第一步已经用 SDK 的符号图对过 6,937 个成员，同一来源更全，也不用在测试里依赖工具链 |
| 2026-11-10 | 实现完成，待用户看过后收尾 | 第二到第五步都已落地，SwiftObjCInteropTests 与新的 ObjCImportedDefinitionTests 在 Ultra 上通过 |
| 2026-11-10 | 用户看过后批准收尾；按本库 CLI 的规定补上请求与命令两侧的 `--swift` 测试，随库发布的 agent 插件 skill 同批写上 `--swift` | 本库规定新开关在请求与命令两侧各有一个测试，改 CLI 要同批更新插件 skill |
| 2026-11-10 | 落地编号 0090，状态改 Implemented。不另写实现说明与使用指南：维护者要知道的契约与坑写进 SwiftObjCInterop、SwiftDeclaration 两份模块参考，用法写进命令行指南的「The Swift view」一节；新术语「ObjC imported declaration」「category merging」登记进术语表 | 模块参考已经覆盖实现里看不出来的取舍，再写一篇实现说明只会复述；没做的几项记进「后续项」 |
