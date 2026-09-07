# PR #122 review findings（大栈执行器接入与跨版本并行，2026-09-04）

并行 review 会话（machoswiftsection-cf，xhigh code-review）对 PR #122（`feature/large-stack-executor-and-cross-version-parallelism` → `feature/self-contained-abi-layer`）的 15 条发现，已按四问逐条裁决：真缺陷 5、误报 1、设计取舍 / 风格 9。本表是原始清单与处置状态；「不修 / 误报 / 延后」的终审条目收录进 [ReviewAdjudications.md](../Documentations/Internal/ReviewAdjudications.md)（A25–A33）。

用户裁定：5 条真缺陷全修，另修重复门（后判为不可消除，A32）与冗余 import；F2 用 Dispatcher 进程级锁；F6 保持核数；F7 加输入标签。

## 真缺陷（5 条）

| # | 位置 | 问题 | 状态 |
|---|---|---|---|
| 1 | `Utilities/BoundedConcurrentMap.swift` | `addTask` 不响应取消：宿主取消后剩余元素全部启动（审查者独立编译复现：8 元素窗口 2 全部启动） | **已修**：`addTaskUnlessCancelled`，被拒即抛 `CancellationError`（不返回残缺数组——否则 `result!` 崩溃）；`cancellationStopsSubmittingPendingElements` 修复前红（元素 1 启动且不抛错） |
| 2 | `LargeStackTaskExecutionTests` | 四个执行器线程测试只挡 `isSupported`，`MACHO_SWIFT_SECTION_LARGE_STACK_EXECUTOR=0` 下必红 | **已修**：`executorIsActive` 同时看 `isEnabled`；修复前该环境变量下两个测试红，修复后绿 |
| 3 | `LargeStackTaskExecution.swift` | 环境变量只认字面量 `"0"`，`=false` 静默保持开启 | **已修**：`isEnabled(fromEnvironmentValue:)`——`0` / `false` / `no` / `off`（大小写、首尾空白不敏感）为关，其余为开；参数化测试 |
| 4 | `SwiftEvolutionInterfaceBuilderTests` | 先串行再并行，并行那轮全是缓存命中 | **已修**：并行先跑 |
| 5 | `BoundedConcurrentMapTests` | `maximumInFlight <= 3` 退化成串行也绿 | **已修**：新增三方 barrier 测试 `theWindowAdmitsItsFullWidth`（窗口不足 3 即挂起、超时失败） |

## 误报（1 条）

| # | 位置 | 结论 | 状态 |
|---|---|---|---|
| F11 | `SwiftDump/Dumpable/*` 六处 `import MachOFoundation` | 审查者按 0018 之前的再导出状态判断；实际必需 | **误报**，见 A25（附带子主张：`FoundationToolbox` 未声明属基线既有归 A23；`AnySwiftEvolutionInterfaceBuilder` 的 `import Utilities` 冗余已删） |

## 设计取舍 / 风格（9 条）

| # | 位置 | 问题 | 状态 |
|---|---|---|---|
| F2 | `AnySwiftEvolutionInterfaceBuilder` | 同一 handler 被 N 个版本的任务并发调用，`Handler` 无 `Sendable` | **已修**：`Dispatcher.dispatch` 用进程级 `NSRecursiveLock` 串行化 handler 调用（`EventDeliverySerializationTests`：修复前 4 个 dispatcher 并发投递时 handler 被并发进入，修复后最大在飞 1；可重入不死锁） |
| F6 | `EvolutionCommand` lineage 路径 | 默认窗口取核数，峰值内存倍增 | **保持**，见 A31 |
| F7 | `DiffCommand` / `EvolutionCommand` | stderr 诊断交错、无输入归属 | **已修**：`ConsoleEventHandler(label:)`，`diff` 用 `old` / `new`，`evolution` 每版本用其 label（新 init 参数 `eventHandlersPerVersion`），snapshot 输入用 label 或文件名；`ConsoleEventHandlerLineTests` |
| F8 | 执行器关闭时窗口占满协作线程池 | 属实 | **不修**，见 A30 |
| F4 | `.serialized` 不保护进程级开关 | 属实但无正确性影响 | **不修**，见 A29 |
| F9 | `run` / `isSupported` 双重可用性门 | 属实但不可消除 | **不修**，见 A32 |
| F12 | `run` 未转发 `#isolation` | 惯用法 | **不修**，见 A28 |
| F10 | 与既有 `concurrentMap(_:)` 同名 | 可读性 | **不修**，见 A27 |
| F13 | 逐定义入口每次包一层 | 维护性 | **不修**，见 A26 |

横向同类：`TypeDatabase.swift:76` 的裸 `addTask`（基线既有）延后，见 A33。
