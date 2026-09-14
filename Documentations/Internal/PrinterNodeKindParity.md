# 打印器 node kind parity：判据、缺口与常驻测试

> 本文是实现说明：讲清 `SwiftPrinting` 与上游 `Demangling` 包 `NodePrinter` 之间的 node kind 缺口为什么会静默产出非法 Swift、每个缺口按什么判据处理、以及那个常驻测试怎么用、allowlist 怎么维护。
> 决策记录见提案 [draft-interface-printer-node-kind-parity](../Evolutions/draft-interface-printer-node-kind-parity.md)（编号落地时分配）。

## 失败模式：缺一个 case，输出就少一段，而且没人会发现

`InterfaceNodePrintable.dispatchPrintName` 依次问五个 `printNameIn*`，五个都返回 `false` 时**什么都不写、返回 `nil`**。所以一个没有 `case` 的 node kind，渲染结果是空字符串——不是报错，不是占位符，是什么都没有。

这种空串在输出里表现为语法残缺：

| 空串出现的位置 | 看起来像 |
|---|---|
| 泛型实参 | `Foundation.Predicate<>` |
| 泛型实参之一 | `MixedScalarAndPack<Swift.Int, >` |
| 返回类型 | `func definition(of: …) -> ` |
| 字段类型 | `var _storage: ` |
| enum payload | `case type()` |

三件事叠加，使它极难被发现：**没有异常**（渲染照常完成）、**dump 路径是对的**（它用上游 `NodePrinter`，368 个 case 全有，所以两条路径的差异只在 interface 一侧）、**输出量大**（一份 SwiftUI interface 十万行，肉眼扫不出一个 `<>`）。

`accessor function at N` 那次（见 [AccessorFunctionReferenceRendering.md](AccessorFunctionReferenceRendering.md)）就是同一个模式的第一例，当时按单点修掉了。这一批把它当作一类来处理。

## 判据：一个缺失 kind 归哪一类

**不要**照着上游的 `case` 列表逐条补。上游 368 个 case 对我们 76 个，差值里绝大多数是 entity 与 SIL kind——一个类型打印器本就不该处理它们。判据是三条，按顺序：

1. **能从节点树算出合法 Swift** → 渲染成**合法 Swift**，不照抄上游拼写。上游 `NodePrinter` 服务于调试 demangle，`Pack{…}`、`Self.X == Y` 这类写法在那里是对的，在 `.swiftinterface` 里不能编译。
2. **信息不在二进制里，不可恢复** → 照抄上游占位符，**逐字一致**。两条路径必须拼写相同，快照归一化也认这个串。
3. **本就不该出现在类型位置** → 不实现，但要**有测试证明它不出现**，而不是默认它不出现。这就是下面 allowlist 的作用。

## 这一批处理的缺口

| kind | 判据 | 渲染成 | SwiftUI 实测 |
|---|---|---|---|
| `.pack` | 1 | 元素逗号分隔，无 `Pack{}` 包装 | 718 处 |
| `.constrainedExistential` + `…RequirementList` + `…Self` | 1 | primary associated type 语法 `any P<Y>` | 22 处 |
| `.index` | 1 | 序号数字 | 3337 处 |
| `.opaqueTypeDescriptorSymbolicReference` | 2 | `opaque type symbolic reference 0x…` | 16 处 |

另外三处不是 kind 缺失，但属于同一类「interface 独有、dump 正确」的 parity 问题：

- **`printOpaqueType` 印错了孩子**：印 child 2（泛型实参表）而不是引用本身，于是单实参引用渲染成 conforming type 自己（`typealias B = ProbeClient.Outer`）——一个真实、全限定、错误的类型。改为**委托上游 printer**：child 0 是 entity 节点，类型打印器一个都不认，开写会印出 `<<opaque return type of >>`（中间是空的），比原状更糟；委托则天然与 dump 逐字一致。`.opaqueReturnTypeOf` 同理。
- **空泛型参数列表**：`printGenericSignature` 无条件写 `<`，extension 成员的参数全属于被扩展类型时，参数数为 0，印出 `init<>(windowID: String) where …`。上游同样无条件写，但 dump 路径从不走到这段代码，所以只有 interface 中招（122 处）。
- **dependent member 的 base 丢失**：`WritableKeyPath<A1, .Value>`。随 `.constrainedExistential` 修复连带消失（那棵树的返回类型原本整个是空的）。

### 为什么 `any P<Y>` 不需要查 protocol facts

`any P<…>` 在源码层**只能**用 primary associated type 语法写出来——Swift 不允许 `any P where …`。所以出现在 `constrainedExistential` 里的 same-type 约束，只可能来自那个语法，把约束的右侧读回来当实参即可，不必知道哪个关联类型是 primary。这与 opaque 类型那边的推断同源，理由写在 [OpaqueReturnTypeResolution.md](OpaqueReturnTypeResolution.md) §2.4。

需要 protocol facts 的只有**顺序**：多个 primary 时 requirement 列表是 canonical 排序而非声明顺序，`P<A, B>` 与 `P<B, A>` 从这里分不出来。那种情况降级为裸 `any P`，不猜——顺序错的实参列表是一个真实、错误、且能编译的类型。目前普查过的二进制里没有多约束样本；接 `ProtocolFactsResolver` 留作后续。

## 常驻测试：`NodeKindParityTests`

`Tests/SwiftPrintingTests/NodeKindParityTests.swift`。它是这一批真正的交付物——上面每一个缺口都是在十万行输出里用肉眼找了两遍找出来的，这个测试让下一个自己变红。

**做法是行为对比，不是 case 列表 diff**：遍历真实二进制的类型树，对每个节点用两个 printer 各印一次，报告「我们印空、上游印非空」的最深节点。不会因上游增删 case 而失效。

三个数据源缺一不可：field records 与 associated-type witness 直接携带类型树；**符号**携带方法签名，而返回类型和参数类型在那里面——`-> ` 这个症状没有别的来源，只用前两个源的普查会对 `.constrainedExistential` 报一个干净的假结论。

两级过滤：先只保留渲染带空串指纹（`<>`、`<, `、行尾 `-> `）的树，再在其中定位**最深**的空节点。没有第二级的话，一个缺口会连带指控它整条祖先链（`.type`、`.typeList`、`.boundGenericStructure`……都是我们处理了的 kind）。

### allowlist 怎么维护

`nonTypePositionKinds` 列出「合法地印空」的 kind 及理由，不在表上的印空即失败。**只减不增**是本意：加一条等于声称某个 kind 永远不需要在类型内部打印，这个声称要经得起读。

当前条目及理由：`.function` / `.variable` / `.extension`（entity scaffolding，各自有专门的 printer）、`.argumentTuple`（函数签名结构，`FunctionNodePrinter` 管）、`.tupleElementName`（`printTuple` 内联消费，从不单独分发）、`.firstElementMarker` / `.number`（function-signature specialization 元数据，不是类型）。

### 它确实会红

摘掉 `.pack` 的 case 跑一次，退出码 1，消息直接点名 `Pack ×716` 并给出上游拼写。**新增或修改这个测试后必须做一次这个验证**——一个不会失败的 parity 测试比没有更糟，因为它把「没人看」伪装成「已验证」。

## 不在这一批里的

**extension 头部的空尖括号**（`extension Swift.Optional<>.ChildTableColumn`，SwiftUI 56 处）：改动前后逐字相同，走的是 extension 头部渲染路径（上游 printer 配 `.interfaceTypeBuilderOnly`），与类型打印器的 kind 覆盖无关，被这一批的普查顺带捞出来而已。

**不进 [ReviewAdjudications.md](ReviewAdjudications.md)**——那张表收的是判定「不修 / 误报」的发现，而这一条是确认为真、该修、只是不属于本批范围。它记在这里和提案的同名小节里，等一个单独的批次。当前状态：SwiftUI interface 56 处，全部在 `extension` 行，`grep -E '^extension.*<>'` 可复现。

**多 primary associated type 的 `any P<A, B>` 排序**：降级为裸 `any P`，理由见上。需要接 `ProtocolFactsResolver` 才能定序，没有样本，同样等单独批次。
