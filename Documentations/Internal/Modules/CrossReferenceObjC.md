# CrossReferenceObjC

交叉引用分析的 Objective-C 层：经 `objc_msgSend`、selector 桩或 libobjc 专用入口的消息发送与 `super` 发送、发送的接收者、classref / superref / 类对象引用，ObjC 方法列表给出的函数名（`ObjCMethodNames`），按 selector 与按类的预筛，以及 libobjc 的运行时辅助函数名单（`ObjCRuntimeHelperNames`）。以识别器（`ObjCCodeReferenceRecognizer` 与它为每次扫描建的会话）接进核心层的扫描。

- 提案：[0097-offline-cross-references-and-symbolication](../../Evolutions/0097-offline-cross-references-and-symbolication.md) 第 2 步从 `CrossReferenceAnalysis` 拆出；发送入口见 [0076-objc-runtime-send-entry-points](../../Evolutions/0076-objc-runtime-send-entry-points.md)。
- 依赖：`CrossReferenceCore`、MachOKit、MachOObjCSection、`MachOFoundation`、`ARM64InstructionDecoding`。不是 library product，接口都是 `package` 级；公开的只有 `ReceiverClassHint`，经 `CrossReferenceAnalysis` 重导出。
- 将来的落脚处：MachOObjCSection，改名 `ObjCCodeReferences`。只许 import 核心层能 import 的模块加 MachOObjCSection 与 `CrossReferenceCore`（`CrossReferenceLayerBoundaryTests`）。
- 怎么工作、关键契约：见 [CrossReferenceAnalysis](CrossReferenceAnalysis.md) 的「三层与识别器」「libobjc 的发送入口」「类引用」各节。
