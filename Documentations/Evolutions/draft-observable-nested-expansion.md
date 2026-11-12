# Draft - `@Observable` 的展开分两层：先出 `@ObservationTracked`，再展开它

- **状态**: In Progress
- **创建日期**: 2026-11-12
- **最后更新**: 2026-11-12
- **实现分支**: `feature/observable-nested-expansion`

## 摘要

提案 [0093](0093-observable-macro-folding.md) 的分块展开（`printMacroExpansionParts`），把每个被跟踪属性的 accessor 块与存储 `_x` 直接算作展开 `@Observable` 的结果。Swift 源码里这是两层。`ObservableMacro` 是 MemberAttributeMacro，只给每个被跟踪属性加一个 `@ObservationTracked`，此外写出成员与 conformance；accessor 块与存储是 `ObservationTrackedMacro` 的 accessor 与 peer 两个角色写的。Xcode 也是在展开结果里再展开一次 `@ObservationTracked`，才看到这两样。RuntimeViewer 要照这个分层显示，用户定由本库印出两层，RuntimeViewer 只负责摆放。

## 方案

改动位置：

- `Sources/Output/SwiftPrinting/MacroExpansionPart.swift:11` 有三处改动。
  - `Placement` 加 `.trackedPropertyAttribute(named:)`，放在属性折叠出的声明上方。
  - 加 `nestedExpansions: [NestedExpansion]`。`NestedExpansion` 有三个字段：嵌套宏的属性在 `content` 里的 UTF-8 范围（`attributeUTF8Range`）、宏（`macro`），以及展开它的分块（`parts`）。
  - `anchorKind` 改成存储属性。两层的分块都指向同一个折叠声明的区域 `attachedMacroTrackedProperty(.observable, named:)`。
- `Sources/Output/SwiftPrinting/SwiftDeclarationPrinter+ObservableMacro.swift:318`（`printIncludedObservableMacroExpansionParts`）：每个被跟踪属性改出一块 `.trackedPropertyAttribute(named:)`，内容是那个属性，写作 `@Observation.ObservationTracked`（打开 module selector 时是 `@Observation::ObservationTracked`）。它的 `nestedExpansions` 只有一项，宏是 `.observationTracked`，分块就是今天的 `.trackedProperty(named:)`：先是 accessor 块（含 init 行），再是存储，内容一字不改。成员块与 conformance 块不变。
- `Sources/Declaration/SwiftDeclaration/Model/SwiftAttachedMacro.swift:30` 加 `SwiftAttachedMacro.observationTracked`。`Sources/Analysis/SwiftInspection/ObservableMacroRecognition.swift:97` 旁边加它的静态名字节点，因为打印器按节点身份缓存片段。

明确不动：

- 折叠形态。
- `--expand-macros` 的展开形态。
- 定位标记。
- 整块展开 `printMacroExpansion`：仍是两层合起来的样子。它印的是一块独立的声明，挂在别的声明上的 `@ObservationTracked` 放不进去。

没问就采用的假设：

- `.trackedProperty(named:)` 只出现在嵌套展开里，顶层不再有。分块 API 还没发版，RuntimeViewer 跟着改。
- 第一层属性块的可见性与它锚定的折叠声明一致，和今天的 accessor 块是同一条规则。
- 第一层分块的内容就是这个属性本身，所以嵌套宏的范围覆盖整块内容。

### 落地步骤

每一步单独构建通过、相关测试通过后提交并推送；测试在 Ultra 上跑。

1. [x] `SwiftAttachedMacro.observationTracked` 与它的名字节点；`MacroExpansionPart` 的 `.trackedPropertyAttribute(named:)`、`NestedExpansion` 与存储的 `anchorKind`；`printMacroExpansionParts` 出两层；分块测试改成两层。
2. [x] 文档：`Modules/SwiftInterface.md`、`AGENTS.md` 里分块的说明；全量测试。

测试：

- 第一层每个被跟踪属性一块，内容是属性，带一项嵌套展开，范围覆盖属性文本。
- 嵌套分块与今天的 `.trackedProperty` 分块逐字节相同。
- fixture 的四个变体都要过。

### 验证

在 JHs-Mac-Studio-Ultra（macOS 27.2、Xcode 26.6）的沙盒里跑，swift-demangling 用它 `next` 的 8809c1b 作本地兄弟依赖。

- 相关套件（`@Observable` 与 init accessor 的测试、投影、注释结构与嵌套定义区域的契约）88 个测试全过。
- 全量 2909 个测试，只有 `FileMappingTests.readersOfOneCacheFileShareOneMapping` 一条失败，基线上同样失败。
- 改动只在分块 API 里，折叠形态、展开形态与 dump 的输出都不变，所以不跑渲染 A/B。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-11-12 | Created as Draft | RuntimeViewer 要照 Swift 源码的两层展开 `@Observable`，用户定由本库印两层 |
| 2026-11-12 | 第一层的属性写作 `@Observation.ObservationTracked`，经类型打印器印出 | 用户选定：与折叠形态的 `@Observation.Observable`、`@Observation.ObservationIgnored` 一致，module selector 也照样生效；宏源码写的是不带模块名的 `@ObservationTracked` |
| 2026-11-12 | 用户批准，开始实现；补上落地步骤 | 精简提案原本没有分步 |
| 2026-11-12 | 被导出过滤排除的属性两层都不出；属性块里不放标记区域 | 两层都摆在折叠声明旁边，声明被排除时宿主找不到锚点；嵌套宏的范围已经由 `attributeUTF8Range` 给出，不必再用 `marksAttachedMacros` 的区域 |
| 2026-11-12 | 实现完成，待用户看过后收尾 | 文档：`Modules/SwiftInterface.md` 与 `AGENTS.md` 已写两层；术语表不加新词，插件 skill 不涉及（CLI 没变） |
