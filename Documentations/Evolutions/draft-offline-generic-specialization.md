# Draft - 离线泛型特化：不经 runtime 特化泛型类型并完整打印

- **状态**: In Progress
- **创建日期**: 2026-09-30
- **最后更新**: 2026-10-02
- **所属愿景**: 无
- **关联文档**: [StaticLayoutEngine.md](../Internal/StaticLayoutEngine.md)「后续工作」里的「用户手动特化前端」一条；[SpecializedInterfaceBoundRenderingRestoration.md](../Internal/SpecializedInterfaceBoundRenderingRestoration.md)（运行时特化的打印机制）；RuntimeViewer 的 [0003-generic-type-specialization](https://github.com/MxIris-Reverse-Engineering/RuntimeViewer/blob/main/Documentations/Evolutions/0003-generic-type-specialization.md)（消费方的 UI 流程）
- **实现分支 / PR**: `feature/offline-generic-specialization`，叠在 `feature/runtime-viewer/find-navigator` 之上，须在它之后合入（见决策日志 2026-10-02）
- **配套文档**: [OfflineGenericSpecialization.md](../Internal/OfflineGenericSpecialization.md)（实现说明）

## 摘要

`GenericSpecializer` 的执行步骤 `specialize` 只能在 `MachO == MachOImage` 时调用：它要调用镜像里的 metadata accessor，镜像必须加载在当前进程里。RuntimeViewer 将来的离线模式读的是磁盘上的 `MachOFile`，现在完全不能特化。离线所需的计算其实大半已经在库里了：静态布局引擎能按给定的实参算出 `Box<Int>` 的字段偏移与整体布局（`StaticLayoutCalculator.fieldLayout(of:genericArguments:)`，只是一直没有调用方），`__swift5_assocty` 的 witness 投影也已经存在。本提案补上缺的部分，让 RuntimeViewer 离线模式能走和在线模式同样的「request → selection → specialize → 打印」流程。具体是四件事：`GenericSpecializer` 在 `MachOFile` 上的离线执行与离线约束检查；特化后的 `TypeDefinition`；让 interface 打印器离线也能打出绑定后的头部、代换后的字段类型和按实参计算的布局注释；以及静态布局引擎接受任意层数的实参。本库自己不提供入口（没有 CLI 选项）。

## 方案

### 调用形态（RuntimeViewer 离线模式）

与在线模式一一对应，只是 `MachO` 换成 `MachOFile`、结果类型换成离线的那一个：

```swift
let specializer = GenericSpecializer(indexer: indexer)   // SwiftDeclarationIndexer<MachOFile>
let request = try specializer.makeRequest(for: typeDefinition.typeContextDescriptorWrapper)
// 用户为每个参数选 .candidate / .boundGeneric
let validation = specializer.staticPreflight(selection: selection, for: request)
let result = try specializer.specialize(request, with: selection)   // StaticSpecializationResult
let specializedDefinition = try await typeDefinition.specialize(
    with: result,
    derivingNestedSpecializationsWith: specializer,
    in: machOFile
)
let interface = try await printer.printTypeDefinition(specializedDefinition)   // SwiftDeclarationPrinter<MachOFile>
```

`makeRequest` 与 `validate` 本来就对任意 `MachO` 可用，不动。

### 改动清单

按实际落地的形状记录；设计细节见实现说明 [OfflineGenericSpecialization.md](../Internal/OfflineGenericSpecialization.md)。

- **SwiftInspection**：
  - 新增 `GenericParameterDepthLayout`：一个 generic context 的参数每层几个。层号只数声明了参数的上下文——本身不声明参数的嵌套类型不开层，extension 按被扩展类型拆成几层。见下文「层号错数整类修复」。
  - 新增公开的 `GenericArgumentBinding`：按层分组的实参（`argumentsByDepth: [[Node]]`），只做显示用的代换（metatype 里也换），以及从实例化类型节点读回 binding 的遍历（`argumentListsByLevel(ofInstantiatedTypeNode:)`，会走进 extension 节点的被扩展类型）。
  - `SymbolicDemangler.instantiatedTypeNode(for:binding:in:)`：移植运行时 `_buildDemanglingForContext`，给原有的 `buildContextDescriptorMangling` 加一个可选的 `ContextInstantiation`，名字的其余部分与未绑定的名字同源。extension 层把实参代换进被扩展类型；被扩展类型本身是嵌套泛型时运行时拼出的名字是畸形的（全部实参塞进最内层），离线按层绑定，这是有意的不同。
- **SwiftSpecialization**：
  - `GenericSpecializer+StaticSpecialization.swift`：`where MachO == MachOFile` 扩展的 `specialize(_:with:)`（返回 `StaticSpecializationResult`）与 `staticPreflight(selection:for:)`。实参取节点的方式、约束检查的两档见下文。
  - `GenericInstantiation`：从 key 实参补齐被 same-type 约束钉死的参数（约束右侧代换已知实参、投影关联类型，反复直到没有进展），按层分组，拼实例化类型名。离线结果和在线特化的类型名都用它。
  - `StaticSpecializationResult` 携带类型描述符、实例化类型名、`GenericArgumentBinding`、所用的 `SpecializationSelection`（派生嵌套类型用）和逐参数的解析结果。
  - `TypeDefinition+Specialization.swift` 新增 `specialize(with: StaticSpecializationResult, in:)` 与 `specialize(with:derivingNestedSpecializationsWith:in:)`，后者不需要另传 selection 与节点，都在结果里。
  - `buildRequirement` 认 `.symbol`：读文件时，对别的镜像里协议的引用落在 bind 上，原先整条需求被丢掉（见「顺带修的问题」）。
- **SwiftDeclaration**：`TypeDefinition.staticSpecialization: GenericArgumentBinding?`，与运行时特化的 `metadata` 互斥。
- **SwiftLayout**：
  - `GenericArgumentEnvironment.make(forBinding:)`；`make(forInstantiatedTypeNode:)` 改用共享的节点遍历，能穿过 extension 节点。
  - `StaticLayoutCalculator` 新增带 `genericArgumentBinding:` 的 `fieldLayout(of:)`、`typeLayout(forMangledTypeName:inContextOfDescriptor:)`、`enumCaseLayoutResult(forDescriptor:)` 与 `nestedFieldOffsetTree(forMangledTypeName:baseOffset:depthLimit:)`；`EnumLayoutBridge.enumCaseLayoutResult` 接受实参环境。提案原列的 `typeLayout(forDescriptor:)` 没有调用方，未加。
  - `ImageUniverse.projectingConcreteMembers(in:)`：把具体类型的关联类型按 witness 记录投影掉，静态展开偏移树也用它（见「顺带修的问题」）。
- **SwiftDeclarationRendering**：
  - `StaticFieldLayoutProvider` 新增四个带 binding 的方法，默认实现返回空，库外实现不受影响；`MachOFileStaticFieldLayoutProvider` 实现它们。
  - `FieldLayoutRenderState` / `FieldLayoutRenderer` 携带 `genericArgumentBinding`，`StaticFieldLayoutBackend` 据此要特化后的布局。`FieldLayoutRenderable.precomputedStaticAggregateFieldLayout` 多一个 binding 参数（只有库内的 `MachOFile` / `MachOImage` 遵循）。
  - `StaticSpecializationNodeSubstitution` 与 `DependentMemberProjection.projectingConcreteMembers`：字段类型的离线代换与关联类型投影。
  - `RuntimeFieldLayoutBackend`：带特化 metadata 的泛型 enum 也出 Enum Layout 注释（决策日志 2026-10-01）。
- **SwiftPrinting**：`boundTypeNode(of:)` 统一给出特化定义头部的绑定名字（运行时取 metadata 的名字，离线取实例化类型名），`renderTypeDeclarationHeader` 改收这个节点；`renderModelFields` 的字段代换与布局注释在 metadata 与 binding 之间二选一。

明确不动：运行时特化的计算路径（`specialize` / `runtimePreflight` / `resolveAssociatedTypeWitnesses`）；SwiftDump 的特化打印；CLI。原列的「未特化定义的打印」因层号整类修复与展开偏移树的投影而改变，见决策日志。

### 离线约束检查

检查逐条对应 `runtimePreflight`，按离线能拿到的证据分两档：

- **报错并拒绝**：结构上确定违反的约束。
  - `AnyObject` 参数给了 struct / enum / tuple；宿主类型按 metadata 的 kind 判断。
  - 父类约束：索引认识、但不在父类子树里的类；宿主类沿它自己完整的父类链按名字比较。
  - 关联类型的 same-type 约束：两侧都解析成具体类型且不相等。被钉死成具体类型的 key 参数不存在（编译器会把它变成非 key），所以实际只有关联类型这一种。
- **只给警告、照样特化**：离线证明不了的约束。
  - 协议遵循：索引记录里查不到（可能是条件遵循、别的模块补上的、运行时合成的），或实参类型不在任何被索引的镜像里。
  - 关联类型投影不出来。
  - 索引没有该父类的类层级信息，或实参类不在任何被索引的镜像里。

错误与警告沿用 `SpecializationValidation` 现有的 case，`SpecializerError` 也不加 case：RuntimeViewer 对这几个枚举做了穷尽 `switch`。关联类型的需求按访问路径命名（`A.Element`），与 request 的 `AssociatedTypeRequirement.fullPath` 一致。

### 层号错数整类修复

原列为「顺带修的旧问题 1」，只涉及特化器。用 0.21.0 的 CLI 跑现场编译的 fixture 证实它是一类问题：未特化的 interface 与 dump 头部同样错（`struct Inner<A2> { var innerElement: A1 }`、`struct DeepConstrainedInner<A1> where A2: Hashable`）。用户选择整类修复，五处改用 `GenericParameterDepthLayout`：

| 位置 | 错数的后果 |
|---|---|
| `GenericSpecializer.buildParameters` | 参数名错，按名字收集需求时漏掉，候选不过滤，运行时特化少算 witness table 而失败 |
| `GenericContext+Dump`（dump 与 interface 头部） | 参数子句与字段对不上 |
| `RuntimeMetadataTypeBuilder.bindings` | 进程内节点还原 metadata 时找不到实参 |
| `AccessorThunkOwnerLayout` | thunk 读到的实参被标到不存在的坐标 |
| `GenericArgumentEnvironment.make(forInstantiatedTypeNode:)` | 遍历在 extension 节点停下，约束 extension 里类型的实例化只收到最内层实参，引用它的字段整体降级 |

`TargetGenericContext.depth` 保留原义（泛型祖先个数，baseline 仍记录它），只是不再拿它命名参数。

### 顺带修的问题

1. **运行时特化的类型名被拍平**：`TypeDefinition.makeSpecializedDefinition` 改用 `GenericInstantiation`，`Outer<Int>.Inner<String>` 不再写成 `Outer.Inner<Int, String>`，派生的 `NestedHost<Int>.Plain` 不再写成 `NestedHost.Plain<Int>`。实参个数与 key 参数对不上时退回旧形状；`typeArgumentNodes` 传 `nil` 时仍保持未绑定的名字。
2. **离线 request 丢掉跨镜像协议需求**（实现时发现）：读文件时 `B: Hashable` 的协议引用解析成 bind 的符号（`$sSHMp`），`buildRequirement` 只认已解析的 descriptor，整条需求被丢掉——候选不过滤，witness table 不计数。现在按符号名还原协议名；在线路径不受影响。
3. **静态展开偏移树不投影具体类型的关联类型**（实现时发现）：`ElementsHolder<[Int]>.first` 原先显示为 `Swift.Optional<Swift.Array<Swift.Int>.Element>` 并在那里停下，运行时的遍历显示 `Swift.Optional<Swift.Int>` 并继续展开。现在先投影再命名和展开，未特化类型里出现的实例化字段同样受益。

### 不在本次范围（实现时发现，未修）

- 引用「嵌套泛型类型的约束 extension 里声明的类型」的字段（`Outer<Int>.SecondMiddle<Bool>.DeepConstrainedInner<String>`）demangle 失败（`unexpected(at: 11)`），引用它的整个类型从 interface 里消失。
- 引用约束 extension 里类型的类型，其 memberwise `init` 后面多出一个 `where A == Swift.Int`。
- class 头部的父类不代换实参（`class Sub<Swift.Int>: Base<A>`），在线路径也是这样。
- 在线特化的调用方不传 `typeArgumentNodes` 时，定义保持未绑定的名字，会查到并打印未代换的成员。

### 不做

- CLI 入口：用户明确这是给 RuntimeViewer 离线模式用的，本库没有使用它的地方。
- 实例化普查（自动为二进制里出现过的每个 `Foo<Int>` 算布局）：另立提案。
- SwiftDump / dump 路径的离线特化：RuntimeViewer 只用 `SwiftDeclarationPrinter`。
- 值泛型与参数包：`makeRequest` 本来就拒绝这两种参数，RuntimeViewer 的 UI 也按不支持展示。
- 成员签名的代换：运行时特化出的定义只打印头部和存储字段（成员按绑定后的名字查符号查不到），离线保持一致。

### 验证

- **离线与在线逐字节对照**（`OfflineSpecializationParityTests`）：`GenericSpecializationFixture` 现场编译一个 dylib，同一个文件按 `MachOFile` 读、`dlopen` 后按 `MachOImage` 读，两条路径分别特化，打开字段偏移、类型布局、enum 布局、展开偏移四种注释后打印，逐字节相同。覆盖 struct、final class、泛型父类的 class、单 payload 与多 payload 泛型 enum、关联类型字段、非声明层下的嵌套泛型、派生的嵌套类型、自带参数的嵌套泛型、私有类型、`.boundGeneric` 实参。两条路径按设计不同、未特化类型也一样的三处（payload extra inhabitant 里的空 case、tuple 字段、泛型标准库 struct 的展开遍历深度）不在对照范围，写在实现说明里。
- **实例化类型名**（`InstantiatedTypeNameTests`）：与运行时名字（经 `RuntimeTypeNameDemangling`）结构相等，含私有类型、约束 extension 里的类型（非 key 参数由约束补齐）、跨模块 extension 里的类型；嵌套泛型的约束 extension 单独断言离线的正确形状。
- **离线执行与约束检查**（`OfflineSpecializationTests`）：request 保留跨镜像协议需求；结果的 binding 与类型名；`.candidate` / `.boundGeneric`；泛型候选的类型化错误；每一档约束检查的正反例。
- **带 binding 的布局**（`BoundInstantiationLayoutTests`）：字段偏移与运行时 metadata 的 field offset vector 相同；展开偏移树投影关联类型。
- **修复前失败的回归测试**：层号五处（`GenericParameterDepthNamingTests`、`GenericParameterDepthDumpTests`、`CanonicalParameterDepthTests`、`AccessorThunkOwnerLayoutDepthTests`、`RuntimeMetadataTypeBuilderTests.nestedGenericBehindNonDeclaringLevelResolvesItsRequirement`、`ExtensionContextInstantiationLayoutTests`），以及运行时类型名拍平、跨镜像协议需求、展开偏移树投影、在线 Enum Layout 四项（把对应修改临时退回旧行为后确认失败）。
- **全量测试**：`swift test --skip IntegrationTests`（JHs-Mac-Studio-Ultra）2210 个测试 / 420 个套件全部通过，原始退出码 0；唯一的 known issue 是早已登记的 `SymbolicManglingIndexTests`。之后把测试 fixture 的单字母泛型参数名改成完整名称，受影响的套件重跑通过（147 个测试）。
- **rebase 后重跑**（2026-10-02，分支已 rebase 到 find-navigator 的 `86f65341` 之上，带 `USING_LOCAL_DEPENDENCIES=1` 用本地兄弟依赖构建）：全量 2224 个测试 / 424 个套件全部通过，原始退出码 0，正好是 rebase 前的 2210 个加上 find-navigator 新增的 14 个；known issue 仍只有 `SymbolicManglingIndexTests`。渲染 A/B 没有重跑。
- **渲染 A/B**（基线 `b2b7d997`，两侧 release CLI，依赖版本逐个相同）：共 132 对，90 对逐字节一致，42 对有差异。每一处差异都核对过，都是本提案预期的改变；两侧各重跑一遍有差异的场景，输出不变，排除了不确定性。
  - 脚本本身的 84 对（15.5 归档 cache；iOS 15.5 / 16.4 / 17.5 / 18.5 / 26.5 模拟器；进程内 `MachOImage` 与当前系统 cache 文件，后两者带布局注释）：22 对有差异，全部是头部参数名的修正。Combine 的 `Optional<A>.Publisher.Inner`、`Result<A, B>.Publisher.Inner` 与 SwiftUICore 的 `TimeDataSource<A>.Resolver.ResolvedOffsetBox` 都嵌在不声明参数的中间层下，头部从 `<A2>` 改成 `<A1>`，与同一行的 `where` 子句（一直写的是 `A1`）终于一致。
  - 脚本写死的 `26.6.2` 归档目录不存在（卷上现在叫 `26.6`），所以手动补了 26.6 与 27.0 两份 cache 的 24 对：8 对有差异，同样只是上面三个头部。
  - 脚本的 CLI 腿只用默认参数、不出布局注释，于是另跑了打开全部布局注释（含展开偏移）的 24 对（26.6 cache 与 iOS 26.5 模拟器）：12 对有差异。除了上面的头部，都是展开偏移树的改进：具体类型的关联类型投影成 witness 后再命名、并继续展开（`Angle.Animatable.AnimatableData` → `Swift.Double`，`BigString._Chunk.RopeElement.Summary` → `BigString.Summary`，`SubviewsCollection.Collection.Index` → `Swift.Int`，`ViewFrame.Animatable.AnimatableData` 展开成 `AnimatablePair<…>` 的各层字段）；以及约束 extension 里类型的实参代换修正（`MeasurementView<A, B>` 的字段 `Measurement<B>.FormatStyle` 展开出的子字段，原先错印成 `Measurement<A>`）。

### 未经询问而采用的假设

- 公开 API 用 `Static` 前缀表示离线（`StaticSpecializationResult`、`staticPreflight`、`staticSpecialization`），与 `StaticLayoutCalculator`、`StaticFieldLayoutBackend` 的命名一致；离线的 `specialize` 与运行时版本同名，靠 `where MachO == …` 区分。
- 离线执行只对 `MachOFile` 开放。`MachOImage` 的布局注释走运行时 metadata，给它一个没有 metadata 的特化定义只会丢注释。
- 实参所在镜像必须在被特化类型所在镜像的依赖闭包里，否则布局按字段降级为 `unknown`，关联类型保持未投影。这是如实降级，不是错误。
- 对照测试用现场编译的 dylib 而不是 SymbolTestsCore：同一个文件要能同时按两种方式读。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-09-30 | 创建为 Draft | 用户：「把离线泛型特化实现一下，我记得之前在做静态布局的时候就提到过这个，目前泛型特化只有运行时才能用」 |
| 2026-09-30 | 不提供 CLI 入口 | 用户：这个功能是给 RuntimeViewer 离线运行用的，本库没有应用的地方 |
| 2026-09-30 | 实例化普查不做，另立提案 | 用户选择 |
| 2026-09-30 | 只接 interface 打印路径，不接 SwiftDump | 未询问自定：RuntimeViewer 只用 `SwiftDeclarationPrinter`，dump 路径在本库没有消费方 |
| 2026-09-30 | 值泛型与参数包不支持 | 未询问自定：与运行时特化器的 request 层一致 |
| 2026-09-30 | 约束检查分「确定违反则报错」与「证明不了则警告」两档 | 未询问自定：离线看不到运行时才知道的遵循关系，照运行时的标准一律报错会误拒合法的特化 |
| 2026-10-01 | Draft → Accepted → In Progress | 用户：「开始实现提案」 |
| 2026-10-01 | 参数层数的错数整类一起修，不只修特化器 | 用 0.21.0 的 CLI 跑现场编译的 fixture 证实：未特化 interface 的头部同样错（`struct Inner<A2> { var innerElement: A1 }`），`RuntimeMetadataTypeBuilder` 与 `AccessorThunkOwnerLayout` 用的是同一种数法。用户选择整类修复，接受未特化输出对这类形状的变化 |
| 2026-10-01 | 在线模式也给特化后的泛型枚举出 Enum Layout 注释 | 运行时后端对任何泛型枚举都不出这项注释（`RuntimeFieldLayoutBackend.swift:607`），离线却能算出，逐字节对照因此做不到。用户选择在线也补上 |
| 2026-10-01 | 对照测试用现场编译的 dylib | 未询问自定：同一个文件要能按 `MachOFile` 读、又能 `dlopen` 成 `MachOImage`，SymbolTestsCore 与测试二进制都做不到这一点 |
| 2026-10-01 | 嵌套泛型的约束 extension 里的类型，实例化名字按层绑定，不照搬运行时 | 未询问自定：运行时把全部实参塞进被扩展类型最内层的列表，拼出的名字不对应任何实例化；其余形状与运行时结构相等 |
| 2026-10-01 | `buildRequirement` 认 `.symbol` | 实现时发现：读文件时跨镜像协议的引用解析成 bind 的符号，离线 request 一直丢掉这类需求；修复前确认测试失败 |
| 2026-10-01 | 静态展开偏移树先投影具体类型的关联类型 | 实现时发现：对照测试里 `first` 字段静态显示 `Array<Int>.Element` 并停止展开，运行时显示 `Int` 并继续展开；这也改变未特化类型里实例化字段的展开，修复前确认测试失败 |
| 2026-10-01 | 不加 `typeLayout(forDescriptor:genericArgumentBinding:)` | 未询问自定：渲染路径没有调用方 |
| 2026-10-02 | 分支 rebase 到 `feature/runtime-viewer/find-navigator`（`86f65341`）之上，须在它之后合入 | 用户：「rebase一下find-navigator，然后提交」。两边都改过的 11 个文件里，代码文件全部自动合并，文档索引与演进账本两处冲突两边内容都保留。find-navigator 的最后一个提交要用 swift-semantic-string 尚未发版的 `DefinitionRegion`，所以本分支现在要用本地兄弟依赖构建，也要等那个版本发布、本库抬高版本下限之后才能落地 |
