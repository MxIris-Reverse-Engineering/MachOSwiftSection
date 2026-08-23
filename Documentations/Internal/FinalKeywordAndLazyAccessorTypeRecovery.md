# `final` 关键字还原与 lazy var 访问器类型：实现说明

> 配套提案见 [0006](../Evolutions/0006-final-keyword-and-lazy-accessor-type-recovery.md)（issue #106 第 1、4 点）。
> 本文记录实际落地的实现、与提案的差异，以及当前覆盖范围与已知降级。面向维护者。姊妹篇：[ClassMemberKeywordRecovery.md](ClassMemberKeywordRecovery.md)（`class`/`static` 还原，同一条 ABI 事实的另一面）。

## 背景与目标

class 成员是否 `final` 决定调用方走 dispatch thunk 还是直接符号，重建 `.swiftinterface` 时写错直接断链接，而 dump 此前完全不区分。判据与 `isClassMember` 同源：**成员有 vtable method descriptor ⇒ 非 final；在证据充分的前提下没有 ⇒ final**。同批修正 lazy var 的类型渲染：field record 里存的是 `Optional` 存储类型，调用方看到的是 getter 的非 Optional 类型。完整动机与测量数据见提案。

## 关键设计决策

**核心不是新解析，是停止丢弃已解析的数据。** stored `var` 的 accessor 符号组早就在 `DefinitionBuilder.variables` 里完成了 method descriptor / vtable slot 解析，只是被 `fieldNames` 去重整组扔掉（避免属性打印两次）。实现把它改成 `variablesProduct`，被抑制的组以 `storedPropertyAccessorsByFieldName` 交还，`TypeDefinition.index` 将其折回 `FieldDefinition.accessors`——`final` 判定、stored var 的 vtable 注释、lazy 的访问器类型三件事都吃这一份数据。

**join key 必须剥掉 `Tu` 的 `.asyncFunctionPointer` 标记（`memberJoinKey`，OverrideSymbolMatcher.swift）。** async 方法的 method descriptor 的 `implementation` 指向 async-function-pointer 常量（`Tu` 符号），其 demangled 树是 `global([asyncFunctionPointer, function(...)])`，而成员符号树是 `global([function(...)])`——按整树结构键 join 永远 miss。这个 miss 在本提案之前就存在（表现为 async 成员没有 vtable 注释、async override 丢 `override` 关键字，都不显眼），`final` 标记让它变成「被子类 override 的方法被标 `final`」的显性错误才被抓到。剥标记后三个症状一起修复。**下次给 join 加新符号形态时，先想它是不是又一个 wrapper-marker 形态**（`needsSkipFirstNodeKinds` 里的 `.asyncSuspendResumePartialFunction`、`.mergedFunction` 是同族；merged function 已由 DefinitionBuilder 的专门去重处理）。

**`@objc` 且无 descriptor ⇒ `@objc dynamic`，绝不标 `final`。** `@objc dynamic` 成员经 objc_msgSend 派发，没有 vtable 条目，但完全可覆写——按裸判据必然误标。模型路径在 `applyThunkAttributes` 之后标记并按 `attributes.contains(.objc)` 排除（这决定了标记块必须排在 thunk 归因之后、`orderedMembers` 构建之前——OrderedMember 持有值拷贝，晚了改不动）；dump 路径用 thunk 成员名集合做同样的排除。非 dynamic 的 `@objc` 成员有 Swift vtable 条目，本来就被 descriptor 判据排除，不受影响。

**证据门是四层的，宁缺勿错。** （a）只有非 actor class 且 `vTableDescriptorHeader != nil` 才可能标记——actor 不可子类化，没 header 的类与 final class 不可分；（b）stored 属性还要求 accessor 组确实 join 上（`accessors.isEmpty` ⇒ 不标——符号被 strip 时缺席不是证据）；（c）`@objc` 排除如上；（d）**`Tq` method-descriptor 符号作负证据**——成员名存在 `Tq` 符号即证明 vtable 条目在场，绝不标 `final`，无论地址 join 说什么。（d）是在真实二进制上抓到的：SourceEditor 把 1128 个空实现 ICF 折叠到同一地址（`SourceEditorView.elide` 等五个类成员在内），descriptor→implementation-symbol 的地址 join 在这种地址上配不上对，函数没有 accessor-join 那样的门，全体误标 `final`；而 `Tq` 是每成员一个、地址唯一的数据符号，不受折叠影响。函数与属性按成员名匹配（重载中任一带 `Tq` 即全组不标——保守方向）；下标共名，按 `.subscript` 子树的结构键精确匹配（与 `DefinitionBuilder.subscripts` 的分组键同一抽取，第一版「任一下标 `Tq` 即全部不标」把 fixture 里合法的 `final subscript` 一起挡了）。任何一层不满足都静默降级为不打 `final`。回归钉死在 `FinalKeywordICFRegressionTests`（环境门控于 Xcode 的 SourceEditor 在场）。

**final class 的成员会获得成员级 `final`，这是接受的行为而非 bug。** final class 因 designated init 的 vtable 条目仍带 vtable header（实测 `Enums.SinglePayloadBoxClass`），门挡不住它。类级 `final` 没有 ABI 位（ClassMemberKeywordRecovery.md 查证过），成员级标记如实反映「无动态派发条目」，对重建场景的链接语义恰好正确；输出比源码啰嗦（源码里 final class 的成员不写 `final`），但诚实。

**stored `let` 不标 `final`。** `let` 本就不可覆写（不会进 vtable，issue 实测 1156 个 stored let 零 dispatch thunk 无一例外），标了是纯噪声；resilient 模块的调用方对 `let` 也不产生 thunk 调用，平凡声明不破坏链接。

**lazy 类型优先取 getter node，回退保持存储类型。** `printThrowingField` 的取型顺序：特化替换节点（specialized 定义，会解析泛型参数）＞ lazy 的 `accessorTypeNode`（getter 符号的类型子节点）＞ field record 存储类型。提案里「getter 缺失时剥一层 Optional」的回退没有实现——getter 缺失意味着符号被 strip，此时保持存储类型是诚实回退，且省掉一个要处理 sugar 形态的 Optional 剥离器。

## 模块结构

```
Sources/SwiftDeclaration/Components/Definitions/
├── FieldDefinition.swift        # + accessors / accessorTypeNode / isFinal / hasVTableAccessor
├── VariableDefinition.swift     # + isFinal（Function/Subscript 同形）
├── DefinitionBuilder.swift      # variables → variablesProduct（交还被抑制的 accessor 组）
├── TypeDefinition.swift         # index()：折回 accessor 组、证据门、final 标记块
└── OverrideSymbolMatcher.swift  # + memberJoinKey（Tu 标记剥离）
Sources/SwiftPrinting/
├── SwiftDeclarationPrinter+Members.swift  # printThrowingField：final 关键字 + fieldTypeNode 取型
├── SwiftDeclarationPrinter+Headers.swift  # renderModelFields：stored var 的 vtable 注释
├── SwiftDeclarationPrinter.swift          # isFinal 传入三个 node printer
└── NodePrinter/{Variable,Function,Subscript}NodePrinter.swift  # printRoot 写 "final "
Sources/SwiftDump/
├── Protocols/TypedDumper.swift   # fieldDeclarationKeywords + isFinal 参数
└── Dumper/ClassDumper.swift      # 名字级 join（vtableAccessorFieldNames / storedAccessorFieldNames）
```

`Keyword.Swift` 增加 `final`；CLI 仅 `--emit-vtable-offsets` 帮助文案更新。

## 与提案的差异

- dump 路径的 lazy 类型**保持存储真相**（`lazy var x: Swift.String?`），不取访问器类型——dump 是原始视图，其 `[Getter]` 符号列表已如实展示访问器类型；提案落地步骤 5 的「lazy 两路对齐」仅 `final` 关键字对齐。
- 「剥一层 Optional」回退未实现（见上）。
- 提案未预见的三项：async join 修复（连带找回 `override` 与 vtable 注释）、`@objc dynamic` 排除、final class 的成员级标记，均记录在提案决策日志。

## 验证

- `Tests/SwiftInterfaceTests/FinalMemberRecoveryTests.swift`——针对 fixture 矩阵类 `VTableEntryVariants.FinalMembersTest`（final/plain × 存储/lazy/计算属性/方法/下标全组合）的五个用例：渲染层 final 配对、lazy 访问器类型、stored var 的 vtable 注释邻接性、模型层 isFinal/accessors/accessorTypeNode 事实。
- `Tests/SwiftInterfaceTests/FinalKeywordICFRegressionTests.swift`——对 Xcode 真实 `SourceEditor.framework`（issue #106 的原始对象）的回归：ICF 折叠地址上带 `Tq` 的成员（`elide` 等）不标 `final`；正例 `SourceEditorDataSource.languageService`（getter 无 `Tq`、lazy）打印 `final lazy var languageService: SourceEditor.SourceEditorLanguageService`——issue 第 1、4 点在原始二进制上的合体验证。机器无 Xcode 时整套跳过。
- 快照回归：interface 整模块快照 + dump 的 `enums`/`genericFieldLayout`/`vTableEntryVariants` 快照，逐行审查过（真阳性：fixture 里声明为 `final` 的成员、final class 的成员、被归到 body 的 extension 成员；async 三成员从误标回到正确形态并新增 `override`）。`Tq` 门对 fixture 快照零扰动（fixture 无 ICF 折叠，`Tq` 证据与 join 结论一致）。
- `nm` 对照：`elide`（`Tq`+`Tj` 在场 ⇒ 非 final）与 `languageService`（仅直接符号 ⇒ final）已逐符号核对。

## 已知降级

- 符号被 strip 的二进制：accessor 组 join 不上，所有 stored 属性静默不标 `final`（interface 上真 final 成员因此漏标——绝不误标的代价）。
- `final override` 不还原：override 成员带 override descriptor，一律打印平凡 `override`（对重建无害，父类声明已提供 thunk 侧正确性）。
- final class 本身不打 `final`（类级无 ABI 位），由成员级标记间接呈现。
- `@objc` 下标无 thunk 名归因通道，理论上的 `@objc dynamic subscript` 误标风险未设防（极罕见）。

## 延伸阅读

- 提案 [0006](../Evolutions/0006-final-keyword-and-lazy-accessor-type-recovery.md)
- [ClassMemberKeywordRecovery.md](ClassMemberKeywordRecovery.md)——`class`/`static` 还原与「ABI 无 final 位」的查证
- [Roadmaps/2026-04-13-swiftinterface-dump-improvements.md](../../Roadmaps/2026-04-13-swiftinterface-dump-improvements.md) 的 Known limitations——不可恢复项清单
