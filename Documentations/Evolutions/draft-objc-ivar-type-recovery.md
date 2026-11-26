# Draft - `@objc @implementation` 只剩 ivar 的存储属性按 ObjC 类型还原 Swift 类型

- **状态**: In Progress
- **作者**: JH
- **创建日期**: 2026-11-26
- **最后更新**: 2026-11-26
- **所属愿景**: 无
- **关联提案**: [0046 objc-implementation-class-recognition](0046-objc-implementation-class-recognition.md)、[0096 swift-first-imported-declarations](0096-swift-first-imported-declarations.md)、[0090 objc-imported-declarations](0090-objc-imported-declarations.md)、[0106 c-imported-type-name-spelling](0106-c-imported-type-name-spelling.md)
- **实现分支 / PR**: `feature/objc-ivar-type-recovery`
- **配套文档**: 待定 —— 落地时登记实现说明 / 使用指南的链接
- **网页版**: 同目录同名的 `.html`

## 摘要

`@objc @implementation` 类的存储属性一旦没有了 `…vpWvd` 字段偏移符号（系统框架剥过符号后几乎全是这样），Swift interface 只打一行注释 `// stored property x: Swift type not recoverable (ObjC ivar, offset …, encoding "…")`。本提案让 interface 与 `dump` 在 ObjC 一侧给得出类型时还原出声明：ivar 的 type encoding 是编译器写的完整 encoding（不是空串也不是 `?`）时，Swift 类型就是这个 ObjC 类型本身（不桥接），按 encoding 还原；encoding 是 `?` 时，Swift 类型是 ObjC 属性类型的桥接形态，按 ObjC 属性的 `T` 特性还原（`NSString` → `String`）。对象类型的可空性未记录，写成 `T!`；`var` / `let` / `weak` 按 ObjC 属性的特性；C 基本类型可以按调用方给的 C 类型替换表改写（`double` → `CGFloat`），与 ObjC 头文件一侧的 C Type Replacement 一致。空 encoding（非 `@objc` 的纯 Swift 属性）仍然只打注释。

## 动机

RuntimeViewer 看 Mac Catalyst 的 UIKitCore，`__C._UISplitViewControllerAdaptiveLayoutTransition` 的 24 个存储属性全部是注释，而同一个类的 ObjC 头文件一侧已经把其中 12 个的类型打出来了（`@property (nonatomic, strong) UIView *mutableContainerView;`、`BOOL mutableIsAnimated`、`CGFloat mutableInteractiveProgress` 等）。用户看 Swift 一侧时得自己去翻 ObjC 一侧、再在脑子里换成 Swift 类型。

现状来自两次有意的决定：0046 给只剩 ivar 的存储属性打「诚实注释、不编类型」；0096 让 Generated Interface 用 ObjC 属性的导入形式代替注释，但明确「Swift 一侧的 interface 照旧打注释——那里要的是 Swift 的类型，ObjC 的类型不是它」。这条理由只对需要桥接的类型成立：编译器写完整 encoding 的前提恰恰是 Swift 类型能原样表示成 ObjC 类型（见前期调研），这时 ObjC 类型就是 Swift 类型；需要桥接的写 `?`，桥接规则又是确定的。所以两类都能还原，只是可空性与集合的泛型参数不在 encoding 里。

## 前期调研

- **编译器怎么写 ivar 的 encoding**：`swift/lib/IRGen/GenClass.cpp` 的 `buildIvar`（约 2083–2096 行）：只有 `varDecl->isObjC() && varDecl->hasStorage()` 才写 encoding；类型 `isTriviallyRepresentableIn(ForeignLanguage::ObjectiveC, …)` 时调 `getObjCEncodingForPropertyType`，否则写 `"?"`（注释原文：「"Unknown type" - used when ObjC classes are bridged to separate Swift types」）；不是 `@objc` 的存储属性 encoding 为空串。`isTriviallyRepresentableIn`（`lib/AST/Type.cpp` 3481 行）对 `Trivial` 与 `Object` 返回 true，对 `Bridged` / `BridgedError` / `StaticBridged` / `None` 返回 false。
- **encoding 与 ObjC 属性的 `T` 特性是同一个函数算的**：`getObjCEncodingForPropertyType`（`lib/IRGen/GenObjC.cpp` 1267 行）取 getter 的 foreign 结果类型对应的 clang 类型，交给 clang 的 `getObjCEncodingForPropertyType`；属性表的 `T` 特性也走它（`GenClass.cpp` 2192 行）。所以 encoding 为 `?` 的 ivar，它的 ObjC 属性 `T` 特性给的是桥接后的 ObjC 类型（`T@"NSString"`）。
- **encoding 不带的信息**：可空性（`UIView` / `UIView?` / `UIView!` 都是 `@"UIView"`）、typedef（`CGFloat`、`NSTimeInterval` 都是 `d`，`NSInteger` 与 `Int` 都是 `q`）、`NSArray` 等的泛型参数（`T@"NSArray"`）、block 的签名（ivar 与属性都只写 `@?`）。
- **已有的转换**：`Sources/Analysis/SwiftObjCInterop/ObjCImportedTypes.swift` 的 `ObjCImportedTypes.typeNode(_:position:)` 按 ClangImporter 的规则把 `ObjCEncodedType` 转成 `Type` 节点：桥接类（`ObjCBridgedStructures`、`NSArray` / `NSDictionary` / `NSSet` / `NSError`）转值类型，`id` 转 `Any`，可空的对象类型转 `T!`，类名经 `ObjCRuntimeNames.classNode(forRuntimeName:in:)` 找 Swift 类、找不到就是 `__C.<Name>`；`__C` 名在打印时经 C 导入类型名改写（0106，接 swift-type-indexing 的 SDK 索引）换成 Swift 名。`ObjCTypeEncoding.type(from:)` 与 `propertyType(fromAttributes:)` 解析 encoding 与 `T` 特性（`ObjCTypeEncoding.swift` 115–132 行）。
- **现状的渲染路径**：`Sources/Output/SwiftPrinting/SwiftDeclarationPrinter+ObjCImplementation.swift` 的 `renderUnrepresentedObjCImplementationInstanceVariables`：有 `Wvd` 符号的 ivar 打 `var name: Type`，否则（Generated Interface 有 stand-in 时打 stand-in）打 `unrecoverableStoredPropertyComment`。`dump` 一侧在 `Sources/Output/SwiftDump/Dumper/ObjCImplementationClassDumper.swift` 约 142–160 行，注释部分写 `Swift type not recoverable`。ObjC 属性与 ivar 的对应：`ObjCImplementationClassFacts.objcProperty(storedIn:swiftPropertyName:)`（先认 `V<ivar>`，再认同名）。
- **ObjC 一侧的 C 类型替换**：MachOObjCSection 的 `Transformer.CType`（`ObjCOutputTransformer`，`Pattern` 13 种 C 基本类型）。RuntimeViewer 在 `RuntimeObjCSection.builderInputs(for:)` 里把它转成 `[ObjCPrimitiveTypePattern: String]` 交给 ObjC 渲染；Swift 打印目前拿不到这份替换表。`ObjCOutputTransformer` 只依赖 `OutputTransformer` 与 `Semantic`。
- **实例**：UIKitCore（macOS 27.2 的 iOSSupport）`_UISplitViewControllerAdaptiveLayoutTransition` 的 24 个 ivar：12 个空 encoding、1 个 `?`（`identifier`，ObjC 属性 `NSString *`）、11 个完整 encoding（`@"UIView"`、`@"<_UISplitViewControllerAdaptiveLayout>"`、`B`、`d` 等）。

## 提议方案

在 `SwiftObjCInterop` 加一个只依赖 ivar 事实与 ObjC 属性的还原函数，interface 与 dump 共用：

1. **encoding 完整**（非空、非 `?`）：`ObjCTypeEncoding.type(from:)` 解析后按「原样表示」规则转成 `Type` 节点——与导入规则只差三处：桥接类保持类本身（`NSString` 还是 `NSString`），`id` 是 `AnyObject`，block / 位域 / 不认识的类型 / 无名结构体还原不出（返回 `nil`，保持注释）。
2. **encoding 是 `?`**：找 ivar 对应的 ObjC 属性，按它的 `T` 特性走现有的导入规则（`NSString` → `String`、`NSArray` → `[Any]`、`id` → `Any`）；没有 ObjC 属性、或 `T` 是 block 等还原不出的类型，保持注释。
3. **空 encoding**：保持注释，二进制里没有任何类型信息。
4. **可空性**：可空的类型写 `T!`（ClangImporter 对无可空性标注的声明的写法，Generated Interface 也这样写）；ObjC 属性是 `weak` 时写 `weak var x: T?`（`weak` 必为可选）。
5. **`var` / `let`**：有 ObjC 属性且是 `readonly` 写 `let`，否则 `var`——与已有的「存储属性按 setter 判 `var` / `let`」同一规则（`printThrowingObjCImplementationStoredProperty`）。
6. **C 类型替换**：`SwiftDeclarationPrintConfiguration` 新增 `cTypeReplacements: [Transformer.CType.Pattern: String]`（默认空）与 `applyTransformers(_: Transformer.ObjCConfiguration)`；还原出的类型本身是 C 基本类型、且表里有替换时，打替换的名字（`var interactiveProgress: CGFloat`）。调用方（RuntimeViewer）把 ObjC 一侧的 C Type Replacement 设置原样交进来，两侧显示一致。
7. **dump**：同一个还原函数，ivar 行打成 `var name: Type`，注释里的 `Swift type not recoverable` 换成类型来源（`Swift type from the ObjC type encoding` / `Swift type from the ObjC property`）。

**没有询问就采用的假设**（用户可以推翻）：

- 还原出的声明不加「类型来自 encoding」的逐行标注：完整 encoding 的类型除可空性外是精确的，`!` 已经说明可空性未知；`dump` 的注释写明来源。
- C 类型替换只作用于「类型本身就是 C 基本类型」的情况，不改指针参数、元组里的基本类型；`dump` 不接替换表。
- `copy` 特性不还原成 `@NSCopying`：对桥接值类型没有意义，对类类型也无从确认源码写了它。
- Generated Interface 已有的 stand-in（0096）不变：它的定位是「ObjC 一侧如何导入」，与本提案的 Swift 一侧不同。

### 非目标

- 不改有 `Wvd` 符号或有 accessor 类型的存储属性。
- 不给空 encoding 的 ivar 猜类型（按大小猜 `Bool`、闭包之类）。
- 不让 `swift-section interface` 新增 `--c-type-replacement` 参数（CLI 另议，写进后续项）。
- RuntimeViewer 一侧的接入（把 `transformer.objc.cType` 交给 Swift 打印、抬依赖版本）不在本仓库，见后续项。

## 改动地图

| 文件 / 类型 | 动作 | 改什么 | 为什么 | 步骤 |
|---|---|---|---|---|
| `Sources/Analysis/SwiftObjCInterop/ObjCInstanceVariableSwiftType.swift` · `ObjCInstanceVariableSwiftType` | 新增 | 还原结果（`Type` 节点、来源、顶层 C 基本类型、ObjC 属性的 `readonly` / `weak`）与 `init?(instanceVariable:objcProperty:in:)` | interface 与 dump 共用一处判定 | 1–3 |
| `Sources/Analysis/SwiftObjCInterop/ObjCImportedTypes.swift` · `ObjCImportedTypes` | 修改 | 新增 `triviallyRepresentedTypeNode(_:)` 与 `bridgedTypeNode(_:)`（还原不出时 `nil`），内部给 `bareTypeNode` / `objectNode` 加「是否桥接」 | 复用导入规则，只换三处差异 | 2–3 |
| `Sources/Output/SwiftPrinting/SwiftDeclarationPrintConfiguration.swift` | 修改 | 新增 `cTypeReplacements` | 调用方传 C 类型替换表 | 1 |
| `Sources/Output/SwiftPrinting/SwiftDeclarationPrintConfiguration+Transformers.swift` | 修改 | 新增 `applyTransformers(_: Transformer.ObjCConfiguration)` | 与 Swift 一侧的 `applyTransformers` 对称 | 4 |
| `Package.swift`（`SwiftPrinting` target） | 修改 | 依赖 `ObjCOutputTransformer` | `Transformer.CType.Pattern` 在那里 | 1 |
| `Sources/Output/SwiftPrinting/SwiftDeclarationPrinter+ObjCImplementation.swift` | 修改 | `renderUnrepresentedObjCImplementationInstanceVariables` 先试还原，还原不出才打注释 | 行为本身 | 2–4 |
| `Sources/Output/SwiftDump/Dumper/ObjCImplementationClassDumper.swift` | 修改 | ivar 行用同一还原，注释写来源 | dump 与 interface 一致 | 5 |
| `Sources/TestSupport/SwiftSectionTestingSupport/ObjCImplementationFixture.swift` | 修改 | 新增 `AdaptiveTransitionWidget`（照 `_UISplitViewControllerAdaptiveLayoutTransition`）：类、协议存在类型、`BOOL`、`CGFloat`、`NSRange`、`readonly` 的 `NSString`、`weak`、`NSArray<NSString *>`、`id`、纯 Swift 属性 | 覆盖每种 encoding | 1 |
| `Tests/SwiftInterfaceTests/ObjCImplementationClassRecognitionTests.swift` | 修改 | 类集合断言加新类；`count` 的断言改成还原后的声明；新增还原的测试 | 行为清单 | 1–4 |
| `Tests/SwiftDumpTests/ObjCImplementationClassDumpTests.swift` | 修改 | dump 的还原断言 | 行为清单 | 5 |
| `Documentations/Internal/Modules/SwiftObjCInterop.md` 等模块说明、`ProjectEvolutionLog.md` | 修改 | 记录还原规则 | 文档同批 | 5 |

## 架构图

```text
SwiftObjCInterop
  ObjCImplementationClassFacts.InstanceVariable   (typeEncoding, swiftTypeNode?)
  ObjCImplementationClassFacts.Property           (attributes: T…,R,W,V…)
+ ObjCInstanceVariableSwiftType(instanceVariable:objcProperty:in:)
+   encoding complete   -> ObjCTypeEncoding.type(from:)          -> ObjCImportedTypes.triviallyRepresentedTypeNode
+   encoding "?"        -> ObjCTypeEncoding.propertyType(fromAttributes:) -> ObjCImportedTypes.bridgedTypeNode
+   encoding ""         -> nil
  ObjCImportedTypes
    typeNode(_:position:)                          (unchanged: imported declarations)
+   triviallyRepresentedTypeNode(_:) -> Node?
+   bridgedTypeNode(_:) -> Node?

SwiftPrinting
  SwiftDeclarationPrintConfiguration
+   cTypeReplacements: [Transformer.CType.Pattern: String]
  renderUnrepresentedObjCImplementationInstanceVariables
    swiftTypeNode (Wvd)?           -> var name: Type
    standIn (Generated Interface)? -> imported ObjC property
+   ObjCInstanceVariableSwiftType? -> [weak] var|let name: Type[!|?]   (C primitive -> replacement)
    else                           -> // stored property …: Swift type not recoverable (…)

SwiftDump
  ObjCImplementationClassDumper
~   ivar row: + recovered `var name: Type`, comment names the type's source
```

```text
_UISplitViewControllerAdaptiveLayoutTransition (UIKitCore, stripped)
  ivar mutableContainerView  "@\"UIView\""                      -> var mutableContainerView: UIView!
  ivar mutableNewLayout      "@\"<_UISplitView…AdaptiveLayout>\"" -> var mutableNewLayout: (any _UISplitView…AdaptiveLayout)!
  ivar mutableIsAnimated     "B"                                -> var mutableIsAnimated: Bool
  ivar mutableInteractiveProgress "d"  + [double: CGFloat]      -> var mutableInteractiveProgress: CGFloat
  ivar identifier            "?"  + property T@"NSString",R     -> let identifier: String!
  ivar animations            ""                                 -> // stored property animations: Swift type not recoverable (…)
```

## 详细设计

```swift
// SwiftObjCInterop
package struct ObjCInstanceVariableSwiftType {
    package enum Source: Sendable, Hashable {
        /// The ivar's own type encoding, written only for a Swift type that
        /// Objective-C represents as it is.
        case instanceVariableEncoding
        /// The `T` attribute of the Objective-C property synthesized on the
        /// ivar, whose type is the bridged one when the ivar says `?`.
        case objcProperty
    }

    /// The `Type` node, unknown nullability already spelled (`T!`, or `T?`
    /// for a `weak` property).
    package let typeNode: Node
    package let source: Source
    /// The C primitive the type is, for a caller's replacement spelling.
    package let primitiveType: ObjCPrimitiveType?
    package let isReadOnly: Bool
    package let isWeak: Bool

    package init?(instanceVariable: ObjCImplementationClassFacts.InstanceVariable, objcProperty: ObjCImplementationClassFacts.Property?, in machO: some MachOSwiftSectionRepresentableWithCache)
}
```

- `ObjCPrimitiveType` 是 `SwiftObjCInterop` 内的 13 种 C 基本类型（与 `Transformer.CType.Pattern` 同名同序，按 `rawValue` 对应），让 SwiftObjCInterop 不必依赖 `ObjCOutputTransformer`。
- `typeNode` 由 `ObjCImportedTypes` 产出；可空判定沿用 `isNullable`（对象、block、`Class`、`char *`、指针）。
- 打印：`cTypeReplacements[Pattern(rawValue: primitiveType.rawValue)]` 非空时打 `TypeName(kind: .other, replacement)`，否则 `printType(typeNode)`。
- 打印用的节点是每次打印新建的 transient 节点，由局部常量持有到打印结束，满足「交给 interface printer 的节点必须活过这次打印」。

## 替代方案考量

- **只用 ObjC 属性、不看 ivar 的 encoding**：两者对完整 encoding 给的是同一个类型，但没有 ObjC 属性的 ivar 就还原不出；encoding 是 `?` 时又只能看属性。所以按 encoding 分流。
- **Swift 一侧也直接打 Generated Interface 的 stand-in**：stand-in 按导入规则桥接，完整 encoding 的 `NSString` 会被打成 `String`，`id`（`AnyObject`）打成 `Any`，是错的。
- **可空性一律写 `T?` 或 `T`**：都是在猜；`T!` 是 ClangImporter 对「可空性未知」的既有写法。用户确认用 `T!`。
- **`d` 一律写 `CGFloat`**：`NSTimeInterval` 等也是 `d`。用户决定走调用方的 C 类型替换表，默认仍是 `Double`。

## 影响

### 源码兼容性（source compatibility）

纯新增：`SwiftDeclarationPrintConfiguration.cTypeReplacements` 与 `applyTransformers(_: Transformer.ObjCConfiguration)` 是新增的公开成员，默认值不改变任何现有调用的输出之外的行为。输出变化：剥过符号的 `@objc @implementation` 类，原来是注释的存储属性有一部分变成声明。

### ABI 兼容性（条件项）

不适用 —— 本库以 SPM 源码分发，使用方每次重新编译。

### 下游影响

- 本仓库：`SwiftPrinting`（新依赖 `ObjCOutputTransformer`）、`SwiftDump`、`SwiftObjCInterop`。
- RuntimeViewer：抬 MachOSwiftSection 依赖后，Swift 接口自动带上还原；C 类型替换要它在 `RuntimeSwiftSection` 里把 `transformer.objc.cType` 交给打印配置（后续项）。

### 文档与示例

模块说明 `Internal/Modules/SwiftObjCInterop.md`、`SwiftPrinting.md`（如有对应段落）与演进账本。

## API 演进与废弃策略

无废弃：只新增成员。不需要 major 版本号跃迁。

## 落地步骤

1. **骨架**：`ObjCInstanceVariableSwiftType`（恒返回 `nil`）、`ObjCPrimitiveType`、`cTypeReplacements`、`SwiftPrinting` 依赖 `ObjCOutputTransformer`；夹具加 `AdaptiveTransitionWidget`，类集合断言跟上。
   - 行为：夹具的 `@objc @implementation` 类集合多出 `AdaptiveTransitionWidget`，其余输出不变。
2. **完整 encoding 还原**：`triviallyRepresentedTypeNode`，interface 接入。
   - 行为：剥过符号的类类型 ivar 打成 `var x: Class!`。
   - 行为：协议存在类型打成 `var x: (any P)!`。
   - 行为：`B` / `d` / `q` 打成 `Bool` / `Double` / `Int`，结构体按结构体名。
   - 行为：`readonly` 的 ObjC 属性打 `let`，`weak` 的打 `weak var x: T?`。
   - 行为：完整 encoding 的 `NSString` 不桥接成 `String`。
   - 行为：空 encoding 仍是注释。
3. **`?` 按 ObjC 属性还原**：`bridgedTypeNode`。
   - 行为：`?` 且有 `NSString` 属性的打成 `String!`，`NSArray` 的打成 `[Any]!`，`id` 的打成 `Any!`。
   - 行为：`?` 且没有 ObjC 属性的仍是注释。
4. **C 类型替换**：`applyTransformers(_: Transformer.ObjCConfiguration)`，打印时替换。
   - 行为：配置 `double → CGFloat` 时 `d` 打成 `CGFloat`。
   - 行为：没有配置或模块关闭时仍是 `Double`。
5. **dump 与文档**：`ObjCImplementationClassDumper` 接入；模块说明与演进账本。
   - 行为：dump 的 ivar 行打出还原的类型，注释写明来源。
   - 行为：还原不出的 ivar 注释仍写 `Swift type not recoverable`。

**收尾时必须判断两件事**：要不要配套专题文章、有没有引入新术语（写进决策日志）。

## 后续项

- RuntimeViewer：`RuntimeSwiftSection` 把 `transformer.objc.cType` 交给 Swift 打印配置（`applyTransformers(_: Transformer.ObjCConfiguration)`），C Type Replacement 改动时让 Swift 输出重印；随 MachOSwiftSection 依赖版本一起抬。
- `swift-section interface` 的 `--c-type-replacement`。
- Generated Interface 的 stand-in 对完整 encoding 的 ivar 是否改用本提案的 Swift 类型（`NSString` 不桥接）。

## 决策日志

| 日期 | 变更 | 说明 |
|------|------|------|
| 2026-11-26 | Created as Draft | 用户在 RuntimeViewer 里看到 UIKitCore 一个 `@objc @implementation` 类的存储属性大半只有注释，而 ObjC 一侧已显示出类型，要求能还原的都还原，类名经 type indexing 转 Swift 名 |
| 2026-11-26 | 用户经 `implement-feature` 批准，提案由 agent 起草、用户事前未审阅 | 用户事先定了四点：对象类型写 `T!`；`d` 走 C 类型替换表；桥接集合也还原（`[Any]`）；方案照此开工 |
| 2026-11-26 | 开始实现 | 在 `feature/objc-ivar-type-recovery` 上按落地步骤做 |
