# Draft - ObjC 类、category 与协议按 ClangImporter 的规则建成 Swift 声明

- **状态**: Accepted
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

- **属性**：读属性表的特性串。`R` 打 `{ get }`，否则 `{ get set }`；类属性打 `class var`；`C` 打 `@NSCopying`，`W` 打 `weak`，既不是 `&` 也不是 `C` / `W` 的对象类型打 `unowned(unsafe)`。`BOOL` 属性有自定义 getter 时 Swift 名取 getter 的名字（`hidden` 打成 `isHidden`，`ImportName.cpp` 的 `isBoolType` 分支）。属性的 getter 与 setter 不再单列成方法。
- **方法**：实例方法打 `open func`，类方法打 `open class func`。名字照 `ObjCImporterNaming`：`init` 家族成初始化器（可空性未知，打 `init!`），`…error:` 成 `throws`，`objectAtIndexedSubscript:` 等四个 selector 成 subscript。
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

1. **准确率测量**（实现之前做）：以本机 macOS 27.2 cache 里的 AppKit 为样本，经 SourceKit 的 `docinfo` 从 SDK 取每个公开 ObjC 成员的 Swift 名（它的 USR 带 selector，例如 `c:objc(cs)NSView(im)convertPoint:fromView:`），再用已有的 `ObjCImporterNaming` 只凭运行时元数据推导，统计完全一致、只差标签、基名不同的比例，并按原因归类（参数丢了类名、`NS_SWIFT_NAME`、工厂方法、`BOOL` 属性等）。结果写回本提案，用来排第 2、3 档的优先级。测量脚本先给用户看过再跑。
2. 三种模型、属性与方法的规则、类型的四档来源。
3. 与 Swift 合并。
4. 打印器与 `swift-section` 开关。
5. 测试：照 0079 的探针，用 `swift-synthesize-interface` 把只含二进制事实的 ObjC 头文件交给真正的 ClangImporter，作为命名规则的对照。

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
