# Draft - `@ResolvableLocatableLayoutWrapper`：样板宏改名并补上遵循

- **状态**: In Progress
- **创建日期**: 2026-11-06
- **最后更新**: 2026-11-06
- **关联提案**: [0027-locatable-layout-wrapping-macro](0027-locatable-layout-wrapping-macro.md)（引入这个宏；本提案推翻它「宏不生成遵循」的决定）
- **实现分支 / PR**: `refactor/resolvable-locatable-layout-wrapper-macro`

## 摘要

0027 引入的 `@LocatableLayoutWrapping` 只生成 `layout` / `offset` / `init(layout:offset:)` 三项存储，遵循仍要在声明处手写 `: ResolvableLocatableLayoutWrapper`。98 个贴了宏的 struct 都是 `ResolvableLocatableLayoutWrapper`（直接写的 51 个，经 `MetadataProtocol`、`ContextDescriptorProtocol`、`TopLevelDescriptor` 这类子协议遵循的 46 个，还有一个只写了 `LocatableLayoutWrapper`），宏与遵循从来成对出现，分开写只是多一处要记住的样板。本提案让宏同时补上遵循，并把它改名为 `@ResolvableLocatableLayoutWrapper`：宏名就是它带来的遵循，和 `@Observable` 宏对 `Observable` 协议是一个思路。

## 方案

- **宏实现**（`Sources/Support/MachOMacros/ResolvableLocatableLayoutWrapperMacro.swift`，由 `LocatableLayoutWrappingMacro.swift` 改名）：在原有的 member 角色之外加一个 extension 角色。编译器只把类型**还缺**的协议交给扩展宏，所以宏照单生成 `extension X: <缺的协议> {}`，一个都不缺时什么也不生成。member 角色的行为不变：访问级别跟随宿主，宿主已手写的成员跳过并发 warning，贴在非 struct 上报 error（extension 角色此时静默返回，不重复报错）。
- **宏声明**从 `Utilities`（`Sources/Support/Utilities/Macros/LocatableLayoutWrapping.swift`）搬到 `MachOSwiftSection`，与 `ResolvableLocatableLayoutWrapper` typealias 放在同一个文件。扩展宏要在声明里写出 `conformances: LocatableLayoutWrapper, Resolvable`，这两个协议分别在 MachOKitExtensions 与 MachOResolving，`Utilities` 看不到。宏与 typealias 同名不冲突：宏只在 `@` 后面查找。`MachOSwiftSection` target 直接声明对 `MachOMacros` 的依赖（此前经 `Utilities` 间接拿到）。
- **98 处用法**：`@LocatableLayoutWrapping` 换成 `@ResolvableLocatableLayoutWrapper`。直接写了 `: ResolvableLocatableLayoutWrapper` 的 51 处删掉它（`BuiltinTypeDescriptor` 留下 `TopLevelDescriptor`），`GlobalActorReference` 删掉 `: LocatableLayoutWrapper`；经子协议遵循的 46 处声明不动——子协议还带着 `where Layout: …` 约束与关联类型，删不得。
- **覆盖率扫描器**（`PublicMemberScanner`）按新宏名认出宿主、补上 `layout` / `offset` 两个成员，覆盖率契约与 baseline 不变。
- **不变的**：每个类型生成的存储成员逐字相同，读取行为不变，所以不跑渲染 A/B。下游仓库（RuntimeViewer、MachOObjCSection、MachOKitUI、swift-decompiler 等）没有一处用到旧宏名，改名不留 deprecated 别名。
- **没问就定的假设**：
  - `GlobalActorReference`、`MetadataBounds`、`ClassMetadataBounds` 此前不是 `Resolvable`，改后多出这个遵循。`Resolvable` 的默认实现就是按布局整块读，三者都没有自己的 `resolve`，行为不变；只是公开 API 多了一个遵循，属于增量变化。
  - 0027 当初保留声明处协议名的两条理由不再成立：宏名就是协议名，`grep ResolvableLocatableLayoutWrapper` 仍能找到全部遵循者；多重遵循的类型现在把其余协议写在声明处、这一个交给宏，宏只补缺的，不会重复。
  - 历史文档（0027 正文、2026-09-11 的任务报告、演进账本的旧章节）保持原样，它们记的是当时的事实；只在 0027 的决策日志末尾追加一行指向本提案。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-11-06 | Created as Draft | 宏与 `ResolvableLocatableLayoutWrapper` 遵循总是成对出现，用户要求把遵循收进宏并给宏改名 |
| 2026-11-06 | 宏名取 `@ResolvableLocatableLayoutWrapper` | 用户在三个候选里选定：与它补上的遵循同名，搜索协议名仍能找到所有遵循者 |
| 2026-11-06 | 按轻量档写精简提案；状态 Draft → Accepted → In Progress | 用户批准方案；提案随功能分支的第一个提交落盘，不先单独提交进 `next`：`next` 的检出里有别处未提交的改动，其中包括提案索引所在的 `Documentations/README.md` |
