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
| 1. 声明本体 | `Components/Definitions/`（`Definition` / `MutableDefinition` 协议、`TypeDefinition` 及其七个功能扩展、`ProtocolDefinition`、`ObjCProtocolDefinition`、`ExtensionDefinition` 及各自的 `+Indexing`（`ExtensionDefinition` 另有 `+ThunkAttributes`，与 `TypeDefinition+ThunkAttributes` 共用 `Building/MemberAttributeApplication`）、`FunctionDefinition`、`VariableDefinition`、`SubscriptDefinition`、`FieldDefinition`、`WrappedPropertyDefinition`、`ObjCCategoryConformance`） |
| 2. 成员构件 | `Components/Members/`（`Accessor`、`OrderedMember`、`MemberCategory`、`StrippedSymbolicRequirement`）——模型的一部分，会出现在公开 API 的返回值里 |
| 3. 构建期机器 | `Components/Building/`（`DefinitionBuilder`、`MemberSymbolBucketing`、`OverrideSymbolMatcher`、`ClassDispatchLookups`、`StandInMemberSymbols`、`AnnotatedSymbol`、`WrappedPropertyRecovery`、`MemberAttributeApplication`）——全是 `package`，索引结束就不再有人碰 |
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
| `+ClassDispatch` | vtable / override / defaultOverride 三张表 → `ClassDispatchLookups`；另为本类每个 `Tq` 能命名的 vtable 槽造一个替身成员符号 |
| `+MemberIndexing` | 六类成员与两个 `deinit` 符号；实现符号缺席的 vtable 成员用替身补上 |
| `+FinalRecovery` | 提案 0006 的 `final` 恢复与它的四道门 |
| `+ThunkAttributes` | `@objc` / `@nonobjc` / `@distributed` 的交叉引用 |
| `+SynthesizedMembers` | 自动合成成员的去重 |
| `+WrappedProperties` | property wrapper 用法的恢复 |

**主干里的顺序是有约束的，不能随手调**：`final` 恢复要在 `applyThunkAttributes` 之后（它要 `@objc` 证据）且在 `orderedMembers` 之前（那一步会把成员值复制走）；wrapped property 恢复要在字段回折与成员构建都完成之后。每个步骤方法的 doc comment 各自写明了自己依赖什么。

### 每个定义只索引一次，可以被并发打印

三个 Definition 的 `index(in:)` 是**同步**函数，都经 `DefinitionIndexing.swift` 执行（提案 [0066-concurrent-definition-printing](../../Evolutions/0066-concurrent-definition-printing.md)）。进程级一把锁守着两样东西：一张「正在索引」的表（按 `ObjectIdentifier(定义)`），和每个定义自己的 `hasCompletedIndexing`。首个调用者认领后在自己的线程上跑完索引体；同时到来的调用者在认领者的 promise（复用 `SharedCacheBuildPromise`，载荷是 `Result`）上阻塞等待，拿到同一个结果。索引体抛错时定义回到未索引、错误交给全部等待者，下次调用重试。`isIndexed` 是只读的计算属性，读的就是锁下的那个标志。

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

每个 `TypeDefinition` / `ProtocolDefinition` 带一个 `ExportStatus`（`exported` / `notExported` / `imageHasNoExportInformation` / `descriptorSymbolNameUnresolvable` / `declarationIsCImported`），在构造时从声明自己的描述符解析一次，存成 `let`。描述符属于 `__C` 或 `__C_Synthesized` 模块时直接是 `declarationIsCImported`，不查 trie：编译器给 Clang 声明的是非唯一链接，每个用到这个 C 类型的模块各自生成一份描述符、谁都不导出，它说明不了类型能不能被外部使用，而本镜像给它写的扩展可以是公开 API（提案 [0083-exported-only-marking-mode](../../Evolutions/0083-exported-only-marking-mode.md)）。`ObjCProtocolDefinition` 的永远是 `declarationHasNoSymbol`：Swift 声明的 `@objc` 协议没有描述符，也没有任何自己的符号。所以 `SwiftDeclarationIndexer.prepare()` 一返回，整张表就都有值了，宿主可以逐行标注而不必抱着 Mach-O。

`TypeDefinition.wrappedProperties` 是索引在 `index(in:)` 末尾算出的 property wrapper 用法（提案 [0041-interface-hides-compiler-synthesized-members](../../Evolutions/0041-interface-hides-compiler-synthesized-members.md)）：每个存储字段 `_x`，只要它的 nominal 类型有 `wrappedValue` accessor——先查本镜像符号索引（internal wrapper 也算），再经 `SwiftDeclarationRendering.PropertyWrapperTypeCatalog` 查本镜像与依赖闭包各镜像的导出 trie（SwiftUI 的 `@State` 用在 app 里）——就记一条 `WrappedPropertyDefinition`：属性名、`_x` / `$x` 的名字、attribute 类型节点（wrapper 恰一个泛型实参且等于被包装类型时省略实参），以及来源：`x` 自己的 accessor 符号还在就是 `declaredMember`；被 strip 了就 `synthesized(declaredTypeNode:hasSetter:)`，类型由 wrapper 的 `wrappedValue` 类型代入 `_x` 的泛型实参得到。`fields` 与 `variables` 里的 `_x`、`$x` 原样保留——diff / snapshot 的记录来自它们——只有 interface 打印器改按这张表渲染。目录由 `SwiftDeclarationIndexer.prepare()` 用索引配置里的 `dependencySearchPaths` 登记、随索引器一起释放（`PerImageCacheEvictionRegistry` 的 `propertyWrapperCatalog` claim）；没登记过的镜像退化成查系统 cache。

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

SE-0436 的类在 `__swift5_*` 里没有身影，模型里它就是那个 `__C.X` 的 `ExtensionDefinition`：`objcImplementation` 装 `SwiftInspection.ObjCImplementationClassFacts`（证据档位、ivar 与 `Wvd` 的 join、方法表），`VariableDefinition.objcImplementationStorage` 标出由访问器符号建出来却是存储属性的成员。这个事实**不进** ABI 快照的容器 key。详见 [ObjCImplementationClassRecognition.md](../ObjCImplementationClassRecognition.md)。

### 成员从符号建，vtable 槽补上缺席的那些

成员定义是符号驱动的：`FunctionDefinition.symbol`、`Accessor.symbol` 都不是可选值，`DefinitionBuilder` 的每个构造点都从一个 `DemangledSymbol` 出发。class 的 vtable 成员是例外来源：library evolution 模块只导出 public class 方法的 `Tj` / `Tq`，实现符号是 local 的，镜像的 local 符号被剥掉之后（系统 dyld shared cache 里的 AppKit、`strip -x` 过的二进制）这些成员没有符号可建。`classDispatchLookups` 为本类每个 `Tq` 能命名、实现指针非 null 的槽造一个替身符号——名字是 `Tq` 名去掉后缀（实现函数本来的 mangled 名），偏移是实现偏移（async 方法再跳到函数入口）——`indexMembers` 经 `ClassDispatchLookups.supplementing(_:in:)` 只补真实符号没有声明的成员。替身按实现符号的样子造，所以导出判定、ObjC 方法表 join、ABI 身份都不用分支。ABI 墓碑、modify / read 协程、override 槽不补。打印时 class 的 vtable 成员（有槽号的成员）按槽号排在最前（`OrderedMember.vtableOrdered`）。详见 [DescriptorOnlyVTableMembers.md](../DescriptorOnlyVTableMembers.md)。

优化构建是另一个例外来源：整模块优化会把 internal 成员的实现符号删掉，只留下同一个成员的另一个入口——`@objc` 成员只剩它的 ObjC thunk（`$s…To`，函数体内联在里面），class 的 initializer 只剩 initializing entry point（`…fc`，allocating entry point 内联进了调用方）。`StandInMemberSymbols` 从这两种入口造替身，规则与 `Tq` 替身相同：名字与成员树照实现符号的样子（thunk 去掉 `To` 与 `objCAttribute`，initializing entry point 把 `constructor` 改写成 `allocator`、`fc` 换成 `fC`），偏移是镜像里留下的那个入口。类成员经 `StandInMemberSymbols.TypeMembers`，extension 成员经 `supplementingExtensionMembers`，都排在真实符号与 `Tq` 替身之后，只补没人声明的成员；去重键 `declaredEntityKey(of:)` 三种替身共用。详见 [ThunkOnlyObjCMembers.md](../ThunkOnlyObjCMembers.md)。

### ObjC 方法表给出的成员事实：`@objc`、`override`、显式 selector

`FunctionDefinition` / `VariableDefinition` / `SubscriptDefinition` 各有一个 `objcMember: ObjCMember?`——这个成员实现的 ObjC 方法：selector、是否类方法、覆写的祖先（可空）、证据档位、selector 是否为源码里 `@objc(name)` 写出的。`isOverride` 与 `isClassMember` 都 OR 上 `objcMember?.isOverride`（覆写的类方法必须打 `class`）；联结上的成员缺 `.objc` 属性就补上（OS 框架 strip 掉了 `To` thunk 符号，方法表是 `@objc` 的唯一证据）；printer 在 `hasExplicitSelector` 时打 `@objc(selector)`。表联结不上的覆写方法**始终**按名字归属一次（第三档），结果照样写进 `objcMember`（`evidence == .selectorName`）——但**不写 `attributes`**，因为紧跟其后的 `final` 还原会把 `@objc` 读成 `@objc dynamic` 的证据，那是消费者还没下的裁决。用不用这一档由消费者决定：`resolvedObjCMemberFacts(trustingSelectorNameEvidence:)`（`ResolvedObjCMemberFacts.swift`）按裁决一次性给出 `attributes` / `isOverride` / `isClassMember` / `isFinal`，printer 传 `SwiftDeclarationPrintConfiguration.infersObjCOverridesFromSelectorNames`。定义自己的 `isOverride` / `isClassMember` 只认前两档（`ObjCMember.isJoinedOverride`）。它由 `Building/ObjCMemberApplication` 在 `TypeDefinition.index(in:)`（`applyThunkAttributes` 之后、`recoverFinalMembers` 之前——`final` 还原用 `@objc` 排除 `@objc dynamic`）和 `SwiftDeclarationIndexer.indexExtensions()`（`__C` 类的 extension 与本镜像 Swift 类的 extension）里从 `SwiftThunkAnalysis.ObjCMembers` 的表 join 上来：函数按自己的符号名，属性 / 下标先按 getter 再按任一 accessor 符号，`init` 按 allocator 符号换 initializer 后缀。第三档「只按名字」的覆写推断也在这里做。这个事实**不进** ABI 快照。详见 [ObjCMemberRecovery.md](../ObjCMemberRecovery.md)。

### Swift 声明的 `@objc` 协议与类对 ObjC 协议的遵循

这种协议没有 protocol descriptor，所以不是 `ProtocolDefinition`（把它的 `protocolDescriptor` 改成可选会破坏下游），而是独立的 `ObjCProtocolDefinition`：名字是 `Type > Protocol`，与 Swift 协议同形，本镜像对它的 `extension` 因此落进它的 `defaultImplementationExtensions`；`index(in:)` 读出继承的协议与要求（`ObjCProtocolRequirementDefinition`：selector、setter selector、实例还是类、required 还是 optional、类型编码、声明的 node、签名来源）。签名来源是 `.selector`（按 importer 规则推出名字，打印时钉住 selector）或 `.conformer(className:)`（实现它的类的成员，声明的上下文已换成协议）。索引期只读成员表，不索引实现者的 `TypeDefinition`。

类对 ObjC 协议的遵循没有 conformance record：`TypeDefinition.objcProtocolNames` 是类的 `class_ro_t` 列的协议（同模块 extension 写的也在里面），在 `index(in:)` 里读；extension 别的模块的类时的 category 遵循是 indexer 的 `objcCategoryConformances`（`ObjCCategoryConformance`）。两者都去掉了某个 Swift 遵循隐含的 ObjC 协议。这些事实都**不进** ABI 快照。详见 [SwiftDeclaredObjCProtocols.md](../SwiftDeclaredObjCProtocols.md)。

### 访问器种类与关联类型的抑制（Swift 6.4）

`AccessorKind` 除 get / set / read / modify 外还有 SE-0507 的 `borrowAccessor` / `mutateAccessor`（符号后缀 `vb` / `vz`）。只声明了这两种访问器的属性、下标与协议要求没有 getter 符号，`DefinitionBuilder` 因此把 getter 与 `borrow` 都当作「读访问器」来选声明节点；打印出的访问器块由 `hasBorrowAccessor` / `hasMutateAccessor` 决定（`{ borrow mutate }`），旁边编译器为满足协议合成的 getter / setter 不盖掉它们。`yielding borrow` / `yielding mutate`（SE-0474）还没有接。

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
