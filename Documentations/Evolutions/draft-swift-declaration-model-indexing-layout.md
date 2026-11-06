# Draft - SwiftDeclaration 的目录分成公开模型与索引代码两块

- **状态**: In Progress
- **创建日期**: 2026-11-06
- **最后更新**: 2026-11-06
- **关联提案**: [0042-swift-declaration-file-layout](0042-swift-declaration-file-layout.md)（上一次整理这个模块的文件；本提案沿用它「`Members/` 是模型、`Building/` 是索引期机器」的分界，把这条分界推到整个模块）
- **实现分支 / PR**: `refactor/swift-declaration-layout`

## 摘要

0042 之后，这个模块新增的文件大多与 ObjC 相关（`ObjCProtocolDefinition`、`ObjCCategoryConformance`、`ResolvedObjCMemberFacts`、`TypeDefinition+ObjCMembers` / `+ObjCProtocols`、`ExtensionDefinition+ObjCMembers` / `+ThunkAttributes`、`DefinitionIndexing`），都放进了 `Components/Definitions/`，那里现在有 25 个文件：四个顶层声明的本体、五个成员定义、十三个 `+Indexing` 一类的索引扩展、两个 ObjC 事实类型，以及「每个定义只索引一次」的那把锁。`Components/` 这一层不区分任何东西，`Events/`、`Extensions/` 却放在它外面；同属成员的定义一半在 `Definitions/`、一半在 `Members/`；还有三个类型藏在别人的文件里。本批把模块分成 `Model/`（下游读的公开模型）和 `Indexing/`（填模型的代码，全是 `package` / `internal`）两棵树。只搬文件、原样剪切三个类型，不改任何代码。

## 方案

```
Sources/Declaration/SwiftDeclaration/
├─ Model/
│  ├─ Definitions/   Definition（含 MutableDefinition）、TypeDefinition、ProtocolDefinition、
│  │                 ExtensionDefinition、ObjCProtocolDefinition（含 ObjCProtocolDefinitionError）
│  ├─ Members/       FunctionDefinition、VariableDefinition、SubscriptDefinition、FieldDefinition、
│  │                 WrappedPropertyDefinition、ObjCProtocolRequirementDefinition、Accessor、
│  │                 OrderedMember、MemberCategory、StrippedSymbolicRequirement、ResolvedObjCMemberFacts
│  ├─ Names/         不变
│  ├─ Kinds/         不变
│  └─ ExportStatus、SwiftAttribute、AssociatedTypeWitnessProjection、ObjCCategoryConformance
├─ Indexing/
│  ├─ DefinitionIndexing.swift
│  ├─ TypeDefinition/        TypeDefinition+{Indexing, ClassDispatch, MemberIndexing, FinalRecovery,
│  │                         ThunkAttributes, SynthesizedMembers, WrappedProperties, ObjCMembers, ObjCProtocols}
│  ├─ ExtensionDefinition/   ExtensionDefinition+{Indexing, ObjCMembers, ThunkAttributes}
│  ├─ ProtocolDefinition+Indexing.swift
│  ├─ ObjCProtocolDefinition+Indexing.swift
│  └─ Building/              原 Components/Building/ 的九个文件，加上 ObjCProtocolNames
├─ Events/           不变
└─ Extensions/       加上 DemanglingNode+StoredVariable
```

- **分界的判据是可见性**：`Model/` 里的类型是 `public` 的、索引结束后还留在模型里；`Indexing/` 里每个声明都是 `package` 或 `internal`，只在 `index(in:)` 与 `SwiftDeclarationIndexer.prepare()` 期间有人调用。逐一核对过：九个 `TypeDefinition+…`、三个 `ExtensionDefinition+…`、两个 `+Indexing` 与 `DefinitionIndexing` 里没有一个 `public` 声明。
- **成员定义全部进 `Model/Members/`**：`FunctionDefinition` 这五个原在 `Definitions/`，和 `Accessor`、`OrderedMember` 本是同一类东西；`ResolvedObjCMemberFacts` 是三种成员定义上的公开投影，一并归入。
- **三处原样剪切**，各自的 import 照抄原文件：
  - `ObjCProtocolRequirementDefinition` 从 `ObjCProtocolDefinition.swift` 末尾抽成 `Model/Members/ObjCProtocolRequirementDefinition.swift`。
  - `ObjCProtocolNames` 从 `TypeDefinition+ObjCProtocols.swift` 抽成 `Indexing/Building/ObjCProtocolNames.swift`：`ObjCCategoryConformance.all(in:)` 也用它，不只属于 `TypeDefinition`。
  - `isStoredVariable` 从 `DefinitionBuilder.swift` 末尾抽成 `Extensions/DemanglingNode+StoredVariable.swift`，与 `DemanglingNode+AccessorKind` 并列。
- **用 `git mv` 搬**，`git log --follow` 能接上每个文件的历史。没有测试、脚本或 `Package.swift` 按路径引用这些文件，源码扫描类测试按模块名取文件，不受目录层级影响。
- **验证**：干净编译库与全部测试 target。不跑渲染 A/B：没有一行代码改变，输出不可能变。
- **文档**：[Modules/SwiftDeclaration.md](../Internal/Modules/SwiftDeclaration.md) 的「文件 → 子系统对照」重写，「TypeDefinition 的扩展」表补上漏掉的 `+ObjCMembers` 与 `+ObjCProtocols`（原文写「七个」、实有九个）；术语表与现行实现说明里写着完整路径的行改成新路径；演进账本加一节。
- **没问就定的假设**：
  - `ProtocolDefinition` 与 `ObjCProtocolDefinition` 的索引扩展各只有一个文件，不单独建目录，照 0042「一个文件的目录是噪音」的判断。
  - `ObjCCategoryConformance` 放在 `Model/` 根下：它是公开的事实类型，挂在索引器上，不属于任何一种声明或成员。它的 `all(in:)` 是 `package` 的构建方法，与类型留在同一个文件，不拆。
  - 历史文档（已落地的提案、`TaskReports/`、`Reviews/`、`Roadmaps/`、演进账本旧章节、`ReviewAdjudications` 的发现记录、`SharedNodeStoreMigration` 与 `FieldMetadataRenderingMigration` 这类迁移记录）里的旧路径是当时的事实，保持原样。只写了 `Building/X.swift` 这种相对路径、且仍是新路径后缀的行也不改。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-11-06 | Created as Draft | 0042 之后新增的文件都堆进了 `Components/Definitions/`，用户要求把这个模块的文件层级重新整理 |
| 2026-11-06 | 采用「公开模型 / 索引代码」两分 | 用户在三个布局里选定。另两个：按声明分目录（每个声明一个目录装本体和全部扩展，但公开模型和索引代码又混在一起）、最小整理（只去掉 `Components/` 并归拢成员定义，`Definitions/` 仍剩约 20 个文件） |
| 2026-11-06 | 按轻量档写精简提案；状态 Draft → Accepted → In Progress | 用户批准方案；提案随功能分支落盘，不先单独提交进 `next`：`next` 的检出里有别处未提交的改动 |
| 2026-11-06 | 实现完成，待用户看过后收尾 | 52 个文件按方案搬完，三处剪切照方案；从空 scratch 编译库与全部测试 target，原始退出码 0。文档：模块参考的两张对照表重写，术语表与四份实现说明改路径，演进账本加一节；不另写实现说明或使用指南，布局与判据写在模块参考里；没有新术语 |
| 2026-11-06 | `AGENTS.md` 的 SwiftDeclaration 条目加一句归位规则 | 用户同意：0042 的布局就是被随手放进 `Definitions/` 的新文件冲乱的，agent 加新的索引步骤时默认会放在 `TypeDefinition.swift` 旁边 |
