# SwiftObjCInterop 模块

> 模块参考文档（module reference），随代码维护。读者：维护者。
> 模块从 SwiftInspection 拆出的来历见提案 [0089-swift-objc-interop-module](../../Evolutions/0089-swift-objc-interop-module.md)；各子系统的来历见下文各节链接的提案与实现说明。本文负责全貌与分工。

## 模块定位

本模块回答「一个 Swift 类型在 Objective-C 一侧留下了什么」：Swift 类的 class object（`__objc_classlist` 与 `class_ro_t`）、`@objc @implementation` 类、Swift 里声明的 `@objc` 协议（`protocol_t`）、类的 ObjC 方法表与祖先链，以及把 selector 翻回 Swift 名字的 ClangImporter 命名规则。dump 与 interface 里的 `@objc`、`override`、`@objc(selector)`、`@objc @implementation`、改过的 ObjC 类名、`@objc` 协议与 ObjC 协议遵循，都从这里取事实。

它在依赖层级上紧挨在 SwiftInspection 之上。用到 SwiftInspection 的只有三样：`SymbolicDemangler`（从描述符造类型名）、`NodeTypeNaming`（节点 → 限定名）与 `GenericParameterDepthLayout`（泛型类的参数分层）；SwiftInspection 反过来不用本模块的任何东西。MachOObjCSection 从这一层进入 Swift 侧的模块栈，SwiftInspection 及其以下都不依赖它。

消费方：

- SwiftLayout：Swift 子类排字段时，改过运行时名的类的 `instanceStart` 从 `SwiftClassObjectIndex` 取；existential 布局认 `@objc` 协议时，source 里改过名的那些靠 `SwiftDeclaredObjCProtocolIndex` 认出来。
- SwiftThunkAnalysis：`ObjCMembers` 把方法表的每一项联结到它的 Swift 成员。联结要解码 thunk（Capstone），所以它留在 SwiftThunkAnalysis，表本身（`ObjCMemberTable`）在本模块。
- SwiftDeclaration 与 SwiftIndexing 把这些事实写进声明模型；SwiftDump、SwiftPrinting、SwiftDeclarationRendering 打印它们；SwiftSectionKit 的 `dump` 有自己的 ObjC 段。

## 文件 → 子系统对照

| 子系统 | 文件 |
|---|---|
| 1. Swift 类在 ObjC 一侧的样子 | `SwiftClassObjectIndex.swift`、`SwiftClassWithoutClassObjectIndex.swift`、`CustomObjCClassName.swift`、`ObjCRuntimeNames.swift`、`ClassHierarchyDumper.swift` |
| 2. `@objc @implementation` 类 | `ObjCImplementationClassIndex.swift`、`ObjCImplementationClassFacts.swift` |
| 3. ObjC 协议 | `SwiftDeclaredObjCProtocolIndex.swift`、`ObjCProtocolAdoptionIndex.swift`、`ObjCProtocolRecord.swift`、`ObjCProtocolRequirements.swift` |
| 4. 方法表、祖先链与成员 | `ObjCClassHierarchy.swift`、`ObjCClassMethodIndex.swift`、`ObjCAncestorResolver.swift`、`ObjCMember.swift`、`ObjCMemberShape.swift` |
| 5. 命名规则与类型编码 | `ObjCImporterNaming.swift`、`ObjCImporterVerbs.swift`、`ObjCTypeEncoding.swift` |
| 公共 | `SharedCacheEvictionGroup+SwiftObjCInterop.swift`（三个淘汰分组）、`Extensions/MachORepresentableWithCache+ObjCReaderKinds.swift`（`objcImplementationClassReader`） |

## 子系统速览

### 1：Swift 类在 ObjC 一侧的样子

- `SwiftClassObjectIndex`：source 用 `@objc(Name)` 或 `@_objcRuntimeName(Name)` 改过运行时名的 Swift 类，运行时名 demangle 不出任何东西，所以经类元数据的描述符指针（resilient 父类的类走 metadata pattern）配回它的描述符。按名字查 Swift 类的 ObjC 侧查找，查不到时都回退到它。`@objc(Name)` 与 `@_objcRuntimeName(Name)` 怎么区分、为什么只在查不到时回退，见 [CustomObjCClassNames.md](../CustomObjCClassNames.md)。
- `SwiftClassWithoutClassObjectIndex`：`__objc_classlist` 不列出的 Swift 类——泛型类，以及 `__objc_stublist` 登记的类——它们的 `class_ro_t` 从 Swift 元数据读出来。ObjC 成员表读它们，SwiftIndexing 把它们作为 `ObjCSuppliedClass` 交给 MachOObjCSection 的索引器。见 [ClassesWithoutClassObjects.md](../ClassesWithoutClassObjects.md)。
- `ObjCRuntimeNames`：ObjC 运行时认识协议与类的名字（`_TtP…`、`_TtC…`、改过的名字），读回成 Swift 的节点。
- `ClassHierarchyDumper`（SPI，只用于进程内的 `MachOImage`）：沿 Swift 类的元数据一路走进 ObjC 父类，列出整条继承链。RuntimeViewer 用它。

### 2：`@objc @implementation` 类

SE-0436 的 `@objc @implementation` 类编出来是纯 ObjC class object，没有 Swift 的 nominal type descriptor 与 field descriptor。`ObjCImplementationClassIndex` 联合 `__objc_classlist` 与符号表认出它们，给出 `ObjCImplementationClassFacts`：证据分 definitive 与 inferred 两档，ivar 按偏移值与 `Wvd` 符号配对，还有方法表。见 [ObjCImplementationClassRecognition.md](../ObjCImplementationClassRecognition.md)。

### 3：ObjC 协议

- **Swift 里声明的 `@objc` 协议没有协议描述符**：只有一条 kind 为 `ObjCProtocol` 的 `__swift5_fieldmd` 记录和一个 ObjC `protocol_t`，两者按名字配对。记录上的 IsSwift 标志不是证据：Swift 给它引用的别的协议也发带这个标志的副本。`SwiftDeclaredObjCProtocolIndex` 做配对；`ObjCProtocolRecord` 读 `protocol_t`，方法表、属性表与扩展类型编码按下标读整张表（MachOObjCSection 的 `extendedMethodTypes(in:)` 只返回第一条）；`ObjCProtocolRequirements` 把读到的记录变成 requirement。
- **类对 ObjC 协议的遵循没有 conformance record**：`class_ro_t` 列出它（同一模块里 extension 声明的遵循也折进这里），只有给别的模块的类写的 category 才另外列出。`ObjCProtocolAdoptionIndex` 读这两处。
- 只剩 selector 的 requirement 由 `ObjCImporterNaming` 起名，再用 `@objc(selector)` 钉住 selector。

见 [SwiftDeclaredObjCProtocols.md](../SwiftDeclaredObjCProtocols.md)。

### 4：方法表、祖先链与成员

- `ObjCClassHierarchy` + `ObjCClassHierarchyProviding` / `ObjCClassHierarchyProviderStore`：按镜像的接缝，宿主把它已经建好的 ObjC 类层级交进来——RuntimeViewer 的索引器，或 SwiftIndexing 包装 `ObjCIndexing.ObjCInterfaceIndexer` 的适配器。
- `ObjCClassMethodIndex`：接缝背后库自己的惰性读取器，读类、元类与同一镜像里 category 的方法表、祖先链、采纳的协议的 selector。
- `ObjCAncestorResolver` / `ObjCAncestorResolverStore`：独立文件里父类或 category 的目标是 bind 时，按名字到它的依赖闭包里找，先查 export trie，再查 class list。indexer 与 `dump` 按镜像、在配置的搜索路径上各注册一个；没注册的文件默认走系统 cache；进程内镜像不需要。这样独立文件的链也能一路走到 libobjc 的 `NSObject`，和 cache 里的镜像一样。
- `ObjCMember` / `ObjCMemberTable`：每个类的 ObjC 成员表，方法表里的每一项联结到它的 Swift 成员，`@objc`、`override` 与显式 selector 三个事实放在一处。
- `ObjCMemberShape`：成员在 selector 层面的形状。importer 的命名规则作为正向检查用，编译器自己从 Swift 名推导 selector 的规则移植过来，用于判定显式 selector。

见 [ObjCMemberRecovery.md](../ObjCMemberRecovery.md) 与 [ThunkOnlyObjCMembers.md](../ThunkOnlyObjCMembers.md)。

### 5：命名规则与类型编码

`ObjCImporterNaming`（词表在 `ObjCImporterVerbs`）移植自 Swift 仓库 `lib/Basic/StringExtras.cpp` 的 `omitNeedlessWords` 与 `lib/ClangImporter/ImportName.cpp`；`ObjCTypeEncoding` 解析 ObjC 协议记录里方法与属性的类型编码，包括 Swift 发出的扩展编码（`@"NSString"`、`@"<NSCopying>"`、block 签名）。这三个文件不读 Mach-O。

## 关键契约

- **SwiftInspection 不依赖本模块。** 新的 ObjC 侧代码放在这里，不放回 SwiftInspection：放回去会让 SwiftInspection 重新依赖 MachOObjCSection。
- **按名字查 Swift 类的 ObjC 侧查找，查不到时回退到 `SwiftClassObjectIndex`**：改过运行时名的类，按 Swift 名字推出的运行时名是查不到的。
- **按镜像的索引都是 `SharedCache`**，淘汰分组在 `SharedCacheEvictionGroup+SwiftObjCInterop.swift`：`objcImplementationClasses`、`objcHierarchy`、`objcAncestorResolver`，都跟随 `symbolStore`。分组的字符串从 SwiftInspection 时期起没变。
- **build closure 经 `objcImplementationClassReader` 转型读取器**：得到 `MachOFile`、`MachOImage`，或宿主包装器底下的那个读取器；不写 `as? MachOFile` / `as? MachOImage`。`ObjCImplementationClassReading` 是本模块自己的协议，外面的包装器无法遵循。
- **日志的 subsystem 仍是 `com.machoswiftsection.swift-inspection`**：RuntimeViewer 按 subsystem 与 category 过滤日志流，拆模块时有意没改。

## 测试锚点

- `SwiftObjCInteropTests`：`ObjCImporterNamingTests`、`ObjCProtocolRequirementBuilderTests`、`SwiftClassObjectIndexTests`、`SwiftClassWithoutClassObjectIndexTests`、`SwiftDeclaredObjCProtocolIndexTests`。
- 经过 dump 与 interface 的端到端测试：SwiftDumpTests 的 `ObjCMemberDumpTests`、`SwiftDeclaredObjCProtocolDumpTests`、`CustomObjCClassNameDumpTests`；SwiftInterfaceTests 的 `ObjCMemberRecoveryTests`、`ObjCImplementationClassRecognitionTests`、`CustomObjCClassNameInterfaceTests`。
- 缓存：SwiftIndexingTests 的 `PerImageCacheEvictionTests`（淘汰）；SwiftInspectionTests 的 `DyldCacheTwinImageTests`（同一构建在两个 dyld cache 里不串用 `ObjCClassMethodIndex` 的缓存）。

## 相关文档

- 拆分：[0089-swift-objc-interop-module](../../Evolutions/0089-swift-objc-interop-module.md)
- 各子系统的提案：[0046](../../Evolutions/0046-objc-implementation-class-recognition.md)（`@objc @implementation`）、[0047](../../Evolutions/0047-objc-ancestor-override-recovery.md)（祖先链与 `override`）、[0048](../../Evolutions/0048-objc-member-selector-recovery.md)（成员与显式 selector）、[0049](../../Evolutions/0049-objc-ancestor-dependency-closure.md)（祖先链走依赖闭包）、[0052](../../Evolutions/0052-objc-custom-class-name.md)（改过的 ObjC 类名）、[0078](../../Evolutions/0078-objc-classes-without-class-objects.md)（没有 class object 的类）、[0079](../../Evolutions/0079-swift-declared-objc-protocols.md)（Swift 声明的 `@objc` 协议）
- 实现说明：[ObjCImplementationClassRecognition.md](../ObjCImplementationClassRecognition.md)、[ObjCMemberRecovery.md](../ObjCMemberRecovery.md)、[ThunkOnlyObjCMembers.md](../ThunkOnlyObjCMembers.md)、[CustomObjCClassNames.md](../CustomObjCClassNames.md)、[ClassesWithoutClassObjects.md](../ClassesWithoutClassObjects.md)、[SwiftDeclaredObjCProtocols.md](../SwiftDeclaredObjCProtocols.md)
- 联结方法表与 Swift 成员的那一半：[SwiftThunkAnalysis.md](SwiftThunkAnalysis.md)
