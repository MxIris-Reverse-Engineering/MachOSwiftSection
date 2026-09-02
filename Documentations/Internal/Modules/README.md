# 模块参考文档（Modules/）

本目录是**按模块组织的参考文档**系列：每个库模块一篇，回答「这个模块是什么、内部分几个子系统、每个子系统的分工与关键契约是什么、细节去哪里看」。它是各模块的**权威入口**——专题文档（迁移记录、审计、提案实现说明）继续留在 `Internal/` 平铺层与 `Evolutions/`，模块文档负责把它们串起来。

写作约定：

- **一个模块一篇**，文件名与模块目录名一致（PascalCase + `.md`）。模块内子系统多的，每个子系统在文中占一个完整章节；已有专题文档覆盖的子系统写导读并链接，不复述。
- 内容以「代码里看不出来的东西」为主：子系统边界、跨文件契约、决策的为什么、测试锚点。逐行复述源码注释的内容不写。
- 与代码同批维护：模块的文件增删、子系统重组，模块文档在同一批次更新。
- 每新增一篇，同批更新本表与 [`Documentations/README.md`](../../README.md) 索引。

## 覆盖状态

| 模块 | 文档 | 说明 |
|---|---|---|
| SwiftInterface | [SwiftInterface.md](SwiftInterface.md) | ✅ 已写 |
| swift-section (CLI) | — | 待写 |
| SwiftIndexing | — | 待写 |
| SwiftPrinting | — | 待写 |
| SwiftSpecialization | — | 待写 |
| SwiftAttributeInference | — | 待写 |
| SwiftDeclaration | — | 待写 |
| SwiftDeclarationRendering | — | 待写 |
| SwiftDump | — | 待写 |
| SwiftInspection | — | 待写 |
| SwiftLayout | — | 待写（专题：[StaticLayoutEngine.md](../StaticLayoutEngine.md)、[StaticLayoutDependencyClosure.md](../StaticLayoutDependencyClosure.md)） |
| SwiftDiffing | — | 待写（专题：[ABIDiffDesignAndLimitations.md](../ABIDiffDesignAndLimitations.md)、[ABIEvolutionDesign.md](../ABIEvolutionDesign.md)） |
| TypeIndexing | — | 待写（专题：[TypeIndexingPipeline.md](../TypeIndexingPipeline.md)） |
| SwiftOutputTransformer | — | 待写（专题：[OutputTransformerMigration.md](../OutputTransformerMigration.md)） |
| MachOSwiftSection | — | 待写 |
| MachOFoundation | — | 待写 |
| MachOSymbols | — | 待写（专题：[SymbolIndexStoreMemoryOptimization.md](../SymbolIndexStoreMemoryOptimization.md)） |
| MachOPointers / MachOSymbolPointers | — | 待写 |
| MachOReading / MachOResolving | — | 待写 |
| MachOCaches | — | 待写 |
| MachODependencies | [MachODependencies.md](MachODependencies.md) | ✅ 已写 |
| MachOSwiftSectionC | — | 待写 |
| MachOMacros | — | 待写 |
| Utilities | — | 待写 |
| MachOFixtureSupport / MachOTestingSupport(C) / baseline-generator | — | 待写（测试基础设施，可合并成一篇） |

（`Demangling` / `Semantic` 来自上游包 swift-demangling / swift-semantic-string，`MachOKitExtensions` / `MachOObjCSection` 是 sibling 外部包，文档归各自仓库。）
