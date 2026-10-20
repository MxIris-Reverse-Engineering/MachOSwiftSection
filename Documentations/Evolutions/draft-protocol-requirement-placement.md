# Draft - 协议约束可选写在各自的关联类型上

- **状态**: In Progress
- **创建日期**: 2026-10-20
- **最后更新**: 2026-10-20
- **实现分支**: `feature/protocol-requirement-placement`

## 摘要

二进制只记录协议的 requirement signature，也就是编译器规范化之后的全部约束，看不出源码把一条约束写在协议的 `where` 子句里还是写在 `associatedtype` 上：两种写法编译出来完全一样。interface 现在把所有约束都堆在协议头的 `where` 子句里：

```swift
protocol MenuBase: AppKit.XPCCodable, Swift.Identifiable where Self.MenuItemType: AppKit.MenuItemBase {
    associatedtype MenuItemType
}
```

本提案给 interface 加一个开关，打开后把关于本协议某个关联类型的约束写到那个 `associatedtype` 上，与编译器生成 `.swiftinterface` 的写法一致：

```swift
protocol MenuBase: AppKit.XPCCodable, Swift.Identifiable {
    associatedtype MenuItemType: AppKit.MenuItemBase
}
```

两种写法表达的约束必须完全相同：每条约束恰好出现一次，文字不变，只换位置。

## 方案

**摆放规则**：逐条看 requirement signature。约束 `Self` 本身的（继承的协议、`AnyObject`、父类）照旧写在协议的继承子句里。其余的：

1. conformance / superclass / layout 约束，主语恰好是 `Self.X`，且 `X` 是本协议自己声明的关联类型：写进 `associatedtype X` 的继承子句，`associatedtype X: P`。
2. 其余约束，找它关于哪个关联类型：在主语里找第一个 `Self.X` 引用，取链的根（`Self.X.Y` 算 `X`）。same-type 约束两边都看，优先取恰好是 `Self.X` 的那一边，其次左边，再次右边。找到就写进 `associatedtype X` 的 `where` 子句，文字与原来逐字相同，比如 `associatedtype Nested: Swift.Sequence where Self.Nested.Element: Probe.Marker`。
3. 找不到本协议的关联类型（比如只约束了继承来的 `Self.Element`）：照旧写在协议的 `where` 子句里。

规则 2 只用于 conformance / superclass / layout / same-type 约束；inverse、same-shape 等其余种类照旧写在协议的 `where` 子句里。

**为什么语义不会变**：协议的 `where` 子句、关联类型的继承子句、关联类型的 `where` 子句，Swift 都把其中的约束收进同一个 requirement signature；`associatedtype X: P` 就是 `where Self.X: P`，关联类型的 `where` 子句里也可以写任何关于 `Self` 的约束。唯一会改变含义的错误，是把约束放进错误的关联类型的继承子句，所以规则 1 只认主语恰好是 `Self.X` 的约束。编译器自己的打印器恰好在这里出错：对源码 `associatedtype Child: RecursiveLeaf where Child.Leaf: Hashable`，Swift 6.3.3 的 `-emit-module-interface` 印出 `associatedtype Leaf : Swift.Hashable`，约束从 `Self.Child.Leaf` 变成了更强的 `Self.Leaf`。规则 2 取链的根，这条约束落在 `Child` 的 `where` 子句里，与源码一致。除此之外摆法与编译器相同，包括 same-type 约束不交换左右（编译器对 `Self == Self.Pointer.Target` 也原样输出）。

**开关与接线**：

- `SwiftDeclarationPrintConfiguration.protocolRequirementPlacement`，类型是新的 `ProtocolRequirementPlacement`（在 SwiftPrinting，与 `SwiftDeclarationMemberSortOrder` 放在一起；`.protocolWhereClause` 是默认值，另一个是 `.associatedTypes`）。默认值下输出逐字节不变。
- SwiftSectionKit 的 `InterfaceRequest.protocolRequirementPlacement`；CLI `interface --requirements-on-associated-types`；agent 插件的 skill 同批更新。
- 划分是 SwiftPrinting 里的 `ProtocolRequirementPartition`（package）：每条约束恰好进一个列表，列表内保持签名里的顺序。`printIncludedProtocolDefinition` 打印一个协议时只算一次，`renderProtocolDeclarationHeader` 和 `renderProtocolAssociatedTypes` 共用。认 `Self.X` 链的两个节点工具（`protocolSelfMemberNames`、`firstProtocolSelfMemberRoot(among:)`）在 SwiftDeclarationRendering 的 `Node+ProtocolSelf.swift`，附带修复也用它们。
- `associatedtype` 的继承子句只印约束的右侧（新增 `dumpProtocolContent(resolver:in:)`）。从协议 extension 推断出的 `~Swift.Copyable` 接在这些约束后面：`associatedtype Element: P, ~Swift.Copyable`。

**不动**：

- dump。dump 以信息完整为目标，约束写在哪不影响信息量。
- diff / evolution 的协议头永远按 `.protocolWhereClause` 打印。它们的 `associatedtype` 行是按名字逐行比较的单位，约束挪走而这些行不带约束就会丢；要带上就得让 diff 比较每个关联类型的约束，超出本提案范围。它们的打印器现在本来就只用默认配置（`InterfaceVersionUnit`），显式传值是为了日后接上配置时不丢约束。
- ABI snapshot / diff 模型。
- RuntimeViewer：拿到新字段和默认值，设置项另议。这个开关不是 `SwiftVisibilityOption`，标记模式（`marksOptionalContent`）下照配置打印，切换要重新打印，与 `usesModuleSelectors` 一样。

**附带修复（单独 commit，两种写法都受益）**：`GenericContext+Dump.swift` 的 `dumpProtocolMangledName` 打印约束右侧的类型时，把整棵类型树里的关联类型名全部收集起来串成一条链，复合类型因此被印成另一条约束：`Self.Second == [Self.First]` 印成 `Self.Second == Self.First`，`Self.Fifth: GenericBase<Self.First>` 印成 `Self.Fifth: Self.First`，`Self.Third == (Self.First, [Self.First])` 印成 `Self.Third == Self.First.First`，`Self.Sixth == [Self]` 印成 `Self.Sixth == [A]`。dump 和 interface 共用这个函数，自 2025-08-21 写下（`fedbf876`）就是这样。改为：类型本身是 `Self.A.B` 这样的链时照旧拼写；否则把整个类型交给 resolver 打印，打印前把协议的泛型参数换成 `.constrainedExistentialSelf`（两个打印器都把它拼作 `Self`），并去掉关联类型的协议限定（上游 `NodePrinter` 会把 `Self.Seventh.[Sequence]Element` 拼成 `Self.Seventh.Swift.Sequence.Element`）。

**验证**：

- 新的现场编译 fixture `ProtocolRequirementPlacementFixture`，覆盖：单个与多个协议、superclass、`AnyObject`、父类加协议、嵌套主语 `Self.X.Y`、same-type 到具体类型、两个关联类型之间、`Self == Self.X.Y`、继承来的关联类型、递归协议、复合类型右侧（含带协议限定的成员）。
- 两种写法的期望文本逐字断言（interface），复合类型右侧在 dump 与 interface 各断言一次。
- 语义往返：把两种写法印出的协议各自用同一模块名重新编译，读回 requirement signature，用通用的 requirement dump（demangler 的默认打印，不经被测的协议打印）逐条比较，必须与原二进制完全相同。这就是「规范化之后 ABI 一样」本身。
- diff 的协议头在 `.associatedTypes` 配置下仍与默认写法的协议头相同。
- `~Copyable` 与继承子句合并：Swift 6.4 fixture 新增 `ConstrainedSuppressedElementContainer`（`Swift64DeclarationShapeInterfaceTests`，需要 Swift 6.4 工具链，CI 不跑）。
- SwiftSectionKit 端到端：`DumpAndInterfaceRequestTests` 用 SymbolTestsCore 的 `ClassBoundGenericProtocol` 对比两种写法；CLI 侧 `CommandRequestMappingTests`。
- 现有快照测试不改一行即全绿，证明默认输出不变。

**落地步骤**（每步单独构建通过、测试通过后提交）：

1. 【已完成，`6b758d0e`】附带修复：先用现场编译的 fixture 写出复合类型右侧的复现测试（dump 与 interface 各一处，修复前红），再改 `dumpProtocolMangledName`。
2. 【已完成，`d618de54`】划分与 interface 接线：`ProtocolRequirementPlacement` 与划分逻辑、`SwiftDeclarationPrintConfiguration` 的新字段、协议头与关联类型行按划分打印、diff / evolution 固定集中写法；测试覆盖两种写法的期望文本、语义往返、diff 不丢约束。
3. 【已完成，`0aa75f70`】SwiftSectionKit 与 CLI：`InterfaceRequest` 的新字段、`interface --requirements-on-associated-types`、两侧的映射测试、agent 插件的 skill、CI 的套件过滤名单。
4. 【已完成，本提交】文档与全量验证：`ProjectEvolutionLog`；SwiftSectionKit 的调用方指南与模块文档不逐个列请求字段，不需要改。全量测试（`IntegrationTests` 除外）的结果记在演进账本这一节。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-10-20 | Created as Draft | interface 要能选择把约束集中写在协议的 `where` 子句，还是写到各自的关联类型上；前提是两种写法语义完全相同，因为二进制里看不出源码写在哪 |
| 2026-10-20 | 继承子句只收主语恰好是 `Self.X` 的约束，不照抄编译器的摆法 | 编译器在递归协议上把 `Self.Child.Leaf: Hashable` 印成 `associatedtype Leaf: Hashable`，改变了语义 |
| 2026-10-20 | 默认保持现在的写法 | 打开即改变每一份 interface 输出和快照 |
| 2026-10-20 | 只接 interface，dump 与 diff / evolution 不接 | dump 不为可读性取舍；diff 的关联类型行不带约束，接上会丢约束 |
| 2026-10-20 | 用户批准，开始实现；附带修复按方案同批做，单独一个 commit | 语义往返测试要覆盖复合类型右侧，否则只能把这类形状排除在外 |
| 2026-10-20 | 规则 2 不处理 inverse、same-shape 等种类，留在协议的 `where` 子句 | IRGen 不为关联类型发 inverse requirement（见 `SuppressedAssociatedTypeInference`），挪动这些种类没有收益，留在原处最保守 |
| 2026-10-20 | 往返测试的比对基准用通用 requirement dump，不经被测的协议打印 | 基准若依赖被测代码，两边一起错也会通过 |
| 2026-10-20 | `~Copyable` 合并的用例放进 Swift 6.4 fixture | SE-0503 的 `~Copyable` 关联类型只有 Swift 6.4 编得出来；`ProtocolRequirementPlacementFixture` 要在 CI 的旧工具链上编 |
| 2026-10-20 | diff / evolution 的协议头显式传 `.protocolWhereClause` | 它们的打印器现在只用默认配置，显式传值防止日后接上配置时约束无处可印 |
| 2026-10-20 | 实现完成，待合并 | 验证结果记在 ProjectEvolutionLog 本节；文档判断：SwiftSectionKit 的调用方指南与模块文档不逐个列请求字段，无需改动；没有引入需要登记术语表的新词 |
