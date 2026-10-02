# 离线泛型特化

提案 [offline-generic-specialization](../Evolutions/draft-offline-generic-specialization.md) 的实现说明：不经 runtime 特化一个从文件读出的泛型类型，并像在线模式一样打印出绑定后的头部、代换后的字段类型和按实参计算的布局注释。给 RuntimeViewer 的离线模式用，本库没有 CLI 入口。

## 一句话

`GenericSpecializer<MachOFile>` 的 `specialize(_:with:)` 把每个实参变成一个类型节点（从不调用目标镜像里的代码），补齐被 same-type 约束钉死的参数，按层分组成 `GenericArgumentBinding`，再按运行时 `_buildDemanglingForContext` 的规则拼出实例化类型名，返回 `StaticSpecializationResult`。`TypeDefinition.specialize(with:in:)` 把它变成特化后的定义（`staticSpecialization` 存 binding），`SwiftDeclarationPrinter<MachOFile>` 打印时：头部用实例化类型名，字段类型按 binding 代换并把关联类型投影成具体类型，布局注释由静态布局引擎按 binding 计算。

```swift
let specializer = GenericSpecializer(indexer: indexer)   // SwiftDeclarationIndexer<MachOFile>
let request = try specializer.makeRequest(for: typeDefinition.typeContextDescriptorWrapper)
let validation = specializer.staticPreflight(selection: selection, for: request)
let result = try specializer.specialize(request, with: selection)
let specializedDefinition = try await typeDefinition.specialize(
    with: result,
    derivingNestedSpecializationsWith: specializer,
    in: machOFile
)
let interface = try await printer.printTypeDefinition(specializedDefinition)
```

## 参数的层号（depth）只数声明了参数的上下文

泛型参数在 mangling 里按 `(depth, index)` 引用（`τ_1_0`，打印成 `A1`），demangler、字段记录、需求签名都用这个坐标。层号只数**声明了参数**的上下文，而 generic context descriptor 只记录一份累计的参数列表，不记录层的边界。从父链推层号有两种形状会推错：

- 本身不声明参数、只因嵌在泛型类型里才算泛型的类型，比如 `Outer<A>.Middle.Inner<B>` 里的 `Middle`。它有 generic context（继承了 `A`），却不开新层：`B` 在第 1 层。
- extension 本身也不声明参数，但它的 generic context 带着被扩展类型的全部参数，可能跨好几层：`extension Outer.SecondMiddle where A == Int` 一个上下文覆盖 `Outer` 的第 0 层和 `SecondMiddle` 的第 1 层，里面声明的 `DeepConstrainedInner<B>` 的 `B` 在第 2 层。

`GenericParameterDepthLayout`（SwiftInspection）给出每层几个参数：类型或 opaque type 上下文增加参数就开一层；extension 增加的参数按被扩展类型（extended context 的 mangling 里每个声明了参数的层各带一个参数列表）拆成几层。拆不开时（读不到、个数对不上）退回「这一级算一层」，不做超出父链的猜测。

此前有五处按「每个泛型祖先一层」计数，全部改用它：

| 位置 | 错数的后果 |
|---|---|
| `GenericSpecializer.buildParameters` | `B` 被命名为 `A2`，按名字收集需求时漏掉 `A1: Hashable`，候选不过滤，运行时特化少算一个 witness table，在 key argument 个数检查处失败 |
| `GenericContext+Dump`（dump 与 interface 的头部） | 未特化的头部打成 `struct Inner<A2> { var innerElement: A1 }`，参数子句和字段对不上（0.21.0 的 CLI 就是这样） |
| `RuntimeMetadataTypeBuilder.bindings` | 进程内把节点还原成 metadata 时 `A1` 找不到实参，带需求的嵌套泛型实例化失败 |
| `AccessorThunkOwnerLayout` | thunk 从参数缓冲区读到的第二个字被标成 `(2, 0)`，是没有字段会引用的坐标 |
| `GenericArgumentEnvironment.make(forInstantiatedTypeNode:)`（SwiftLayout） | 节点遍历在 extension 节点处停下，`Outer<Int>.ConstrainedInner<String>` 只收到最内层的实参，把 `String` 绑到第 0 层，引用它的字段整体降级 |

`TargetGenericContext.depth`（ABI 模型）保留原义——泛型祖先的个数，baseline 仍记录它——只是不再拿它命名参数。`AccessorThunkOwnerLayout(genericContext:)` 留作没有 descriptor 时的形式，改为跳过不增加参数的祖先；extension 跨层的情况只有带 `depthLayout` 的新初始化方法能处理，库内调用点全部改用后者。opaque type 的 descriptor 可能在进程内、本镜像或别的镜像里读出，它的父链必须在读它的那个上下文里遍历，所以 `Node+OpaqueType` 在读出 descriptor 的地方就算好 `AccessorThunkOwnerLayout`（`ReadOpaqueType`）。

## 实参按层绑定：`GenericArgumentBinding`

`argumentsByDepth[depth][index]` 是参数 `(depth, index)` 的实参，`.type` 包装的类型节点。它和实例化类型节点可以互相转换：demangler 只给声明了参数的层包 `boundGeneric*` 节点，所以 `argumentListsByLevel(ofInstantiatedTypeNode:)` 从内到外收集每层的 `TypeList` 再反转，恰好就是按层的实参；遇到 extension 节点时走进它的被扩展类型（外层实参挂在那里）。静态布局引擎的 `GenericArgumentEnvironment` 和层号计算都用这一个遍历。

`substituting(in:)` 是给显示用的代换：和布局引擎的代换不同，它也代换 metatype 里的参数（`A.Type` 显示成 `Swift.Int.Type`）。布局引擎故意不代换 metatype 的实例，因为 metatype 的存储大小由实例的语法形状决定，与实参无关。

## 实例化类型名

`SymbolicDemangler.instantiatedTypeNode(for:binding:in:)` 移植运行时的 `_buildDemanglingForContext`：沿描述符路径从外到内，某个类型上下文的累计参数数超过外层已用掉的数量，就把中间那几个实参挂成这一层的 `boundGeneric*`；不声明参数的类型保持普通节点挂在绑定后的父节点下。实现上给原有的 `buildContextDescriptorMangling` 加了一个可选的 `ContextInstantiation`，私有鉴别符、C 导入类型的身份、匿名上下文和 extension 上下文的处理与未绑定的名字完全相同。

extension 上下文有一处有意与运行时不同。运行时只给被扩展类型的最外一层（`selfType` 的第一个 `TypeList`）换实参：被扩展类型本身是嵌套泛型时，它把全部实参塞进 `SecondMiddle` 的列表、`Outer<A>` 保持未绑定，拼出的名字不对应任何实例化。离线把 binding 代换进被扩展类型，每层都绑定。和运行时一样，绑定后的 extension 节点不带泛型签名。

被 same-type 约束钉死的参数不接受 key argument（`extension Outer where A == Int { struct Inner<B> }` 里的 `A`），request 也不提供它，但它的层照样要绑定、名字里也要写出来。`GenericInstantiation`（SwiftSpecialization）从固定它的约束补上：取约束右侧，代换已知实参，再把具体类型的关联类型投影掉；右侧引用另一个被固定的参数时反复代换直到不再有进展。运行时用 `_gatherWrittenGenericParameters` 做同一件事。

运行时特化的类型名也改用这套构造（`TypeDefinition.makeSpecializedDefinition`）。此前 `boundGenericTypeName` 把所有实参放进最内层：`Outer<Int>.Inner<String>` 被写成 `Outer.Inner<Int, String>`，派生出的 `NestedHost<Int>.Plain` 被写成 `NestedHost.Plain<Int>`。打印出来的头部不受影响（它用 metadata 的运行时名字），但 `typeName` 是 RuntimeViewer 侧边栏的显示名和标识。实参个数与 key 参数对不上时仍退回旧形状。

## 离线执行与约束检查

实参变成类型节点的方式：`.candidate` 取候选的 `TypeName` 节点；`.boundGeneric` 用绑定到候选所在镜像的内层 specializer 递归离线特化，取内层结果的类型名；`.metatype` / `.metadata` / `.specialized` 用本进程运行时给的名字（`RuntimeTypeNameDemangling.node(forMetatype:)`，与在线路径的头部和字段类型同源）。每一层的实参只解析一次，`.boundGeneric` 嵌套的工作量随深度线性增长。

`staticPreflight` 对类型泛型签名里的每条需求（根参数有实参的）检查，分两档：

| 结果 | 情形 |
|---|---|
| 错误 | `AnyObject` 参数给了 struct / enum / tuple（宿主类型按 metadata 的 kind 判断）；索引认识、但不在父类子树里的类（宿主类沿它自己完整的父类链按名字比较）；关联类型的 same-type 约束两侧都解析成具体类型且不相等 |
| 警告 | 索引记录里查不到的协议遵循（可能是条件遵循、别的模块补上的、运行时合成的）；关联类型投影不出来；索引没有该父类的类层级信息；实参类型不在任何被索引的镜像里 |

错误与警告沿用 `SpecializationValidation` 现有的 case（RuntimeViewer 对它们做了穷尽 `switch`）。`specialize` 与在线路径一样：静态校验或约束检查有错误时抛 `specializationFailed`，泛型 `.candidate` 抛 `candidateRequiresNestedSpecialization`。关联类型的需求用访问路径命名（`A.Element`），与 request 的 `AssociatedTypeRequirement.fullPath` 一致。

读文件时，对别的镜像里协议的引用落在 loader 要解析的 bind 上（`Hashable` 是 `$sSHMp`），`resolvedContent` 给出 `.symbol`。`buildRequirement` 原先只认 `.element`，于是离线 request 丢掉了所有跨镜像协议需求：候选不过滤，witness table 也没计数。现在 `.symbol` 按符号名还原协议名。在线路径的 bind 已经解析，不受影响。

## 特化后的定义与打印

`TypeDefinition.staticSpecialization`（SwiftDeclaration）存离线特化的 binding，与运行时特化的 `metadata` 互斥。打印器的三处都在两者之间二选一：

- **头部**：`boundTypeNode(of:)` 给出绑定后的名字——运行时特化取 metadata 的运行时名字，离线特化取定义自己的实例化类型名，两者形状相同，都交给 `BoundDumpedTypeNameRenderer`。
- **字段与 enum payload 的类型**：离线时对字段节点做 binding 代换，再用 `DependentMemberProjection.projectingConcreteMembers` 把具体类型的关联类型投影掉（`Elements.Element?` 在 `Elements == String` 时打成 `Swift.Character?`）；投影走被特化类型所在镜像的依赖闭包，投影不了的保留原样。
- **布局注释**：`FieldLayoutRenderState.genericArgumentBinding` 把 binding 交给 `StaticFieldLayoutBackend`，后者调用 `StaticFieldLayoutProvider` 新增的四个带 binding 的方法（字段布局、payload 布局、逐 case 的 enum 布局、展开的嵌套偏移树）。这四个方法有返回空的默认实现，库外的 provider 不受影响，只是不出注释。

为了让两条路径对同一个实例化给出相同的注释，顺带改了两处既有行为：

- **在线路径给特化后的泛型 enum 出 Enum Layout 注释**。`RuntimeFieldLayoutBackend` 原先对任何泛型 enum 都不算布局；现在定义带着特化 metadata 时，payload 类型经 metadata 代换后解析，enum 自身的 value witness table 从进程内读，仍用它的 size 交叉校验。未特化的泛型 enum 照旧没有这项注释。
- **静态的展开偏移树投影具体类型的关联类型**。`ElementsHolder<[Int]>` 的 `first` 原先显示为 `Swift.Optional<Swift.Array<Swift.Int>.Element>` 并在那里停下，运行时的遍历显示 `Swift.Optional<Swift.Int>` 并继续展开；现在静态遍历也先投影（`ImageUniverse.projectingConcreteMembers`）再命名和展开。这对未特化类型里出现的实例化字段同样生效。

## 验证

`GenericSpecializationFixture`（MachOTestingSupport）现场编译一个 dylib，同一个文件按 `MachOFile` 读（离线）、`dlopen` 后按 `MachOImage` 读（在线）。`OfflineSpecializationParityTests` 对 struct、final class、泛型父类的 class、单 payload 与多 payload 泛型 enum、关联类型字段、非声明层下的嵌套泛型、派生的嵌套类型、自带参数的嵌套泛型、私有类型和 `.boundGeneric` 实参，两条路径分别特化、打开全部布局注释后打印，要求逐字节相同。

有三处两条路径按设计就不同，未特化的类型也一样，对照的形状避开了它们：

- 空 case 存在 payload 的 extra inhabitant 里的单 payload enum：只有运行时能经 value witness 投影出确切字节，静态路径标注 not resolved。
- tuple 类型的字段：运行时的 Type Layout 注释逐元素展开。
- `Array` 这类泛型标准库 struct 的字段：运行时的展开遍历在第一个以该 struct 自身参数为类型的嵌套字段处停下（`_buffer: _ArrayBuffer<Element>`），静态遍历会继续往下。

另有：`InstantiatedTypeNameTests` 把离线的实例化类型名与运行时名字按结构比较（含私有类型、约束 extension 里的类型、跨模块 extension 里的类型），`OfflineSpecializationTests` 覆盖 request、结果与约束检查每一档的正反例，`BoundInstantiationLayoutTests` 把带 binding 的字段偏移与运行时 metadata 的 field offset vector 比较。层号的五处修复各有修复前失败的回归测试（`GenericParameterDepthNamingTests`、`GenericParameterDepthDumpTests`、`CanonicalParameterDepthTests`、`AccessorThunkOwnerLayoutDepthTests`、`RuntimeMetadataTypeBuilderTests.nestedGenericBehindNonDeclaringLevelResolvesItsRequirement`、`ExtensionContextInstantiationLayoutTests`）。

真实系统框架上（渲染 A/B，明细在提案的「验证」一节），未特化输出的变化只有三类，都是修正：

- 嵌在不声明参数的中间层下的泛型类型，头部参数名与它自己的 `where` 子句对上了：Combine 的 `Optional<A>.Publisher.Inner<A1>`、`Result<A, B>.Publisher.Inner<A1>`，SwiftUICore 的 `TimeDataSource<A>.Resolver.ResolvedOffsetBox<A1>`，原先都打成 `<A2>`。macOS 15.5 到 27.0 的 cache、iOS 15.5 到 26.5 的模拟器文件、进程内镜像，三条 reader 路径都一样。
- 展开偏移树里，具体类型的关联类型投影成它的 witness 再命名，并继续往下展开：`Angle.Animatable.AnimatableData` 显示为 `Swift.Double`，`ViewFrame.Animatable.AnimatableData` 展开成 `AnimatablePair<AnimatablePair<CGFloat, CGFloat>, …>` 的各层字段，`SubviewsCollection.Collection.Index` 显示为 `Swift.Int` 并展开出 `_value`。
- 约束 extension 里声明的类型，其实例化作字段时实参能代换进去了：`MeasurementView<A, B>` 的字段 `Measurement<B>.FormatStyle` 展开出的子字段原先印成 `Measurement<A>`（读起来像 `MeasurementView` 的第一个参数），现在是 `Measurement<B>`。

## 已知限制与顺带发现

- **实参所在镜像要在依赖闭包里**。离线布局与关联类型投影都走被特化类型所在镜像的依赖闭包；RuntimeViewer 让用户从别的、互不依赖的镜像里挑候选时，相关字段降级为 unknown、关联类型保持未投影。这是如实降级。
- **宿主类型的协议遵循查不到**。`.metatype` 给的宿主类型不在任何被索引的镜像里，它的协议遵循只能报警告。
- **class 头部的父类不代换**：`class Sub<Swift.Int>: Base<A>`，在线路径也是这样。
- **特化后的定义不打印成员**：成员按绑定后的名字查符号查不到，两条路径一致。调用方不传 `typeArgumentNodes` 时，在线路径的定义保持未绑定的名字，会查到并打印未代换的成员（`init(first: A, …)`），这是既有行为。
- **未修的旧问题**：引用「嵌套泛型类型的约束 extension 里声明的类型」的字段（`Outer<Int>.SecondMiddle<Bool>.DeepConstrainedInner<String>`）demangle 失败（`unexpected(at: 11)`），引用它的整个类型从 interface 里消失；引用约束 extension 里类型的类型，其 memberwise `init` 后面会多出一个 `where A == Swift.Int`。两者都与本提案无关，记录在提案里。
