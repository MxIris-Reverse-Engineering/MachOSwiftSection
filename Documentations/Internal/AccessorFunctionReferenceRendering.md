# Accessor-Function Symbolic Reference 的渲染与解析阶梯

## 背景：kind-9 引用是什么、怎么触发

Swift 的 field record 里存的类型名通常是可 demangle 的 mangled name，但有一类例外：当 payload 类型的 mangling 用到了「部署目标的 runtime demangler 不认识」的语言特性时，编译器不再嵌入类型名，而是嵌入一个字节 `0x09` + 指向 metadata accessor thunk 的相对指针——运行时解析这种引用不做 demangle，直接调用该函数拿 metadata。这是为向后部署新类型系统特性设计的逃生门（swiftlang/swift `lib/IRGen/GenReflection.cpp`：`getRuntimeVersionThatSupportsDemanglingType` 逐特性判最低 runtime 版本，`mangledNameIsUnknownToDeployTarget` 命中则走 `getTypeRefByFunction`）。

实测触发案例（Xcode 26.5 的 Testing.framework，即 swift-testing，部署目标低于 macOS 15）：

- `Event.Kind.valueAttached(_ attachment: Attachment<AnyAttachable>)`——`Attachment<AttachableValue: Attachable & ~Copyable>` 的泛型签名带 inverse requirement，mangling 需要 Swift 6.0 runtime；
- `TypeInfo._Kind.type(_ type: any (~Copyable & ~Escapable).Type)`——带 inverse 的 protocol composition，同样需要 6.0。

随着各框架采用 noncopyable/nonescapable 泛型并保持向后部署，这类引用会越来越常见。

离线（`MachOFile`）读取器不能执行目标二进制的代码。**但「不能执行」不等于「不可解析」**——见下面的层 3，thunk 的指令序列本身就把答案写在里面了。在层 3 之前，这种引用的处理是：`MetadataReader` 把 thunk 的文件偏移存进 node 的 index（`MetadataReader.swift` 的 `.accessorFunctionReference` 分支），Demangling 包的 `NodePrinter` 打出兜底文案 `accessor function at <offset>`。

## 症状与历史

`SwiftPrinting` 自己的节点渲染器家族（`NodePrintable` 及四个分类 printer）不认识 `.accessorFunctionReference` 这个 kind，`dispatchPrintName` 全部 miss 后静默返回——节点渲染为空串。叠加枚举 case 的「mangled name 非空就加括号」gating，interface 输出出现 `case type()` / `indirect case valueAttached()`，`swiftc -parse` 拒绝（"enum element with associated values must have at least one associated value"）。

这个 bug 早于 leaf 迁移：迁移前（`aa233bc^`）的 interface 对同一二进制输出逐字节相同的空括号。迁移后的 main 改按「渲染文本」gating，意外遮住了它，但代价是 Void payload 回归（`case a(Void)` 塌成裸 `case a`）；PR #98 恢复 mangled-name gating 后空括号重新暴露。dump CLI 一直显示 `case type(accessor function at 750396)`，因为 `swift-section dump` 配的 resolver 走 Demangling 包的 `NodePrinter`（有兜底文案），而 interface 配的是 `SwiftPrinting` 的渲染器（没有）。

## 解析阶梯（能真解析就真解析，不能就诚实占位）

### 层 0：占位渲染补齐（已实现，2026-08-02，随 PR #98）

- `SwiftPrinting/NodePrintables/NodePrintable.swift` 的 `printNameInBase` 补 `.accessorFunctionReference` case，文案与 Demangling `NodePrinter` 逐字一致（`accessor function at <index>`），保证 dump/interface 两路拼写一致。
- `FieldFlags.hasMangledTypeName`（`SwiftDeclaration`）：index 时从 field record 捕获「mangled type name 非空」，`renderModelFields` 的 payload gating 改读模型 flag，不再按下标读 record（消除位置对齐的隐式依赖）。
- 双防护网：`printThrowingEnumCase`（interface 路径）与 `EnumDumper.fields`（dump 路径）在 payload 渲染结果为空串时退回裸 case——括号绝不包空。防将来再出现未覆盖 kind 时复发非法 `case name()`。

明确的限制：`case type(accessor function at 750396)` 依然不是合法 Swift——离线本就还原不出类型名，这是诚实标注（与 dump 的历史行为一致），不是可编译输出。要真类型名需要下面两层。

### 层 1：进程内真解析（关联类型 witness 已实现，2026-09-11，提案 0028 收尾批次；field record 待做）

kind-9 的设计意图就是「调函数拿 metadata」，进程内完全可以照做。库里已有同类先例：layout 注释路径的 `resolveFieldMetatype` 对每个非泛型字段都在调 `getTypeByMangledNameInContext`，特化替换路径（`SpecializedMetadataNodeSubstitution`）也在用 `_mangledTypeName` + `demangleAsNode` 回读节点，所以不引入新的风险类别。

**关联类型 witness 这一半已落地**（`SwiftDeclarationRendering/InProcessAccessorFunctionResolution.swift`）：`MachOImage` 上，opaque 展开后树里还留有 kind-9 引用时，把**整条 witness 的 mangled name** 交给 `swift_getTypeByMangledNameInContext`，context 是 conforming type 的 descriptor、实参是它 metadata 的泛型实参区——与 runtime 自己的 `swift_getAssociatedTypeWitnessSlow` 完全同一套调用（thunk 会读那块实参缓冲，所以必须传真实的区而不是 null），再 `_mangledTypeName` → `demangleAsNodeTransient` 回读。三个 witness 调用点（`AssociatedTypeDumper`、`SwiftDeclarationPrinter+Headers`、`SwiftDeclarationIndexer.resolvedWitnessProjections`）都走 `Node.resolveOpaqueType(witnessMangledName:conformingTypeName:in:)`。两处刻意不猜：**泛型 conformer** 没有实参就没有 metadata，runtime 对 conformer 本身就返回 nil（SwiftUI 17 条 kind-9 witness 里 12 条，`Slider` / `Toggle` / `TextField` / `Picker` 等）；**class conformer** 的泛型实参偏移不是常数，且没有实测样本，这条腿没接。实测 SwiftUI（macOS 26，dlopen 进测试进程）：17 条里 5 条由 runtime 答出，其中包括离线读不了的 `DefinesSearchCompletionModifier.Body`。runtime 只答当前系统这一支，「另一支是什么」仍是层 3 离线独有的事实。

- 助手放 `MachOSwiftSection/Runtime/RuntimeFunctions.swift` 旁：`demangledNodeByResolvingAccessorFunction(for: MangledName, in: MachOImage) -> Node?`——整条 mangled name 交给 `swift_getTypeByMangledNameInContext`（runtime 会执行 thunk），成功后 `_mangledTypeName(metatype)` → `demangleAsNode` 得到真实节点。
- 两个挂接点（kind-9 只在 Reflection/FieldMetadata 两个 role 下发出，即 field record，所以这两处覆盖全部实际出现）：`FieldRecord.demangledTypeNode(in:)`（`SwiftDeclaration/Extensions.swift`，interface/模型索引路径）与 `TypedDumper.fieldDemangledTypeNode(for:)`（`SwiftDump`，dump 路径）。mangled name 含 `0x09` 控制字节且 reader 是进程内 `MachOImage` 时先走助手，失败（泛型上下文缺实参等）回落层 0 占位。
- 边界：`MetadataReader` 本体保持纯读取——「执行目标代码」是策略决定，留在字段入口层，不下沉进底层 reader。
- 效果：RuntimeViewer 与进程内 dump/interface 直接显示 `case valueAttached(Testing.Attachment<Testing.AnyAttachable>)`。

### 层 2：离线符号表还原（待验证可行性）

编译器给 thunk 起的符号名内嵌完整类型 mangling：`IRGenMangler.cpp` 的 `mangleSymbolNameForMangledMetadataAccessorString` 产出 `get_type_metadata <generic-signature><type-mangling>`，noncopyable 类型再追加 ` noncopyable` 后缀，private linkage 本地符号。离线拿 node 里存的文件偏移查 `SymbolIndexStore`，命中这种符号就剥前缀 demangle 出真类型——纯符号表读取，不执行代码，可以放进 `MetadataReader` 的离线分支。

限制与前置：strip 过的 OS 框架查不到（Testing.framework 实测已 strip，nm 只能看到偏移前 16 字节处相邻的枚举自身 metadata accessor）；只对未 strip 的用户二进制生效。立项前先在一个未 strip 的向后部署二进制上验证符号确实保留、且带泛型签名的符号后缀能被 demangler 接受。

### 层 3：离线反汇编还原（已实现，2026-09-11，提案 0028）

**推翻了本文档原来「构造上不可解析」的判断。** 实测 SwiftUI（macOS 26 共享缓存）的 kind-9 引用不是
「mangling 特性不支持」那条触发路径，而是 **SE-0360 的 availability-conditional opaque result type**：
thunk 里先调 `__isPlatformVersionAtLeast`，再按结果在两个类型之间二选一。两个答案都写在指令里，读出来
不需要执行。

- 模块：`SwiftThunkAnalysis`（SPM trait `ThunkAnalysis`，默认关闭）。
- 覆盖两种形态：`cmp`/`csel` 在两个 metadata 地址之间选；`cbz` 分两支各调一个 metadata accessor。
- 实测 SwiftUI 关联类型的裸地址 **17 → 5**，包含 RuntimeViewer issue #5 的 `FeedbackGenerator.Body`。
- 剩余 5 条来自一个「一支是真实构造代码链」的 thunk，那一支**刻意不猜**（取第一个 `bl` 会给出真实但
  错误的类型）。
- 完整设计与实测数据见[提案 0028](../Evolutions/0028-offline-opaque-accessor-thunk-resolution.md)。

**收尾批次（2026-09-11，同提案）**补齐了三件事：

- **回落不再抹掉整棵树**。此前 rewriter 在 underlying type 不是 `.type` 节点时整支放弃，于是
  `printOpaqueType` 打出 `opaque type symbolic reference 0x<描述符偏移>.0`，把周围的 `ModifiedContent<…>`
  链和全部泛型实参一起丢掉。现在含 kind-9 的树照常走实参替换与嵌套展开，kind-9 位置由层 0 那句
  `accessor function at N` 兜底——不开 trait 时 17 条全部变成「类型里嵌一个未读引用」，开 trait 后剩下
  5 条亦然。文案沿用而不换，是因为它出自上游 `NodePrinter`、两条打印路径有 parity 测试钉着、快照归一化
  也认这个前缀。
- **另一支进了模型**。`AssociatedTypeWitnessProjection.conditionalCandidates`：每支一条，带版本条件、
  thunk 那一支的类型、以及整条 witness 按该分支替换后的全文（宿主不必知道 thunk 嵌在树的哪一层）。
  `Node.resolveOpaqueTypeCollectingConditionalCandidates(in:)` 用同一个 rewriter 跑一遍记下候选，再对
  每个非默认分支按选择重跑一遍——每条 witness 一个双向 thunk（实测全部如此）就多一趟，没有笛卡尔积。
  同一批顺带让索引期投影解析 opaque（此前 ABI 快照里每个 `some View` 的 `Body` 都是裸偏移，跨版本 diff
  全报 modified）。
- **进程内路径**见层 1。

### 层 3′：类型构造求值（已实现，2026-09-12，提案 0029）

层 3 的两种读法（`csel` 取两个操作数、`cbz` 分支里取唯一一次调用）都是「查表」读法，剩下的 5 条 SwiftUI
witness 指向的 thunk 不查表而是**构造**类型：调 `_TagTraitWritingModifier` 的 metadata accessor，再把结果和
参数缓冲区里的另一个词交给 `ModifiedContent` 的 accessor。把每次调用查出名字后发现 thunk 只用三种运行时入口
（泛型类型的 metadata accessor、`swift_getWitnessTable`、`__swift_instantiateConcreteTypeFromMangledName`），
每一种的语义都是类型层面的，于是改成**符号求值**（[术语表](../Glossary.md#type-construction-evaluation类型构造求值)）：
寄存器和栈槽里放类型表达式，函数返回时 `x0` 里的表达式就是答案；能判定的条件跳转直接判定（运行时能力标志、
已知立即数），判定不了的按「假设为假 / 假设为真」各跑一遍，两次结果就是 `if #available` 的两支。

**它同时修正了层 3 的两处误读**：`csel` 形态的 `ResolvedMenuStyle.Body` 实际在 `csel` 之后尾调用了
`ModifiedContent` 的 accessor，正确答案是 `ModifiedContent<参数 0, 选中的那个>`，层 3 只报了选中的那个；
`cbz` 形态的 `FeedbackGenerator.Body` 不满足支里有三次调用（其中一次是尾调用 `b`，层 3 数 `bl` 没数到它），
层 3 报的 `_TaskValueModifier` 是中间结果，正确答案是 `ModifiedContent<_ViewModifier_Content<FeedbackGenerator<A>>, _TaskValueModifier<SensoryFeedback>>`。
两处都由进程内 runtime 的答案做 oracle 证实（`ConstructedThunkOracleTests`，SwiftUI 上 5 条非泛型 conformer
的 witness 逐字相等，私有类型上下文的两种拼法归一后比较）。

调用目标的命名：同镜像的 accessor 走 `MetadataAccessorIndex`；跨镜像的经 dyld 缓存 stub → 槽位 → rebase 目标 →
主缓存 image 表定位所属镜像 → 该镜像的 accessor 索引或导出表；非缓存文件的 stub 是 bind，直接按名分类；编译器
塞进镜像自身的 `__swift_instantiateConcreteTypeFromMangledName` 副本按原始符号表（不是只收 Swift 符号的索引）
认。accessor 的实参顺序按被调类型的泛型上下文（shape class、有 key 实参的类型参数、有 key 实参的见证表），
超过三个从 `x1` 指向的栈缓冲区取；`argument(k)` 按 thunk 主人的泛型上下文映射为第 `(depth, index)` 个参数节点，
交给既有的实参替换。为此 seam 多了 `AccessorThunkOwnerLayout` 参数。

**field record 里的 kind-9 也在这一层接入**：`TypeDefinition.index`（模型 / interface 路径）与
`TypedDumper.fieldDemangledTypeNode`（dump 路径）在离线且 resolver 已注册时走同一个 rewriter，thunk 的参数
缓冲区就是所在类型的泛型实参，未特化 dump 直接打印 `A` / `B`。fixture 的 `AccessorFunctionReferences` 命名空间
（形态 A：`_swift_runtimeSupportsNoncopyableTypes` 检查 + `csel` 两个 metadata；形态 B：
`__swift_instantiateConcreteTypeFromMangledNameV2` 读一条 mangled name）由 `FieldRecordThunkResolutionTests`
钉住，期望值是 fixture 源码里声明的类型。`SwiftUI.Drag.LazyItem<A>.state` 解成
`Synchronization.Mutex<SwiftUI.Drag.LazyItem<A>.State>`。

实测（SwiftUI，macOS 26 共享缓存）：关联类型 witness 未读引用 17 → **0**，全量 dump 未解析的 kind-9 引用
6 → **0**。层 0 的占位渲染只在不开 trait、或 thunk 调了不认识的函数时出现。

## 验证

- **fixture 覆盖**（2026-08-02 补）：`SymbolTestsCore` 新增 `AccessorFunctionReferences` 命名空间——利用 kind-9 的第二条触发路径（字段类型 always-noncopyable 时 reflection 走 runtime capability check，**不看部署目标**，所以在 fixture 的 macOS 26 目标下也能发出；第一条「部署目标过旧」路径在该目标下永远不触发，这正是 fixture 此前零覆盖的原因）。覆盖四个形态：普通 noncopyable 字段、bound-generic-with-inverse 字段（`NoncopyableGenericBoxTest<Int>`，即 swift-testing `Attachment<AnyAttachable>` 的形态）、枚举 payload case（历史失败形态 `case holding()`）、kind-9 字段之后的普通尾随字段（钉「渲染继续而非中断」）。快照 `accessorFunctionReferencesSnapshot` 与整模块 interface 快照都经 `normalizingAccessorFunctionOffsets` 把偏移归一为 `<offset>`——thunk 文件偏移每次重建都会漂移，归一化让快照对 fixture 重建保持稳定。注意 `any (~Copyable & ~Escapable).Type` 这类「组合带 inverse」的 existential metatype 在 macOS 26 目标下不走 kind-9（运行时能 demangle），要覆盖它需要低部署目标的独立 target——未做，记录在案。
- 单测：`NodePrinterTests.typeNodePrinterAccessorFunctionReference`（合成 kind-9 节点，钉兜底文案）；`EnumCaseRenderingParityTests`（Void payload 括号与两路拼写一致，不受影响）。
- A/B：Testing.framework（arm64e）整文件 interface diff——层 0 前后仅三行变化，全部是修复本身：`indirect case valueAttached()` → `indirect case valueAttached(accessor function at 428216)`、`case type()` → `case type(accessor function at 750396)`，以及一处此前没被发现的**存储字段**同源问题 `var _storage: `（悬空冒号，同样非法）→ `var _storage: accessor function at 283740`（`Attachment` 的 `Allocated<AttachableValue>` 字段）。三行均与 dump 路径拼写逐字一致。
