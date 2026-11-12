# SwiftDeclaration 模块

> 模块参考文档（module reference），随代码维护。读者：维护者。
> 细节文档见文末[「相关文档」](#相关文档)；本文负责全貌与分工，不复述细节。

## 模块定位

SwiftDeclaration 是**共享声明模型**：`SwiftIndexing` 往里填，`SwiftPrinting` / `SwiftDiffing` / `SwiftSpecialization` / `SwiftAttributeInference` 从里读。索引与打印是平级的，谁也不依赖谁，能这样是因为中间隔着这份模型。

它同时是**降级上报的类型入口**（`SwiftIndexEvents`），虽然事件的分发和落点是宿主的事。

模型的设计张力只有一句：**它要既够用来打印一份完整接口，又不能钉住 Mach-O**。索引完之后宿主可能只想拿着一张类型表做界面，这时候还抱着解析好的胖 wrapper 和整张符号表就说不过去了。

## 文件 → 子系统对照

模块分成两棵树，判据是可见性（提案 [draft-swift-declaration-model-indexing-layout](../../Evolutions/draft-swift-declaration-model-indexing-layout.md)）：`Model/` 是下游读的公开模型，索引结束后还留着；`Indexing/` 是把模型填满的代码，里面每个声明都是 `package` 或 `internal`，只在 `index(in:)` 与 `SwiftDeclarationIndexer.prepare()` 期间有人调用。新文件按这条判据归位：类型是 `public` 的、会出现在公开 API 的返回值里，进 `Model/`；只在索引期活着，进 `Indexing/`。将来要把索引代码整体挪到 `SwiftIndexing`，边界已经画好了。

| 子系统 | 文件 |
|---|---|
| 1. 声明本体 | `Model/Definitions/`（`Definition` / `MutableDefinition` 协议、`TypeDefinition`、`ProtocolDefinition`、`ExtensionDefinition`、`ObjCProtocolDefinition`，以及 ObjC 声明导入成 Swift 的 `ObjCImportedClassDefinition`、`ObjCImportedCategoryDefinition`、`ObjCImportedProtocolDefinition`）——只有存储属性、`init` 与 materialize 方法，不含索引逻辑 |
| 2. 成员 | `Model/Members/`：成员定义（`FunctionDefinition`、`VariableDefinition`、`SubscriptDefinition`、`FieldDefinition`、`WrappedPropertyDefinition`、`ObjCProtocolRequirementDefinition`、`ObjCImportedMemberDefinition`）、宏展开的描述 `ObservableMacroExpansion`、成员构件（`Accessor`、`OrderedMember`、`MemberCategory`、`StrippedSymbolicRequirement`），以及三种成员定义上的公开投影 `ResolvedObjCMemberFacts` |
| 3. 名字 | `Model/Names/`（`DefinitionName`、`TypeName`、`ProtocolName`、`ExtensionName`） |
| 4. 种类枚举 | `Model/Kinds/` |
| 5. 挂在声明上的独立概念 | `Model/` 根下的 `ExportStatus`、`SwiftAttribute`、`SwiftAttachedMacro`、`ResolvedAssociatedTypeWitness`、`ObjCCategoryConformance` |
| 6. 各声明的索引 | `Indexing/`：`DefinitionIndexing`（每个定义只索引一次，见下文）、`TypeDefinition/` 下的十个扩展（见下表）、`ExtensionDefinition/` 下的 `+Indexing` / `+ObjCMembers` / `+ThunkAttributes`、`ProtocolDefinition+Indexing`、`ObjCProtocolDefinition+Indexing`、`ObjCImportedDefinitions+Indexing`（三种 ObjC 导入定义） |
| 7. 构建期机器 | `Indexing/Building/`（`MemberDefinitionBuilder`、`MemberSymbolBucketing`、`OverrideSymbolMatcher`、`ClassDispatchLookups`、`StandInMemberSymbolBuilder`、`AnnotatedSymbol`、`WrappedPropertyRecovery`、`ObservableMacroExpansionRecovery`、`ThunkAttributeMatcher`、`ObjCMemberMatcher`、`ObjCProtocolNameBuilder`）——各声明的索引扩展调用的构件；`TypeDefinition+ThunkAttributes` 与 `ExtensionDefinition+ThunkAttributes` 共用 `ThunkAttributeMatcher`，两个 `+ObjCMembers` 共用 `ObjCMemberMatcher`。命名空间按角色取后缀（提案 [draft-swift-declaration-type-naming](../../Evolutions/draft-swift-declaration-type-naming.md)）：造出新东西的叫 `…Builder`，拿二进制里另一处的证据（thunk 符号、ObjC 方法表、override 描述符）对到已建好的成员上的叫 `…Matcher`，补回二进制丢掉的事实的叫 `…Recovery`；不用 `…Application`，它会被读成「应用程序」 |
| 8. 对上游类型的扩展 | `Extensions/`（按被扩展的类型分文件：`ProtocolConformance+Names`、`TypeContext+Names`、`FieldRecord+DemangledType`、`Node+TypeKind`、`DemanglingNode+StoredVariable`……） |
| 9. 事件 | `Events/SwiftIndexEvents` |

### TypeDefinition 的十一个扩展

本体 `TypeDefinition.swift` 在 `Model/Definitions/`：存储属性、两个 `init`、`materializedTypeContext(in:)`，不含任何索引逻辑。索引代码在 `Indexing/TypeDefinition/`：主干在 `+Indexing`，`index(in:)` 串起来的其余十件互不相干的事每件一个文件，主干只剩调用顺序：

| 文件 | 负责 |
|---|---|
| `+Indexing` | `index(in:)` 主干、字段记录 → `FieldDefinition`、accessor 组回折、源码给类起的 ObjC 运行时名字 |
| `+InitAccessors` | SE-0400 init accessor 初始化哪些字段的推断 → `VariableDefinition.initializedFieldNames`（规则在 SwiftInspection 的 `InitAccessorFieldInference`） |
| `+ClassDispatch` | vtable / override / defaultOverride 三张表 → `ClassDispatchLookups`；另为本类每个 `Tq` 能命名的 vtable 槽造一个替身成员符号 |
| `+MemberIndexing` | 六类成员与两个 `deinit` 符号；实现符号缺席的 vtable 成员用替身补上 |
| `+ThunkAttributes` | `@objc` / `@nonobjc` / `@distributed` 的交叉引用 |
| `+ObjCMembers` | 类自己的 ObjC 方法表 join 到成员上：`@objc`、`override`、显式 selector（经 `Building/ObjCMemberMatcher`） |
| `+FinalRecovery` | 提案 0006 的 `final` 恢复与它的四道门 |
| `+SynthesizedMembers` | 自动合成成员的去重 |
| `+WrappedProperties` | property wrapper 用法的恢复 |
| `+ObservableMacro` | `@Observable` 展开的恢复 → `observableMacroExpansion`（规则在 `Building/ObservableMacroExpansionRecovery`） |
| `+ObjCProtocols` | 类的 `class_ro_t` 列出的 ObjC 协议 → `objcProtocolNames`（经 `Building/ObjCProtocolNameBuilder`） |

**主干里的顺序是有约束的，不能随手调**：`final` 恢复要在 `applyThunkAttributes` 与 `applyObjCMembers` 之后（两者都给它 `@objc` 证据，它据此排除 `@objc dynamic`），且在 `orderedMembers` 之前（那一步会把成员值复制走）；init accessor 的推断同样要在 `orderedMembers` 之前，紧跟在字段回折之后；wrapped property 恢复要在字段回折与成员构建都完成之后；`@Observable` 展开的恢复又要在它之后，wrapper 的存储字段不归宏。每个步骤方法的 doc comment 各自写明了自己依赖什么。

### 每个定义只索引一次，可以被并发打印

七个 Definition（`TypeDefinition`、`ProtocolDefinition`、`ExtensionDefinition`、`ObjCProtocolDefinition` 与三种 ObjC 导入定义）的 `index(in:)` 是**同步**函数，都经 `Indexing/DefinitionIndexing.swift` 执行（提案 [0066-concurrent-definition-printing](../../Evolutions/0066-concurrent-definition-printing.md)）。进程级一把锁守着两样东西：一张「正在索引」的表（按 `ObjectIdentifier(定义)`），和每个定义自己的 `hasCompletedIndexing`。首个调用者认领后在自己的线程上跑完索引体；同时到来的调用者在认领者的 promise（复用 `SharedCacheBuildPromise`，载荷是 `Result`）上阻塞等待，拿到同一个结果。索引体抛错时定义回到未索引、错误交给全部等待者，下次调用重试。`isIndexed` 是只读的计算属性，读的就是锁下的那个标志。

阻塞等待不会死锁，靠两条前提，改索引时要守住：

- **索引体里没有 `await`**。函数签名是同步的，由编译器保证：认领者在认领与交付结果之间不会被挂起。
- **索引体不去索引别的定义**。它只经 `SharedCache` 一族读镜像，而这些缓存都在 `SwiftDeclaration` 之下的模块里，构建闭包按依赖方向根本够不到定义。认领或等待时如果当前线程正在跑某个索引体，`precondition` 直接 trap，免得等待成环。

打印期也不写定义：类型级 attribute 由打印器每次推断成局部变量，不存回 `TypeDefinition`。所以 `MachOImage` 读者下，同一个 printer 实例可以被多个任务同时调用，包括同时打印同一个定义、父类型与它的嵌套子类型（`ConcurrentDefinitionPrintingTests`）。`MachOFile` 读者仍然不行：MachOKit 的文件读取共用一个 `FileHandle`。`specialize(...)` 往泛型定义的 `specializedChildren` 追加时不加锁，也不在这个承诺里。

## 关键契约

### 持有描述符引用，不持有解析好的 wrapper

`TypeDefinition.typeContextDescriptorWrapper`、`ExtensionDefinition.protocolConformanceDescriptor`、`ProtocolDefinition.protocolDescriptor` 存的是**描述符引用**；完整 wrapper（连同尾随对象）按需经 `materializedTypeContext(in:)` / `materializedProtocolConformance(in:)` / `materializedProtocol(in:)` 重建。

> **materialization 纪律**：一次操作（索引它 / 打印它 / 特化它）至多 materialize 一次，用局部变量串下去。**不要写成每次访问都重建的 computed property，也不要把结果缓存回 definition 上**——缓存等于按浏览顺序把当初瘦身省下来的内存重新攒回来。`DeclarationModelInstanceSizeTests` 盯着实例尺寸上限。

索引期用的段 wrapper 群（`types` / `protocols` / `protocolConformances` / `associatedTypes` 以及按解析值做 key 的 conformance 映射）是**索引期临时物**，`prepare()` 结束就释放，没有公开投影。索引后还留着的 conformance 事实是名字级的映射（`conformingProtocolNamesByTypeName` / `conformingTypesByProtocolName` 及其合并变体），后续消费者要的就是这些。

### 名字按结构比较，`kind` 不参与相等

三个 `Name` 类型把 `Hashable` 定制成结构语义（`structurallyEquals` + `structuralHash`）：`NodeReference` 自带的 `Hashable` 是 store 身份的，会把 mint 到不同 store 的相等 key 劈成两个。

`kind` **不参与相等判定**：节点本身已经标识了类型，而 `kind` 是各生产者各自推导的（描述符的 kind vs. 在 demangle 树上走一遍），两者对 C 导入类型必然打架——C tag 枚举在描述符看来是 enum，在所有 mangling 里都是 structure；被提升的 C typedef 是 typeAlias。这个分歧曾经把一个 conformance 和它的 `__swift5_assocty` 记录、witness 符号劈开。

这几个类型**故意不是 `Codable`**：上游取消了 `Node: Codable`（一个 mangled symbol 本身就是这棵树的序列化形式，更小、跨工具链稳定、还保留共享结构），而且没有任何东西需要持久化它们。真需要时持久化 `mangleAsString(node)`，读回来用 `demangleAsNode(_:)`，不要重新引入节点编码。

### 导出状态在构造时定死

每个 `TypeDefinition` / `ProtocolDefinition` 带一个 `ExportStatus`（`exported` / `notExported` / `imageHasNoExportInformation` / `descriptorSymbolNameUnresolvable` / `declarationIsCImported`），在构造时从声明自己的描述符解析一次，存成 `let`。描述符属于 `__C` 或 `__C_Synthesized` 模块时直接是 `declarationIsCImported`，不查 trie：编译器给 Clang 声明的是非唯一链接，每个用到这个 C 类型的模块各自生成一份描述符、谁都不导出，它说明不了类型能不能被外部使用，而本镜像给它写的扩展可以是公开 API（提案 [0083-exported-only-marking-mode](../../Evolutions/0083-exported-only-marking-mode.md)）。描述符上没有符号、名字又不能可信地重整（镜像没留本地符号，声明在带约束的扩展里）时，私有或局部声明判 `notExported`，其余是 `descriptorSymbolNameUnresolvable`。`ObjCProtocolDefinition` 只能看名字：Swift 声明的 `@objc` 协议没有描述符，也没有任何自己的符号，私有的（或嵌在私有类型里的）判 `notExported`，其余是 `declarationHasNoSymbol`（提案 `export-verdict-without-local-symbols`）。所以 `SwiftDeclarationIndexer.prepare()` 一返回，整张表就都有值了，宿主可以逐行标注而不必抱着 Mach-O。

`TypeDefinition.wrappedProperties` 是索引在 `index(in:)` 末尾算出的 property wrapper 用法（提案 [0041-interface-hides-compiler-synthesized-members](../../Evolutions/0041-interface-hides-compiler-synthesized-members.md)）：每个存储字段 `_x`，只要它的 nominal 类型有 `wrappedValue` accessor——先查本镜像符号索引（internal wrapper 也算），再经 `SwiftDeclarationRendering.PropertyWrapperTypeCatalog` 查本镜像与依赖闭包各镜像的导出 trie（SwiftUI 的 `@State` 用在 app 里）——就记一条 `WrappedPropertyDefinition`：属性名、`_x` / `$x` 的名字、attribute 类型节点（wrapper 恰一个泛型实参且等于被包装类型时省略实参），以及来源：`x` 自己的 accessor 符号还在就是 `declaredMember`；被 strip 了就 `synthesized(declaredTypeNode:hasSetter:)`，类型由 wrapper 的 `wrappedValue` 类型代入 `_x` 的泛型实参得到。`fields` 与 `variables` 里的 `_x`、`$x` 原样保留——diff / snapshot 的记录来自它们——只有 interface 打印器改按这张表渲染。目录由 `SwiftDeclarationIndexer.prepare()` 用索引配置里的 `dependencySearchPaths` 登记、随索引器一起释放（`PerImageCacheEvictionRegistry` 的 `propertyWrapperCatalog` claim）；没登记过的镜像退化成查系统 cache。

`@Observable` 宏分两层进模型（提案 [draft-observable-macro-folding](../../Evolutions/draft-observable-macro-folding.md)）。`TypeDefinition.attachedMacros` 在构造时算出，和 `ExportStatus` 一样 `prepare()` 一返回就在：类里有类型正是 `Observation.ObservationRegistrar` 的 `_$observationRegistrar` 字段、又没有 SwiftData `@Model` 留下的 `_$backingData`，就记 `.observable`。规则只读字段记录（`SwiftInspection.ObservableMacroRecognition`），所以剥过符号的镜像照样认得出；特化出来的定义沿用泛型定义的值。`SwiftAttachedMacro` 用 struct 加静态成员而不是 enum，以后识别别的宏，宿主的 `switch` 不会编不过。索引器建 conformance extension 时，给宏生成的 `extension X: Observation.Observable {}` 记上 `ExtensionDefinition.generatingMacro`。

`index(in:)` 在 wrapped property 恢复之后算 `TypeDefinition.observableMacroExpansion`：哪些 `_x` 是被跟踪属性 `x` 的存储、来源（`x` 的 accessor 还在镜像里是 `declaredMember`，否则 `synthesized`）与认定它的证据，哪些存储的 `var` 是 `@ObservationIgnored`，以及宏生成的方法。证据依次是：`x` 的 init accessor；镜像里成员 `x` 的 setter 或 `_modify`；初始值表达式挂在 `x` 名下。`_x` 自己的初始值表达式、或 `_x` 有 accessor 而 `x` 一个都没有，把它排除；什么都没有时只凭存储字段名认作被跟踪，这一档会把 `@ObservationIgnored var _y` 读成被跟踪的 `y`。镜像带不带本地符号不分流：系统框架链接时 dead-strip，SwiftUI 带本地符号却没有 init accessor，缺了不代表没有。初始值表达式不进成员桶；init accessor 进了（它是所属属性的 `AccessorKind.initAccessor`，见下文），这里照旧和初始值表达式一样，用 `symbols(of: .initAccessor)` / `symbols(of: .initializer)` 按类型筛，先比名字再比上下文——按 kind 的索引对每个符号都记一行，进不进成员桶都不影响它。初始值表达式只在 accessor 定不下来时才查，每个类最多一次。和 wrapped property 一样，`fields`、`variables`、`functions` 原样保留，只有 interface 打印器按这份描述折叠。

四个「没有结论」的态**作用域不同**，不要混：`imageHasNoExportInformation` 是镜像级的（根本没有 export trie，此时把它读成「未导出」会把一个 `.o` 文件的每个声明都报成未导出）；`descriptorSymbolNameUnresolvable` 是声明级的（trie 没问题，但这一个名字的 remangle 不可信）；`declarationHasNoSymbol` 也是声明级的，但不是读不出，是本来就没有可查的符号；`declarationIsCImported` 同样是声明级的，符号倒是有，只是那是本镜像的一份副本，不是声明自己的。

对外投影只有两个：`isExported: Bool?` 和 `isDefinitelyNotExported`——**过滤和标注只能依据后者**。

### 库代码不写进程流

每一处降级——丢掉的声明、跳过的描述符、加载不了的依赖——都作为事件分发出去，落到哪儿由**宿主**决定。`Dispatcher.dispatch` 有个**兜底**：一个 handler 都没挂时它用 `#log` 报出来，而不是丢掉。

> 什么算 failure 由 `Payload.unhandledFailureDescription` 定，那是一个**故意穷举**的 `switch`——新增 failure case 必须显式登记进去，否则它会静默绕过兜底。

Handler 的调用是**进程级串行**的（跨所有 dispatcher 一把递归锁）：`Handler` 没有 `Sendable` 要求，而跨版本准备会让 N 个 task 上的 N 个 dispatcher 共用宿主的同一个 handler。跨 dispatcher 的投递**顺序**仍是先到先得。

> 永远不要用 `FileHandle.standardError/Output.write(_:)`——这个重载在流已关闭或损坏时抛出无法捕获的 ObjC 异常，直接终止宿主。用 `fputs` / `fwrite`。（`write(contentsOf:)` 要 macOS 10.15.4，高于本包 10.15 的下限。）

有两个模块在事件层**之下**、够不到它（`SwiftDeclaration` 依赖 `SwiftDeclarationRendering`，在那里命名事件类型会成环）：`Node+OpaqueType` 收一个注入的报告闭包，`MultiPayloadEnumDescriptorCache` 直接打日志；两者都落到同一个 `#log` 兜底上。

`PrintFailureEventTests.libraryModulesWriteToNoProcessStream` 是一次源码扫描，带一份显式的、**只许缩短**的历史豁免名单。

### `@objc @implementation` 类挂在 extension 上

SE-0436 的类在 `__swift5_*` 里没有身影，模型里它就是那个 `__C.X` 的 `ExtensionDefinition`：`objcImplementation` 装 `SwiftObjCInterop.ObjCImplementationClassFacts`（证据档位、ivar 与 `Wvd` 的 join、方法表），`VariableDefinition.objcImplementationStorage` 标出由访问器符号建出来却是存储属性的成员。这个事实**不进** ABI 快照的容器 key。详见 [ObjCImplementationClassRecognition.md](../ObjCImplementationClassRecognition.md)。

### 成员从符号建，vtable 槽补上缺席的那些

成员定义是符号驱动的：`FunctionDefinition.symbol`、`Accessor.symbol` 都不是可选值，`MemberDefinitionBuilder` 的每个构造点都从一个 `DemangledSymbol` 出发。class 的 vtable 成员是例外来源：library evolution 模块只导出 public class 方法的 `Tj` / `Tq`，实现符号是 local 的，镜像的 local 符号被剥掉之后（系统 dyld shared cache 里的 AppKit、`strip -x` 过的二进制）这些成员没有符号可建。`classDispatchLookups` 为本类每个 `Tq` 能命名、实现指针非 null 的槽造一个替身符号——名字是 `Tq` 名去掉后缀（实现函数本来的 mangled 名），偏移是实现偏移（async 方法再跳到函数入口）——`indexMembers` 经 `ClassDispatchLookups.supplementing(_:in:)` 只补真实符号没有声明的成员。替身按实现符号的样子造，所以导出判定、ObjC 方法表 join、ABI 身份都不用分支。ABI 墓碑、modify / read 协程、override 槽不补。打印时 class 的 vtable 成员（有槽号的成员）按槽号排在最前（`OrderedMember.vtableOrdered`）。详见 [DescriptorOnlyVTableMembers.md](../DescriptorOnlyVTableMembers.md)。

优化构建是另一个例外来源：整模块优化会把 internal 成员的实现符号删掉，只留下同一个成员的另一个入口——`@objc` 成员只剩它的 ObjC thunk（`$s…To`，函数体内联在里面），class 的 initializer 只剩 initializing entry point（`…fc`，allocating entry point 内联进了调用方），Swift 6.4 连它也只剩函数签名特化副本（`…fcTf…`）。`StandInMemberSymbolBuilder` 从这几种入口造替身，规则与 `Tq` 替身相同：名字与成员树照实现符号的样子（thunk 去掉 `To` 与 `objCAttribute`，initializing entry point 把 `constructor` 改写成 `allocator`、`fc` 换成 `fC`，特化副本先去掉 `Tf…` 后缀再照 initializing entry point 处理），偏移是镜像里留下的那个入口。类成员经 `StandInMemberSymbolBuilder.TypeMembers`，extension 成员经 `supplementingExtensionMembers`，都排在真实符号与 `Tq` 替身之后，只补没人声明的成员；去重键 `declaredEntityKey(of:)` 三种替身共用。详见 [ThunkOnlyObjCMembers.md](../ThunkOnlyObjCMembers.md)。

### ObjC 方法表给出的成员事实：`@objc`、`override`、显式 selector

`FunctionDefinition` / `VariableDefinition` / `SubscriptDefinition` 各有一个 `objcMember: ObjCMember?`——这个成员实现的 ObjC 方法：selector、是否类方法、覆写的祖先（可空）、证据档位、selector 是否为源码里 `@objc(name)` 写出的。`isOverride` 与 `isClassMember` 都 OR 上 `objcMember?.isOverride`（覆写的类方法必须打 `class`）；联结上的成员缺 `.objc` 属性就补上（OS 框架 strip 掉了 `To` thunk 符号，方法表是 `@objc` 的唯一证据）；printer 在 `hasExplicitSelector` 时打 `@objc(selector)`。表联结不上的覆写方法**始终**按名字归属一次（第三档），结果照样写进 `objcMember`（`evidence == .selectorName`）——但**不写 `attributes`**，因为紧跟其后的 `final` 还原会把 `@objc` 读成 `@objc dynamic` 的证据，那是消费者还没下的裁决。用不用这一档由消费者决定：`resolvedObjCMemberFacts(trustingSelectorNameEvidence:)`（`ResolvedObjCMemberFacts.swift`）按裁决一次性给出 `attributes` / `isOverride` / `isClassMember` / `isFinal`，printer 传 `SwiftDeclarationPrintConfiguration.infersObjCOverridesFromSelectorNames`。定义自己的 `isOverride` / `isClassMember` 只认前两档（`ObjCMember.isJoinedOverride`）。它由 `Building/ObjCMemberMatcher` 在 `TypeDefinition.index(in:)`（`applyThunkAttributes` 之后、`recoverFinalMembers` 之前——`final` 还原用 `@objc` 排除 `@objc dynamic`）和 `SwiftDeclarationIndexer.indexExtensions()`（`__C` 类的 extension 与本镜像 Swift 类的 extension）里从 `SwiftThunkAnalysis.ObjCMembers` 的表 join 上来：函数按自己的符号名，属性 / 下标先按 getter 再按任一 accessor 符号，`init` 按 allocator 符号换 initializer 后缀。第三档「只按名字」的覆写推断也在这里做。这个事实**不进** ABI 快照。详见 [ObjCMemberRecovery.md](../ObjCMemberRecovery.md)。

### Swift 声明的 `@objc` 协议与类对 ObjC 协议的遵循

这种协议没有 protocol descriptor，所以不是 `ProtocolDefinition`（把它的 `protocolDescriptor` 改成可选会破坏下游），而是独立的 `ObjCProtocolDefinition`：名字是 `Type > Protocol`，与 Swift 协议同形，本镜像对它的 `extension` 因此落进它的 `defaultImplementationExtensions`；`index(in:)` 读出继承的协议与要求（`ObjCProtocolRequirementDefinition`：selector、setter selector、实例还是类、required 还是 optional、类型编码、声明的 node、签名来源）。签名来源是 `.selector`（按 importer 规则推出名字，打印时钉住 selector）或 `.conformer(className:)`（实现它的类的成员，声明的上下文已换成协议）。索引期只读成员表，不索引实现者的 `TypeDefinition`。

类对 ObjC 协议的遵循没有 conformance record：`TypeDefinition.objcProtocolNames` 是类的 `class_ro_t` 列的协议（同模块 extension 写的也在里面），在 `index(in:)` 里读；extension 别的模块的类时的 category 遵循是 indexer 的 `objcCategoryConformances`（`ObjCCategoryConformance`）。两者都去掉了某个 Swift 遵循隐含的 ObjC 协议。这些事实都**不进** ABI 快照。详见 [SwiftDeclaredObjCProtocols.md](../SwiftDeclaredObjCProtocols.md)。

### ObjC 声明按 Swift 导入的样子

镜像里的 ObjC 类、category 与协议，按 Swift 导入它们的样子建成 `ObjCImportedClassDefinition`、`ObjCImportedCategoryDefinition`、`ObjCImportedProtocolDefinition`（提案 [0090-objc-imported-declarations](../../Evolutions/0090-objc-imported-declarations.md)）。一个镜像的 ObjC 类动辄上千，所以它们不随 `prepare()` 建，而是由 `SwiftDeclarationIndexer` 的 `objcImportedClassDefinition(named:)` 等方法按名字现建，第一次打印时索引自己：从 SwiftObjCInterop 的记录建出成员（`ObjCImportedMemberDefinition`）、父类与协议的名字。名字保持 `__C` 下的 ObjC 名，与 mangling 一致，Swift 里改了名的交给打印时的类型名提供者。

类与 category 定义带着实现它们的 Swift 定义：桥接出去的 Swift 类带 `swiftClassDefinition`，`swiftExtensions` 是本镜像里这个类的 Swift extension。成员与 Swift 成员的配对在打印器里做（按 Swift 成员的 `objcMember`），模型不记。建这两样时有两个容易踩的坑：

- **同一模块里 extension 的成员在 mangling 里就是类型自己的成员**（extension 没有约束时不带 extension 上下文），所以它们已经在 `TypeDefinition` 里，`typeExtensionDefinitions` 里没有对应的 extension。
- **`TypeDefinition.extensions` 没有人填**，一直是空的。要一个类型在本镜像里的 extension，按 `typeName.extensionName` 去查 indexer 的 `typeExtensionDefinitions` 与 `conformanceExtensionDefinitions`。

### 访问器种类与关联类型的抑制（Swift 6.4）

`AccessorKind` 除 get / set / read / modify 外还有 SE-0507 的 `borrowAccessor` / `mutateAccessor`（符号后缀 `vb` / `vz`）。只声明了这两种访问器的属性、下标与协议要求没有 getter 符号，`MemberDefinitionBuilder` 因此把 getter 与 `borrow` 都当作「读访问器」来选声明节点；打印出的访问器块由 `hasBorrowAccessor` / `hasMutateAccessor` 决定（`{ borrow mutate }`），旁边编译器为满足协议合成的 getter / setter 不盖掉它们。`yielding borrow` / `yielding mutate`（SE-0474）还没有接。

SE-0400 的 init accessor 是 `AccessorKind.initAccessor`（符号后缀 `vi`，提案 [draft-init-accessor-recovery](../../Evolutions/draft-init-accessor-recovery.md)）。编译器把它的访问级别写死为 `internal`，只有 `@usableFromInline` 的才导出，所以优化过、链接时 dead-strip 的镜像里通常只剩导出的那几个，`hasInitAccessor == false` 不说明源码里没有。它在同名那组 accessor 里排最后（`accessors.first` 代表属性，例如它的 witness table 偏移），不参与成员排序（`OrderedMember.minSymbolOffset`：镜像留不留它随构建而变），也不算 `final` 恢复的证据（它从不进 vtable）。声明节点照旧取 getter 或 `borrow`；名字与某个存储字段相同的组照旧回折到字段上——SwiftUICore 为兼容旧客户端，在已改回存储属性的 `_GeometryActionModifier.value` 上留了一个同名函数。二进制不记录 `@storageRestrictions`：`initializedFieldNames` 只在类型有名叫 `_<属性名>`、类型与属性相同（剥掉 `weak` / `unowned`）的存储字段时给出 `["_<属性名>"]`，其余为 `nil`，`accesses:` 从不还原。比较的类型取 init accessor 自己的符号，不取 getter 的：getter 可能被 `@_silgen_name` 钉在旧 mangling 上（SwiftUICore 的 `_GeometryActionModifier2.value` 少了 `@Sendable`）。规则在 SwiftInspection 的 `InitAccessorFieldInference`（`initializedFieldNames(ofInitAccessorSymbol:)`），dump 直接读字段记录、对同一个符号套用同一条规则。这个推断**不进** ABI 快照；init accessor 本身进（`|acc:` 标签里的 `init`，快照格式 13）。

`ProtocolDefinition.suppressedInvertibleProtocolsByAssociatedTypeName` 记 `associatedtype Element: ~Copyable`（SE-0503）。二进制本身不记录这个声明，这里只装 `SwiftInspection.SuppressedAssociatedTypeInference` 从本镜像里该协议的 extension 签名证明出来的部分，而且只有主关联类型留得下证据；没有条目不代表关联类型是 Copyable。这个事实**不进** ABI 快照：证据有无随版本里写没写 extension 变化。详见提案 [0070-borrow-accessors-and-suppressed-associated-types](../../Evolutions/0070-borrow-accessors-and-suppressed-associated-types.md)。

## 相关文档

- [DeclarationModelMemoryFootprint.md](../DeclarationModelMemoryFootprint.md)——模型内存占用与瘦身。
- [EventBasedDegradationReporting.md](../EventBasedDegradationReporting.md)——事件层设计。
- [SharedNodeStoreMigration.md](../SharedNodeStoreMigration.md)——声明值持有 `NodeReference` 之后的规则。
- [ExtensionContainerUnification.md](../ExtensionContainerUnification.md)——extension 容器归并。
- [PerConformanceAttribution.md](../PerConformanceAttribution.md)——逐 conformance 的归属。
- [ExportedOnlyInterfaceFiltering.md](../ExportedOnlyInterfaceFiltering.md)、[InterfaceHeaderAndExportStatusAnnotations.md](../InterfaceHeaderAndExportStatusAnnotations.md)——导出状态的两种消费方式。
- [DescriptorOnlyVTableMembers.md](../DescriptorOnlyVTableMembers.md)——实现符号被剥掉的 class vtable 成员怎么从 `Tq` 补回来，以及 vtable 顺序打印。
- [ThunkOnlyObjCMembers.md](../ThunkOnlyObjCMembers.md)——优化构建删掉实现符号后，成员怎么从 `@objc` thunk 或 initializing entry point 补回来。
- [SwiftDeclaredObjCProtocols.md](../SwiftDeclaredObjCProtocols.md)——Swift 声明的 `@objc` 协议与类对 ObjC 协议的遵循。
- 演进提案：[0002](../../Evolutions/0002-declaration-model-descriptor-slimming.md) 描述符化瘦身 · [0005](../../Evolutions/0005-event-based-degradation-reporting.md) 事件化上报 · [0023](../../Evolutions/0023-type-import-info-identity.md) C 导入类型的身份 · [0024](../../Evolutions/0024-exported-declaration-flag.md) 导出标志。
