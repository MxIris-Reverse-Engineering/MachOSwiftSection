# Draft - Swift 实现的类，导入声明以 Swift 一侧为准

- **状态**: In Progress
- **创建日期**: 2026-11-17
- **最后更新**: 2026-11-17
- **关联提案**: [0090-objc-imported-declarations](0090-objc-imported-declarations.md)（本提案改它的「与 Swift 合并」）、[0048-objc-member-selector-recovery](0048-objc-member-selector-recovery.md)（把 ObjC 方法联结到 Swift 成员的三档证据）、[0046-objc-implementation-class-recognition](0046-objc-implementation-class-recognition.md)（认出 `@objc @implementation` 类）；RuntimeViewer 的提案 0084（Generated Interface）
- **跨仓库**: 本提案是三个库共用的唯一提案，MachOObjCSection 与 RuntimeViewer 的提案索引各有一行 cross-repository draft 指向这里；各库的部分见「三个库各做什么」
- **实现分支 / PR**: 三个仓库都是 `feature/swift-first-imported-declarations`（从各自的 `next` 切出）

## 摘要

RuntimeViewer 的 Generated Interface 显示 macOS 27.2 共享缓存里 SceneHosting 的 `SHScenePresentation`（一个 `@objc @implementation` 类）时，只有 5 个成员用上了 Swift 声明，其余都按 ClangImporter 的规则从 selector 推导，例如 `func isHostingSceneLayer(_: Any!) -> Swift.Bool`，而同一镜像的 Swift 一侧就有 `func isHosting(sceneLayer: __C.FBSceneLayer) -> Swift.Bool`。原因在 0090 的配对只认符号证据：系统框架剥掉了 `To` thunk 的符号，`-O` 又把 Swift 函数体整段内联进 thunk（`-[SHScenePresentation isHostingSceneLayer:]` 的实现不再调用 `isHosting(sceneLayer:)`），第二档找不到引用；只按名字配的第三档在 0048 里只算 override，0090 接上的也只有这一部分。

本提案让 Swift 实现的类以 Swift 一侧为准：Swift 一侧有的成员照它的声明打印，ObjC 一侧只补 Swift 一侧没有的。头文件标了 `NS_REFINED_FOR_SWIFT`、在 Swift 里改成 `__` 开头的成员，两边都标出来：Swift 视图写出它的 `__` 声明，ObjC 头文件打上这个宏。这一项跨三个库：本库判定哪些成员改了名，MachOObjCSection 在头文件里打宏，RuntimeViewer 把两者接起来。

## 方案

### 打印形状

- **`@objc @implementation` 类**（类的 Swift extension 里有 0046 认出的 `@implementation` 主体）改成与桥接出去的 Swift 类同一种形状：类头仍取 ObjC 记录的父类与协议；类体是 Swift 一侧 interface 里 `@implementation` extension 的内容，存储属性、`final` 的纯 Swift 成员都在；本镜像里这个类的其余 Swift extension 跟在类后面；ObjC 方法表里没有 Swift 成员回答的，按规则推导、加注明，放在类体最后。
- 桥接出去的 Swift 类形状不变。ObjC 实现、只被 Swift 扩展的类（夹具里的 `ClangWidget`）与 category 仍逐个成员替换。三种都用下面的配对：Swift 类末尾那个「没有 Swift 成员回答」的 extension 会少掉误列的成员。

### 配对：哪个 ObjC 成员有 Swift 成员回答

前两档（IMP 处的 `To` 符号、thunk 引用到的实现）不变。两档都没配上的 ObjC 成员，到实现这个类的 Swift 定义里、还没配上的成员中按名字找：

- 不再只限 override。在打印时做（`ObjCImplementingSwiftMembers`），不改 0048 在索引期记下的事实，dump 与 Swift 一侧的 interface 不受影响。
- 名字判据沿用 `ObjCMemberShape.isConsistent(withSelector:isClassMethod:)`，加一条：认 `NS_REFINED_FOR_SWIFT` 加的 `__` 前缀（属性名、方法基名、初始化器的第一个标签）。同一个 selector 既对得上 `__layerFilter`、又对得上纯 Swift 的 `layerFilter` 时取前者：头文件标了 `NS_REFINED_FOR_SWIFT` 的才是 ObjC 那个成员。
- 类型明显对不上的不配：ObjC 一侧是对象（`@`），Swift 成员的类型却是 Swift 与 Foundation 之外定义的 struct 或 enum；或者 ObjC 一侧是标量，Swift 成员却是类或 existential。宁可漏配，不配错，与 0048 一致。
- 仍然只在恰好一个候选时配。

### 改了 Swift 名字的成员（`NS_REFINED_FOR_SWIFT`）

只看 `@implementation` 类与被本镜像 Swift extension 扩展的 ObjC 类；桥接出去的 Swift 类没有头文件，不涉及。两种判定：

- **有凭据**：ObjC 成员配上的是 `__` 开头的 Swift 成员（`layerFilter` ↔ `__layerFilter`）。
- **推断**：ObjC 属性没配上，而 Swift 一侧有同名属性、类型明显对不上（`settings` 对上本模块的 struct `ScenePresentationSettings`）。Swift 不允许一个类型里有两个同名属性，ObjC 那个只能是在 Swift 里改了名。只用于属性：方法可以按参数类型重载，同名说明不了改过名。

两边怎么标：

- **Swift 视图**（Generated Interface）：有凭据的照 Swift 一侧打（`var __layerFilter: …`）。推断的没有 Swift 符号可抄，在类体末尾打一条结构化注释（`StructuredComment`），内容是按 importer 规则推出的 `__` 声明。
- **ObjC 头文件**：两种都在声明的分号前打 `NS_REFINED_FOR_SWIFT`。头文件由 MachOObjCSection 打印，由宿主告诉它哪些成员要打（见「三个库各做什么」）。

### Swift 一侧缺、ObjC 一侧有的事实

- `@implementation` 的存储属性没有 setter 符号时，现在一律打 `let`，可 `-O` 下 setter 常被内联进 thunk、不留符号。改为 ObjC 属性可写就打 `var`，特性串带 `W` 就加 `weak`：`scene` 由 `let scene: FBScene?` 变成 `weak var scene: FBScene?`。Swift 一侧的 interface 同样生效。
- 只剩 ivar、Swift 类型还原不出的存储属性（`observers`、`_isActive`）：Generated Interface 里有同名 ObjC 属性时，在原位置打这个属性的导入形式（`var observers: Any!`），代替注释。Swift 一侧的 interface 照旧打注释——那里要的是 Swift 的类型，ObjC 的类型不是它。

### 以 `SHScenePresentation` 为例

Generated Interface，现在（节选）：

```swift
class SHScenePresentation: __C.NSObject {
    var settings: __C.SHScenePresentationSettings! { get set }
    weak var scene: __C.FBScene! { get set }
    var layerFilter: __C.SHSceneLayerFilter! { get set }
    @objc var priority: Swift.Int { get set }
    func isHostingSceneLayer(_: Any!) -> Swift.Bool
}
```

改后（节选；注释的措辞实现时定）：

```swift
class SHScenePresentation: __C.NSObject {
    var observers: Any! { get set }
    // stored property layerController: Swift type not recoverable (ObjC ivar, …)
    weak var scene: __C.FBScene?
    var __layerFilter: __C.SHSceneLayerFilter { get set }
    var layerFilter: SceneHosting.SceneLayerFilter { get set }
    @objc var priority: Swift.Int { get set }
    var settings: SceneHosting.ScenePresentationSettings { get set }
    func isHosting(sceneLayer: __C.FBSceneLayer) -> Swift.Bool

    // Objective-C methods of the class that no Swift member answers to. …
    // NS_REFINED_FOR_SWIFT: var __settings: __C.SHScenePresentationSettings! { get set }
}
```

ObjC 头文件，改后（节选）：

```objc
@property (nonatomic, strong) SHSceneLayerFilter *layerFilter NS_REFINED_FOR_SWIFT; // getter IMP: …
@property (nonatomic, strong) SHScenePresentationSettings *settings NS_REFINED_FOR_SWIFT; // getter IMP: …
```

### 三个库各做什么

- **MachOObjCSection**：头文件渲染接受宿主按成员给出的 Swift 导入标注，形状照 Clang 的 API notes——方法以 selector 加实例/类方法为键，属性以名字加实例/类属性为键，每项是一个可以加属性的值类型。现在只有 `isSwiftPrivate`（API notes 的 `SwiftPrivate`，即 `NS_REFINED_FOR_SWIFT`），日后的 `NS_SWIFT_NAME` 是再加一个 `swiftName`。`ObjCInterfaceBuilder` 打印类的两个入口（`classInterface`、`markedClassInterface`）多一个参数，默认为空；宏打在属性与方法声明的分号前、行尾注释之前。不传时输出逐字节不变。只接类，category 与协议先不接。

  ```swift
  // 类型与参数的名字实现时定
  var notes = ObjCSwiftImportNotes()
  notes[.property(named: "settings")] = .init(isSwiftPrivate: true)
  let header = builder.classInterface(named: "SHScenePresentation", options: options, swiftImportNotes: notes)
  ```

- **本库**：上面的配对、打印形状、存储属性两条，以及一个查询：一个类里哪些 ObjC 成员是 `NS_REFINED_FOR_SWIFT`。查询用本库自己的类型——本库按版本依赖 MachOObjCSection，直接用它的新类型就得先等它发版、再抬下限。
- **RuntimeViewer**：抬锁文件里两个库的修订号（两个都按 `branch: "next"` 依赖，不等发版），Generated Interface 由此得到改动。服务进程打印一个 ObjC 类的头文件之前，向同一镜像的 Swift section 要这个类改了名的成员，转成 MachOObjCSection 的标注；镜像没有 Swift section、或这个类没有 Swift 参与时不传。Find 语料里的头文件同样带上，与显示逐字一致——Find 按位置高亮结果。标注只在服务进程里用，请求与回复没有新字段，混版本不受影响。

### 没问就定的假设

- 纯 Swift 成员（`final`、`@nonobjc`）照打：Swift 一侧有的就以它为准。
- `@objc` 照 Swift 一侧原样打：符号证据配上的成员带，名字配上的不带。
- category 不改成 Swift 优先，也不标 `NS_REFINED_FOR_SWIFT`：同一个类的几个 category 共用这个镜像里这个类的全部 Swift extension，分不清哪个成员属于哪个 category。
- 镜像里根本没有 Swift 符号的成员（0090 后续项里 `NSGlassEffectView` 的 `init(frame:)`）仍按规则推导：Swift 一侧确实没有它。
- `__` 名字照 importer 的规则推：属性名与方法基名加 `__`，初始化器加在第一个标签上。
- 本库的公开 API 只多「一个类哪些成员是 `NS_REFINED_FOR_SWIFT`」这一个查询；Swift 优先的打印在打印器内部，`ObjCImportedClassDefinition` 已带着 `swiftExtensions`。
- `NS_SWIFT_NAME` 不在本提案，见后续项。

### 落地步骤

1. （已完成）MachOObjCSection：头文件渲染接受宿主给的 Swift 导入标注、打出 `NS_REFINED_FOR_SWIFT`；测试覆盖属性、实例方法、类方法，不传标注时输出逐字节不变，marked 形式投影后与普通形式一致；文档写进它的使用指南「库调用方」一节与下一个版本的 Changelog。
2. 本库测试先红：夹具加一个照 `SHScenePresentation` 写的 `@implementation` 类，成员 `public`，像系统框架那样留下导出符号——一个让 importer 把类型名拆成标签的方法（`isHosting(sceneLayer:)` 那种）、一对 `NS_REFINED_FOR_SWIFT` 属性加同名的纯 Swift 属性（一个留下 `__` 成员的符号、一个不留）、一个 `weak` 可写存储属性、一个只留 ivar 的存储属性。在 `.optimizedStripped` 变体上断言 Generated Interface 与改名查询的结果，先确认它们在改动前失败。
3. 本库实现：配对、打印形状、改了 Swift 名字的成员（判定、Swift 视图的注释、给宿主的查询）、存储属性的两条。
4. RuntimeViewer：抬两个库的修订号；ObjC 头文件的显示与 Find 语料带上标注，测试接线；在 App 里看 `SHScenePresentation` 复核（交互验收由用户做）。
5. 文档：模块参考 SwiftObjCInterop 与 SwiftDeclaration 里「ObjC 声明按 Swift 导入的样子」、命令行指南的「The Swift view」、演进账本、术语表；插件 skill 里讲 `objc interface --swift` 输出的地方一并核对。

## 后续项

- `NS_SWIFT_NAME`：配上的 Swift 成员的名字与 importer 推出的名字不同时，头文件里打 `NS_SWIFT_NAME(…)`。推导要用上 Swift 成员的参数类型——只凭 `@` 推不准，`isHostingSceneLayer:` 拿 `FBSceneLayer` 才推得出 `isHosting(sceneLayer:)`。MachOObjCSection 的标注已为它留了位置。
- `swift-section objc interface` 与 `objc dump` 也打这个宏：要 MachOObjCSection 先发带新接口的版本，本库再抬依赖下限。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-11-17 | Created as Draft | RuntimeViewer 的 Generated Interface 里，系统框架中的 `@objc @implementation` 类大多数成员仍是按 selector 推导的名字与 `Any!`；用户要求 Swift 实现的类以 Swift 一侧的类型与签名为准，只有 Swift 一侧没有的才用 ObjC 一侧的 |
| 2026-11-17 | ObjC 属性与 Swift 一侧的属性同名而类型对不上时（`settings`），Swift 视图用结构化注释写出它的 `__settings` 声明，ObjC 头文件给它标 `NS_REFINED_FOR_SWIFT`；MachOObjCSection 现在不会打这个宏，要给它加上，接口为日后的 `NS_SWIFT_NAME` 留好位置 | 用户选定。两边各用自己的语言说同一件事，与 SDK 里头文件和它导入后的样子一致 |
| 2026-11-17 | 本库用自己的类型给出改了名的成员，由 RuntimeViewer 转成 MachOObjCSection 的输入；`swift-section` 的 ObjC 头文件暂不打这个宏 | 本库按版本依赖 MachOObjCSection，直接用它的新类型就得先发版、再抬下限；RuntimeViewer 按分支依赖两个库，不用等 |
| 2026-11-17 | 三个库共用这一份提案，另两个仓库的提案索引各加一行 cross-repository draft | 一次改动一份提案；MachOObjCSection 的索引里已有这种跨仓库草案的先例 |
| 2026-11-17 | 用户批准，开始实现 | 按 MachOObjCSection → 本库 → RuntimeViewer 的顺序做，三个仓库各一条 `feature/swift-first-imported-declarations` |
