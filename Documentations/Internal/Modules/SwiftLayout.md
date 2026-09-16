# SwiftLayout 模块

> 模块参考文档（module reference），随代码维护。读者：维护者。
> 细节文档见文末[「相关文档」](#相关文档)；本文负责全貌与分工，不复述细节。

## 模块定位

SwiftLayout 是**静态聚合布局引擎**：不加载进程、不调用 metadata accessor，直接从 Mach-O 文件算出 struct / class 的存储属性偏移与类型的整体布局（size / stride / alignment / extra inhabitants / bitwise-takable）。它是离线 ABI 分析路径的底座——`swift-section dump` 和 `interface` 在读文件（而非进程内镜像）时，字段偏移注释、type layout 注释、enum layout 注释全部由它算出来。

它在模块图里是 `SwiftInspection` + `MachOSwiftSection` 的**平级消费者**（另加 `MachOObjCSection` 用于取 Objective-C 祖先类的实例尺寸），上游是 `SwiftDeclarationRendering` 的 `FieldLayoutRenderer`。同一个 renderer 按 reader 分叉：`MachOImage` 路径读进程内活 metadata，`MachOFile` 路径走本模块静态计算，两条腿产出同一套注释。

**能力边界一句话**：凡是二进制里带着的事实，它都能算；凡是需要泛型实参而二进制没记的，它诚实降级成 `FieldResolution.unknown(<原因>)`，绝不编一个看起来合理的偏移出来。

## 文件 → 子系统对照

| 子系统 | 文件 |
|---|---|
| 1. 入口与递归求解 | `StaticLayoutCalculator`、`StaticTypeLayoutResolver`、`StaticTypeLayout`、`AggregateFieldLayout`、`LayoutResolutionError` |
| 2. 基础布局累加 | `BasicLayout` |
| 3. 已知布局表 | `KnownLayoutTable`、`BuiltinTypeLayoutIndex` |
| 4. 各类型形态的桥接 | `EnumLayoutBridge`、`ExistentialLayoutBridge`、`DependentMemberTypeBridge` |
| 5. 泛型实参环境 | `GenericArgumentEnvironment`、`ClassBoundGenericParameterAnalysis` |
| 6. Objective-C 互操作 | `ObjCClassIndex`、`ObjCProtocolIndex` |
| 7. 镜像查找面 | `ImageUniverse`、`ImageReference`、`ImageUniverse+DependencyClosure` |
| 8. 命名与嵌套展开 | `NodeTypeNaming`、`NestedFieldOffsetTree` |

## 子系统速览

### 1 / 2：入口与累加

`StaticLayoutCalculator` 是唯一入口，三个层次的请求共用一条按字段推进的路径（`accumulateFieldLayout`，环境默认 `.empty`）：非泛型描述符（`fieldLayout(of:)`）、给定实参的泛型实例化（`fieldLayout(of:genericArguments:)`）、二进制里的 bound generic mangled 引用（`fieldLayout(forInstantiationMangledName:)`）。每个字段独立降级，一个字段解不出来不会毁掉整个类型。

`StaticTypeLayoutResolver` 是「mangled name → `StaticTypeLayout`」的递归求解器，按 `Node.Kind` 分派、带记忆化和环路保护；类引用到一个指针为止，不再往下展开。

`StaticTypeLayout` 除 size / stride / alignment / extra inhabitant 数 / bitwise-takable 之外，还带两个 value witness 事实：**bitwise-borrowable**（能否按位借用；只有 `@_rawLayout` 类型及含它的聚合为否，其余等同 takable）与 **addressable-for-dependencies**（值的地址是否是生命周期依赖的一部分；`Builtin.FixedArray` 恒为是，聚合从任一字段继承）。聚合的折叠规则照运行时：borrowable 取 AND，addressable 取 OR，enum 的 payload 同理。两者目前只服务一个消费者——`Builtin.Borrow<T>`（Swift 6.4，`Swift.Ref` / `MutableRef` 的唯一存储字段，mangling `BW`）的布局：移植 `stdlib/public/runtime/Borrow.cpp` 的 `swift_getBorrowRepresentation`，referent 超过 4 个指针宽、或 addressable-for-dependencies、或不可按位借用时退化为一个 `Builtin.RawPointer`（8 字节、XI 1），否则与 referent 同 size / stride / alignment / XI；borrow 自身恒可按位 take 与 borrow、不 addressable。本机没有 6.4 运行时可对账，`BorrowLayoutTests` 用规则算出的字面值断言。提案：[draft-builtin-borrow-support](../../Evolutions/draft-builtin-borrow-support.md)。

`@_rawLayout(like: T)` 结构体没有存储属性，Swift 6.4 起编译器在它的字段描述符里多发一条**人造记录**（flag `isArtificial`，名字 `_rawLayout`，类型 = like 类型），专门让离线工具能算出大小。引擎把这条记录当作「like 类型的 size / stride / alignment，但 **0 个 extra inhabitant**、不可按位借用、addressable-for-dependencies」折进聚合（`StaticTypeLayoutResolver.rawLayoutStorage`）——raw storage 是不透明的，`Optional<_Cell<UnsafePointer<Int>>>` 因此是 9 字节而不是 8，与运行时一致（上游 RemoteInspection 在 6.4 修的正是这一处）。`movesAsLike` 二进制里没有记录，bitwise-takable 沿用 like 类型，只影响 flag 不影响偏移。6.4 之前编译的二进制没有这条记录，这类类型仍会被算成空结构体——那是二进制里确实没有事实，不是引擎能补的。提案：[draft-raw-layout-artificial-field-handling](../../Evolutions/draft-raw-layout-artificial-field-handling.md)。

`@_rawLayout` 是任何模块都能开的实验特性，另外两种写法走的不是人造记录：`size:alignment:` 与非泛型的 `likeArrayOf:count:` 只留下 `__swift5_builtin` 描述符（IRGen 对 `@_alignment` / `@_rawLayout` 类型一律发的不透明尺寸记录），`structureLayout` 对非实例化的 `.structure` 节点本来就先查 `BuiltinTypeLayoutIndex`，所以这两种写法的大小、对齐与 0 个 extra inhabitant 都正确（`RawLayoutBuiltinDescriptorLayoutTests` 用现场编译的模块钉住）。**泛型的 `likeArrayOf:count:` 什么都不留**，引擎会把它算成 0 字节、后续字段偏移随之出错，且与空泛型 struct 无法区分——这是上游只给标量 `like:` 发人造记录留下的缺口，目前只能记录。另一个要知道的事实：运行时实例化泛型 raw layout 元数据时（`swift_initRawStructMetadata` / `…2`）照抄 like 类型的 extra inhabitant 数，与编译期布局（0 个）和 6.4 的 RemoteInspection 不一致；引擎对齐的是编译期布局，那才决定字段偏移。部署目标低于 27 时非拷贝字段类型藏在 accessor thunk 后面、引擎算不出的缺口见 [draft-static-layout-through-accessor-thunks](../../Evolutions/draft-static-layout-through-accessor-thunks.md)。

`BasicLayout` 是运行时 `performBasicLayout` 的离线移植。它同时负责值聚合的 **extra inhabitant 数 = 各字段取最大**（`swift_initStructMetadata` 的规则），这条曾经缺失，导致任何以「带 extra inhabitant 的 struct」为 payload 的 single-payload enum 被算大一个字节，并沿着后续字段一路串错。

### 3：已知布局表与 builtin 段

`KnownLayoutTable` 是标准库类型的冻结布局，`BuiltinTypeLayoutIndex` 读镜像的 `__swift5_builtin` 段——编译器为「反射推不出结构的类型」内嵌的整体布局，也就是**导入的 C 值类型**和**多 payload 枚举**。解析器在走自己的结构化 struct / enum 路径之前先查它。

顶层入口还会拿 foreign（C 导入）struct 描述符跟 builtin 记录**交叉校验**：Swift 的 field record 看不见 C 的位域和填充，一旦两边不一致，以 builtin 的整体事实为准，并把每个字段降级为 `.unknown(.foreignTypeFieldOffsetsUnavailable)`——宁可说不知道，也不报一串自信的错偏移。有一种不一致形态已被证明安全（issue #116）：当每个结构化字段都正好落在前序字段尺寸之和、且该和等于 builtin 的整体尺寸时，两种布局都没有藏填充的余地，逐字段偏移可信。

**精度这件事上，leaf 的 extra inhabitant 数是最容易出错、后果最隐蔽的一环**：托管指针族饱和到 `0x7FFF_FFFF`，unsafe pointer 族只保留 null（XI 1），`weak` 引用字 XI 0 且非 bitwise-takable，`unowned`（safe）引用字恰好 XI 1。这些值都逐条对着活的 value witness table 和 IRGen / runtime 源码核过，`WholeTypeLayoutVsRuntimeTests` 对每个 fixture 类型断言完整的五元组。数值本身与推导见 [StaticLayoutEngine.md](../StaticLayoutEngine.md)。

### 4：三个桥接

- `EnumLayoutBridge`——无 payload 与单 payload 走运行时 `getEnumTagCounts` 公式；多 payload 优先查 builtin 整体记录，缺记录时复用 `SwiftInspection.EnumLayoutCalculator` 结构化算。泛型多 payload 枚举按**编译器自己的记录**分流：实参无关的那类（builtin + `__swift5_mpenum` 记录齐全）走 spare bits，实参相关的那类走运行时的 tagged 公式。
- `ExistentialLayoutBridge`——existential 容器与 existential metatype，从运行时反射 lowering 移植。类约束性逐协议判定；Swift 声明的 `@objc` 协议不发 Swift protocol descriptor，靠 `__objc_protolist` 兜底。
- `DependentMemberTypeBridge`——具体实例化后仍留下的关联类型字段（`C.Index`），查 `__swift5_assocty` witness 再把 base 自己的实参代进去。

### 5：没有实参也能算的那部分

`GenericArgumentEnvironment` 做具体 bound generic 的字段代换，**实参按 nominal parent 链逐层收集**，所以特化父类型的嵌套类型（`Environment<Bool>.Content` 这种自身没有实参列表的节点）也能绑上父层的实参。代换是手写的自顶向下递归，不是 `Node.Rewriter` 的自底向上——pack expansion 是上下文相关的。

`ClassBoundGenericParameterAnalysis` 是另一条前线：**完全不给实参**时，从 requirement signature 里挖出签名本身就钉死的事实——类约束参数（必是一个对象引用）与具体 same-type 约束（`Value == Date`，来自受约束的 extension）。加上「参数的 metatype 字段恒为 thick」这条，泛型类型在无特化的情况下也能解出可观比例的字段。

### 6 / 7：ObjC 祖先与镜像查找

`ObjCClassIndex` 读 `class_ro_t.instanceSize`（Swift 子类第一个字段的起点），并索引每个静态发出的 Swift 类自己的 `instanceStart`——实际祖先变大时这个值会被 ObjC runtime 滑移（objc4 的 `moveIvars`），dyld cache 里的镜像带的已是滑移后的终值。是否在 classlist 里决定走哪套规则。

`ImageUniverse` 是五个解析 seam 的统一查找面（类型、协议类约束、ObjC 类实例尺寸、assocty witness、ObjC 协议声明），可以是单镜像，也可以是**依赖闭包**——根镜像急切索引，依赖按解析顺序**惰性**折进来，所以几百个镜像的系统闭包不会被急切 demangle 一遍。闭包本身由 `MachODependencies` 提供，本模块只是薄封装。

## 关键契约

- **降级是产品的一部分，不是失败**。`FieldResolution.unknown(<原因>)` 带着可判读的原因枚举，渲染层会把它印成 `Field offset: unknown (<reason>)`。新增一种解不出来的情形时，加原因枚举，不要让它退化成静默的 0 或跳过。
- **实参永远赢过推断**。签名挖出来的 same-type 约束、类约束参数都只是无实参时的兜底；一旦有真实实参，用实参。
- **官方离线实现不是标准答案**。RemoteInspection 的 `TypeLowering.cpp` 在几处比本模块保守或直接错（spare bits 的 XI 不结构化推导、`unowned` 的 XI 声称继承引用的计数、packs 直接拒绝）。跟运行时对不上时以**活的 value witness table** 为准，不是以那份 C++ 为准。
- **跨模块偏移按「这一次具体部署」算**。resilient 类的字段偏移是拿依赖的那个实际二进制算出来的，不是抽象的 ABI 契约。

## 相关文档

- [StaticLayoutEngine.md](../StaticLayoutEngine.md)——引擎主文档：各阶段的推导、精确数值、逐条与运行时对照的审计记录。
- [StaticLayoutDependencyClosure.md](../StaticLayoutDependencyClosure.md)——依赖闭包在布局解析里的用法。
- [StaticFieldOffsetComputation.md](../StaticFieldOffsetComputation.md)——静态字段偏移的最初设计。
- [GenericArgumentSubstitution.md](../GenericArgumentSubstitution.md)——泛型实参代换。
- [NestedFieldOffsetCycleGuard.md](../NestedFieldOffsetCycleGuard.md)——嵌套展开的环路保护。
- [EnumLayoutAuditFixes.md](../EnumLayoutAuditFixes.md)——枚举布局逐行审计（`SwiftInspection` 侧，本模块复用其计算器）。
- [FieldLayoutRendererReaderSpecialization.md](../FieldLayoutRendererReaderSpecialization.md)——渲染层如何按 reader 分叉消费本模块。
- [Modules/MachODependencies.md](MachODependencies.md)——依赖闭包本体。
