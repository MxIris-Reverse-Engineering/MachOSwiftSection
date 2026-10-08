# `@objc @implementation` 类还解不出的成员与 ivar 类型（2026-09-29）

用户问「为什么很多 `@objc @implementation` 类在 Swift 侧看不到方法、ObjCSection 把一些 ivar 打成 `Unknown`」，调研后查明了成因，也试了几条推断路线。

**当前状态：只落记录，推断部分的代码未改。** 用户裁定「先把能解补了，然后剩下的记下来」。符号明明在、库却漏读的那一处（`private` 属性与 `lazy var` 存储的 field offset global，名字节点是 `privateDeclName`）已在同一批次修复，见 [ProjectEvolutionLog](../Documentations/Internal/ProjectEvolutionLog.md) 第 72 节。本文只记还需要推断的部分。

## 现象

- macOS 26.7 的 AppKit 里有 38 个 `@implementation` 类，Swift 侧显示的成员与 AppKit 的 export trie 逐类一致，没有一个来自 local 符号。NSScreen 有 138 个 ObjC 方法，Swift 侧只有 6 个；NSCoordinateSpace 与 NSHostedViewScene 一个都没有；NSFontPanelColorWellVisualProvider 有 43 个 ObjC 方法，Swift 侧只有编译器合成的 `init()`。
- 26.6.2 的 AppKit 里这些类共有 170 个 ivar，55 个拿到了 Swift 类型，全部来自导出的 field offset global（`…vpWvd`）。编码为空串的 61 个一个都没拿到。
- ObjCSection 把编码为 `""` 和 `"?"` 的 ivar 打成 `Unknown`。

## 成因（都已核实）

1. **编译器不给 `@implementation` 类发 field descriptor。** `lib/IRGen/GenReflection.cpp` 里，类有 `getObjCImplementationDecl()` 时 `needsFieldDescriptor = false`；这类类也没有 vtable 和 method descriptor。所以 Swift 名字和类型只存在于符号里：成员实现符号、field offset global（ivar 的 offset 槽位指向的就是它）、访问器。普通 Swift 类的字段类型记在 `__swift5_fieldmd` 里，是数据，strip 删不掉，这就是两者的差别。
2. **符号是否留下，取决于源码写的访问级别。** `SILDeclRef::getDefinitionLinkage` 按访问级别定链接属性：`public` / `open` 导出；`internal` 是 hidden，链接后变成 local 符号；`private` 同样是 local 符号；`To` thunk 永远是 private。AppKit 在 cache 里剥掉了 local 符号，只剩导出的。SE-0436 不要求这些成员写 `public`（ObjC 侧能否调用由头文件决定），Apple 大多没写，于是大多数成员没有名字。编译器合成的 `override init()` 取被实现类的访问级别（`lib/Sema/CodeSynthesis.cpp` 的 `configureInheritedDesignatedInitAttributes`，导入的 ObjC 类是 public），所以它经常是唯一导出的成员。
3. **ivar 编码规则**（`lib/IRGen/GenClass.cpp` 的 `buildIvar`）：
   - `""`：这个存储属性不是 `@objc`，包括 `final` / `@nonobjc` 的 Swift 独有成员和 `lazy var` 的合成存储。它的类型可以是任何东西，ObjC 类也可以。
   - `"?"`：属性是 `@objc`，但存储类型不能直接用 ObjC 表示，包括桥接的 `String` / `Array` / `Dictionary` / `Set` / `Data`、`weak` 引用、`AnyObject.Type`、闭包、可选的 typed enum。编译器注释原话是 "used when ObjC classes are bridged to separate Swift types"。
   - 其余是真实编码。非可选的 typed enum（`NS_TYPED_ENUM`）拿到的是 `@"NSString"`，typedef 的名字不会进 ObjC 元数据。
4. **三条编译期限制**（写探针 fixture 时被编译器拒绝后才知道）：
   - `@implementation` 的实例属性不能用 property wrapper，所以不会有 wrapper 生成的 `_x` 存储。
   - 存储属性不能用 library evolution 下大小可变的类型（`Date`、`URL` 都不行，`@frozen` 的 `Data` 可以），所以 `ivar_t` 里记的大小永远准确，可以当推断的校验条件。
   - 非 `final` 的成员即使是 `private` 也隐式 `@objc`，会拿到 `"?"` 编码并进 ObjC 属性表；Swift 独有的存储必须写成 `final` 或 `@nonobjc`。

## 剩下的路线

### 一、只用元数据的推断（不碰汇编，成本最低）

1. **`"?"` 编码且有同名 ObjC 属性：推出桥接后的外层类型。** `NSString *` 占 16 字节的是 `String`（可不可选分不出，`String?` 也是 16 字节）；占 8 字节的是包着 NSString 的 typed enum，名字拿不到。`NSArray *` / `NSDictionary *` / `NSSet *` 推到 `Array` / `Dictionary` / `Set`，元素类型丢了。26.6.2 AppKit 里 19 个能用 field offset global 核对答案的 `"?"` ivar 全部符合这条规则。
2. **`$__lazy_storage_$_x` 且 `x` 是 ObjC 属性：类型是 `Optional<x 的类型>`。** 这个前缀在 ObjC ivar 名里，strip 之后还在。
3. **真实编码映射成 Swift 类型。** `q` → `Int`（也可能是 `NS_ENUM`，分不清），`B` → `Bool`，`{CGSize=dd}` → `CGSize`，`@"NSColor"` → `NSColor`（可不可选不知道）。现在 Swift 侧对这些也写「Swift type not recoverable」。
4. **`weak` / `unowned` 关键字。** field offset global 的 mangled 类型不带引用的所有权修饰（普通类的这个信息在 field descriptor 里，而这类类没有），所以现在 dump 和 interface 都把 `weak var delegate` 打成普通 `var`。`@objc` 属性可以从 ObjC 属性特性 `W` 拿到，Swift 独有的只能看代码里的 `swift_unknownObjectWeak*`。
5. **没有 Swift 符号的 ObjC 方法，在 interface 里一行都不出。** 可以列成注释，免得 Swift 侧看起来是空的；dump 的 `objcImplementationClasses` 段已经全列了。
6. **按「类自己 extension 里嵌套的类型 + 大小」出候选。** `NSScreen._state`（304 字节）正好对上 AppKit 里唯一一个 304 字节的结构体 `NSScreen.(State in _939AF…)`，它就嵌套在 `NSScreen` 自己的 extension 里。但一般情况区分度很低：61 个没解出的 ivar 里 47 个是 8 字节的引用，大小说明不了任何问题；其余按大小各撞 6 到 39 个同尺寸结构体，纯数值结构体同尺寸时完全分不开。只能当带置信度的候选。

### 二、SDK 头文件（结果精确，但覆盖的类少）

`@implementation` 的 Swift 成员必须和头文件导入后的声明一一对应，所以只要有头文件，名字、类型、nullable 都是准的，不是推断。`TypeIndexing` 已经在用 SourceKit 生成模块接口，可以复用。实测 38 个类里只有 6 个有公开头文件：NSGlassEffectView、NSGlassEffectContainerView、NSScreen、NSGradient、NSScrollEdgeEffectStyle、NSBackgroundExtensionView。其余私有类在公开 SDK 和本机的 15.5 内部 SDK 里都找不到。用的时候要注意 SDK 版本和二进制版本的差异。

### 三、运行时采样（RuntimeViewer 一侧）

RuntimeViewer 在进程内时，可以直接读活对象的 ivar 值拿到动态类型。对引用类型的 ivar 最直接（没解出的 61 个里有 47 个），但需要现成的实例，拿到的可能是子类，值为 nil 或空集合单例时什么也拿不到。这不在离线库的范围内。

### 四、反汇编推断（已在 26.6.2 AppKit 与 strip 后的 fixture 上验证可行）

ObjC 的 ivar 偏移在运行时可能被滑动，所以代码每次访问 ivar 都要先从它的 offset global 里取偏移，而 ivar 表里记的正是这个全局变量。「哪段代码碰了哪个 ivar」不需要任何符号就知道（IDA 直接把它们标成 `_OBJC_IVAR_$_Class.ivar`）。线索按可信度排：

1. **代码需要类型元数据时，取的是 `__swift5_typeref` 里的 mangled name。** 调用形如 `__swift_instantiateConcreteTypeFromMangledNameV2(cache, {相对偏移, 长度})`，名字是数据，strip 删不掉，而且带泛型实参。实例：`NSApplicationSceneWorkspace.sceneHandlers` 在 `init` 里由一个特化的字典构造函数赋初值，它给字典分配存储时引用了 `_DictionaryStorage<String, any NSApplicationSceneHandler>`。其中 `0x0C` 是指向 ObjC 协议的 symbolic reference，目标是两个相对地址，第二个指向不含 symbolic reference 的 `So25NSApplicationSceneHandler_p`。
2. **ObjC 属性的 getter 直接转发这个 ivar。** `-[NSApplicationSceneWorkspace workspace]` 读的就是 `underlyingWorkspace`，为 nil 时 `brk`（强制解包失败），所以它是 `FBSWorkspace?`。
3. **形状指纹。** `.cxx_destruct` 怎么释放它：`objc_release`、`swift_release`、在第几个字上 `swift_bridgeObjectRelease`、`swift_unknownObjectWeakDestroy`。`init` 给什么初值：空字符串是 `(0, 0xE000000000000000)`，`Bool?` 的 nil 是字节 `2`，空集合引用 libswiftCore 的 `_swiftEmpty*` 单例（导入符号永远有名字）。类没有 `.cxx_destruct`，说明所有 ivar 都是平凡类型。
4. **具名 C 函数的签名能给字段定型。** `NSCoordinateSpace.coordinateSpace`（88 字节）从代码里还原出 `CGRect` 在 0、`Bool` 在 0x20、`CGAffineTransform` 在 0x28（最后一个是 `CGAffineTransformMakeScale()` 的返回值），默认值 `(.zero, false, .identity)`。但 AppKit 里没有任何名义类型是这个布局，多半是元组（没有类型描述符）或者定义在别的镜像，只能按结构渲染，不能声称知道它叫什么。
5. **nullable（Swift 实现的 ObjC 成员）。** 桥接类型能精确推出：可选的 setter 在调 `_unconditionallyBridgeFromObjectiveC` 之前有一条 `CBZ`，getter 遇到 `.none` 返回 0，block 在 `_Block_copy` 之后同样判空。类类型的参数和返回值不管可不可选，编出来的代码完全一样（fixture 里 `setNumber:` 与 `setObject:` 逻辑相同，还和可选 typed enum 的 setter 共用一个编译器合并出来的函数），只能靠旁证：`init` 往 ivar 里存 nil 的一定可选，`weak` 的一定可选，getter 里 `brk` 强制解包的返回值一定非空。clang 编译的 ObjC 代码不受 nullable 注解影响，推不出。

成本：需要 ARM64 上的数据流跟踪（某个函数的返回值被存进了 self + ivar 偏移、那个函数用哪个 mangled name 取了元数据），结果取决于优化器怎么生成代码，输出要带证据档位（像现有的「只按名字」那一档）。`SwiftThunkAnalysis` 已有 Capstone 解码器和寄存器跟踪（给 kind-9 thunk 做符号求值用的），但现在只收集调用目标和代码里算出的地址。只支持 ARM64 不算限制：macOS 27 起系统二进制只有 arm64 和 arm64e。建议分层做：先做局部的模式匹配（`.cxx_destruct` / `init` 指纹、getter 转发），最后才做跨函数追到 `__swift5_typeref` 的关联。

### 真正解不出的

- 没有任何代码引用其元数据的自定义 struct / enum：只能拿到布局。
- 平凡类型（`Int`、`Double`、元类型）：析构时什么都不做，初值都是 0，除了大小什么都看不出。
- clang 编译的 ObjC 成员的 nullable。

## 验收（动手时）

- 每条推断都带证据档位：dump 全部打出来并标明来源，interface 默认只打有把握的（沿用「dump 信息最大化、interface 管可读性」）。
- 用 field offset global 能核对的 ivar（26.6.2 AppKit 的 55 个）做对照集，推断结果与符号给出的类型逐条一致。
- 回归测试用现场编译的 fixture，每种线索配一个 `-O` 加 `strip -x` 的变体钉住。

## 附：调研用的探针 fixture

没有放进仓库。它是一对成员完全相同的 `@implementation` 类，一个全用默认访问级别、一个能写 `public` 的都写了，28 个存储属性覆盖三种编码的每一类（真实编码、桥接类型、`weak`、`Class`、闭包、typed enum、lazy 存储、`final` / `@nonobjc` 的 Swift 独有成员、`private` 的 `@objc` 成员），用 `-O` 编成 dylib，再复制一份 `strip -x`。结论：strip 后，internal 那个类的 ivar 一个类型都解不出；public 那个类除 lazy 存储和 `private` 成员外全部解出，因为这两者的 field offset global 永远是 local 符号。仓库里的回归测试（`ObjCImplementationFixture` 的 `Widget`）已经覆盖了 `private` 属性和 lazy 存储这两种情况。

## 关联

- [Internal/ObjCImplementationClassRecognition.md](../Documentations/Internal/ObjCImplementationClassRecognition.md)「边界与已知限制」
- [Internal/ObjCMemberRecovery.md](../Documentations/Internal/ObjCMemberRecovery.md)（ObjC 方法表与 Swift 成员的联结）
- [Internal/ProjectEvolutionLog.md](../Documentations/Internal/ProjectEvolutionLog.md) 第 72 节
