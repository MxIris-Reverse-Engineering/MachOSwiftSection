# 0055 - `Sources/` 按层分组

- **状态**: Implemented
- **创建日期**: 2026-09-29
- **最后更新**: 2026-09-29
- **实现分支 / PR**: `refactor/group-sources`（worktree `.worktrees/MachOSwiftSection-SourcesGrouping`）

## 摘要

`Sources/` 下平铺着 31 个 target，找一个模块要在一长串名字里翻。本提案按 AGENTS.md 里的依赖层级把它们分进 8 个目录，每个 target 在 `Package.swift` 里用 `path:` 指向新位置。target 名、product 名、模块名一个都不变，RuntimeViewer 等下游从源码重编译时感知不到这次改动；只是纯搬迁，dump / interface 输出不受影响。

## 方案

分组（组目录 → 其中的 target）：

| 目录 | target |
|------|--------|
| `Support/` | `Utilities`、`MachOMacros` |
| `MachO/` | `MachOReading`、`MachOResolving`、`MachOPointers`、`MachOBase`、`MachOSymbols`、`MachOCaches`、`MachODependencies`、`MachOFoundation` |
| `ABI/` | `MachOSwiftSection`、`MachOSwiftSectionC` |
| `Analysis/` | `SwiftInspection`、`SwiftLayout`、`SwiftThunkAnalysis` |
| `Declaration/` | `SwiftDeclaration`、`SwiftIndexing`、`SwiftAttributeInference`、`SwiftSpecialization`、`TypeIndexing` |
| `Output/` | `SwiftDeclarationRendering`、`SwiftOutputTransformer`、`SwiftPrinting`、`SwiftDump`、`SwiftInterface`、`SwiftDiffing` |
| `Executables/` | `swift-section`、`baseline-generator` |
| `TestSupport/` | `MachOFixtureSupport`、`MachOTestingSupport`、`MachOTestingSupportC` |

目录多了一层，下面几处靠「源文件正好在 `Sources/<Target>/` 下」算路径的代码要跟着改，否则测试变红：

- **fixture 路径**：`MachOFileName` / `MachOImageName` 里 `SymbolTests*` 的 rawValue 是相对「解析它的源文件所在目录」的路径（`loadFromFile`、`MachOSwiftSectionFixtureTests.resolveFixturePath`、`InProcessMetadataPicker.resolveFixturePath` 三处用 `#filePath` 解析），`../../Tests/…` 改为 `../../../Tests/…`。
- **源码扫描测试**：`PrintFailureEventTests` 把 `Sources` 下一层当模块名来豁免 CLI 与测试支持模块，改为取下两层；`MachOSwiftSectionCoverageInvariantTests` 的 `Models/` 路径加上 `ABI/`。`NodeStoreMigrationInvariantTests` 递归扫描整个 `Sources/`，不受影响。
- **CI**：`release.yml` 与 `version-check.yml` 写死的 `Sources/swift-section/Version.swift`。

未经询问所作的假设：

- `Tests/` 保持平铺，不在本次范围内。
- 活文档（AGENTS.md、Glossary、`SwiftEnumLayout` 两份公开文档、`Internal/` 下的主题笔记）里的 `Sources/<Target>` 路径全部改成新路径；带日期的记录（TaskReports、Reviews、Roadmaps、已落地提案、ProjectEvolutionLog、Changelogs）保留当时的路径——它们记录的是当时的状态，而且都是纯文本、不是链接，不会断。
- target 用字面量写 `path:`，不引入生成路径的 helper：字面量方便 grep，也不需要为新 target 多学一层抽象。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-09-29 | Created，用户要求「帮我分一下组，全部放在一个文件夹太杂了」 | — |
| 2026-09-29 | 选按层分 8 组，而不是粗分 4 组（MachO / Swift / 可执行 / 测试支持） | 用户选定；粗分方案里 `Swift/` 下仍有 16 个 target，没解决「太杂」 |
| 2026-09-29 | 修 fixture 路径时改 rawValue 的 `../` 层数，不改成以包根为锚 | 最小改动；三处解析器与 rawValue 的约定保持一致，AGENTS.md 记下这个深度假设 |
| 2026-09-29 | Implemented | `swift test --skip IntegrationTests` 原始退出码 0：19 批、2145 个测试、405 个套件全部通过，含三个依赖目录深度的扫描套件。纯搬迁、输出不可能变，不跑渲染 A/B 验证 |
| 2026-09-29 | 不写配套的使用指南 / 实现说明，不登记新术语 | 分组规则与深度假设一句话就说完，已写进 AGENTS.md；本次没有引入新词 |
