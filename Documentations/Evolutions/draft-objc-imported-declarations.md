# Draft - ObjC 类、category 与协议按 ClangImporter 的规则建成 Swift 声明

- **状态**: In Progress
- **创建日期**: 2026-11-10
- **最后更新**: 2026-11-10
- **关联提案**: [0079-swift-declared-objc-protocols](0079-swift-declared-objc-protocols.md)（Swift 定义的 `@objc` 协议：本提案把它为协议要求移植的命名规则与类型桥接推广到类、category 与任意协议）、[0048-objc-member-selector-recovery](0048-objc-member-selector-recovery.md)（ObjC 成员表：按 selector 把 ObjC 方法联结到 Swift 成员，本提案靠它把 Swift 实现的成员换成真实声明）、[0046-objc-implementation-class-recognition](0046-objc-implementation-class-recognition.md)（识别 `@objc @implementation` 类）；下游是 RuntimeViewer 的草案 `draft-objc-generated-interface`
- **实现分支 / PR**: `feature/objc-imported-declarations`（worktree `.worktrees/MachOSwiftSection-ObjCImportedDeclarations`，自 `next` 切出）

## 摘要

本库只把 Swift 声明打印成 Swift 接口，ObjC 类、category 与协议只有 MachOObjCSection 打出的 ObjC 头文件。RuntimeViewer 要做 Xcode 的 Generated Interface——把一个 ObjC 类显示成 Swift 导入它之后的样子——需要本库给出这种声明。0079 已经为 Swift 定义的 `@objc` 协议移植过 ClangImporter 的命名规则（`omitNeedlessWords`、初始化器、error 约定、subscript）与类型桥接，但只用在协议要求上。本提案把它推广到镜像里任意的 ObjC 类、category 与协议，建成三种新的声明模型，交给 `SwiftDeclarationPrinter` 打印。成员由 Swift 实现时（桥接出去的 Swift 类、`@objc @implementation` 类、Swift 写的 category），经 0048 的 ObjC 成员表联结到那个 Swift 成员，照抄它的真实声明，不再按规则推导。

## 方案

### 三种声明

| ObjC 一侧 | 打印成 | 新模型 |
|---|---|---|
| 类 | `open class Name : Superclass, Protocol… { … }` | `ObjCImportedClassDefinition` |
| category | `extension Name : Protocol… { … }`，category 名写进注释 | `ObjCImportedCategoryDefinition` |
| 协议 | `public protocol Name : Inherited… { … }`，optional 要求打 `@objc optional` | `ObjCImportedProtocolDefinition` |

- 协议沿用 0079 的 `ObjCProtocolRequirementBuilder`：它本来就从 `protocol_t` 记录与带类名的扩展类型编码建要求，只是现在只给 Swift 定义的协议用。
- 类名与协议名的换算沿用 0079 的 `ObjCRuntimeNames`：Swift 类按 `_TtC…` demangle，改过运行时名的经 `SwiftClassObjectIndex` 换回 Swift 名。与同一镜像里某个类同名的协议加 `Protocol` 后缀（`ImportName.cpp` 的规则；`NSObject` 固定换成 `NSObjectProtocol`）。
- C struct 与 union 不在本提案内。

### 成员

- **属性**：读属性表的特性串。`R` 打 `{ get }`，否则 `{ get set }`；类属性打 `class var`；`C` 打 `@NSCopying`，`W` 打 `weak`，既不是 `&` 也不是 `C` / `W` 的对象类型打 `unowned(unsafe)`。`BOOL` 属性有自定义 getter 时 Swift 名取 getter 的名字（`hidden` 打成 `isHidden`，`ImportName.cpp` 的 `isBoolType` 分支）。名字开头的缩写词改小写（`CGPath` 打成 `cgPath`），再照 importer 对属性名做删减：属性类型与所在的类相同时删掉名字里重复的类型名（`NSColor` 的类属性 `blackColor` 打成 `black`），属性类型来自特性串。属性的 getter 与 setter 不再单列成方法。
- **方法**：实例方法打 `open func`，类方法打 `open class func`。名字照 `ObjCImporterNaming`：`init` 家族成初始化器（可空性未知，打 `init!`），`objectAtIndexedSubscript:` 等四个 selector 成 subscript。error 约定只认 selector 里名为 `error` 的那一段（或以 `AndReturnError`、`WithError` 结尾的基名）：编码里的 `^@` 也可能是 `NSDictionary **`，`initWithRTF:documentAttributes:` 不能打成 `init(rtf:)`。
- **工厂方法**（`+colorWithRed:green:blue:alpha:`）：importer 只在返回 `instancetype` 时才把它转成 `convenience init(red:green:blue:alpha:)`，而类的方法编码只记 `@`，看不出来。见下文「没问就定的假设」。
- importer 隐藏或标为不可用的成员（`dealloc`、`.cxx_destruct`、ARC 下禁用的几个）照 importer 的做法处理，具体做法以第一步的对照为准。

### 类型从哪来

参数与返回值的类型按下面的顺序取，取到即止：

1. **联结上的 Swift 成员**（见「与 Swift 合并」）：精确，含可空性。
2. **类采纳的协议**（含协议的继承链）里同一 selector 的扩展类型编码：带类名与 block 签名（`@"NSString"`、`@?<v@?@"NSError">`）。clang 在每个引用某协议的镜像里都放一份它的 `protocol_t`，所以本镜像里就有。
3. **属性的特性串**（`T@"NSString"`）：给这个属性的 getter 与 setter。
4. **都没有**：`id` 与不知道类名的 `@` 打 `Any`；对象一律 `T!`，这正是 importer 对没有可空性标注的声明的做法。

第 4 档推出的名字会走偏：importer 靠参数的类名删掉多余的词，而类的方法编码只记 `@`。例如 `convertPoint:fromView:` 的第二个参数丢了类名 `NSView`，推出 `convert(_:fromView:)`，Swift 里的真名是 `convert(_:from:)`。所以推导出的成员沿用 0079 的做法：编译器从打印出的 Swift 名推出的 selector 与实际不同时，打 `@objc(selector)` 钉住原 selector。

### 与 Swift 合并

打印每个成员之前先查 0048 的 ObjC 成员表。方法实现能联结到一个 Swift 成员（IMP 处的 `To` 符号，或反汇编 thunk 找到的调用目标；只认这两档确定性证据，不认只按名字的第三档）时，打印那个 Swift 成员的声明，`Origin` 记为 `.swiftMember`；联结不上的才按上面的规则推导，`Origin` 记为 `.selector`。三种情形：

- **桥接出去的 Swift 类**（class data 的 Swift 位为 1）：类声明来自 Swift 的 `TypeDefinition`，与 Swift 一侧的 interface 相同；方法表里没有 Swift 成员认领的方法另列在后面，按规则推导并注明。
- **`@objc @implementation` 类**：类头（父类、协议）来自 ObjC 记录，成员来自 `@implementation` extension 里联结上的成员。这些 Swift 名就是编译器导入头文件时得到的名字，所以这种类的输出与 Xcode 的 Generated Interface 一致。
- **Swift 写给 ObjC 类的 category**（`extension NSView { @objc func … }`）：成员来自本镜像那个 `extension __C.NSView` 里联结上的成员。

### API 形状

照 0079 的 `ObjCProtocolDefinition` 与 `printObjCProtocolDefinition(_:level:)`：模型放 SwiftDeclaration，由 `SwiftDeclarationIndexer` 按名字现建（ObjC 类动辄上千个，不随索引一次建完，建过的缓存），打印器打印。category 按 MachOObjCSection 的 `uniqueName` 取，与 `ObjCInterfaceBuilder.categoryInterface(uniqueName:)` 一致。

```swift
// 最简单：一个纯 ObjC 类
if let definition = try indexer.objcImportedClassDefinition(named: "NSView") {
    let interface = try await printer.printObjCImportedClassDefinition(definition)
}

// 常见：桥接出去的 Swift 类，成员自动换成 Swift 声明，不需要调用方做什么
let contentView = try indexer.objcImportedClassDefinition(named: "_TtC8MyModule11ContentView")

// category 与协议
let category = try indexer.objcImportedCategoryDefinition(uniqueName: categoryUniqueName)
let dataSource = try indexer.objcImportedProtocolDefinition(named: "NSTableViewDataSource")
```

成员模型照 `ObjCProtocolRequirementDefinition` 的形状（`kind`、`node`、`selector`、`setterSelector`、`isClassMember`、`origin`、`hasExplicitSelector`），`Origin` 用 `.selector` 与 `.swiftMember(…)` 两种，与命名整理草案 `draft-swift-declaration-type-naming` 统一用的 `Origin` 一致。协议要求能否与它共用一个类型，实现时再定。

`swift-section objc interface` 加一个 `--swift` 开关，打印这种 Swift 声明而不是 ObjC 头文件，用于测试与下面的测量。

### 落地步骤

1. **准确率测量**（已完成，结果见下一节）：以 macOS 27.2 的 AppKit 为样本，从 SDK 取每个公开 ObjC 成员的 Swift 名（它的 USR 带 selector，例如 `c:objc(cs)NSView(im)convertPoint:fromView:`），再用已有的 `ObjCImporterNaming` 只凭运行时元数据推导，统计一致的比例，并按原因归类。
2. 三种模型、属性与方法的规则、类型的四档来源。
3. 与 Swift 合并。
4. 打印器与 `swift-section` 开关。
5. 测试：照 0079 的探针，用 `swift-synthesize-interface` 把只含二进制事实的 ObjC 头文件交给真正的 ClangImporter，作为命名规则的对照。

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

- 工厂方法：选择子开头能与类名末尾对上（`matchFactoryAsInitName` 的规则）、返回对象的类方法，按返回 `instancetype` 处理，打成 `convenience init`，并在注释里说明是推测。
- 不打 `async` 版本：importer 会给带 completion handler 的方法另打一个 `async` 版本，但类的方法编码里 block 没有签名，推不出结果类型。与 0079 一致，只打 completion handler 形式。
- 公开 API 不查 SDK：经 SourceKit 读 SDK 头文件能给公开 API 换上精确的名字，但要装 Xcode、只能在 macOS 上用，留作以后的提案。
- 发版：新增公开 API，随下一个小版本发布；RuntimeViewer 抬 pin 后接入。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-11-10 | Created as Draft | RuntimeViewer 要做 Xcode 的 Generated Interface，把 ObjC 对象显示成 Swift 接口；由 Swift 实现的类要与 Swift 一侧的信息合在一起 |
| 2026-11-10 | 在本库扩展已有的 ClangImporter 移植，不在运行时调用编译器 | 用户选定。纯 Swift，离线文件、iOS 与命令行都能用；调用 `swift-synthesize-interface` 要装 Xcode、每次几秒，而且输入缺的信息一样缺 |
| 2026-11-10 | 按轻量档写精简提案，与 RuntimeViewer 的草案各管一个仓库 | 用户选定；准确率测量放进落地第一步 |
| 2026-11-10 | 用户批准，开始实现；先做落地第一步的准确率测量，测量程序写完给用户看过再跑 | 用户批准时指定的顺序；按全局规则，自己写的脚本先给用户看 |
| 2026-11-10 | 第一步完成：只凭运行时元数据，AppKit 的公开成员有 80.8 % 与 SDK 的 Swift 名一致；「成员」一节补三条规则（属性缩写词小写、属性名删减、error 约定只认 `error` 段），状态改 In Progress | 用户看过测量程序后批准在 Ultra 上运行；三条都是移植的缺口，测量里分别对应 26、117、20 个成员。其余差异要 SDK 才能补，按原假设留给以后的提案 |
