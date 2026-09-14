# Draft - interface 打印器与上游 NodePrinter 的 node kind parity

- **状态**: In Progress
- **创建日期**: 2026-09-14
- **最后更新**: 2026-09-14
- **所属愿景**: 无
- **关联提案**: [0033](0033-by-name-opaque-reference-expansion.md)（它的决策日志里记下了 `printOpaqueType` 会把 conformer 印成 witness，明说「留给打印器的下一次整理」——就是这一批）
- **实现分支 / PR**: `feature/printer-node-kind-parity`（worktree `.worktrees/MachOSwiftSection-PrinterNodeKindParity`，从 `next` 切出）
- **配套文档**: [AccessorFunctionReferenceRendering.md](../Internal/AccessorFunctionReferenceRendering.md)（`accessor function at N` 那次补 case 的先例与 A/B 数据）、[OpaqueReturnTypeResolution.md](../Internal/OpaqueReturnTypeResolution.md)（primary associated type 的推断链，本批复用）

## 摘要

`SwiftPrinting` 是 interface 路径的类型打印器，与上游 `Demangling` 包的 `NodePrinter` 是两套独立实现。上游有 368 个 `case`，`SwiftPrinting` 有 76 个——它只需要类型位置上的 kind，所以这个差值本身不说明问题。真正的问题是**缺失时的行为**：`InterfaceNodePrintable.dispatchPrintName` 依次问五个 `printNameIn*`，全部返回 `false` 就什么都不写、静默返回 `nil`。于是一个没有 `case` 的 node kind 印出来是**空字符串**，在输出里表现为语法残缺的、看不出来的非法 Swift。

`dump` 路径用的是上游 `NodePrinter`，所以同一个二进制的同一个类型，两条路径印出来不一样，而错的是 interface 那条。

实测于 macOS 26.6 宿主 cache 的 SwiftUI（interface 106903 行 / dump 111009 行，2026-09-14）：

| 症状 | 处数 | 成因 | dump 印什么 | interface 印什么 |
|---|---|---|---|---|
| `<>` 空泛型实参 | 201 | `.pack` 缺 case | `Foundation.Predicate<Pack{Foundation.URL}>` | `Foundation.Predicate<>` |
| `-> ` 空返回类型 | 8 | `.constrainedExistential` 系列缺 case | `-> any SwiftUI.ValidatingTextAttributeDefinition<Self.ValidationToken == ...Constraints>` | `-> ` |
| `init<>()` 空泛型参数列表 | 122 | 参数列表为空时仍印尖括号 | — | `init<>(windowID: Swift.String) where ...` |
| `<A1, .Value>` 以点开头的残缺类型 | 1 | dependent member type 的 base 丢失 | `A1.Value` | `.Value` |

第三、四行成因与前两行不同（不是 kind 缺失），但同属「interface 路径独有、dump 路径正确」的打印器 parity 问题，本批一并修。

opaque 那条线是同一个模式的另一处：`printOpaqueType` 印的是节点的 child 2（泛型实参表）而不是引用本身，0033 已记录它在独立文件上会把 conformer 印成 witness（`typealias B = ProbeClient.Outer`），当时没修。

目标：把「上游有 case、我们没有 → 静默空串」这个模式一次修干净，并补上一个**能变红的常驻 parity 测试**，让同类问题以后自己暴露而不是靠肉眼在十万行输出里找。

## 方案

### 判据：每个缺失 kind 归哪一类

三类，按优先级判断：

1. **能从节点树算出合法 Swift** → 渲染成合法 Swift，**不照抄上游拼写**。上游 `NodePrinter` 是调试用的 demangle 打印器，`Pack{...}`、`Self.X == Y` 这些写法本身就不是合法 Swift；interface 的产物要可编译，判据不同。
2. **信息不在二进制里，不可恢复** → 照抄上游占位符，**逐字一致**。先例是 `accessor function at N`（`NodePrintable.swift:86`，注释里写明「mirror the Demangling NodePrinter fallback verbatim」），理由是 dump/interface 两路拼写必须一致、快照归一化认这个串。
3. **本就不该出现在类型位置** → 不实现，但要有测试证明它确实不出现，而不是默认它不出现。

### 已确证的缺口

| kind | 归类 | 渲染成 | 依据 |
|---|---|---|---|
| `.pack` | 1 | pack 元素逗号分隔展开：`Predicate<Foundation.URL>` | 源码里写的就是 `Predicate<each Input>` 实例化成 `Predicate<URL>`，实参完整在节点树里 |
| `.constrainedExistential` + `.constrainedExistentialRequirementList` + `.constrainedExistentialSelf` | 1 | primary associated type 语法：`any P<Y>` | 见下方「参数化存在类型怎么渲染」 |
| `.opaqueTypeDescriptorSymbolicReference` | 2 | `opaque type symbolic reference 0x…` | 上游 `NodePrinter.swift:564`；cache 路径下 `opaqueType` 的 child 0 |
| `.index` | 1 | 数字 | 上游 `NodePrinter.swift:488`；`opaqueType` 的 child 1（那个 `.0` 序号） |

### 参数化存在类型怎么渲染

`any P<Self.X == Y>` 要还原成 `any P<Y>`，需要知道 `X` 是不是 `P` 的 primary associated type、是第几个。**这与线 A 的 opaque 约束还原是同一道题**，`SwiftInterfaceBuilderOpaqueTypeProvider` 那套推断链（anchor 身份比对 → refine 闭包 → 内置表 `BuiltinStandardLibraryProtocolFacts`）已经解过，本批复用，不另起一套。

降级规则沿用那边的「宁缺毋滥」：约束的关联类型不是 primary、或顺序推不出来时，**不猜尖括号**，退回 `any P` 并把丢掉的约束记为降级（走 `SwiftIndexEvents`），而不是印一个真实但错误的约束。`any P` 比 `any P<错的>` 好，也比现在的空串好。

### 探针实际报出来的（已完成）

静态比对只能证明「上游有」，不能证明「实际会出现」，所以候选清单不预先实现，交给探针回答。实测于 macOS 26.6 宿主 cache 的 SwiftUI：

| 探针报告 | 裁决 |
|---|---|
| `Pack` ×718 | 真缺口，判据 1 |
| `Index` ×3337 | 真缺口，判据 1 |
| `OpaqueTypeDescriptorSymbolicReference` ×16 | 真缺口，判据 2 |
| `ConstrainedExistentialSelf` ×11、`ConstrainedExistentialRequirementList` ×11 | 真缺口，判据 1（`.constrainedExistential` 本身被「最深空节点」过滤器挡住，一并补） |
| `ArgumentTuple` ×177、`Variable` ×122、`Extension` ×93、`TupleElementName` ×84、`Function` ×18、`FirstElementMarker` / `Number` ×14 | 判据 3，进 allowlist——entity scaffolding 与 function-signature specialization 元数据，各有专门的 printer 或被内联消费 |
| `Type` ×21、`TypeList` ×18、`OpaqueType` ×5（首轮） | 连锁假阳性，加「最深空节点」过滤器后消失 |

静态候选里其余那些（`.sugared*`、`.errorType`、`.retroactiveConformance`、`.anonymousContext`、`.builtinFixedArray`、`.metatypeRepresentation`、`.assocTypePath`、`.typeSymbolicReference` …）**一个都没出现**，按判据 3 不实现；常驻测试会在它们哪天真的出现时变红。这正是不照着 case 列表补的理由。

### opaque 的四处

`Sources/SwiftPrinting/NodePrintables/TypeNodePrintable.swift:68` 的 `printOpaqueType` 现在是 `await printOptional(name[safeChild: 2])`——只印实参表。这行是 commit `798bca8c`「Fix Interface missing type list of opaque type」注释掉 `printFirstChild` 换上的：当时的观察对（实参丢了），修法错（把打印对象从「引用」换成了「实参表」，于是实参表被当类型印出来）。0033 之后能定位的引用都由 `OpaqueTypeRewriter` 展开、实参随展开正确出现，child 2 这条路没有存在意义了。

但**不能简单改回 `printFirstChild`**：child 0 在独立文件上是 `.opaqueReturnTypeOf`，它的 child 是一个 entity 节点（`.function` / `.variable` / `.extension` / `.static` / `.getter` …），这些 kind `SwiftPrinting` **一个都没有**（它是类型打印器，entity 打印是上游 `NodePrinter` 里最复杂的一块）。照搬会印出 `<<opaque return type of >>`，中间是空的，比现状更糟。

所以这一处走**委托**：无法展开时把这棵子树交给上游 printer（`node.print(using:)`），把结果写进 target。项目里已有这个模式的先例——`SwiftDeclarationPrinter+Headers.swift:160` 的 `currentTypeNode.print(using: .interfaceTypeBuilderOnly)`。好处是拼写与 dump 天然逐字一致（同一个 printer），且不必在 `SwiftPrinting` 里复刻 entity 打印。

连带仍需在 `SwiftPrinting` 补的只有 `.index` 与 `.opaqueTypeDescriptorSymbolicReference` 两个（cache 路径下 child 0 是后者，不经过 `.opaqueReturnTypeOf`）。

**明确不动**：`printOpaqueReturnType`（`some` 的正常打印，走 delegate，另一条路）、`OpaqueTypeRewriter` 与整个展开链、dump 路径。

### 两类额外 bug

- **空泛型参数列表**（122 处）：泛型参数列表为空时不应印 `<>`。位置在函数/初始化器的签名打印，改成列表为空即整段省略。注意与「有参数但印不出来」区分开——后者是 kind 缺失，修法不同，不能用「为空就省略」把它掩盖掉。
- **dependent member base 丢失**（1 处）：`WritableKeyPath<A1, .Value>` 少了 base。`dependentMemberTypeDepth` 的处理里 `shouldPrintContext` 在深度 > 0 时返回 `false`，疑似是这里吃掉了 base，待定位确认后再定修法。

### 实施顺序

1. **审计探针**（`Tests/SwiftPrintingTests/`，照 `RealThunkShapeProbe` 的 `@Suite(.disabled("Research probe — ..."))` 模式）：遍历真实二进制里所有类型节点树，逐节点用两个 printer 各印一次，报告「`SwiftPrinting` 为空而上游非空」的节点 kind 与样本。这是行为对比而非列表对比，不会因上游增删 case 而失效。
2. 按判据把探针产出的 kind 归类、实现。
3. opaque 那一处委托 + 两个 kind。
4. 两类额外 bug。
5. 探针转常驻测试（见下）。

### 测试

- **常驻 parity 测试**（探针去掉 `.disabled`，改成断言）：对 fixture 与宿主 cache，断言不存在「我们印空、上游印非空」的节点。这是本批的核心资产——它让同类问题以后自己变红。按 `ExclusiveImageAccess` 的规矩声明镜像独占。
- **症状回归**：SwiftUI interface 输出里 `<>`、行尾 `-> `、`<, `、`init<>` 计数归零，且**逐项确认归零是因为印对了**而不是因为整段没印。
- `CrossImageOpaqueReferenceTests` 补第四个测试：interface 路径 + 不给搜索路径，断言印出 `opaque return type of` 且不含 `typealias B = ProbeClient.`（现有三个测试覆盖了 dump±搜索路径与 interface+搜索路径，缺的正是这一格）。
- **A/B**：按 0033 的先例跑标准样本整文件 diff，确认只有该变的行变。本批触及打印器主路径，按 AGENTS.md 属于「touching demangling, printing」，跑完整的 rendering A/B verification。

### 文档

`Documentations/Internal/` 新增一篇实现说明（打印器 parity 的判据与常驻测试怎么用）；`ProjectEvolutionLog.md` 新一节；任务报告；`Documentations/README.md` 索引。探针判定为「不出现在类型位置」的 kind 登记到已裁决清单。

AGENTS.md 是否新增一条默认（「给 `SwiftPrinting` 加 kind 前先查上游 parity」）待定——先看常驻测试是否已经足以兜住，能兜住就不占 AGENTS.md 的常驻空间。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-09-14 | 从「只修 `printOpaqueType` 一处」扩到全面 parity 审计 | 用户在两个选项间选了审计。随后的实测证明这是对的：opaque 那一处在宿主 cache 上根本不触发，而同一个模式在 `.pack`（201 处）和 `.constrainedExistential`（8 处）上正在产出错误输出，只修 opaque 会全部漏掉 |
| 2026-09-14 | 能算对的渲染成合法 Swift，不照抄上游拼写 | 用户选择。上游 `NodePrinter` 是调试打印器，`Pack{...}` / `Self.X == Y` 不是合法 Swift；interface 的产物要可编译，判据不同。不可恢复的仍照抄（`accessor function at N` 先例） |
| 2026-09-14 | 两类非 kind 缺失的 bug 一并修 | 用户选择。同属「interface 独有、dump 正确」的打印器 parity，分批修等于让已知的非法输出多存在一轮 |
| 2026-09-14 | opaque 那一处走委托而非补 case | 补 case 需要在 `SwiftPrinting` 里复刻整套 entity 打印（`.function` / `.extension` / `.variable` / `.static` / `.getter` …，上游最复杂的一块），而那些 kind 只在这个占位符文本里出现。委托拼写天然与 dump 一致，且项目已有先例 |
| 2026-09-14 | 候选 kind 先探针后实现，不预先实现 | 静态比对只能证明「上游有」，不能证明「实际会出现」。为想象中的场景写代码，既无法验证也无法维护 |
| 2026-09-14 | 参数化存在类型复用线 A 的 primary associated type 推断 | 同一道题（约束 → 尖括号语法），那边已经解过并踩完坑；降级规则也沿用「宁缺毋滥」 |
| 2026-09-14 | Draft → In Progress | 用户批准，开始实施 |
| 2026-09-14 | `any P<Y>` 不经 `NodePrintableDelegate` 注入 protocol facts | 实施中发现 `BuiltinStandardLibraryProtocolFacts` 在 SwiftInterface、打印器在 SwiftPrinting，依赖方向是反的，原以为要新增一个跨模块 resolver 角色。但 `any P<…>` 在源码层只能用 primary associated type 语法写出，约束必然来自那个语法，读回右侧即可——只有多 primary 的排序才真需要 facts，那种情况降级为裸 `any P`。跨模块改动因此整个省掉 |
| 2026-09-14 | opaque 两处改委托上游 printer，而非补 entity kind | 补 case 要在 `SwiftPrinting` 复刻整套 entity 打印（child 0 是 `.function` / `.variable` / `.extension` …，上游最复杂的一块），且开写会印出中间为空的 `<<opaque return type of >>`，比原状更糟。委托则与 dump 逐字一致，项目已有先例 |
| 2026-09-14 | 空泛型参数列表的修法定为「参数数为 0 即整段不印」 | 上游同样无条件写 `<`，但 dump 路径从不走到这段代码（实测 dump 侧 `<>` 为 0 处），所以这是 interface 独有症状，按 interface 的可编译目标修 |
| 2026-09-14 | extension 头部空尖括号 56 处不纳入本批 | 改动前后逐字相同，走 extension 头部渲染路径（上游 printer 配 `.interfaceTypeBuilderOnly`），与类型打印器的 kind 覆盖无关。确认为真、该修，但属于另一个批次；不进 `ReviewAdjudications.md`（那是「不修 / 误报」的表） |
