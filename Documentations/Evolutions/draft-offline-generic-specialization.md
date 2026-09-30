# Draft - 离线泛型特化：不经 runtime 特化泛型类型并完整打印

- **状态**: Draft
- **创建日期**: 2026-09-30
- **最后更新**: 2026-09-30
- **所属愿景**: 无
- **关联文档**: [StaticLayoutEngine.md](../Internal/StaticLayoutEngine.md)「后续工作」里的「用户手动特化前端」一条；[SpecializedInterfaceBoundRenderingRestoration.md](../Internal/SpecializedInterfaceBoundRenderingRestoration.md)（运行时特化的打印机制）；RuntimeViewer 的 [0003-generic-type-specialization](https://github.com/MxIris-Reverse-Engineering/RuntimeViewer/blob/main/Documentations/Evolutions/0003-generic-type-specialization.md)（消费方的 UI 流程）
- **实现分支 / PR**: `feature/offline-generic-specialization`（未开始实现）
- **配套文档**: 待定

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

- **SwiftInspection**：新增公开的 `GenericArgumentBinding`，表示「某个泛型签名的参数被绑定到哪些实参」，按 canonical depth 分组（`argumentsByDepth: [[Node]]`），并提供一个只做显示用的代换（`dependentGenericParamType` 按 `(depth, index)` 换成实参，metatype 里面也换）。在 `SymbolicDemangler.swift:460` 的 `buildContextDescriptorMangling` 旁边新增实例化类型名的构造：给定类型描述符和全部实参，产出绑定后的类型节点（`Outer<Swift.Int>.Inner<Swift.String>`）和对应的 `GenericArgumentBinding`。它移植的是运行时 `stdlib/public/runtime/Demangle.cpp` 的 `_buildDemanglingForContext`：沿描述符路径从外到内，某层上下文的累计参数数比已用掉的多，就把多出来的那几个实参挂在这一层；extension 层挂在被扩展的类型上。于是离线得到的名字和在线模式下运行时给出的名字形状一致，名字里的各部分（私有鉴别符、C 导入类型的身份）仍由 `SymbolicDemangler` 生成。
- **SwiftSpecialization**：
  - `GenericSpecializer`（`GenericSpecializer.swift`）新增 `where MachO == MachOFile` 的扩展，放在 `:1320` 运行时执行扩展的旁边：`specialize(_:with:)` 返回 `StaticSpecializationResult`，`staticPreflight(selection:for:)` 是 `runtimePreflight` 的离线对应。
  - 实参取节点：`.candidate` 取候选的 `TypeName` 节点；`.boundGeneric` 用绑定在候选自己镜像上的内层 specializer 递归离线特化，取内层结果的类型节点；`.metatype` / `.metadata` / `.specialized` 用宿主进程的运行时名字（`RuntimeTypeNameDemangling`），不调用目标镜像的任何代码。
  - 没有 key argument 的参数（被同型约束钉死的，例如 `extension Outer where A == Int { struct Inner<B> }` 里的 `A`）由约束的右侧补齐。
  - `StaticSpecializationResult` 携带类型描述符、绑定后的 `TypeName`、`GenericArgumentBinding` 和逐参数的解析结果（参数名、实参节点、`.boundGeneric` 的内层结果）。
  - `TypeDefinition+Specialization.swift` 新增两个 `specialize(with: StaticSpecializationResult, …, in: MachOFile)` 重载，与 `:120` / `:166` 的运行时版本对应（含嵌套派生）。
- **SwiftDeclaration**：`TypeDefinition`（`TypeDefinition.swift:152` 的 `metadata` 旁）新增 `staticSpecialization: GenericArgumentBinding?`。运行时特化填 `metadata`，离线特化填这个，打印器按哪个非空选路径。
- **SwiftLayout**：
  - `GenericArgumentEnvironment` 能从 `GenericArgumentBinding` 建环境。现在只有 `:147` 的 depth-0 版本，嵌套泛型的内层实参绑不上。
  - `StaticLayoutCalculator` 的 `fieldLayout` / `typeLayout(forDescriptor:)` / `typeLayout(forMangledTypeName:inContextOfDescriptor:)` / `enumCaseLayoutResult`、`nestedFieldOffsetTree` 各加一个接受 `GenericArgumentBinding` 的重载。
  - `EnumLayoutBridge.swift:307` 的 `enumCaseLayoutResult` 目前不接受实参环境，要补上，特化后的泛型枚举才有逐 case 的布局。
- **SwiftDeclarationRendering**：
  - `FieldLayoutRenderState` / `FieldLayoutRenderer`（`FieldLayoutRenderer.swift:38` / `:139`）携带 `GenericArgumentBinding`，`StaticFieldLayoutBackend` 据此向 provider 要特化后的布局。
  - `StaticFieldLayoutProvider`（`StaticFieldLayoutProvider.swift:36`）的新方法带默认实现，已有的外部实现不受影响。
  - 新增离线的字段类型代换：先按 binding 代换，再把 `C.Element` 这类关联类型经 `DependentMemberProjection` 投影成具体类型；投影不了的保留原样。
- **SwiftPrinting**：`SwiftDeclarationPrinter.swift:275` 与 `SwiftDeclarationPrinter+Headers.swift:37` / `:359` / `:436` 现在只认 `metadata`。改为：头部的绑定节点、字段代换、布局注释三处都在「运行时 metadata」与「离线 binding」之间二选一。

明确不动：运行时特化的计算路径（`specialize` / `runtimePreflight` / `resolveAssociatedTypeWitnesses`）；SwiftDump 与 dump 输出；CLI；未特化定义的打印。

### 离线约束检查

检查逐条对应 `runtimePreflight`，但离线能拿到的证据不同，所以分两档：

- **报错并拒绝**：结构上确定违反的约束。
  - `AnyObject` 参数给了 struct / enum。
  - 父类约束：实参不在索引记录的父类子树里。
  - 具体同型约束与实参对不上。
- **只给警告、照样特化**：离线证明不了的约束。
  - 协议遵循。候选列表本来就按 indexer 里的遵循记录筛过；`.boundGeneric` 的条件遵循、别的模块补上的遵循、ObjC 协议、marker 协议都查不全。
  - 关联类型约束（`A.Element: Hashable`）投影不出来的情况。
  - 父类约束在 indexer 没有类层级信息时。

错误与警告沿用 `SpecializationValidation` 现有的 case，`SpecializerError` 也不加 case：RuntimeViewer 对这几个枚举做了穷尽 `switch`，加 case 会让它编译失败。

### 顺带修的两个旧问题

两处都在本提案要复用的代码上，不修的话离线结果也会错：

1. **参数层数可能数错（待测试确认）**：`GenericSpecializer.swift:164` 的 `perLevelNewParameterCounts` 把父链上每个泛型上下文都当成一层。一个本身不声明参数、只因嵌在泛型类型里才算泛型的中间层（`Outer<A>.Middle.Inner<B>` 的 `Middle`），会占掉一个层号。于是 `B` 被命名成 `A2`，而字段记录与约束里写的是 canonical 的 `A1`（τ_1_0），这个参数的约束就收集不到。约束 extension 里声明的泛型类型可能有同样的问题。先用现场编译的 fixture 写出会失败的测试，确认后改为只数真正声明参数的层，和上面的实例化类型名构造共用同一套计数。fixture 里目前没有这两种形状，所以现有测试不会发现。
2. **运行时特化的类型名被拍平**：`TypeDefinition+Specialization.swift:333` 的 `boundGenericTypeName` 把全部实参放进最内层，`Outer<Int>.Inner<String>` 被写成 `Outer.Inner<Int, String>`，`GenericOuter<Int>.Inner` 被写成 `GenericOuter.Inner<Int>`。打印出来的头部不受影响（它用的是 metadata 的运行时名字），但 `typeName` 是 RuntimeViewer 侧边栏的显示名和标识。改为用上面的实例化类型名构造，在线与离线两种模式的名字才一致。`typeArgumentNodes` 传 `nil` 时仍保持未绑定的名字，这个现有约定不变。

### 不做

- CLI 入口：用户明确这是给 RuntimeViewer 离线模式用的，本库没有使用它的地方。
- 实例化普查（自动为二进制里出现过的每个 `Foo<Int>` 算布局）：另立提案。
- SwiftDump / dump 路径：RuntimeViewer 只用 `SwiftDeclarationPrinter`。
- 值泛型与参数包：`makeRequest` 本来就拒绝这两种参数，RuntimeViewer 的 UI 也按不支持展示。
- 成员签名的代换：运行时特化出的定义只打印头部和存储字段（成员按绑定后的名字查符号查不到），离线保持一致。

### 验证

- **离线与运行时逐字节对照**：对 fixture 里一组泛型类型与实参组合，分别用运行时（`MachOImage`）和离线（`MachOFile`）特化，打开字段偏移、类型布局、枚举布局、展开偏移几种注释，打印出的 interface 应当逐字节相同。覆盖 struct / class / 单 payload 与多 payload 泛型枚举 / 嵌套泛型 / 非泛型嵌套类型 / 关联类型字段 / `.boundGeneric` 实参。
- 实例化类型名与运行时 `_mangledTypeName` 给出的名字结构相等；私有类型与约束 extension 里的类型用现场编译的 fixture。
- 离线约束检查的每一档各有正反例；两个旧问题各有修复前失败、修复后通过的回归测试。
- 渲染 A/B 验证：本提案不改未特化的打印，但动了打印路径与布局引擎，按项目规定跑一遍。

### 未经询问而采用的假设

- 公开 API 用 `Static` 前缀表示离线（`StaticSpecializationResult`、`staticPreflight`），与 `StaticLayoutCalculator`、`StaticFieldLayoutBackend` 的命名一致；离线的 `specialize` 与运行时版本同名，靠 `where MachO == …` 区分。
- 离线执行只对 `MachOFile` 开放。`MachOImage` 的布局注释走运行时 metadata，给它一个没有 metadata 的特化定义只会丢注释。
- 实参所在镜像必须在被特化类型所在镜像的依赖闭包里，否则布局按字段降级为 `unknown`，关联类型保持未投影。RuntimeViewer 让用户从别的、互不依赖的镜像里挑候选时就会这样，这是如实降级，不是错误。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-09-30 | 创建为 Draft | 用户：「把离线泛型特化实现一下，我记得之前在做静态布局的时候就提到过这个，目前泛型特化只有运行时才能用」 |
| 2026-09-30 | 不提供 CLI 入口 | 用户：这个功能是给 RuntimeViewer 离线运行用的，本库没有应用的地方 |
| 2026-09-30 | 实例化普查不做，另立提案 | 用户选择 |
| 2026-09-30 | 只接 interface 打印路径，不接 SwiftDump | 未询问自定：RuntimeViewer 只用 `SwiftDeclarationPrinter`，dump 路径在本库没有消费方 |
| 2026-09-30 | 值泛型与参数包不支持 | 未询问自定：与运行时特化器的 request 层一致 |
| 2026-09-30 | 约束检查分「确定违反则报错」与「证明不了则警告」两档 | 未询问自定：离线看不到运行时才知道的遵循关系，照运行时的标准一律报错会误拒合法的特化 |
