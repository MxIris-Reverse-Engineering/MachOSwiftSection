# Draft - SwiftDeclaration 的类型名按角色统一后缀

- **状态**: In Progress
- **创建日期**: 2026-11-06
- **最后更新**: 2026-11-06
- **关联提案**: [draft-swift-declaration-model-indexing-layout](draft-swift-declaration-model-indexing-layout.md)（同一批整理的上一步：先把文件分成 `Model/` 与 `Indexing/`，本提案再理顺名字）
- **实现分支 / PR**: `refactor/swift-declaration-layout`

## 摘要

这个模块的类型名有三处不成套。`Indexing/Building/` 下的六个命名空间用了四种起名法：「做事的人」`DefinitionBuilder`，「这一步」`MemberAttributeApplication` / `ObjCMemberApplication` / `WrappedPropertyRecovery`，「产物的复数」`StandInMemberSymbols` / `ObjCProtocolNames`；`OverrideSymbolMatcher.swift` 里却没有这个类型，只有两个包级自由函数。同一个意思用了两个词：`WrappedPropertyDefinition.Origin` 与 `ObjCProtocolRequirementDefinition.Source` 都表示「这条声明从哪来」。`AssociatedTypeWitnessProjection` 的「Projection」在模块里只此一处，存它的属性叫 `resolvedAssociatedTypeWitnesses`。本批按角色给命名空间统一后缀，并把三个公开名字改成与模块其余部分一致的词，公开的旧名留 deprecated 别名。

## 方案

**命名空间按角色取后缀**，后缀本身说明它干哪一类事：

| 角色 | 后缀 | 成员 |
|---|---|---|
| 造出新的东西（成员定义、替身符号、协议名） | `…Builder` | `DefinitionBuilder` → `MemberDefinitionBuilder`，`StandInMemberSymbols` → `StandInMemberSymbolBuilder`，`ObjCProtocolNames` → `ObjCProtocolNameBuilder` |
| 拿二进制里另一处的证据对到已经建好的成员上 | `…Matcher` | `MemberAttributeApplication` → `ThunkAttributeMatcher`（thunk 符号 → `@objc` / `@nonobjc` / `distributed`），`ObjCMemberApplication` → `ObjCMemberMatcher`（ObjC 方法表 → `@objc`、`override`、显式 selector），`OverrideSymbolMatcher`（新建 `package enum`，收进原来的自由函数 `memberJoinKey` 与 `demangledOverrideSymbol`） |
| 补回二进制丢掉的事实 | `…Recovery` | `WrappedPropertyRecovery`（不变） |

`MemberDefinitionBuilder` 多出的 `Member`：它只造成员定义（函数、变量、下标），不造 `TypeDefinition` 这类声明本体，`DefinitionBuilder` 读起来像后者。`ThunkAttributeMatcher` 里的 `Thunk` 与调用它的 `TypeDefinition+ThunkAttributes`、`ExtensionDefinition+ThunkAttributes` 对上。这几个都是 `package`，直接改名，模块外只有 SwiftIndexing、SwiftDiffing、SwiftDump 与一个测试在调用，一并改掉。

**三个公开名字**，旧名照仓库惯例在新类型旁边留 `@available(*, deprecated, renamed:)` 的别名：

- `AssociatedTypeWitnessProjection` → `ResolvedAssociatedTypeWitness`，与存它的属性 `ExtensionDefinition.resolvedAssociatedTypeWitnesses` 同名。
- `ConditionalWitnessCandidate` → `ResolvedAssociatedTypeWitness.ConditionalCandidate`：它只出现在见证的 `conditionalCandidates` 里，嵌进去之后名字不必再重复「Witness」。
- `ObjCProtocolRequirementDefinition.Source` / `source` → `Origin` / `origin`，与 `WrappedPropertyDefinition.Origin` / `origin` 用同一个词。没选 `Source`：这个仓库里 `source` 还指源码与 `MachOSource`，`Origin` 不会被读歪。

**不改的**：`…Definition`（源码里有名字的一条声明）、`…Name`、`…Kind`、`…Facts`（与 SwiftInspection 的 `ObjCImplementationClassFacts` 同一个词）这几个后缀各自只表示一类东西；`ExportStatus`、`MemberCategory`、`OrderedMember`、`StrippedSymbolicRequirement`（没有名字，不是一条声明，所以不叫 `…Definition`）是互不相同的概念，名字不成套是对的。事件命名空间 `SwiftIndexEvents` 也有不一致（结果类型里夹着一个 `…Input`、计数字段三种拼法），另开一批：它的 payload case 改名留不了别名。

- **验证**：改名不改输出，干净编译库与全部测试 target；不跑渲染 A/B。`ResolvedAssociatedTypeWitness` 是 `Codable` 的，编码用的是属性名，类型改名与嵌套不改变 JSON。
- **文档**：模块参考、术语表与现行实现说明里的名字改成新名；已落地的提案、任务报告、评审记录、演进账本旧章节、`ReviewAdjudications` 里的旧名保持原样。`Documentations/README.md` 的索引摘要这次不改：那几行概括的是历史文档，而且集成分支的检出里这份文件有别处未提交的改动。
- **没问就定的假设**：
  - deprecated 别名与 0057 的废弃转发一起在 0.25.0 删除。
  - 测试套件 `AssociatedTypeWitnessProjectionTests` 随类型改名为 `ResolvedAssociatedTypeWitnessTests`；CI 的套件筛选里没有它，不用跟着改。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-11-06 | Created as Draft | 目录整理之后，用户指出这个模块的类型名不成套 |
| 2026-11-06 | 范围定为包内命名空间加三个公开名字，事件命名空间另开一批 | 用户在三档范围里选定；事件 payload 的 case 改名留不了别名，改动量也大几倍 |
| 2026-11-06 | 命名空间按「造新东西 / 对证据 / 补事实」三类取后缀 | 用户选定，没选「一律叫做事的人」：`Applier`、`Recoverer` 读起来别扭 |
| 2026-11-06 | 第二类用 `…Matcher`，不用 `…Application` | 用户指出 `Application` 会被读成「应用程序」；`…Matcher` 与模块里已有的 `OverrideSymbolMatcher` 同类，用户选定。`…Applier` 读着别扭，`…Join` 不像名词，`…Annotator` 会和输出里的 annotation 撞词 |
| 2026-11-06 | 按轻量档写精简提案；状态 Draft → Accepted → In Progress | 用户批准方案；接着在目录整理的分支上做 |
| 2026-11-06 | 实现完成，待用户看过后收尾 | 按方案改完；`OverrideSymbolMatcher.swift` 原来两段文档注释叠在 `memberJoinKey` 上，收进 enum 时各归各位；SwiftIndexing 里私有的 `resolvedWitnessProjections` 一并改成 `resolvedAssociatedTypeWitnesses`。增量编译库与全部测试 target，原始退出码 0。文档：模块参考写上后缀规则，术语表与十份现行文档换成新名，演进账本加一节；不另写实现说明或使用指南；没有新术语 |
