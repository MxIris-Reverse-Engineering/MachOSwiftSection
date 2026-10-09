# ObjC 侧的外部变化（ObjCChanges/）

本目录跟踪**本仓库之外**发生、会改变二进制里 ObjC 相关事实的变化：Swift Evolution 提案、clang / LLVM 的 ABI 改动、objc4 runtime 的变化、Apple SDK 与系统二进制的新形态。每一篇回答三件事：上游变了什么、编出来的二进制因此长成什么样、我们的读取器（ObjC 成员恢复、`@objc @implementation` 识别、`swift-section objc`）会不会因此崩、读错或漏读。

它和相邻目录的分工：

- `Evolutions/` 记录**我们自己**的改动决策。这里的某条变化要动手支持时，另立一份提案，并从这里链过去。
- `References/` 是外部资料的译文，讲的是已经稳定的编码规则。这里记录的是还在变动中的东西，状态会随上游推进而更新。
- `ObjCMemberRecovery.md`、`ObjCImplementationClassRecognition.md` 等实现说明描述我们今天怎么读。这里描述的是「明天可能出现、今天还读不到」的形态。

## 写作约定

- **一个话题一篇**，PascalCase 文件名。同一件事的 clang 侧和 Swift 侧（例如 direct method 的新 ABI 与 `@objcDirect` 提案）放在同一篇，因为二进制里的痕迹是同一套。
- **头部固定四个字段**：上游链接、上游状态、最后核对日期、我们的动作（观望 / 已立提案 / 已支持）。上游状态变化时原地更新，并在文末「核对记录」追加一行，不另起新文件。
- **影响要分级写清**：不受影响、静默漏信息、会读错、会崩。静默漏信息最危险，因为输出看起来完整。
- **「将来支持时的要点」只写约束，不写方案**。方案属于提案；这里只记下现在就知道、到时候容易忘的坑。
- 每新增一篇，同批更新下表与 [`Documentations/README.md`](../../README.md) 索引。

## 状态总表

| 话题 | 上游状态（核对日期） | 对我们的影响 | 我们的动作 |
|---|---|---|---|
| [ObjCDirectMethods.md](ObjCDirectMethods.md)：direct method 的新 ABI 与 Swift `@objcDirect` | clang 侧已合入 LLVM 23；Swift 侧是第二次 pitch，未进入审查，实现 PR 未合（2026-10-09） | 静默漏信息：这类方法不在 method list 里，ObjC 成员恢复看不到它们；不崩、不读错 | 观望，未立提案 |
