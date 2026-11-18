# CrossReferenceCore

交叉引用分析与语言无关的核心：读取层（`CrossReferenceMemory`，进程内与文件两种实现）、与读取器无关的镜像描述 `CodeImage` 与 `__LINKEDIT` 读法 `ImageLinkEdit`、镜像集 `CodeImageSet`（进程内、cache 文件、一组独立文件三个构造器）（镜像、路径、内存区间、按镜像缓存的函数表、链接关系与改名再导出）、函数表 `ImageFunctionTable` 与它的附件机制、指令扫描 `ReferenceScanner` 与寄存器跟踪 `RegisterFile`、调用目标解析 `CallTargetResolver`、按导入名与链接关系预筛、导出表起名 `ExportedFunctionNames`，以及识别器扩展点（`CodeReferenceRecognitionSession`、`CodeReferenceRecording`）。

- 提案：[draft-offline-cross-references-and-symbolication](../../Evolutions/draft-offline-cross-references-and-symbolication.md) 第 2 步从 `CrossReferenceAnalysis` 拆出。
- 依赖：MachOKit、`MachOFoundation`、`ARM64InstructionDecoding`、`CodeAddressResolution`（文件模式的槽解析与地址空间）。不是 library product，接口都是 `package` 级，不对外承诺。
- 将来的落脚处：MachOKitExtensions，改名 `MachOCodeReferences`（本库里的名字刻意不同，免得与已发布版本的同名模块冲突）。为此它只许 import MachOKitExtensions 将来也有的模块，源码里不许出现 `objc_` / `swift_` 开头的字面量，`CrossReferenceLayerBoundaryTests` 守着这两条。
- 怎么工作、各子系统的分工、关键契约与吞吐：见 [CrossReferenceAnalysis](CrossReferenceAnalysis.md) 的「三层与识别器」与「子系统」两节，这里不重复。
