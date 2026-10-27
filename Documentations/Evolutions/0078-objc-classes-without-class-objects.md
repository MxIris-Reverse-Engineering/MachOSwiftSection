# 0078 - 没有 class object 的 Swift 类：从 Swift 元数据读出它们的 ObjC 类数据

- **状态**: Implemented
- **创建日期**: 2026-10-27
- **最后更新**: 2026-10-27
- **关联 issue**: [#137](https://github.com/MxIris-Reverse-Engineering/MachOSwiftSection/issues/137)（ObjC 侧）
- **关联提案**: [0077-thunk-only-objc-members](0077-thunk-only-objc-members.md)（Swift 侧）；MachOObjCSection 的 0014 `host-supplied-classes`（跨仓库，提供本提案要用的 `ObjCSuppliedClass`，随 MachOObjCSection 0.8.201 发布）
- **实现分支**: `feature/objc-classes-without-class-objects`（已合入 `next`）
- **配套文档**: [ClassesWithoutClassObjects.md](../Internal/ClassesWithoutClassObjects.md)（实现说明）

## 摘要

有三种 Swift 类在文件里没有静态的 class object：泛型类；父类在别的 resilience domain 的非泛型类；父类是本模块泛型类的非泛型类。`__objc_classlist` 里没有它们，后两种只在 `__objc_stublist` 里登记一个 stub。`swift-section objc` 的各个子命令因此看不见它们；本库自己的 ObjC 方法表（判 `override` 与显式 selector 的证据）也读不到它们，所以提案 0077 补回来的只剩 thunk 的成员，在这些类里只有 `@objc`、没有 `override`。它们的 `class_ro_t` 其实都静态存在，只是要从 Swift 元数据才能找到。MachOObjCSection 0.8.201 新增了 `ObjCSuppliedClass`，让宿主把这种类交给 `ObjCInterfaceIndexer`；本提案让本库算出这些类交出去，同时让本库自己的 ObjC 方法表也认识它们。

## 方案

1. **按镜像的索引** `SwiftClassWithoutClassObjectIndex`（SwiftInspection，`SharedCache`，`.objcHierarchy` 驱逐组，跟随 `.symbolStore`）：从类型描述符枚举三种类，每一种算出 `class_ro_t`、元类的 `class_ro_t`、stub、名字、父类，以及有没有 ObjC 祖先。
   - **泛型类**：generic metadata pattern 的 extra-data pattern 里，`class_ro_t` 在 pattern 数据的第 (`ClassRODataOffset` − `OffsetInWords`) 个字，元类的在第 (`MetaclassRODataOffset` − `OffsetInWords`) 个字（运行时 `initializeClassMetadataFromPattern` 的算法）。模板里的 `class_ro_t.name` 是空指针，名字用 Swift 限定名加上各层泛型参数（`Xcode_Service.MenuBarPanelWindow<A>`；嵌套在泛型里的写成 `<A, A1>`）。
   - **父类在别的 resilience domain 的非泛型类**（Resilient 策略）：`ResilientClassMetadataPattern.data` 是 `class_ro_t`，`metaclass` 指向的元类的 `data` 字段是元类的 `class_ro_t`；stub 来自描述符的 `ObjCResilientClassStubInfo`。
   - **父类是本模块泛型类的非泛型类**（Singleton 策略）：静态 incomplete metadata 本身就是一个 class object 的形状，`class_ro_t` 与元类都经 MachOObjCSection 的读取器从它读出；描述符里不记 stub，而这种 stub 是非公开的，只有完整 stub 的私有符号 `…CMt`，isa 字段在它后面一个字；剥掉 local 符号的镜像里没有这个符号，就不记。Update 与 FixedOrUpdate 策略的类同样有 singleton 初始化，但它们的元数据在 class list 里，按偏移排除。
   - 绝对指针（class object 的 `data` 与 `isa` 字段）一律经 MachOObjCSection 的读取器解，相对指针自己解，这样 dyld cache 的几套偏移不必在这里处理。
   - **有没有 ObjC 祖先**：看类标志位的 `UsesSwiftRefcounting`（ObjC 对象模型下为 0），继承 `NSObject` 的 actor 例外。
   - **父类**：ObjC 父类给它的运行时名（`__C.NSPanel` 给 `NSPanel`），没有声明父类的给 `_TtCs12_SwiftObject`；同一镜像里有 class object 的 Swift 父类给它的运行时名；同一镜像里同样没有 class object 的给它在本索引里的名字；其余（别的镜像里的 Swift 类）给 Swift 写法，只作显示用。
2. **交给 MachOObjCSection**：SwiftIndexing 新增公开的 `ObjCSuppliedClass.swiftClassesWithoutClassObjects(in:)`，交出全部泛型类，以及 `__objc_stublist` 登记的那些非泛型类——编译器只给有 ObjC 祖先的类登记 stub，MachOObjCSection 给这两类写的注释也是「registered through `__objc_stublist`」。SwiftSectionKit 的 `ObjCInterfaceSession` 与 `ObjCAPIRequests` 两处构造索引器时传入；SwiftIndexing 的 `ObjCInterfaceIndexerClassHierarchyProvider` 在 `classGroup(forName:)` 落空时查 `suppliedClassGroup(forName:)`。
3. **本库的 ObjC 方法表**：`ObjCClassMethodIndex.runtimeNames(forSwiftClassQualifiedName:in:)` 也给出本索引里的名字，`hierarchy(forRuntimeName:in:)` 在没有 class object 时从算出的 `class_ro_t` 读方法表，父类按上面的规则续链；父类同样没有 class object 时，祖先链里新增一种位置 `ObjCSuperclassLocation.withoutClassObject` 接着走。按名字找 ObjC 父类的 `ObjCAncestorResolver.classObject(named:)` 在进程内也到已加载的镜像里找：进程内 class object 的父类都是真指针，原本用不着按名字找，没有 class object 的类却只有父类的名字。方法表这一侧不过滤 ObjC 祖先：纯 Swift 类没有 ObjC 方法，自然不出表。
4. **依赖**：MachOObjCSection 的要求升到 `"0.8.201" ..< "0.9.0"`，随之要求 MachOKit 0.55.100、swift-objc-dump 0.8.102。

已知限制（本版不做）：

- 父类是另一个镜像里的 Swift 类时（`Xcode Service` 的 `MenuBarLabelHostingView` 继承 SwiftUI 的 `NSHostingView<MenuBarLabel>`，SwiftUI 的类继承 SwiftUICore 的类），链在那里断，`override` 照旧不判。非泛型的那种可以按限定名到依赖镜像的 class list 里找，留作后续。
- 本库自己的读取器读不到挂在 stub 上的 category（Swift `extension` 里的 `@objc` 成员），因为 `targetClassName(of:)` 从 stub 读不出名字；MachOObjCSection 的索引器按 `classStubOffset` 归类，宿主走 provider 时没有这个问题。

验证：

- fixture `ClassesWithoutClassObjectsFixture`（测试时现编：一个开 library evolution 的 kit，加上使用它的客户端，`.full` 与 `strip -x` 两种）：三种类各一个，加一个纯 Swift 的泛型类、一个没有 ObjC 祖先的 Singleton 类和一个有 class object 的对照组。
- 先在不含本改动的 `next` 上跑 interface 与 `objc dump` 两组行为测试，确认失败；再在分支上确认通过。
- `Xcode Service`：两个类在 `objc dump` 里出现、方法表与 MachOObjCSection 那边的测试一致；`MenuBarPanelWindow` 的 `canBecomeKey` 等成员在 interface 里变成 `@objc override`。
- 渲染 A/B：Swift 侧 interface 应只多出 `override` 与 `@objc`（以及随之少掉的 `final`）；dump 多出 ObjC 方法表的注释。

## 后续项

- **别的镜像里的 Swift 父类续链**：非泛型的那种（SwiftUI 的类继承 SwiftUICore 的类）按限定名到依赖镜像的 class list 里找 class object；泛型的那种（`NSHostingView<…>`）要跨镜像读它的 generic metadata pattern。
- **本库读取器读挂在 stub 上的 category**：按 category 的目标指针与 `classStubOffset` 比对，像 MachOObjCSection 的索引器那样归到类上。
- **RuntimeViewer 采用**：它的 ObjC 侧包着自己的 `ObjCInterfaceIndexer`（`RuntimeObjCInterfaceIndexer`），读文件时传入 `ObjCSuppliedClass.swiftClassesWithoutClassObjects(in:)` 就能列出这些类。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-10-27 | Created as Draft，状态 Accepted | #137 的 ObjC 侧；用户批准本库与 MachOObjCSection 两边并行开工，MachOObjCSection 的 host-supplied-classes 提案已获批准。轻量档。 |
| 2026-10-27 | 与 MachOObjCSection 商定的 API | `ObjCSuppliedClass(name:superClassName:readOnlyDataOffset:metaclassReadOnlyDataOffset:classStubOffset:kind:)`；`classStubOffset` 是 stub 的 `isa` 字段（公开 stub 的 `…CMs` 所指），由本库要求加上，用来把挂在 stub 上的 category 归到这个类。 |
| 2026-10-27 | 改为 In Progress；依赖直接用 MachOObjCSection 0.8.201 | 对面已发版（tag 指向 e40982f），不必再用 SwiftPM 的 edit 模式指向它的工作树。 |
| 2026-10-27 | 非泛型的两类只交出有 ObjC 祖先的，泛型类全交 | 编译器只把有 ObjC 祖先的类的 stub 登记进 `__objc_stublist`（`GenMeta.cpp` 的 `emitClassMetadata`），MachOObjCSection 的注释写的正是这一点；泛型类哪个表都不进，注释「instantiated at runtime」对所有泛型类都成立。索引本身两种都记，本库的方法表不过滤。 |
| 2026-10-27 | 别的镜像里的 Swift 父类只作显示，不续链 | 运行时名要用旧式 mangling 拼，本库没有旧式 remangler；按限定名到依赖镜像找 class object 可行，但不在 #137 的范围里，记为后续。 |
| 2026-10-27 | 进程内也按名字找 ObjC 父类 | 起初把进程内断链记成已知限制，但已有的 `optimizedImageInProcessDeclaresWhatTheFileDeclares` 要求进程内与文件打印出同样的声明，泛型类在进程内少了 `override` 就红了。`ObjCAncestorResolver` 本来就持有进程内根的已加载镜像，按名字查与文件的依赖闭包用同一套 export trie 预检。 |
| 2026-10-27 | Singleton 类的 stub 找 `…CMt`，不找 `…CMs` | 探针证实非公开 stub 只定义完整 stub 的私有符号 `…CMt`（`emitObjCResilientClassStub` 只在公开时才给 isa 字段定义别名 `…CMs`），isa 字段在它后面一个字。 |
| 2026-10-27 | 父类名改用 `.interface` 预设打印 | `Xcode Service` 上抓到 `.interfaceType` 预设去掉泛型实参，`MenuBarLabelHostingView` 的父类读成了 `SwiftUI.NSHostingView`。fixture 加了一个父类是别的模块泛型类的例子。 |
| 2026-10-27 | 渲染 A/B 的差异全部是预期中的改进 | 96 对里 30 对不同，都在 SwiftUI 与 SwiftUICore，没有删掉的声明，也没有类型变化。interface 只多出关键字：`override`、`static` 改成 `override class`、剥过符号的模拟器腿上的 `@objc`，以及 12 处显式 selector。显式 selector 逐个核过：两个 focus 方法与基线给有 class object 的兄弟类的判定相同，`_nsAttributedSubstringFromRange:` 与基线在 iOS 18.5 模拟器腿上的判定相同，`springLoadingHighlightExited:` 是 `NSHostingView<Content>` 方法表里的真实 selector。dump 只多出方法表与祖先链的注释。两侧渲染耗时相同。细节见实现说明的「验证」。 |
| 2026-10-27 | 改为 Implemented，编号 0078 | 用户批准：A/B 差异全部是预期中的改进就合入 `next`。配套文档写了实现说明 [ClassesWithoutClassObjects.md](../Internal/ClassesWithoutClassObjects.md)，不需要单独的使用指南（CLI 的变化写进了 [ObjCCommandLine.md](../ObjCCommandLine.md) 第 5 条与插件 skill）；新术语 class without a class object 已登记进术语表。 |
