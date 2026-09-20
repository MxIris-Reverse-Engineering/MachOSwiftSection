# 从 ObjC 祖先链还原 `override`

> 提案 [draft-objc-ancestor-override-recovery](../Evolutions/draft-objc-ancestor-override-recovery.md) 的实现说明。读者：维护者。为什么 Swift 元数据里没有这条事实、判据怎么推导的在提案里，本文只讲落地后的形状、三档证据在代码里的位置、以及边界。

## 一句话

interface 的 `override` 一直只来自 Swift vtable 的 override 表，而覆写一个从 ObjC 继承来的成员时编译器只发一条**新的**普通 vtable 项（`@objc @implementation` 类连 vtable 都没有），所以 AppKit 里 173 个、SwiftUI 里 165 个 ObjC 派生的 Swift 类，覆写 NSView / NSObject 的成员全部打成裸 `func`。现在从 ObjC 侧把它找回来：类自己的 ObjC 方法表里某个 IMP 对应的 Swift 成员，其 selector 在祖先链上有人实现，就是 `override`。macOS 26.6 的 AppKit：interface 里的 `override` 行从 2 变成 52，`NSGlassEffectView` 的 15 个覆写成员标出 9 个，剩下 6 个是优化器把方法体内联掉、thunk 里不剩任何 Swift 符号引用的（见「第三档」）。

## 落地形状

| 层 | 文件 | 做什么 |
|---|---|---|
| SwiftInspection | `ObjCClassHierarchy.swift` | 值类型 `ObjCClassHierarchy`（类自己的方法：selector、实例/类、IMP 位置；祖先列表：名字 + 实例/类 selector 集合；链是否走完）；接缝协议 `ObjCClassHierarchyProviding`（class-bound）；按镜像**弱引用**的注册表 `ObjCClassHierarchyProviderStore`；驱逐入口 `ObjCClassHierarchies.removeCache(for:)`。 |
| SwiftInspection | `ObjCClassMethodIndex.swift` | 库自己的读取器，`SharedCache` 子类。急切部分只读 classlist 与 `class_ro_t.name` 建「运行时名 → class object」与「Swift 限定名 → 运行时名」两张表；方法表与祖先 selector 集合按 class object 惰性求值、锁保护 memo；祖先在别的镜像时 memo 落在那个镜像自己的 `Storage`。`ObjCImplementationClassReading` 协议新增 `superclassLocation(of:)`（`.root` / `.resolved(reader, class)` / `.unresolvable(name)`）。 |
| SwiftInspection | `ObjCAncestorOverride.swift` | `ObjCAncestorOverride`（selector、实例/类、最近祖先名、`evidence` 三档）与 `ObjCAncestorOverrideTable`（按符号名索引的覆写事实 + 联结不上的 `unattributedOverriddenMethods` + 第三档的 `inferredOverrides(forMemberShapes:)`）。 |
| SwiftInspection | `ObjCMemberShape.swift` | 一个 Swift 成员对 selector 而言的形状（基名、标签、参数个数 / 属性名 / 是否类型级 / 所属类型），从 demangle 树建；`isConsistent(withSelector:isClassMethod:)` 是 importer 命名规则的**正向**检查。 |
| SwiftInspection | `NodeTypeNaming.swift` | 从 SwiftLayout 下沉（`package`），加 `nominalQualifiedName(ofDemangledRoot:)` 与 `swiftClassQualifiedName(fromRuntimeName:)`，ObjC 侧与 Swift 侧的类名 key 用同一个函数算。 |
| SwiftThunkAnalysis | `ObjCOverride/ObjCAncestorOverrides.swift` | 门面与联结表构建器：`table(forObjCClassNamed:in:)` / `table(forSwiftClassQualifiedName:in:)`，先问注册的 provider 再走库读取器；`infersOverridesFromSelectorNames`（第三档开关，默认 `false`）。放这里而不是 SwiftInspection，因为第二档要用本模块的 Capstone 解码器。 |
| SwiftThunkAnalysis | `ObjCOverride/ObjCMethodThunkReferences.swift` | 把一个 IMP 的代码反汇编，收 `bl` / 尾调 `b` 的目标与 `adrp`+`add` / `adr` 物化出的地址，换成本镜像的 Swift 符号名。MachOFile 与 MachOImage 两条腿；仅 ARM64。 |
| SwiftDeclaration | `FunctionDefinition` / `VariableDefinition` / `SubscriptDefinition` 的 `objcAncestorOverride`；`AccessorRepresentable` 新增该要求 | `isOverride` 与 `isClassMember` 各 OR 上它：覆写的类方法打 `class`，`override static` 不是合法 Swift。`FieldDefinition` 恒为 `nil`（存储属性不能覆写）。 |
| SwiftDeclaration | `Building/ObjCAncestorOverrideApplication.swift`、`TypeDefinition+ObjCAncestorOverrides.swift`、`ExtensionDefinition+ObjCAncestorOverrides.swift` | 把表 join 到成员定义上：函数按 `symbol.name`，属性 / 下标按任一 accessor 符号，`init` 按 allocator 符号换 initializer 后缀；第三档（开关打开时）对仍未标的成员按形状唯一匹配。`TypeDefinition.index(in:)` 在 `applyThunkAttributes` 之后调用。 |
| SwiftIndexing | `SwiftDeclarationIndexer.indexExtensions()`、`registerObjCClassHierarchyProvider(_:)`、`deinit` | `__C` 类的 extension 也过一遍表（`@implementation` 主体与 category 共用同一张表）；宿主注册 provider 的便利入口；随符号表一起驱逐。 |
| SwiftIndexing | `ObjCInterfaceIndexerClassHierarchyProvider.swift` | ObjCSection 索引器的适配器（`ObjCIndexing.ObjCInterfaceIndexer` → provider）与 `ObjCClassHierarchy.init(classInfoChain:isAncestorChainComplete:)`，RuntimeViewer 让自己的索引器遵循协议时一行转换。 |
| SwiftDump | `ClassDumper`、`ObjCImplementationClassDumper`、`ObjCAncestorOverrideRendering.swift` | 类头下一行 `// ObjC ancestor chain: NSView → NSResponder → NSObject`（断链标 `(bound; chain not resolvable offline)`），成员符号行尾 `// overrides -[NSView layout] (<证据>)`，`@implementation` 的 ObjC 方法行 `overrides NSView` / `overrides NSView (no Swift member tied to this IMP)`。 |

interface 侧没有新代码：三个成员 printer 本来就按 `isOverride` / `isClassMember` 打关键字。

## 三档证据在代码里的位置

联结全在 `ObjCAncestorOverrides.table(for:ownerQualifiedName:in:)` 的循环里，对类自己方法表中「selector 被某个祖先实现」的每一条：

1. **`To` 符号在 IMP 处**（`evidence: .thunkSymbol`）：`machO.symbols(offset:)` 在 IMP 处找到 Swift 符号，就按那个符号名（`$s…FTo`、`$s…vgTo`、`$s…fcTo`）登记。成员定义查表时拿自己的符号名加 `To`（allocator `…fC` 换成 initializer `…fcTo`）。只对没 strip 的二进制成立。
2. **thunk 引用成员实现**（`.thunkReference`）：IMP 处没符号时，`ObjCMethodThunkReferences` 反汇编那段代码，把它引用的每个地址换成 Swift 符号名，逐个过两道守卫——`ObjCMemberShape.ownerQualifiedName` 必须等于这个类（`__C.NSGlassEffectView` 或 Swift 限定名），`isConsistent(withSelector:)` 必须成立——通过的按**成员实现的符号名**登记（`$s…F`、`$s…vs`、`$s…fc`），成员定义查表时裸名也能命中。IDA 核实的三种形状：`bl $s…layoutyyF`（普通方法与 `init`）、`adrl x16, $s…FZ; pacia; mov x3, x16; b outlined`（类方法，地址物化给 outlined helper）、setter 同 `bl`。
3. **只按名字**（`.selectorName`，`infersOverridesFromSelectorNames == true` 时才有）：前两档都联结不上的方法进 `unattributedOverriddenMethods`；`ObjCAncestorOverrideApplication.inferFromSelectorNames` 收集类里**尚未标记**的成员形状（函数、静态函数、`init`、属性的每个 accessor），`table.inferredOverrides(forMemberShapes:)` 给每个未联结方法找一致的成员，**恰好一个**才归属。NSGlassEffectView 剩下的 6 个（`renewGState` / `viewDidHide` / `viewDidUnhide` / `_windowChangedKeyState` / `_viewDidChangeEffectiveCornerRadii` / `encode(with:)`）全是这一档：方法体是 `super.xxx()` 被内联成 `objc_msgSendSuper` 或一个 outlined helper，thunk 里不剩任何 Swift 符号引用。

`ObjCMemberShape.isConsistent` 的规则（importer 的正向拼法）：零参方法 / getter 与 selector 相等；setter 是 `set` + 属性名首字母大写，`is` 前缀可省（`isEnabled` ↔ `setEnabled:`）；n 参方法 selector 恰有 n 段，第一段以基名开头、去掉基名后小写首字母以第一个标签开头（`viewWillMoveToWindow:` ↔ `viewWillMove(toWindow:)`、`encodeWithCoder:` ↔ `encode(with:)`），后续每段小写首字母以对应标签开头（`withObject:` ↔ `with:`），无标签参数接受任何段；`init` 同上并跳过开头的 `With`。参数个数从 function type 的 argument tuple 数，不从 labelList 数——全无标签时 demangler 不发 labelList。APINotes 或 `@objc(name)` 改过名的成员通不过检查，只会漏标不会错标。

## 两个 join 的键

- **Swift 类 ↔ ObjC class object**：`TypeDefinition.typeName.node` 物化后 `NodeTypeNaming.nominalQualifiedName(ofDemangledRoot:)`，与 `ObjCClassMethodIndex` 对 `_TtC…` / `$s…` 运行时名 demangle 后算的限定名是同一个函数。同名私有类落进同一个 key 时（两条运行时名）拒绝归属并 `#log`。泛型类不在 classlist 里，查不到就什么都不标。
- **成员定义 ↔ 表**：按符号名，见上。属性 / 下标任一 accessor 命中即整个成员标 `override`。

## 边界与已知限制

- **泛型 ObjC 派生类**（SwiftUI 26 个）无静态 class object，不标。它们的 `class_ro_t` 在泛型 metadata pattern 的 extra-data 块里，留待后续。
- **磁盘上的独立二进制**：父类在别的镜像时是 bind，`superclassLocation` 返回 `.unresolvable(name)`，链在那里断；同镜像祖先照常判。fixture 的 `SwiftDerivedWidget.description` 覆写 NSObject 的，文件上不标、`dlopen` 后以 `MachOImage` 读则标，两种结果都固定成了测试。
- **Swift extension 里的 `@objc override`**：编成 `__objc_catlist` 的 category，不在类自己的方法表里，不读。
- **仅 ARM64**：第二档的解码器与模块其余部分一样只认 ARM64，x86_64 镜像只有第一、三档。
- **`required` 不还原**：`init?(coder:)` 打成 `override init?(coder:)`，库本来就不还原 `required`。
- **不进 ABI 快照**：`objcAncestorOverride` 不在 `MemberRecord` 里，`formatVersion` 不变。
- **第三档默认关**：用户的既定裁决是「只联结不猜」；开关放在 `ObjCAncestorOverrides.infersOverridesFromSelectorNames`，dump 用 `(selector name, no symbol evidence)` 标出这一档的来源。

## 验证

- `ObjCAncestorOverrideRecoveryTests`（SwiftInterfaceTests）：fixture 的普通 Swift 子类 / 孙类（`@objc dynamic` 基）/ `@implementation` 子类三种覆写，反例，文件与进程内两条腿，provider 等价性（`ObjCInterfaceIndexer` 适配器 + spy），弱注册，`ObjCClassInfo` 链转换，成员形状与 selector 一致性，第三档只归属唯一候选。
- `AppKitObjCAncestorOverrideTests`：系统 cache 的 AppKit，NSGlassEffectView 的链为 NSView → NSResponder → NSObject 且走完，六个覆写全由第二档（`.thunkReference`）给出，`clipsToBounds` getter 与 `viewDidHide` 在未联结列表里；macOS 26 以下跳过。
- `ObjCAncestorOverrideDumpTests`（SwiftDumpTests）：两个 dumper 的链注释与 `overrides` 注释。
- 全量测试与渲染 A/B 结果见任务报告。
