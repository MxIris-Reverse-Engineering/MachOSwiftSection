# 从 ObjC 方法表还原 Swift 成员的 ObjC 事实：`@objc`、`override`、显式 selector

> 提案 [draft-objc-ancestor-override-recovery](../Evolutions/draft-objc-ancestor-override-recovery.md)（`override`）与 [draft-objc-member-selector-recovery](../Evolutions/draft-objc-member-selector-recovery.md)（`@objc` 与显式 selector，把前者推广到类的每一条 ObjC 方法）的实现说明。读者：维护者。为什么 Swift 元数据里没有这些事实、判据怎么推导的在提案里，本文只讲落地后的形状、证据档位在代码里的位置、以及边界。

## 一句话

一个 Swift 类的 ObjC 方法表就是它的 `@objc` 成员清单：每条一个 selector 加一个 IMP。库把每条方法联结到实现它的 Swift 成员，得到 per-class 的 **ObjC 成员表**（`ObjCMemberTable`），从中读出三件 Swift 元数据不记的事实：这个成员是 `@objc`（strip 掉 `To` thunk 符号的 OS 框架上，这是唯一证据——macOS 26.6 的 AppKit interface 里成员级 `@objc` 从 0 变为正数）；它 `override` 了哪个祖先的成员（selector 在祖先链上有人实现；编译器给这种覆写发的是新的普通 vtable 项，`@implementation` 类连 vtable 都没有）；它的 selector 是不是源码里 `@objc(name)` 写出来的（与编译器从 Swift 名正向推出的默认值不同）。

## 落地形状

| 层 | 文件 | 做什么 |
|---|---|---|
| SwiftInspection | `ObjCClassHierarchy.swift` | 值类型 `ObjCClassHierarchy`（类自己的方法：selector、实例/类、IMP 位置——含本镜像 category 的；祖先列表：名字 + 实例/类 selector 集合 + 该祖先采纳协议的 selector 集合；链是否走完；类自己采纳协议的 selector 集合 `adoptedProtocolSelectors`，含 `isComplete`；`adoptedProtocolDeclares` 与 `isAdoptedProtocolSetComplete` 连祖先一起算）；接缝协议 `ObjCClassHierarchyProviding`（class-bound）；按镜像**弱引用**的注册表 `ObjCClassHierarchyProviderStore`；驱逐入口 `ObjCClassHierarchies.removeCache(for:)`。 |
| SwiftInspection | `ObjCClassMethodIndex.swift` | 库自己的读取器，`SharedCache` 子类。急切部分读 classlist 与 `class_ro_t.name` 建「运行时名 → class object」「Swift 限定名 → 运行时名」两张表，再扫 `__objc_catlist` 按目标类名归组 category；方法表、祖先 selector 集合、协议 selector 按 class object 惰性求值、锁保护 memo；祖先在别的镜像时 memo 落在那个镜像自己的 `Storage`。目标类不在本镜像的 category（SwiftUI 给 `NSView` 加的）按目标类名另立一张 hierarchy，能跟着 class 指针走到 cache / 进程内的类时连祖先链一起给出。 |
| SwiftInspection | `ObjCImplementationClassIndex.swift` | 读取器协议 `ObjCImplementationClassReading`（MachOFile / MachOImage 两份实现）：`superclassLocation(of:)`（`.root` / `.resolved(reader, class)` / `.unresolvable(name)`；旧 bind 格式的槽位经 MachOKitExtensions 的 `resolveBind(fileOffset:)` 取名，Swift 类永不当根）、category 的目标类名 / 目标类 / 实例与类方法表 / 协议表、类与 category 的协议 selector（`RawObjCProtocolSelectors`，沿协议继承链递归；跟不到的 bind、以及读成**空字符串**的 selector——归档 cache 里另一镜像的协议方法表，名字串读不到——都标 `isComplete = false`）。 |
| SwiftInspection | `ObjCMember.swift` | `ObjCMember`（所属类名、selector、实例/类、`overriddenAncestorClassName?`、`evidence` 三档、`hasExplicitSelector`）与 `ObjCMemberTable`（按符号名索引的成员事实 + 联结不上的 `unattributedMethods` + 覆写投影 `overrides` / `unattributedOverriddenMethods` + 第三档的 `inferredOverrides(forMemberShapes:)`）。 |
| SwiftInspection | `ObjCMemberShape.swift` | 一个 Swift 成员对 selector 而言的形状（基名、标签、参数个数 / 属性名 / subscript accessor / 是否类型级 / 所属类型 / `throws` / `async`），从 demangle 树建（`To` thunk 符号的 `objCAttribute` 子节点跳过）。两套规则：`isConsistent(withSelector:isClassMethod:)` 是 importer 命名规则的**正向**检查（有损，做守卫）；`defaultSelector()` / `isDefaultSelector(_:)` 是编译器 `getObjCSelector` 的移植（无损，判显式 selector），含 30 个介词的 `prepositions` 与驼峰分词 `CamelCaseWords`。 |
| SwiftInspection | `NodeTypeNaming.swift` | 从 SwiftLayout 下沉（`package`），`nominalQualifiedName(ofDemangledRoot:)` 与 `swiftClassQualifiedName(fromRuntimeName:)`，ObjC 侧与 Swift 侧的类名 key 用同一个函数算。 |
| SwiftThunkAnalysis | `ObjCMembers/ObjCMembers.swift` | 门面与成员表构建器：`table(forObjCClassNamed:in:)` / `table(forSwiftClassQualifiedName:in:)`，先问注册的 provider 再走库读取器；`infersOverridesFromSelectorNames`（第三档开关，默认 `false`）。放这里而不是 SwiftInspection，因为第二档要用本模块的 Capstone 解码器。 |
| SwiftThunkAnalysis | `ObjCMembers/ObjCMethodThunkReferences.swift` | 把一个 IMP 的代码反汇编，收 `bl` / 尾调 `b` 的目标与 `adrp`+`add` / `adr` 物化出的地址，换成本镜像的 Swift 符号名。MachOFile 与 MachOImage 两条腿；仅 ARM64。 |
| SwiftDeclaration | `FunctionDefinition` / `VariableDefinition` / `SubscriptDefinition` 的 `objcMember: ObjCMember?`；`AccessorRepresentable` 的同名要求 | `isOverride` 与 `isClassMember` 各 OR 上 `objcMember?.isOverride`：覆写的类方法打 `class`，`override static` 不是合法 Swift。`FieldDefinition` 恒为 `nil`（存储属性不能覆写，也不以字段名进方法表）。 |
| SwiftDeclaration | `Building/ObjCMemberApplication.swift`、`TypeDefinition+ObjCMembers.swift`、`ExtensionDefinition+ObjCMembers.swift` | 把表 join 到成员定义上：函数按 `symbol.name`，属性 / 下标**先按 getter** accessor（显式 selector 是 getter 的名字，只经 setter 联结上的成员把 `hasExplicitSelector` 清掉），`init` 按 allocator 符号换 initializer 后缀；联结上的成员缺 `.objc` 属性就补上；第三档（开关打开时）对仍未标的成员按形状唯一匹配覆写。`TypeDefinition.index(in:)` 在 `applyThunkAttributes` 之后、`recoverFinalMembers` **之前**调用——`final` 还原把「`@objc` 且没有 descriptor」当 `@objc dynamic` 排除，strip 后的 `@objc` 就是这里补的。 |
| SwiftIndexing | `SwiftDeclarationIndexer.indexExtensions()`、`registerObjCClassHierarchyProvider(_:)`、`deinit` | `__C` 类的 extension（`@implementation` 主体、category、对外部类的 category）与本镜像 Swift 类的 extension（`@objc` 成员编成的 category）都过一遍表；宿主注册 provider 的便利入口；随符号表一起驱逐。 |
| SwiftIndexing | `ObjCInterfaceIndexerClassHierarchyProvider.swift` | ObjCSection 索引器的适配器（`ObjCIndexing.ObjCInterfaceIndexer` → provider，按目标类名归组 indexer 另存的 category）与 `ObjCClassHierarchy.init(classInfoChain:categoryInfos:isAncestorChainComplete:)`（协议 selector 从 `ObjCClassInfo.protocols` 递归收，`isComplete = true`），RuntimeViewer 让自己的索引器遵循协议时一行转换。indexer 不认识的类答 nil，库读取器接手——对外部类的 category 也是。 |
| SwiftPrinting | 三个成员 printer 与 `@implementation` 存储属性 printer 的属性循环 | `.objc` 且 `objcMember?.hasExplicitSelector` 时打 `@objc(selector)`，其余维持 `@objc`。`override` / `class` / `final` / export-status 豁免不改代码，靠模型事实生效。 |
| SwiftDump | `ClassDumper`、`ObjCImplementationClassDumper`、`ObjCMemberRendering.swift` | 类头下一行 `// ObjC ancestor chain: NSView → NSResponder → NSObject`（断链标 `(bound; chain not resolvable offline)`），成员符号行尾 `// overrides -[NSView layout] (<证据>)` 或 `// @objc -[Class selector][, explicit selector] (<证据>)`；`@implementation` 的 ObjC 方法行 `overrides NSView` / `… (no Swift member tied to this IMP)` / `no Swift member tied to this IMP`；export-status 注释对表里的成员豁免。 |

## 三档证据在代码里的位置

联结全在 `ObjCMembers.table(for:ownerQualifiedName:in:)` 的循环里，对类自己方法表中的**每一条**（不再先按祖先 selector 过滤）：

1. **`To` 符号在 IMP 处**（`evidence: .thunkSymbol`）：`machO.symbols(offset:)` 在 IMP 处找到 Swift 符号，就按那个符号名（`$s…FTo`、`$s…vgTo`、`$s…fcTo`）登记。同一 IMP 处有多个符号（identical code folding 把两个成员的 thunk 叠在一起）时，只登记形状与 selector 一致的那些；一个都不一致才全部登记。成员定义查表时拿自己的符号名加 `To`（allocator `…fC` 换成 initializer `…fcTo`）。只对没 strip 的二进制成立。
2. **thunk 引用成员实现**（`.thunkReference`）：IMP 处没符号时，`ObjCMethodThunkReferences` 反汇编那段代码，把它引用的每个地址换成 Swift 符号名，逐个过两道守卫——`ObjCMemberShape.ownerQualifiedName` 必须等于这个类（`__C.NSGlassEffectView` 或 Swift 限定名），`isConsistent(withSelector:)` 必须成立——通过的按**成员实现的符号名**登记（`$s…F`、`$s…vs`、`$s…fc`），成员定义查表时裸名也能命中。IDA 核实的三种形状：`bl $s…layoutyyF`（普通方法与 `init`）、`adrl x16, $s…FZ; pacia; mov x3, x16; b outlined`（类方法，地址物化给 outlined helper）、setter 同 `bl`。**显式 selector 的成员过不了第二道守卫**（`pokeUsingForce:` 不是任何 importer 对 `poke(force:)` 的拼法），所以 strip 后它连 `@objc` 都拿不到——诚实漏标，不错标；fixture 的 `.strippedLocals` 变体把这一点固定成了测试。
3. **只按名字**（`.selectorName`，`infersOverridesFromSelectorNames == true` 时才有，且只对覆写）：前两档都联结不上的方法进 `unattributedMethods`；`ObjCMemberApplication.inferFromSelectorNames` 收集类里**尚未标记**的成员形状，`table.inferredOverrides(forMemberShapes:)` 给每个未联结的**覆写**方法找一致的成员，**恰好一个**才归属。NSGlassEffectView 剩下的 6 个（`renewGState` / `viewDidHide` / `viewDidUnhide` / `_windowChangedKeyState` / `_viewDidChangeEffectiveCornerRadii` / `encode(with:)`）全是这一档：方法体是 `super.xxx()` 被内联成 `objc_msgSendSuper` 或一个 outlined helper，thunk 里不剩任何 Swift 符号引用。

`ObjCMemberShape.isConsistent` 的规则（importer 的正向拼法）：零参方法 / getter 与 selector 相等；setter 是 `set` + 属性名首字母大写，`is` 前缀可省（`isEnabled` ↔ `setEnabled:`）；n 参方法 selector 恰有 n 段，第一段以基名开头、去掉基名后小写首字母以第一个标签开头（`viewWillMoveToWindow:` ↔ `viewWillMove(toWindow:)`、`encodeWithCoder:` ↔ `encode(with:)`），后续每段小写首字母以对应标签开头（`withObject:` ↔ `with:`），无标签参数接受任何段；`init` 同上并跳过开头的 `With`；subscript 的 accessor 接受运行时的四个固定 selector。参数个数从 function type 的 argument tuple 数，不从 labelList 数——全无标签时 demangler 不发 labelList。APINotes 或 `@objc(name)` 改过名的成员通不过检查，只会漏标不会错标。

## 显式 selector 的判据

`ObjCMemberShape.defaultSelector()` 是 `lib/AST/Decl.cpp` `AbstractFunctionDecl::getObjCSelector` 与 `VarDecl::getDefaultObjCSetterSelector` 的移植：无参 = 基名；单个无标签参数 = `基名:`；有标签的第一段 = 基名 +（`With`，除非第一个标签的首词或基名的末词是介词）+ 首字母大写的标签，后续段 = 标签原文（无标签为空段）；`throws` 追加 `error:`（无参时 `基名AndReturnError:`），`async` 追加 `completionHandler:`（无参时 `基名WithCompletionHandler:`），`async throws` 只追加后者；`init` 是基名为 `init` 的方法；getter = 属性名，setter = `set` + 首字母大写的属性名（**没有** `is` 处理，那是 importer 的规则）。介词表是 `lib/Basic/PartsOfSpeech.def` 的 30 个词；驼峰分词按 `camel_case::Words`（全大写连续段视为一个缩写词，`URLSession` → `URL` / `Session`）。

`hasExplicitSelector` = 实际 selector ≠ 默认推导，**且**不是覆写（selector 从被覆写者继承）、**且**不是 `@objc` 协议要求的 witness（selector 从要求继承——类自己采纳的协议**和每个祖先采纳的协议**都算，conformance 是继承的：`NSTableView` 的 `NSDraggingSource` 决定子类 `draggingSession(_:movedTo:)` 的 selector）、**且**继承的两个来源都读完了——`isAncestorChainComplete` 与 `isAdoptedProtocolSetComplete`（类与每个祖先的协议集合都完整）同时成立。磁盘上独立二进制的父类与 SDK 协议是 bind，读不到，就**不下判定**：第一轮 A/B 在模拟器运行时的 SwiftUI 文件上把 `hitTest:withEvent:` / `drawRect:` 这类 UIKit 覆写全判成了显式 selector，合法但误导。dump 注释里 selector 照样写出，只是不加 `explicit selector`。第一轮 A/B 还抓到另一种「读完了但没读对」：macOS 15.5 归档 cache 里 WidgetKit 的类采纳 Foundation 的 `NSSecureCoding`，跨镜像读它的方法表得到的 selector 全是空字符串，集合看似完整、`encodeWithCoder:` 却不在其中，于是 witness 被判成显式——空 selector 现在一律视为读失败、集合标不完整。`@objc @implementation` 体**不是**例外：编译器同样从 Swift 名推导并要求头文件声明了那个 selector（`draw(in:)` 推出 `drawIn:`，头文件只有 `drawInRect:` 就报错），所以 AppKit 里 `NSGradient` 的 `draw(in:angle:)` 对 `drawInRect:angle:` 是源码写了 `@objc(drawInRect:angle:)`。interface 打 `@objc(selector)`，属性用 getter 的 selector；dump 在注释里加 `, explicit selector`。

## 三个 join 的键

- **Swift 类 ↔ ObjC class object**：`TypeDefinition.typeName.node` 物化后 `NodeTypeNaming.nominalQualifiedName(ofDemangledRoot:)`，与 `ObjCClassMethodIndex` 对 `_TtC…` / `$s…` 运行时名 demangle 后算的限定名是同一个函数。同名私有类落进同一个 key 时（两条运行时名）拒绝归属并 `#log`。泛型类不在 classlist 里，查不到就什么都不标。
- **extension ↔ 表**：`__C.X` 的 extension 按裸名 `X`（`@implementation` 主体、category、对外部类的 category 共用一张表）；本镜像 Swift 类的 extension 按限定名，与类本体同一张表——category 成员本就折进了类的 hierarchy。
- **成员定义 ↔ 表**：按符号名，见上。属性 / 下标任一 accessor 命中即整个成员标记，getter 优先。

## 边界与已知限制

- **泛型 ObjC 派生类**（SwiftUI 26 个）无静态 class object，不标。它们的 `class_ro_t` 在泛型 metadata pattern 的 extra-data 块里，留待后续。
- **磁盘上的独立二进制**：父类在别的镜像时是 bind，`superclassLocation` 返回 `.unresolvable(name)`，链在那里断；同镜像祖先照常判，显式 selector 一律不判。旧的 `LC_DYLD_INFO` bind 格式（部署目标低于 macOS 12 / iOS 16——iOS 15.5 模拟器运行时的全部框架）把 bind 槽位留成 0，MachOObjCSection 把它读成「没有父类」；读取器补了一道 MachOKitExtensions 的 `resolveBind(fileOffset:)`（两种格式都认）取 bind 符号名，再兜一道「Swift 类不可能是 ObjC 根类」，否则链会被误判为走完、每个 UIKit 覆写都成了显式 selector（第一轮 A/B 的模拟器腿就是这样）。fixture 的 `.legacyBinds` 变体固定。fixture 的 `SwiftDerivedWidget.description` 覆写 NSObject 的、`poke(force:)` 的 `@objc(pokeUsingForce:)`，文件上都不标、`dlopen` 后以 `MachOImage` 读则都标，两种结果都固定成了测试。
- **strip 后的显式 selector**：只有第一档能给；第二档的 importer 拼法守卫天然拒绝它（见上），第三档只管覆写。
- **仅 ARM64**：第二档的解码器与模块其余部分一样只认 ARM64，x86_64 镜像只有第一、三档。
- **`required` 不还原**：`init?(coder:)` 打成 `override init?(coder:)`，库本来就不还原 `required`。
- **`init` 与 `.cxx_destruct` 也在表里**：编译器给每个 ObjC 派生的 Swift 类合成的 `init` 与指向 ivar destroyer 的 `-.cxx_destruct` 都是方法表条目；前者联结到 allocator 定义（`@objc init()`，默认 selector `init` 不算显式），后者没有对应的成员定义，只在 dump 的符号行上留一条注释。
- **不进 ABI 快照**：`objcMember` 不在 `MemberRecord` 里，`formatVersion` 不变。
- **第三档默认关**：用户的既定裁决是「只联结不猜」；开关放在 `ObjCMembers.infersOverridesFromSelectorNames`，dump 用 `(selector name, no symbol evidence)` 标出这一档的来源。

## 验证

- `ObjCMemberRecoveryTests`（SwiftInterfaceTests）：fixture 的普通 Swift 子类 / 孙类（`@objc dynamic` 基）/ `@implementation` 子类三种覆写，extension（category）里的覆写与 `@objc` 成员，反例，文件与进程内两条腿；`.strippedLocals` 变体上 `@objc` 与 `override` 靠第二档、`@objc dynamic` 不再被打成 `final`、显式 selector 诚实缺席；显式 selector 与默认推导（`throws` / `async` / 介词 / 无标签 / witness）的 interface 输出与表事实；provider 等价性（`ObjCInterfaceIndexer` 适配器 + spy，含 category 与协议）、弱注册、`ObjCClassInfo` 链转换（含 category 去重与协议 selector）、成员形状与两套规则的对照表、第三档只归属唯一候选。
- `AppKitObjCMemberTests`：系统 cache 的 AppKit，NSGlassEffectView 的链为 NSView → NSResponder → NSObject 且走完，覆写全由第二档给出且无一声称显式 selector，`clipsToBounds` getter 与 `viewDidHide` 在未联结列表里，协议 selector 在 cache 内读完整；macOS 26 以下跳过。
- `ObjCMemberDumpTests`（SwiftDumpTests）：两个 dumper 的链注释、`overrides` 注释、`@objc -[…]` 注释（含 `explicit selector`）、strip 后的证据档位。
- 全量测试与渲染 A/B 结果见两份任务报告。
