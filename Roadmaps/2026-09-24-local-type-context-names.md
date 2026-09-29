# 函数体里的局部类型丢了函数上下文（2026-09-24）

提案 [0050-symbolic-mangling-symbol-index](../Documentations/Evolutions/0050-symbolic-mangling-symbol-index.md) 的对照测试发现的问题：
`SymbolicDemangler` 从描述符还原函数体里声明的类型时，丢掉了函数那一层。

**当前状态：只落记录，代码未改。** 用户裁定先记下来（「第二个先记下来」），修复批次另起。

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
