# SwiftDeclaration 模块

> 模块参考文档（module reference），随代码维护。读者：维护者。
> 细节文档见文末[「相关文档」](#相关文档)；本文负责全貌与分工，不复述细节。

## 模块定位

SwiftDeclaration 是**共享声明模型**：`SwiftIndexing` 往里填，`SwiftPrinting` / `SwiftDiffing` / `SwiftSpecialization` / `SwiftAttributeInference` 从里读。索引与打印是平级的，谁也不依赖谁，能这样是因为中间隔着这份模型。

它同时是**降级上报的类型入口**（`SwiftIndexEvents`），虽然事件的分发和落点是宿主的事。

模型的设计张力只有一句：**它要既够用来打印一份完整接口，又不能钉住 Mach-O**。索引完之后宿主可能只想拿着一张类型表做界面，这时候还抱着解析好的胖 wrapper 和整张符号表就说不过去了。

## 文件 → 子系统对照

目录名说什么，里面就只放什么：`Definitions/` 只有声明本体，成员构件与构建期机器各有自己的目录。

| 子系统 | 文件 |
|---|---|
| 1. 声明本体 | `Components/Definitions/`（`Definition` / `MutableDefinition` 协议、`TypeDefinition` 及其七个功能扩展、`ProtocolDefinition`、`ExtensionDefinition` 及各自的 `+Indexing`（`ExtensionDefinition` 另有 `+ThunkAttributes`，与 `TypeDefinition+ThunkAttributes` 共用 `Building/MemberAttributeApplication`）、`FunctionDefinition`、`VariableDefinition`、`SubscriptDefinition`、`FieldDefinition`、`WrappedPropertyDefinition`） |
| 2. 成员构件 | `Components/Members/`（`Accessor`、`OrderedMember`、`MemberCategory`、`StrippedSymbolicRequirement`）——模型的一部分，会出现在公开 API 的返回值里 |
| 3. 构建期机器 | `Components/Building/`（`DefinitionBuilder`、`MemberSymbolBucketing`、`OverrideSymbolMatcher`、`ClassDispatchLookups`、`AnnotatedSymbol`、`WrappedPropertyRecovery`、`MemberAttributeApplication`）——全是 `package`，索引结束就不再有人碰 |
| 4. 名字 | `Components/Names/`（`DefinitionName`、`TypeName`、`ProtocolName`、`ExtensionName`） |
| 5. 种类枚举 | `Components/Kinds/` |
| 6. 挂在声明上的独立概念 | `Components/ExportStatus`、`Components/AssociatedTypeWitnessProjection`、`Components/SwiftAttribute` |
| 7. 对上游类型的扩展 | `Extensions/`（按被扩展的类型分文件：`ProtocolConformance+Names`、`TypeContext+Names`、`FieldRecord+DemangledType`、`Node+TypeKind`……） |
| 8. 事件 | `Events/SwiftIndexEvents` |

### TypeDefinition 的七个扩展

`index(in:)` 串起来的是六件互不相干的事，每件一个文件，主干只剩调用顺序：

| 文件 | 负责 |
|---|---|
| `TypeDefinition.swift` | 存储属性、两个 `init`、`materializedTypeContext(in:)`——不含任何索引逻辑 |
| `+Indexing` | `index(in:)` 主干、字段记录 → `FieldDefinition`、accessor 组回折 |
| `+ClassDispatch` | vtable / override / defaultOverride 三张表 → `ClassDispatchLookups` |
| `+MemberIndexing` | 六类成员与两个 `deinit` 符号 |
| `+FinalRecovery` | 提案 0006 的 `final` 恢复与它的四道门 |
| `+ThunkAttributes` | `@objc` / `@nonobjc` / `@distributed` 的交叉引用 |
| `+SynthesizedMembers` | 自动合成成员的去重 |
| `+WrappedProperties` | property wrapper 用法的恢复 |

**主干里的顺序是有约束的，不能随手调**：`final` 恢复要在 `applyThunkAttributes` 之后（它要 `@objc` 证据）且在 `orderedMembers` 之前（那一步会把成员值复制走）；wrapped property 恢复要在字段回折与成员构建都完成之后。每个步骤方法的 doc comment 各自写明了自己依赖什么。

三个 Definition 的 `isIndexed` setter 是 `internal` 而非 `private`，**只因为索引扩展在另一个文件里**：包内其它 target 仍然改不动它。

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

每个 `TypeDefinition` / `ProtocolDefinition` 带一个四态 `ExportStatus`（`exported` / `notExported` / `imageHasNoExportInformation` / `descriptorSymbolNameUnresolvable`），在构造时从声明自己的描述符符号解析一次，存成 `let`。所以 `SwiftDeclarationIndexer.prepare()` 一返回，整张表就都有值了，宿主可以逐行标注而不必抱着 Mach-O。

`TypeDefinition.wrappedProperties` 是索引在 `index(in:)` 末尾算出的 property wrapper 用法（提案 [draft-interface-hides-compiler-synthesized-members](../../Evolutions/draft-interface-hides-compiler-synthesized-members.md)）：每个存储字段 `_x`，只要它的 nominal 类型有 `wrappedValue` accessor——先查本镜像符号索引（internal wrapper 也算），再经 `SwiftDeclarationRendering.PropertyWrapperTypeCatalog` 查本镜像与依赖闭包各镜像的导出 trie（SwiftUI 的 `@State` 用在 app 里）——就记一条 `WrappedPropertyDefinition`：属性名、`_x` / `$x` 的名字、attribute 类型节点（wrapper 恰一个泛型实参且等于被包装类型时省略实参），以及来源：`x` 自己的 accessor 符号还在就是 `declaredMember`；被 strip 了就 `synthesized(declaredTypeNode:hasSetter:)`，类型由 wrapper 的 `wrappedValue` 类型代入 `_x` 的泛型实参得到。`fields` 与 `variables` 里的 `_x`、`$x` 原样保留——diff / snapshot 的记录来自它们——只有 interface 打印器改按这张表渲染。目录由 `SwiftDeclarationIndexer.prepare()` 用索引配置里的 `dependencySearchPaths` 登记、随索引器一起释放（`PerImageCacheEvictionRegistry` 的 `propertyWrapperCatalog` claim）；没登记过的镜像退化成查系统 cache。

两个「没有结论」的态**作用域不同**，不要混：`imageHasNoExportInformation` 是镜像级的（根本没有 export trie，此时把它读成「未导出」会把一个 `.o` 文件的每个声明都报成未导出）；`descriptorSymbolNameUnresolvable` 是声明级的（trie 没问题，但这一个名字的 remangle 不可信）。

对外投影只有两个：`isExported: Bool?` 和 `isDefinitelyNotExported`——**过滤和标注只能依据后者**。

### 库代码不写进程流

每一处降级——丢掉的声明、跳过的描述符、加载不了的依赖——都作为事件分发出去，落到哪儿由**宿主**决定。`Dispatcher.dispatch` 有个**兜底**：一个 handler 都没挂时它用 `#log` 报出来，而不是丢掉。

> 什么算 failure 由 `Payload.unhandledFailureDescription` 定，那是一个**故意穷举**的 `switch`——新增 failure case 必须显式登记进去，否则它会静默绕过兜底。

Handler 的调用是**进程级串行**的（跨所有 dispatcher 一把递归锁）：`Handler` 没有 `Sendable` 要求，而跨版本准备会让 N 个 task 上的 N 个 dispatcher 共用宿主的同一个 handler。跨 dispatcher 的投递**顺序**仍是先到先得。

> 永远不要用 `FileHandle.standardError/Output.write(_:)`——这个重载在流已关闭或损坏时抛出无法捕获的 ObjC 异常，直接终止宿主。用 `fputs` / `fwrite`。（`write(contentsOf:)` 要 macOS 10.15.4，高于本包 10.15 的下限。）

有两个模块在事件层**之下**、够不到它（`SwiftDeclaration` 依赖 `SwiftDeclarationRendering`，在那里命名事件类型会成环）：`Node+OpaqueType` 收一个注入的报告闭包，`MultiPayloadEnumDescriptorCache` 直接打日志；两者都落到同一个 `#log` 兜底上。

`PrintFailureEventTests.libraryModulesWriteToNoProcessStream` 是一次源码扫描，带一份显式的、**只许缩短**的历史豁免名单。

### `@objc @implementation` 类挂在 extension 上

SE-0436 的类在 `__swift5_*` 里没有身影，模型里它就是那个 `__C.X` 的 `ExtensionDefinition`：`objcImplementation` 装 `SwiftInspection.ObjCImplementationClassFacts`（证据档位、ivar 与 `Wvd` 的 join、方法表），`VariableDefinition.objcImplementationStorage` 标出由访问器符号建出来却是存储属性的成员。这个事实**不进** ABI 快照的容器 key。详见 [ObjCImplementationClassRecognition.md](../ObjCImplementationClassRecognition.md)。

### ObjC 方法表给出的成员事实：`@objc`、`override`、显式 selector

`FunctionDefinition` / `VariableDefinition` / `SubscriptDefinition` 各有一个 `objcMember: ObjCMember?`——这个成员实现的 ObjC 方法：selector、是否类方法、覆写的祖先（可空）、证据档位、selector 是否为源码里 `@objc(name)` 写出的。`isOverride` 与 `isClassMember` 都 OR 上 `objcMember?.isOverride`（覆写的类方法必须打 `class`）；联结上的成员缺 `.objc` 属性就补上（OS 框架 strip 掉了 `To` thunk 符号，方法表是 `@objc` 的唯一证据）；printer 在 `hasExplicitSelector` 时打 `@objc(selector)`。它由 `Building/ObjCMemberApplication` 在 `TypeDefinition.index(in:)`（`applyThunkAttributes` 之后、`recoverFinalMembers` 之前——`final` 还原用 `@objc` 排除 `@objc dynamic`）和 `SwiftDeclarationIndexer.indexExtensions()`（`__C` 类的 extension 与本镜像 Swift 类的 extension）里从 `SwiftThunkAnalysis.ObjCMembers` 的表 join 上来：函数按自己的符号名，属性 / 下标先按 getter 再按任一 accessor 符号，`init` 按 allocator 符号换 initializer 后缀。第三档「只按名字」的覆写推断也在这里做（开关默认关）。这个事实**不进** ABI 快照。详见 [ObjCMemberRecovery.md](../ObjCMemberRecovery.md)。

## 相关文档

- [DeclarationModelMemoryFootprint.md](../DeclarationModelMemoryFootprint.md)——模型内存占用与瘦身。
- [EventBasedDegradationReporting.md](../EventBasedDegradationReporting.md)——事件层设计。
- [SharedNodeStoreMigration.md](../SharedNodeStoreMigration.md)——声明值持有 `NodeReference` 之后的规则。
- [ExtensionContainerUnification.md](../ExtensionContainerUnification.md)——extension 容器归并。
- [PerConformanceAttribution.md](../PerConformanceAttribution.md)——逐 conformance 的归属。
- [ExportedOnlyInterfaceFiltering.md](../ExportedOnlyInterfaceFiltering.md)、[InterfaceHeaderAndExportStatusAnnotations.md](../InterfaceHeaderAndExportStatusAnnotations.md)——导出状态的两种消费方式。
- 演进提案：[0002](../../Evolutions/0002-declaration-model-descriptor-slimming.md) 描述符化瘦身 · [0005](../../Evolutions/0005-event-based-degradation-reporting.md) 事件化上报 · [0023](../../Evolutions/0023-type-import-info-identity.md) C 导入类型的身份 · [0024](../../Evolutions/0024-exported-declaration-flag.md) 导出标志。
