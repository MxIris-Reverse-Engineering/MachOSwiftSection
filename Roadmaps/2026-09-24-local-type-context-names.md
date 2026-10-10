# 函数体里的局部类型丢了函数上下文（2026-09-24）

提案 [0050-symbolic-mangling-symbol-index](../Documentations/Evolutions/0050-symbolic-mangling-symbol-index.md) 的对照测试发现的问题：
`SymbolicDemangler` 从描述符还原函数体里声明的类型时，丢掉了函数那一层。

**当前状态（2026-10-11）：已修，见提案 [local-type-context-names](../Documentations/Evolutions/draft-local-type-context-names.md)。** 下面是 2026-09-24 的原始记录，保持原貌；它的推断有几处被后来的调查更正，列在文末「更正（2026-10-10）」。

## 现象

对照测试（`SymbolicManglingIndexTests.descriptorBuiltNamesAgreeWithTheCompilersSpelling`）拿 `_symbolic` 符号里编译器写下的
被引用者，逐个比对 `SymbolicDemangler.demangleContext` 从描述符还原的名字。macOS 26.7 的 AppKit 里被直接引用的 880 个类型与
协议描述符，878 个逐字一致，剩下 2 个都是局部类型：

| 从描述符还原 | 编译器写的 |
|---|---|
| `AppKit.NSWMDeferrableWMWindowTransaction.DeferralState` | `DeferralState #1 in AppKit.NSWMDeferrableWMWindowTransaction.deferCompletionUntil() -> () -> ()` |
| `(extension in AppKit):__C._NSLocalizedIndexedCollation.ObjectWrapper` | `ObjectWrapper #1 in (extension in AppKit):__C._NSLocalizedIndexedCollation.sortedArray(from: Swift.Array<Any>, collationStringSelector: ObjectiveC.Selector) -> Swift.Array<Any>` |

后果：局部类型被打印成外层类型的直接成员；同一个类型里两个函数各自声明的同名局部类型会解成同一个名字——和 2026-09-24
修掉的「同名 private 类型撞名」是同一种形状。

## 成因（推断，未单独验证）

局部类型的父级是一个代表外层函数的 anonymous context。和 private 类型的情况一样，编译器只在
`-enable-anonymous-context-mangled-names` 下才写出它的 mangled name，dyld shared cache 里它上面也查不到符号，于是
`SymbolicDemangler` 的 `.anonymous` 分支退回父级，函数和局部编号（`#1`）一起丢了。运行时名字那条路
（`RuntimeTypeNameDemangling`）同理：私有鉴别符索引里查不到这个匿名上下文，就把 `AnonymousContext("$…")` 换成父节点。

待核实：这两个类型描述符的父级确实是 anonymous context，且父级的父级是外层类型（或 extension）。

## 修复方向（未评估）

`_symbolic` 符号的被引用者已经写出了完整的局部上下文，`SymbolicManglingIndex.referentNode(of:in:)` 就能拿到。可以把
`AnonymousContextPrivateDiscriminatorIndex` 从「匿名上下文 → 私有鉴别符」推广成「匿名上下文里的类型 → 编译器给它的名字」，
让 `.anonymous` 分支按需重建 `privateDeclName`，或者「函数上下文 + `localDeclName`」。要先想清楚的：

- 一个函数的匿名上下文里可以有好几个局部类型（`#1`、`#2`），所以键得是类型描述符，不能是匿名上下文。
- 闭包、嵌套函数、泛型函数里的局部类型分别长什么样。
- interface 打印器和 RuntimeViewer 怎么显示这种名字。
- 没有 `_symbolic` 符号的局部类型（没有字段描述符、也没被引用过）仍然退回父级。

## 验收

- 对照测试里的 `withKnownIssue` 不再记录问题（到时它会自己报「已知问题没有出现」），删掉它后差异为空。
- 以 `DeferralState` 为锚点的回归测试，覆盖 `MachOFile`（cache）与进程内两条路径，修复前红、修复后绿。
- AppKit 的 `dump` / `interface` 对比：只有局部类型的名字变化。

## 关联

- 提案决策日志：「函数体里的局部类型：对照测试登记为已知问题，本提案不修」。
- [Internal/SymbolicManglingSymbols.md](../Documentations/Internal/SymbolicManglingSymbols.md)「边界」。
- [Internal/ProjectEvolutionLog.md](../Documentations/Internal/ProjectEvolutionLog.md) 2026-09-24 两节。

## 更正（2026-10-10）

RuntimeViewer 会话在 macOS 27.2 的 SwiftUI 上复现了这个问题并查清根因，转交过来修。对上面记录的更正：

- 「dyld shared cache 里它上面也查不到符号」只对 AppKit 成立。SwiftUI、SwiftUICore 在 cache 里保留了本地符号，匿名描述符的 `$s<上下文>MXX` 符号都在，进程内也读得到。当时的代码没有用它取名，只用 `first(of: .privateDeclName)` 从里面取鉴别符，取到的是外围 private 函数的，于是局部类型被伪造成 private 类型（`AccessibilityRotorInfo.(unknown context at _0306…).(IndexingWrappingGenerator in _0306…)`）。
- 「父级是 anonymous context，再上一层是外层类型」：父链确实是一串匿名上下文，而且是多层——类型自己一层、每个闭包一层、函数一层（`lib/IRGen/GenDecl.cpp` 的 `getAddrOfContextDescriptorForParent`）。
- 除了撞名，还有两个症状没记：上面那个伪造的 private 类型；以及成员符号用真名记录，跟错的名字永远对不上，成员静默丢失，带扩展上下文的成员（`~Copyable` 泛型参数让成员落在一个 inverse 约束扩展里）在 RuntimeViewer 里成了孤立的顶层 Ex。
- debug 构建也错：driver 只在 `-g -Onone` 时加 `-enable-anonymous-context-mangled-names`，描述符这时带着名字，但 2025-05 的 `be2f186e` 把匿名上下文改成「直接丢掉」之后，采用名字的那段逻辑只在外围函数恰好是 private 时才把函数接上。
- 修复方向里「键得是类型描述符，不能是匿名上下文」不必要：类型自己那一层匿名上下文是每个类型各有一个的（`getAddrOfAnonymousContextDescriptor(ofChild)`），按它做键就是按类型做键。
