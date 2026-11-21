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
| SwiftSectionKit | [SwiftSectionKit.md](SwiftSectionKit.md) | ✅ 已写（调用方指南：[SwiftSectionKit.md](../../SwiftSectionKit.md)） |
| swift-section (CLI) | [SwiftSectionKit.md](SwiftSectionKit.md) | ✅ 已写（与 SwiftSectionKit 同篇：包装层只剩 flag 映射、错误翻译、流路由与退出码） |
| SwiftIndexing | — | 待写 |
| SwiftPrivateDiscriminators | [SwiftPrivateDiscriminators.md](SwiftPrivateDiscriminators.md) | ✅ 已写（提案 [0063-private-declarations](../../Evolutions/0063-private-declarations.md)） |
| SwiftPrinting | — | 待写 |
| SwiftSpecialization | — | 待写 |
| SwiftThunkAnalysis | [SwiftThunkAnalysis.md](SwiftThunkAnalysis.md) | ✅ 已写（入门：[AccessorThunkResolutionExplained.md](../AccessorThunkResolutionExplained.md)） |
| CrossReferenceAnalysis | [CrossReferenceAnalysis.md](CrossReferenceAnalysis.md) | ✅ 已写（提案 [0072-cross-reference-analysis](../../Evolutions/0072-cross-reference-analysis.md)） |
| ARM64InstructionDecoding | MachOKitExtensions 的 [ARM64InstructionDecoding.md](https://github.com/MxIris-Reverse-Engineering/MachOKitExtensions/blob/main/Documentations/Internal/ARM64InstructionDecoding.md) | 已搬去 MachOKitExtensions（提案 `move-cross-reference-layers`）：手写的指令字读取与跳板形状，CrossReferenceAnalysis 与 SwiftThunkAnalysis 经 `@_spi(Internals)` 用 |
| MachOAddressResolution（原 CodeAddressResolution） | MachOKitExtensions 的 [MachOAddressResolution.md](https://github.com/MxIris-Reverse-Engineering/MachOKitExtensions/blob/main/Documentations/Internal/MachOAddressResolution.md) | 已搬去 MachOKitExtensions：离线的地址空间、桩链、槽解析与 cache 镜像定位，线程读取与交叉引用文件模式共用 |
| MachOCodeReferences（原 CrossReferenceCore） | MachOKitExtensions 的 [MachOCodeReferences.md](https://github.com/MxIris-Reverse-Engineering/MachOKitExtensions/blob/main/Documentations/Internal/MachOCodeReferences.md) | 已搬去 MachOKitExtensions：交叉引用与语言无关的核心层；总说明仍在 [CrossReferenceAnalysis.md](CrossReferenceAnalysis.md) |
| ObjCCodeReferences（原 CrossReferenceObjC） | MachOObjCSection 的 [ObjCCodeReferences.md](https://github.com/MxIris-Reverse-Engineering/MachOObjCSection/blob/next/Documentations/Internal/ObjCCodeReferences.md) | 已搬去 MachOObjCSection：交叉引用的 ObjC 层；总说明仍在 [CrossReferenceAnalysis.md](CrossReferenceAnalysis.md) |
| SwiftAttributeInference | — | 待写 |
| SwiftDeclaration | [SwiftDeclaration.md](SwiftDeclaration.md) | ✅ 已写 |
| SwiftDeclarationRendering | — | 待写 |
| SwiftDump | — | 待写 |
| SwiftInspection | — | 待写（ObjC 一侧已拆进 SwiftObjCInterop） |
| SwiftObjCInterop | [SwiftObjCInterop.md](SwiftObjCInterop.md) | ✅ 已写（拆分来历：[0089-swift-objc-interop-module](../../Evolutions/0089-swift-objc-interop-module.md)） |
| SwiftLayout | [SwiftLayout.md](SwiftLayout.md) | ✅ 已写（专题：[StaticLayoutEngine.md](../StaticLayoutEngine.md)、[StaticLayoutDependencyClosure.md](../StaticLayoutDependencyClosure.md)） |
| SwiftDiffing | — | 待写（专题：[ABIDiffDesignAndLimitations.md](../ABIDiffDesignAndLimitations.md)、[ABIEvolutionDesign.md](../ABIEvolutionDesign.md)） |
| TypeIndexing | — | 待写（专题：[TypeIndexingPipeline.md](../TypeIndexingPipeline.md)） |
| SwiftOutputTransformer | — | 待写（专题：[OutputTransformerMigration.md](../OutputTransformerMigration.md)） |
| MachOSwiftSection | — | 待写 |
| MachOFoundation | — | 由 MachOKitExtensions 提供（2.0.0 起，同名 product）：再导出 `MachOBase`、`MachOSymbols`、`MachODependencies` |
| SwiftSymbols | [SwiftSymbols.md](SwiftSymbols.md) | ✅ 已写（Swift 符号索引 `SwiftSymbolIndexStore`；专题：[SymbolIndexStoreMemoryOptimization.md](../SymbolIndexStoreMemoryOptimization.md)） |
| MachOSymbols | — | 由 MachOKitExtensions 提供（2.0.0 起）：符号表、采集与 C/C++ 符号索引，实现说明 [SymbolIndex.md](https://github.com/MxIris-Reverse-Engineering/MachOKitExtensions/blob/main/Documentations/Internal/SymbolIndex.md) |
| MachOBase | — | 由 MachOKitExtensions 提供（2.0.0 起）：伞模块，ABI 层允许看到的全部——reading / resolving / pointers，不再再导出 `Utilities`（ABI 模块 `MachOSwiftSection` 自己再导出）；边界见 [SelfContainedABILayer.md](../SelfContainedABILayer.md) |
| MachOPointers | — | 由 MachOKitExtensions 提供（2.0.0 起）：相对 / 间接指针与 `SymbolOrElementPointer`（自 `MachOSymbolPointers` 并入的来历见 [SelfContainedABILayer.md](../SelfContainedABILayer.md)） |
| MachOReading / MachOResolving | — | 0.25.0 起是 MachOKitExtensions 包的模块（2.0.0 起，同名），实现说明在该包的 `Documentations/Internal/ReadingContextAbstraction.md`；本库怎么用它们见 [ReadingContextAbstraction.md](../ReadingContextAbstraction.md) |
| MachOCaches | — | 由 MachOKitExtensions 提供（2.0.0 起），实现说明 [SharedCache.md](https://github.com/MxIris-Reverse-Engineering/MachOKitExtensions/blob/main/Documentations/Internal/SharedCache.md) |
| MachODependencies | — | 由 MachOKitExtensions 提供（2.0.0 起），实现说明 [DependencyResolution.md](https://github.com/MxIris-Reverse-Engineering/MachOKitExtensions/blob/main/Documentations/Internal/DependencyResolution.md) |
| MachOSwiftSectionC | — | 待写 |
| SwiftSectionMacros | — | 待写 |
| Utilities | — | 待写 |
| SwiftSectionFixtureSupport / SwiftSectionTestingSupport(C) / baseline-generator | — | 待写（测试基础设施，可合并成一篇）；通用部分建在 MachOKitExtensions 的 `MachOFixtureSupport` / `MachOTestingSupport` 上，见 [FixtureTestingAndContinuousIntegration.md](../FixtureTestingAndContinuousIntegration.md)「测试支持的通用部分在 MachOKitExtensions」 |

（`Demangling` / `Semantic` 来自上游包 swift-demangling / swift-semantic-string，`MachOKitExtensions` / `MachOObjCSection` 是 sibling 外部包，文档归各自仓库——上表标「由 MachOKitExtensions 提供」的模块也一样。）
