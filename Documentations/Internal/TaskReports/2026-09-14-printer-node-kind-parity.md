# 2026-09-14 打印器 node kind parity：从一处 opaque 占位符查到 155 处非法输出

## 起点

用户问 `accessor function at N` 与 `opaque return type of` 分别什么情况出现。答复里提到一条既有缺陷：依赖镜像定位不到时，interface 路径的 `printOpaqueType` 会把 conforming type 印成 witness（`typealias B = ProbeClient.Outer`），提案 0033 记录过但留给「打印器的下一次整理」。用户说「那 interface 也加上这个吧」。

## 范围怎么从一处变成一批

按全局规约（确认为真的问题必须横向排查同类）向用户给了两个选项：只修 opaque 一处，或做一次定向审计把同类一次修干净。用户选后者。

这个选择是对的，而且理由是实测出来的：**opaque 那一处在宿主 cache 上根本不触发**（`accessor function at` 与 `opaque return type of` 在 macOS 26.6 的 SwiftUI 上都是 0 处），而同一个失败模式正在别处产出错误输出。只修 opaque 会全部漏掉。

## 关键调研发现

**失败模式**：`dispatchPrintName` 依次问五个 `printNameIn*`，全部返回 `false` 时什么都不写、静默返回 nil。没有 `case` 的 node kind 渲染成空字符串——不报错、不留占位符。dump 路径用上游 `NodePrinter`（368 个 case）所以是对的，差异只在 interface 一侧，且一份 SwiftUI interface 十万行，肉眼扫不出来。

**静态比对没有用**：上游 368 个 case 对我们 76 个，差值 292 里绝大多数是 entity 与 SIL kind，一个类型打印器本就不该处理。差值本身不说明任何问题，必须实测「哪些 kind 真的会到达类型位置」。

**实测口径**：跑真实二进制，grep 空串在输出里的语法指纹（`<>`、`<, `、行尾 `-> `、悬空冒号），再用 dump 路径对同一处的渲染作对照。macOS 26.6 宿主 cache 的 SwiftUI，四类症状：

| 症状 | 处数 | dump | interface |
|---|---|---|---|
| `<>` | 201 | `Predicate<Pack{Foundation.URL}>` | `Predicate<>` |
| `-> `（空返回类型） | 8 | `-> any ValidatingTextAttributeDefinition<…>` | `-> ` |
| `init<>()` | 122 | —（dump 不走这段代码） | `init<>(windowID: String) where …` |
| `<A1, .Value>` | 1 | `A1.Value` | `.Value` |

悬空冒号 17 处全是注释行的正常结尾，误报。

**一个把方案形状改掉的发现**：原计划给 `.opaqueReturnTypeOf` 补 `<<…>>` 前后缀，实际会印出 `<<opaque return type of >>`——中间是空的，比原状更糟。因为它的 child 是 entity 节点（`.function` / `.variable` / `.extension` / `.static` / `.getter`），这些 `SwiftPrinting` 一个都没有。改走委托上游 printer，拼写天然与 dump 逐字一致，也不必复刻 entity 打印那一整块（上游最复杂的部分）。项目已有这个模式的先例（`SwiftDeclarationPrinter+Headers.swift:160`）。

**一个省掉跨模块 delegate 的发现**：`any P<Y>` 需要知道哪个关联类型是 primary，而 `BuiltinStandardLibraryProtocolFacts` 在 SwiftInterface，打印器在 SwiftPrinting，依赖方向是反的。但 `any P<…>` 在源码层只能用 primary associated type 语法写出来（Swift 不允许 `any P where …`），所以出现在这里的 same-type 约束必然来自那个语法，读回右侧即可，不必查 facts。与 opaque 约束还原同源的推理。只有多 primary 的排序才真需要 facts，那种情况降级为裸 `any P`。

## 执行

四个 kind（`.pack` / `.index` / `.opaqueTypeDescriptorSymbolicReference` / `.constrainedExistential` 三件套）+ 三处逻辑修正（`printOpaqueType` 与 `.opaqueReturnTypeOf` 改委托、空泛型参数列表不印括号）。判据是三档：能算出合法 Swift 的算对（不照抄上游的 `Pack{…}` / `Self.X == Y`），不可恢复的照抄上游占位符逐字一致，不该出现在类型位置的不实现但要有测试证明它不出现。

## 验证

**端到端**（同一份 SwiftUI，两侧 release CLI）：

| 症状 | before | after |
|---|---|---|
| `<>` | 201 | 56 |
| `init<>` | 122 | 0 |
| `-> `（空返回） | 8 | 0 |
| `<, ` | 1 | 0 |
| `<A1, .Value>` | 1 | 0 |

行数两侧均 106903，无结构性变化。剩余 56 处全部在 `extension` 行，且**改动前后逐字相同**——另一条路径的既有问题，不属于本批。

**dump 路径不受影响**：SwiftUICore 的 dump 两侧逐字节相同（它走上游 printer，本就不该变）。

**测试**：`SwiftPrintingTests` 29、`SwiftDumpTests` 80、`SwiftInterfaceTests` 177，原始退出码均为 0。`SymbolTestsCoreInterfaceSnapshotTests` 的基线重录，diff 恰好 5 增 5 删，全部是 pack 修复（含一处 `MixedScalarAndPack<Swift.Int, >` 的悬空逗号），无夹带。

**常驻测试自身能变红**：摘掉 `.pack` 的 case 跑一次，退出码 1，消息点名 `Pack ×716`。一个不会失败的 parity 测试比没有更糟，所以这一步是必做项而非可选项。

## 追加：`repeat each`（用户追问后）

**这一批第一轮的验证漏判了一处。** 快照 diff 里 `VariadicPack<>` → `VariadicPack<repeat A>` 被当成了「修好」的证据，还写进了本报告——但源码是 `VariadicPack<repeat each Element>`，`repeat A` 同样不能编译。用户追问「repeat each 这种语法修了吗」才发现。

常驻测试也抓不到它：它找的是「印空」，这个是「印了但不完整」。

补修三处中的两处，第三处在下面的遗留里：

- **使用位置**：`repeat (each A)`。从语言约束恢复——`repeat` 的 pattern 必须展开至少一个 pack，所以 pattern 里只有一个 distinct 参数时那个参数必然是它；多个则不下结论。括号无条件加，因为 `swiftc -typecheck` 实测 `repeat each T.Type` 与 `repeat each T?` 都被拒（`'each' cannot be applied to non-pack type`），而括号形式在四种位置全合法。
- **声明位置**：两个叠加的 bug，各自单独不可见。`dependentGenericParamType` 的 children 是 (depth, index)，比较写反了——depth == index 时照样成立，也就是所有顶层泛型；而循环变量 `gpDepth` 是 count 节点的位置不是真实 depth，名字那行早就用 `depths` 解析了（所以叫 `A1`），pack 查询没有。嵌套一层的 pack 参数于是印成 `<A1>`，紧挨着自己的 `repeat (each A1)`。

现场编译了两个 dylib 做复现（`Outer<T>.f<each A1>` 与顶层 `acceptsAny<each A>`）：depth 0 那个修前修后都对，depth 1 那个只有修后才对——这正是 bug 能长期隐身的原因。

验证：288 tests / 44 suites 退出码 0；SwiftUI `static func acceptsAny<each A1>(_: repeat (each A1).Type)`；SwiftUI dump 与本批基线逐字节相同；行数仍 106903。

## 留下的东西

真正的交付物不是那 155 处修复，是 `NodeKindParityTests`：遍历真实二进制的类型树，逐节点用两个 printer 各印一次，断言不存在「我们印空、上游印非空」的节点。行为对比而非 case 列表 diff，不会因上游增删 case 失效。allowlist（`nonTypePositionKinds`）按「只减不增」维护，每条要写清为什么那个 kind 不是类型位置。

两级过滤是必要的：先按空串指纹筛树，再定位最深的空节点——没有第二级，一个缺口会连带指控它整条祖先链，首轮就报了 `Type` / `TypeList` / `OpaqueType` 这些我们明明处理了的 kind。三个数据源也缺一不可，`-> ` 这个症状只有符号（方法签名）这一个来源，只用 field record 与 associated type 的普查会对 `.constrainedExistential` 报一个干净的假结论。

## 遗留

- **extension 头部空尖括号** 56 处（`extension Swift.Optional<>.ChildTableColumn`）：确认为真、该修、不在本批，走的是另一条渲染路径。
- **多 primary associated type 的排序**：降级为裸 `any P`，接 `ProtocolFactsResolver` 才能定序，当前无样本。
- **函数 where 子句里的 pack 约束**：`where A1: StyleCtx` 应为 `where repeat each A1: StyleCtx`。类型那侧是对的（requirement subject 在 mangling 里带 `packExpansion`），函数的 subject 是裸参数，要补得在 requirement 这一级包 `repeat` 并带一份签名级 pack 集合——与已修的两处都不是同一个机制。
