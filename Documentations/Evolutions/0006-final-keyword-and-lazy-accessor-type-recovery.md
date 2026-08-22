# 0006 - `final` 成员关键字还原与 lazy var 访问器类型修正

- **状态**: Implemented
- **作者**: JH
- **创建日期**: 2026-08-22
- **最后更新**: 2026-08-22
- **所属愿景**: 无
- **关联提案**: [0007](0007-extension-container-dedup-and-default-impl-attribution.md)（同一 issue 的扩展块问题）、[0008](0008-interface-header-and-export-status-annotations.md)（同一 issue 的头部与导出标注）
- **实现分支 / PR**: `feature/0006-final-and-lazy-recovery`
- **配套文档**: [FinalKeywordAndLazyAccessorTypeRecovery.md](../Internal/FinalKeywordAndLazyAccessorTypeRecovery.md)（实现说明）

## 摘要

对 class 成员还原 `final` 关键字：判据是「成员没有 vtable method descriptor ⇒ 源码是 `final`」，与既有的 `class`/`static` 还原（`isClassMember`，见 [ClassMemberKeywordRecovery.md](../Internal/ClassMemberKeywordRecovery.md)）是同一条 ABI 事实的镜像。实现的关键是停止丢弃 stored `var` 的 accessor→vtable 归属信息 —— 这份数据今天已经被完整解析出来，只是在去重时被扔掉了。同一处改动顺带修正 lazy var 的类型渲染：不再打印 Optional 的存储类型，改用 getter 符号携带的访问器类型。`final` 关键字默认输出；stored var 的 vtable offset 注释跟随既有的 `--emit-vtable-offsets` 开关。

来源：[issue #106](https://github.com/MxIris-Reverse-Engineering/MachOSwiftSection/issues/106) 的第 1、4 点 —— 用 dump 重建 Xcode 私有 `SourceEditor.framework`（13289 个 Swift 符号）的实战反馈中代价最高的两点。

## 动机

issue #106 作者手写可编译 `.swiftinterface` 时，`final` 缺失是唯一**破坏链接**的问题：经 dispatch thunk 调用的成员必须平凡声明，只有直接符号的成员必须声明 `final`，声明错了直接 `Undefined symbols: dispatch thunk of …`。而 dump 完全不区分两者 —— `grep -rn '"final"' Sources` 零命中，`final` 在整个代码库里不存在。

更糟的是当前输出会**误导**：stored `var` 只从 field descriptor 打印，即使它的 getter/setter 就在 vtable 里（非 final），也不带任何 vtable 注释，看起来和静态派发的成员一模一样。issue 作者据此推出「没有 vtable 注释 ⇒ final」的错误规则，被 `SourceEditorView.dataSource`、`SourceEditorView.gutter` 这类导出了 dispatch thunk 的 stored var 打脸。

lazy var 问题同源：`lazy var languageService: SourceEditor.SourceEditorLanguageService?` 打印的是 Optional 存储类型，而导出的 getter 返回非 Optional —— Optional 属于 lazy 存储的实现细节，不属于调用方看到的属性类型。本仓库自己的快照就复现：`Tests/SwiftInterfaceTests/Snapshots/__Snapshots__/SymbolTestsCoreInterfaceSnapshotTests/interfaceSnapshot.1.txt` 打印 `lazy var lazyProperty: Swift.String?`，而 dump 快照同一属性的 getter 符号明明白白是 `Swift.String`（`Tests/SwiftDumpTests/.../classesSnapshot.1.txt` 的 `[Getter]` 行）。

## 前期调研

调研先在 main（`32bf83c1`）上完成，开工时已在 next（`a03d0f1b`，本分支基线）上复核 —— 核心机制原样成立，行号与类型形态按 next 现值记录；与 main 的差异（0002 号提案的 descriptor 化）在最后一条单列。

- **判据用 method descriptor 而非 dispatch thunk（`Tj`）。** issue 建议靠 `Tj` 符号判 final，但 `Tj` 只在 library evolution 开启时发射，非 resilient 二进制里「没有 thunk」对每个成员都成立。而「有 vtable method descriptor ⇒ 非 final」在两种二进制里都成立（issue 自己的数据：evolution 关闭的库仍有 317 个 `Tq` method descriptor），且在两个 resilient 二进制里 `Tj == Tq` 严格相等 —— 两条判据在都有效的地方完全一致。descriptor 判据还覆盖非 public 成员（internal 非 final stored var 没有导出 thunk，但有 method descriptor），thunk 判据覆盖不了。
- **ABI 上没有 `final` 位。** [ClassMemberKeywordRecovery.md](../Internal/ClassMemberKeywordRecovery.md) 已查证 `ClassFlags`、`TypeContextDescriptorFlags`、ObjC `class_ro_t` 均无 final 标记；descriptor 的**存在与否**就是全部事实。`static` 成员隐式 final、永远没有 descriptor，所以 `final` 只对实例成员和 stored var 有意义（`isClassMember` 的对称面）。
- **accessor→vtable 归属已经算出来了，在 `Sources/SwiftDeclaration/Components/Definitions/DefinitionBuilder.swift:30` 被丢弃。** `DefinitionBuilder.variables` 对每组 accessor 符号已经完成 `methodDescriptorLookup` / `vtableOffsetLookup` 解析（按 `StructuralNodeReferenceKey` 匹配；lookup 由 `TypeDefinition` 的 index 流程构建，`Sources/SwiftDeclaration/Components/Definitions/TypeDefinition.swift:213-296`），产出完整的 `[Accessor]`（每个带 `methodDescriptor` 与 `vtableOffset`），然后 `guard !fieldNames.contains(name) else { continue }` 为了避免属性打印两次（一次来自 field record、一次来自 accessor 符号）把整组扔掉。缺的不是解析能力，是保留结果。
- **lazy 检测是纯字段名前缀匹配。** `$__lazy_storage_$_` 前缀（`Sources/SwiftDeclarationRendering/Extensions/String+.swift`）→ `FieldFlags.isLazy`（`TypeDefinition.swift:184`），剥前缀后的字段名与 accessor 名相同，所以 lazy 属性的 getter `VariableDefinition` 恰好也被上面同一行 guard 丢弃。getter node 的类型子节点就是正确的访问器类型（`Sources/SwiftPrinting/NodePrinter/VariableNodePrinter.swift` 已有取用先例）。
- **渲染面已有全部基础设施。** `VTableOffsetComment` 组件（`Sources/SwiftPrinting/SemanticExtensions/SemanticComponents.swift`，支持 `(getter)` / `(setter)` 标签）；字段渲染在 `renderModelFields`（`Sources/SwiftPrinting/SwiftDeclarationPrinter+Headers.swift:311`）与 `printThrowingField`（`SwiftDeclarationPrinter+Members.swift:42`）；`isClassMember` 的三个 node printer 接线点（`VariableNodePrinter` / `FunctionNodePrinter` / `SubscriptNodePrinter`）就是 `final` 的接线位置。`OrderedMember` 没有 `.field` case，stored var 的 vtable 注释只能加在 `renderModelFields` 里。
- **`Keyword` 词表没有 `final`**（`Sources/SwiftDeclarationRendering/Extensions/Keyword+Swift.swift`），`SwiftAttribute` 也没有 —— 且 `SwiftAttribute` 渲染成声明前独立一行，对 `final` 是错误的位置；应做成与 `isOverride` / `isClassMember` 同形态的关键字位标志。
- **`MemberAttributeInferrer` 是死代码。** `Sources/SwiftAttributeInference/MemberAttributeInferrer.swift` 仅测试引用；真正的成员属性推断（`dynamic` / `@objc` / `@nonobjc`）散在 `DefinitionBuilder` 与 `TypeDefinition.applyThunkAttributes` 里。issue 说「`final` 应该放它旁边」，但事实上模型层才是活的推断层，`final` 应与 `isClassMember` 对称地放在模型上。
- **fixture 现状**：`Tests/Projects/SymbolTests/SymbolTestsCore/Classes.swift` 已有 lazy 属性；含 `final` 成员、非 final stored var 全组合的类需要补充。SymbolTestsCore 未开 library evolution，但 descriptor 判据不依赖 resilience，fixture 可直接验证。
- **next 相对 main 的模型层漂移**（0002 号提案 descriptor 化的结果，不影响本方案）：`FieldDefinition.typeNode` 是 `NodeReference`（经 `InternedNodeReferenceCache` interning，`TypeDefinition.swift:207`），lookup 键是 `StructuralNodeReferenceKey` 而非裸 `Node` —— 新增字段与 join 逻辑照此形态实现即可。

## 提议方案

1. **保留 stored 属性的 accessor 归属**：`DefinitionBuilder.variables` 不再无条件丢弃与字段同名的 accessor 组，改为将解析好的 `[Accessor]` 交还给 `TypeDefinition` 的 index 流程，挂到对应 `FieldDefinition` 上（字段仍只渲染一次，accessor 组不再作为独立 `VariableDefinition` 出现，与现状一致）。
2. **`final` 推断**：模型层计算属性 —— class 语境下，成员（function / variable / subscript / stored field）没有任何 vtable method descriptor 即 `isFinal`。安全门：仅当所属 class 的 vtable 段确实可读（`vTableDescriptorHeader != nil`）时才判定，join 失败（符号被 strip、实现地址不唯一）降级为不打 `final` —— 宁缺勿错。`static` / `isClassMember` 成员不打 `final`（隐式 final / 语义冲突）。
3. **渲染**：`Keyword` 增加 `final`，在三个 node printer 与字段关键字（`fieldDeclarationKeywords`）的 `override` / `class` 同批位置输出，**默认开启**；stored var 的 getter/setter vtable offset 注释在 `renderModelFields` 里用既有 `VTableOffsetComment` 输出，**跟随既有 `printVTableOffset` 开关**（CLI `--emit-vtable-offsets`），并修正该 flag 的帮助文案（不再是 "class methods and computed properties"）。
4. **lazy var 类型修正**：`FieldDefinition` 携带来自 getter node 的访问器类型（`accessorTypeNode`），lazy 字段渲染时优先使用；getter 符号不可得时回退为「剥一层 Optional」（lazy 存储恒为 `Optional<T>` 包装，剥一层语义精确）。保留 `lazy` 关键字与 `// Field offset:` 注释（存储事实不变）。
5. **dump 路径对齐**：`ClassDumper` 的字段段落与成员段落输出同样的 `final` 关键字与 lazy 类型修正，维持两路一致性。

### 非目标

- **class 级 `final` 不做**。类本身是否 `final` 没有 ABI 位；「类没有 vtable 段」既可能是 final class 也可能是恰好没有可覆写成员的类，无法可靠区分。作为已知局限记录（成员级 `final` 在这种类上也整体不发射，因为安全门要求 vtable 可读）。
- **`open` vs `public` 不做**（不可恢复，已在 Roadmaps 的 Known limitations 列表）。
- **extension / struct / enum / protocol 成员不打 `final`**（extension 成员静态派发是语言规则，`final` 在那些语境非法或冗余）。
- **override 成员的 `final override` 不做**：override 成员带 method override descriptor，按判据打印为平凡 override；漏掉 `final` 对重建场景无害（父类声明已提供 thunk 侧的正确性），保守降级。

## 详细设计

```swift
// SwiftDeclaration — FieldDefinition 扩容（示意，形态按 next 的 NodeReference/interning 现状）
@MemberwiseInit(.public)
public struct FieldDefinition: Sendable {
    public let name: String
    public let typeNode: NodeReference
    public let flags: FieldFlags
    /// Accessors resolved from the symbol table for this stored property (getter/setter/modify),
    /// each carrying its methodDescriptor / vtableOffset when the class vtable attribution succeeded.
    public let accessors: [Accessor]
    /// The caller-facing type from the getter symbol (differs from `typeNode` for lazy storage).
    public let accessorTypeNode: NodeReference?

    /// True when any accessor carries a vtable method descriptor.
    public var hasVTableAccessor: Bool { accessors.contains { $0.methodDescriptor != nil } }
}

// isFinal 判定（对 FunctionDefinition / VariableDefinition / SubscriptDefinition 同形）：
// owningClassHasReadableVTable && !isGlobalOrStatic && methodDescriptor == nil
```

数据流：`TypeDefinition` 的 index 流程在 fields 定稿与 instance variables 构建之间，把 `DefinitionBuilder.variables` 因 `fieldNames` 命中而跳过的 accessor 组按剥过 lazy 前缀的名字 join 回 `FieldDefinition`。join 键与现状一致：accessor 侧 `variableNode.identifier`，字段侧 `stripLazyPrefix` 后的名字。「vtable 可读」由 index 流程在构建 lookup 时一并记录（`cls.vTableDescriptorHeader != nil`）并传给成员构建。

渲染接线：

- `Keyword+Swift.swift` 增加 `case final`。
- `fieldDeclarationKeywords`（`SwiftDeclarationPrinter+Members.swift`）：class 语境且 `field.isFinal` 时前置 `final `；lazy 分支类型改用 `accessorTypeNode ?? strippedOptional(typeNode)`。
- 三个 node printer 在写 `override` 的位置按 `isFinal` 写 `final`。
- `renderModelFields`（`SwiftDeclarationPrinter+Headers.swift:311` 起）在 `storedFieldComments` 旁按 `printVTableOffset` 输出 accessor 的 `VTableOffsetComment`（带 `(getter)` / `(setter)` 标签）。
- dump 路径：`ClassDumper` 字段段落与 `TypedDumper.fieldDeclarationKeywords` 做同构修改。

## 替代方案考量

- **靠 `Tj` dispatch thunk 判 final（issue 原建议）** —— 否。仅 resilient 二进制有效，且覆盖不了非 public 成员；descriptor 判据是它的严格超集（见前期调研）。`Tj` 计数留给提案 0008 的 library evolution 标注行。
- **`SwiftAttribute` 增加 `.final` case** —— 否。`SwiftAttribute` 渲染为声明前独立一行，`final` 是声明修饰符位置的关键字；与 `isOverride` / `isClassMember` 同形态的标志才是正确形状。
- **复活 `MemberAttributeInferrer` 并把 `final` 放进去** —— 否（本次）。该类型是死代码，真正的推断在模型层；把 `dynamic` / `@objc` 逻辑集中迁回去是独立的重构，与本提案的用户价值无关，不捆绑。
- **lazy 只做「剥一层 Optional」不引 getter node** —— 否为主方案、留作回退。剥层方案改动最小且语义精确（lazy 存储恒为 `Optional<T>`），但 getter node 是调用方类型的第一手来源，且 accessor 组本来就因本提案被保留下来，一并携带无额外成本。

## 影响

### 源码兼容性（source compatibility）

`FieldDefinition` 是 public struct（`@MemberwiseInit(.public)` 生成 memberwise 初始化器）：新增字段带默认值（`accessors: [Accessor] = []`, `accessorTypeNode: NodeReference? = nil`）保持既有调用点纯新增。模型新增计算属性（`isFinal` / `hasVTableAccessor`）为纯新增。`swift-section` CLI 无 flag 增删（`final` 默认开、vtable 注释复用既有 flag），仅帮助文案变化。

**输出行为变化**：默认输出新增 `final` 关键字 —— 所有快照基线重生成一次；RuntimeViewer 升级依赖后用户默认可见。开启 `--emit-vtable-offsets` 时 stored var 新增 vtable 注释行。

### ABI 兼容性（条件项）

不适用 —— 本库以 SPM 源码分发，使用方每次重新编译。

### 下游影响

本仓库内：`SwiftDeclaration`（模型）、`SwiftPrinting`（interface 渲染）、`SwiftDump`（dump 渲染）、`SwiftDeclarationRendering`（Keyword 词表）、`swift-section`（帮助文案）、全部快照测试。`SwiftDiffing` 需确认：`MemberRecord` 的 identity/payload key 不含 `final`，本提案不改 diff key（如后续想把 `final` 变化纳入 diff，另行提案并 bump formatVersion）。

下游仓库：RuntimeViewer 输出默认出现 `final`；若其有基于输出文本的对比/缓存需感知。SymbolViewer / MachOKitUI 不消费渲染输出，预计无感。

### 文档与示例

AGENTS.md 架构段的 SwiftPrinting 条目、`ClassMemberKeywordRecovery.md` 追加 `final` 镜像一节（或新实现说明并互链）、`Roadmaps/2026-04-13-swiftinterface-dump-improvements.md` 的 Known limitations 相应更新（lazy 类型从「错误」变「已修正」）。

## API 演进与废弃策略

- 无被替代的旧 API；`FieldDefinition` 走带默认值参数的新增，不需要废弃期。
- 不需要 semver major；按 `Version.swift` 契约做 minor bump 并配 `Changelogs/<version>.md`。

## 落地步骤

1. fixture 扩充：`SymbolTestsCore` 增加覆盖矩阵类（`final func` / 平凡 `func` / `final var` 计算属性 / 平凡计算属性 / stored `let` / `final` stored `var` / 平凡 stored `var` / `lazy var`，含 override 组合），重建 fixture 二进制。
2. `DefinitionBuilder` / `TypeDefinition`：保留 accessor 组并 join 到 `FieldDefinition`；记录 vtable 可读性；单测（join 命中 / lazy 前缀 / strip 降级）。
3. 模型 `isFinal` 计算属性 + `Keyword.final`；interface 三个 printer + 字段关键字接线；快照重生成并逐行审查 drift。
4. lazy 类型修正（getter node 优先、剥层回退）两路接线；快照复核 `lazyProperty: Swift.String`。
5. `renderModelFields` 的 stored var vtable 注释（`printVTableOffset` 门控）；CLI 帮助文案更新。
6. dump 路径对齐 + `SwiftDumpTests` 快照重生成。
7. 全量 `swift test --skip IntegrationTests`；对真实 resilient 框架（SourceEditor）人工抽查 `final` 与 `nm` 的 dispatch thunk 对照。
8. 文档同批：实现说明、AGENTS.md、Roadmaps 限制列表、changelog；提案状态推进。

**收尾时必须判断两件事**（判断结果写进决策日志，不允许沉默跳过）：

- **要不要配套专题文章** —— `final` 判据与安全门属于「代码本身看不出来的决策」，预计需要实现说明（或并入 ClassMemberKeywordRecovery.md）。
- **有没有引入新术语** —— 待定（accessor attribution / vtable readability gate 若成为常用语则登记）。

## 决策日志

| 日期 | 变更 | 说明 |
|------|------|------|
| 2026-08-22 | Created as Draft | 源自 issue #106 第 1、4 点调研；用户决定：`final` 关键字默认开、注释类跟随 flag；两点同批（同一根因 `DefinitionBuilder.swift:30`）。 |
| 2026-08-22 | Draft → In Progress | 用户批准三批全做并指示基于 next 建 worktree 开工（0006 首批）。原编号 0005 因 next 上已被 `0005-event-based-degradation-reporting.md` 占用，改为 0006；前期调研在 next（`a03d0f1b`）上复核通过，机制无漂移，行号与类型形态已更新为 next 现值。实现分支 `feature/0006-final-and-lazy-recovery`。 |
| 2026-08-22 | In Progress → Implemented | 实现完成于 `feature/0006-final-and-lazy-recovery`（待并入 next）。全量 1438 tests 全绿；fixture 矩阵类 + `FinalMemberRecoveryTests` 五用例 + 四份快照逐行审查重录 + ABI 基线 regen（96 行纯 offset）。**收尾两判**：配套文档已写并登记（[FinalKeywordAndLazyAccessorTypeRecovery.md](../Internal/FinalKeywordAndLazyAccessorTypeRecovery.md)，含与提案的差异）；无需登记新术语（member-level final / evidence gate 均为描述性短语，非项目自造代号）。落地步骤 7 的真实 resilient 框架 `nm` 对照留待有 SourceEditor 二进制的环境补做。 |
| 2026-08-22 | 补第四道门：`Tq` 符号负证据（SourceEditor 实测驱动） | 落地步骤 7 的真实框架对照在 0007 开工前补做，当场抓到假阳性：SourceEditor 把 1128 个空实现 ICF 折叠到同一地址（`SourceEditorView.elide` 等，`nm` 证实带 `Tq`+`Tj`），descriptor→symbol 的地址 join 配不上对，函数无 accessor-join 门，全体误标 `final`。修复为第四道门——成员名存在 `Tq` method-descriptor 符号（每成员唯一地址的数据符号，ICF 免疫）即绝不标 `final`；dump 路径同步。回归钉死在 `FinalKeywordICFRegressionTests`（Xcode 在场才启用），并顺带验证正例 `languageService` 在原始二进制上打印 `final lazy var …: SourceEditorLanguageService`（issue 两点合体）。fixture 快照零扰动。 |
| 2026-08-22 | 实现中的发现与偏差（快照审查驱动） | （1）**async 成员的 descriptor join 从未成功过**：method descriptor 的 implementation 指向 `Tu` async-function-pointer 常量，其 demangled 树多一层 `.asyncFunctionPointer` 前导标记，结构键与成员符号树不匹配——首轮快照把被子类 override 的 `asyncMethod` 误标 `final` 暴露了它。修复为 join key 剥标记（`memberJoinKey`），顺带找回 async 成员一直缺失的 `override` 关键字与 vtable 注释（修的是既有 bug）。（2）**`@objc` 无 descriptor ⇒ `@objc dynamic`**（经 ObjC runtime 派发、可覆写），从 `final` 标记中排除（模型路径按 attributes、dump 路径按 thunk 成员名，标记块因此移到 `applyThunkAttributes` 之后）。（3）**final class 的成员会获得成员级 `final`**：final class 因 designated init 的 vtable 条目而带 vtable header，门挡不住；接受此行为——类级 `final` 无 ABI 位不可恢复，成员级标记如实反映派发形态，对重建链接恰好正确。（4）stored `let` 不打 `final`（本就不可覆写，纯噪声）。（5）**dump 路径的 lazy 类型保持存储真相**（`Swift.String?`），与提案落地步骤 5 的「lazy 两路对齐」偏离：dump 是原始视图、其 `[Getter]` 符号列表已如实展示访问器类型；`final` 关键字则两路对齐。（6）被归到类 body 的 extension 成员（既有归属行为）获得 `final` 属真阳性——静态派发，对重建正确。 |
