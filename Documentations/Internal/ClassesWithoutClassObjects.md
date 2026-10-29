# 没有 class object 的 Swift 类

提案 [`objc-classes-without-class-objects`](../Evolutions/0078-objc-classes-without-class-objects.md) 的实现说明。

## 一句话

泛型类、父类在别的 resilience domain 的类、父类是本模块泛型类的类，这三种 Swift 类在 `__objc_classlist` 里没有 class object，但它们的 `class_ro_t` 都静态存在于 Swift 元数据里。`SwiftClassWithoutClassObjectIndex`（SwiftInspection）按镜像把它们找出来，本库的 ObjC 方法表据此给出 `override` 与显式 selector 的证据，`swift-section objc` 经 MachOObjCSection 0.8.201 的 `ObjCSuppliedClass` 把它们列出来。

## 三种类与编译器的元数据策略

编译器按 `IRGenModule::getClassMetadataStrategy`（`GenClass.cpp`）给每个类选一种元数据策略，只有 Fixed、Update、FixedOrUpdate 三种会把元数据静态生成完整并登记进 `__objc_classlist`（`GenMeta.cpp` 的 `emitClassMetadata`）。另外三种情况没有 class object：

| 类 | 策略 | `class_ro_t` 在哪 | 元类的 `class_ro_t` | stub |
|---|---|---|---|---|
| 泛型类 | generic metadata pattern | generic metadata pattern 的 extra-data pattern 里第 (`ClassRODataOffset` − `OffsetInWords`) 个字 | 同一块里第 (`MetaclassRODataOffset` − `OffsetInWords`) 个字 | 没有 |
| 父类在别的 resilience domain | Resilient | `ResilientClassMetadataPattern.data` | `ResilientClassMetadataPattern.metaclass` 指向的元类的 `data` 字段 | 描述符的 `ObjCResilientClassStubInfo` |
| 父类是本模块的泛型类 | Singleton | 静态的 incomplete metadata（一个 class object 形状的结构）的 `data` 字段 | 它的 `isa` 字段指向的元类的 `data` 字段 | 只有私有符号 `…CMt` 能找到 |

几点细节：

- 泛型类那一行照的是运行时 `initializeClassMetadataFromPattern`（`Metadata.cpp`）：它把 extra-data pattern 拷到实例化元数据 extra data 的 `OffsetInWords` 处，再让 data 指向 extra data 的第 `ClassRODataOffset` 个字。所以在 pattern 自己的数据里，模板在第 (`ClassRODataOffset` − `OffsetInWords`) 个字。模板里的 `class_ro_t.name` 是空指针，由运行时给每个实例化各取一个名字。没有 extra-data pattern 的泛型类是不开 ObjC interop 的构建，跳过。
- Resilient 与 Singleton 的描述符都有 singleton metadata initialization，`incompleteMetadata` 字段在 Resilient 下改指向 `ResilientClassMetadataPattern`（两者是同一个 union），靠描述符的 `hasResilientSuperclass` 区分。
- Update 与 FixedOrUpdate 策略的类同样有 singleton metadata initialization，它们的 incomplete metadata 就是 class list 里的 class object，所以按偏移排除：偏移落在 class list 里的不算。
- Singleton 的 stub 描述符不记录（`addObjCResilientClassStubInfo` 只在 Resilient 策略下写），只能按符号找。编译器给它的是非公开 stub（`emitObjCResilientClassStub(_:isPublic: false)`）：完整 stub 有一个私有符号 `…CMt`，它的第一个字是保留字，第二个字才是 isa；指向 isa 的别名 `…CMs` 只给公开 stub 定义，这里没有。所以把描述符符号 `…CMn` 换成 `…CMt` 去符号表里找（`SymbolIndexStore.offset(ofSymbolNamed:in:)`），再加一个字。`…CMt` 是 local 符号，剥掉 local 符号的镜像里找不到，`classStubOffset` 就留空。这种类的 category 不指向 stub（见下一条），MachOObjCSection 的索引器也只拿 `classStubOffset` 归挂在 stub 上的 category，所以缺了不影响什么。公开的 stub（Resilient 那一行）两个符号都有，`…CMs` 正是描述符记录的那个地址。
- **category 指向哪里**：Swift `extension` 里的 `@objc` 成员编成 category，三种类各不相同。父类在别的 resilience domain 的类（`AncestryFlags::ResilientOther`），category 指向它的 stub，放在 `__objc_catlist2` 里（`GenClass.cpp` 的 `getClassMetadataRef()`、`GenDecl.cpp` 的 `emitExtension`）。父类是本模块泛型类的类，category 指向类自己的 incomplete metadata，放在 `__objc_catlist` 里，从那里读得出 `class_ro_t` 里的运行时名。泛型类的 `extension` 不许有 `@objc` 成员（`TypeCheckDeclObjC.cpp` 报 `objc_in_generic_extension`），没有 category。
- 绝对指针（Singleton 的 `data` 与 `isa` 字段、Resilient 的元类的 `data` 字段）一律构造成 `ObjCClass64` 交给 MachOObjCSection 的读取器解：它处理 rebase、chained fixup、dyld cache 的偏移、进程内已 realize 的类（`data` 指向 `class_rw_t`）这些情况。相对指针（pattern 里的字段、`data`、`metaclass`、stub）用 `resolvedDirectOffset` 自己解。读出来的元类 `class_ro_t` 必须带 `RO_META` 标志，不带就当没读到。

## 名字与父类

- **名字**：泛型类用 Swift 限定名加上各层泛型参数（`Xcode_Service.MenuBarPanelWindow<A>`，按 depth 与 index 命名，嵌套在泛型里的写成 `Outer.Inner<A, A1>`），因为模板里没有名字。另外两种用 `class_ro_t` 里的运行时名（`_TtC13Xcode_Service23MenuBarLabelHostingView`）。本库的 ObjC 方法表按 Swift 限定名查类，限定名到这些名字的映射由索引维护（`names(forSwiftClassQualifiedName:in:)`）。
- **父类**：从描述符的 superclass mangled name 读，按能不能续链分四种（`SwiftClassWithoutClassObject.Superclass`）：
  - ObjC 类给运行时名（`__C.NSPanel` 给 `NSPanel`），没有声明父类的 Swift 根类给 `_TtCs12_SwiftObject`（运行时给它的父类）。祖先解析器按这个名字到依赖镜像里找：文件在它的依赖闭包里找，进程内镜像在已加载的镜像里找，两边都先查 export trie。进程内原本不需要按名字找（class object 的父类都是真指针），没有 class object 的类只有父类的名字，这一步是为它们加的，`ObjCAncestorResolver.classObject(named:)` 因此也接受进程内的根。
  - 同一镜像里有 class object 的 Swift 类，给 class list 里它的运行时名（`ObjCClassMethodIndex` 的名字表，以及改过名的类的 `SwiftClassObjectIndex`）。
  - 同一镜像里同样没有 class object 的类，给它在本索引里的名字，祖先链经新的 `ObjCSuperclassLocation.withoutClassObject` 接着走。
  - 别的镜像里的 Swift 类，给 Swift 写法（`SwiftUI.NSHostingView<Xcode_Service.MenuBarLabel>`），只作显示，链在这里断，`unresolvedAncestorName` 留空，不拿这个写法去查。
- **有没有 ObjC 祖先**：看类标志位的 `UsesSwiftRefcounting`，ObjC 对象模型下它是 0；继承 `NSObject` 的 actor 保留 Swift 引用计数，按「是 actor 且有父类」另判（与 `SwiftClassObjectIndex` 判 `@objc(Name)` 合不合法用的是同一条规则）。

## 交给谁

- **本库的 ObjC 方法表**（`ObjCClassMethodIndex`）：`runtimeNames(forSwiftClassQualifiedName:in:)` 把本索引的名字并进来，`hierarchy(forRuntimeName:in:)` 在找不到 class object 时从本索引读方法表、续链。这一侧不按 ObjC 祖先过滤，纯 Swift 类本来就没有 ObjC 方法，不出表。
- **MachOObjCSection 的索引器**：`ObjCSuppliedClass.swiftClassesWithoutClassObjects(in:)`（SwiftIndexing，公开）交出全部泛型类，以及有 ObjC 祖先的另外两种——编译器只给这些类往 `__objc_stublist` 登记 stub，MachOObjCSection 给它们写的注释也是 `registered through __objc_stublist`。`ObjCInterfaceSession` 与 `ObjCAPIRequests` 构造索引器时传入；`ObjCInterfaceIndexerClassHierarchyProvider` 在 `classGroup(forName:)` 落空时查 `suppliedClassGroup(forName:)`。

## 已知限制

- 父类是另一个镜像里的 Swift 类时链就断，`override` 不判。非泛型的那种（SwiftUI 的类继承 SwiftUICore 的类）可以按限定名到依赖镜像的 class list 里找；泛型的那种（`NSHostingView<…>`）在那个镜像里同样没有 class object，要跨镜像读它的 pattern。都留作后续。
- 本库自己的读取器看不到父类在别的 resilience domain 的类的 category（Swift `extension` 里的 `@objc` 成员）：读取器只读 `__objc_catlist`，这些 category 在 `__objc_catlist2` 里，它们指向的 stub 也读不出类名。MachOObjCSection 的索引器按 `classStubOffset` 归类，宿主经 provider 时拿得到。父类是本模块泛型类的类不受影响：category 指向类自己的 metadata，`targetClassName(of:)` 读出它的运行时名，照常并进方法表。fixture 里还没有带 `@objc` 成员的 `extension`，这两种情况都没有测试钉住。
- 运行时名要用旧式 mangling 拼，本库没有旧式 remangler，所以别的镜像里的 Swift 父类只能给 Swift 写法，不能给它在运行时的名字。

## 验证

- `ClassesWithoutClassObjectsFixture`（MachOTestingSupport）测试时现编两个镜像：开 library evolution 的 kit（`ResilientBase: NSObject`），加上使用它的客户端，`.full` 与 `strip -x` 两种。客户端里有三种类各一个、纯 Swift 的泛型类、没有 ObjC 祖先的 Singleton 类，以及有 class object 的对照组。
- `SwiftClassWithoutClassObjectIndexTests`（SwiftInspectionTests）：文件、剥过的文件、进程内三条路径读出的种类、名字、父类、stub、方法表；方法表经泛型父类续到 `NSObject`，文件与进程内都是。
- `ClassesWithoutClassObjectsInterfaceTests`（SwiftInterfaceTests）与 `ClassesWithoutClassObjectsRequestTests`（SwiftSectionKitTests）：interface 里的 `@objc override`，`objc dump` 列出这些类。这两组与改过的 `ThunkOnlyObjCMemberTests` / `ThunkOnlyObjCMemberDumpTests` 在不含本改动的代码上都失败。
- `PerImageCacheEvictionTests`：索引随 indexer 一起驱逐。
- SymbolTestsCore 的快照随之变化：三个继承 `NSObject` 的泛型类，编译器合成的 `init()` 在 interface 里成了 `@objc override init()`，dump 里多了祖先链与覆写注释，与非泛型类一直以来的输出一致。
- `Xcode Service`（Xcode 27.2）：`objc dump` 列出 `Xcode_Service.MenuBarPanelWindow<A> : NSPanel`（9 个方法，与 MachOObjCSection 那边的测试一致）与 `_TtC13Xcode_Service23MenuBarLabelHostingView : SwiftUI.NSHostingView<Xcode_Service.MenuBarLabel>`；interface 里 `MenuBarPanelWindow` 的 8 个 ObjC 成员（`canBecomeKey`、`setFrame(_:display:)`、`init(contentRect:styleMask:backing:defer:)` 等）都是 `@objc override`。
- 渲染 A/B（2026-10-27，JHs-Mac-Studio-Ultra，基线 `next` d68e6c10）：96 对里 66 对一致、30 对不同，都在 SwiftUI 与 SwiftUICore，各条腿都有。逐行归类：
  - interface 只多出关键字：1576 处 `override`；14 处 `static` 改成 `override class`（`layerClass`、`cellClass`、`requiresConstraintBasedLayout` 这类 UIKit / AppKit 类成员的覆写）；iOS 16.4 / 17.5 模拟器腿上剥过符号的 4 + 4 处 `@objc`；12 处新的显式 selector。没有删掉的声明，也没有类型变化。
  - 显式 selector 逐个核过。`_didUpdateFocusInContext:` 与 `_shouldUpdateFocusInContext:`：基线给有 class object 的兄弟类（`UIKitFocusableFillerItem`、`UIKitFocusableViewResponderItem`）的判定相同，这次是泛型的 `UIKitContainerFocusResponderItem<A>`。`_nsAttributedSubstringFromRange:`：基线在 iOS 18.5 模拟器腿上就是这样判的。`springLoadingHighlightExited:`：`NSHostingView<Content>` 的方法表里只有这个 selector，没有 `springLoadingExited:`，类也不遵循 `NSSpringLoadingDestination`，所以 Swift 方法 `springLoadingExited(_:)` 确实以别的 selector 导出（看起来是 SwiftUI 的笔误，AppKit 不会调到它）。
  - dump 只多出注释：方法表的行尾注释、`// ObjC ancestor chain:` 一行及其后的空行、成员行前的 `@objc`；`ListCollectionViewCell` 原本是一行的空类体，多了祖先链注释后展开成多行。
  - 两侧渲染耗时相同（macOS 26.6 cache 的 SwiftUI interface 都是 19 秒）。
