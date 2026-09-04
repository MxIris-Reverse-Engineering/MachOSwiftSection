# Draft - 大栈任务执行器接入与跨版本并行准备

- **状态**: In Progress
- **作者**: JH
- **创建日期**: 2026-09-03
- **最后更新**: 2026-09-03
- **所属愿景**: 无
- **关联提案**: swift-demangling 提案 0014「大栈 TaskExecutor」（上游前置，执行器本体在那边；本提案只做接入）；[0018-self-contained-abi-layer](0018-self-contained-abi-layer.md)（同一轮调研产物，互不依赖）
- **实现分支 / PR**: `feature/large-stack-executor-and-cross-version-parallelism`，[PR #122](https://github.com/MxIris-Reverse-Engineering/MachOSwiftSection/pull/122)（堆叠在 ABI 提案的 PR #121 之上，base 随其合并切到 `next`）
- **配套文档**: [LargeStackTaskExecutorAdoption.md](../Internal/LargeStackTaskExecutorAdoption.md)（实现说明）；任务报告 [2026-09-03-large-stack-executor-and-cross-version-parallelism.md](../Internal/TaskReports/2026-09-03-large-stack-executor-and-cross-version-parallelism.md)

## 摘要

这个库的 async 是「签名上的 async」：306 个 async 函数、72 个公开 async 入口，但除了 `TypeIndexing` 的两个 actor 之外没有任何 actor，真正会挂起任务的地方只有三处。真正的开销在打印路径：每次 `printSemantic` 都跳到 swift-demangling 的 8 MB 大栈线程再用信号量停住协作线程，每次固定多付 8–21 µs；索引路径已经用 `withLargeStack` 包住整趟符号扫描摊掉了跳转，打印循环因为是 async 包不住。本提案做两件事：**接入上游提供的大栈 `TaskExecutor`**——`StackSafeExecutor` 按线程剩余栈空间探测，任务只要跑在 16 MB 线程上，demangle / print / remangle 全部内联、零跳转，同步被调方一并受益；**把 diff / evolution 的多版本准备改成并行**——各版本是不同文件、缓存按 UUID 键控、读取走 mmap，实测三版本并行约 2 倍。两者都不改任何输出，逐字节由渲染 A/B 守住。版本内逐定义并行不在本提案内。

## 动机

### 1. 打印路径每次调用付一次线程往返，而且现在包不住

`Node.printSemantic(using:)`（`Sources/SwiftDeclarationRendering/Extensions/Node+.swift:117-122`）走 `DemanglingPrinter<SemanticString, Self>.print`，上游那里是 `StackSafeExecutor.execute`：探测当前线程剩余栈是否 ≥ 2 MB（`swift-demangling/Sources/Demangling/Utils/StackSafeExecutor.swift:161-169`，用 `pthread_get_stackaddr_np` / `pthread_get_stacksize_np` 算），不够就提交到 8 MB 池线程并在信号量上等（`:183-200`）。Darwin 给协作线程和 libdispatch 线程的栈都是 512 KB，探测永远不通过。实测（`Documentations/Internal/Reviews/2026-07-31-node-store-migration-review.md:80-96`，release）：

| 场景 | 每次调用固定开销 | 放大倍数 |
|---|---|---|
| 小树打印 | 8.2 µs | 2.28× |
| 916 字符真实符号 | 20.8 µs | 1.14× |

索引侧的同类问题已修：`SymbolIndexStore.buildStorageImpl` 把整趟扫描包进 `withLargeStack`（`Sources/MachOSymbols/SymbolIndexStore.swift:456-482`），10 万符号 1317 → 701 ms。打印侧做不到，评审记录 `:128` 写明：「打印侧的循环在 `SwiftDeclarationPrinter` 里，是 async，同步的 `withLargeStack` 无法包裹。真要摊销需要自定义一个跑在 8 MB 线程上的 `SerialExecutor`，或把打印批次改成同步。」`Node+.swift:79,109` 的注释还引用着上游已不存在的 `executeWithUncheckedSendability`。

### 2. 多版本准备是串行的，而它们彼此独立

`DiffCommand` 先 `oldBuilder.prepare()` 再 `newBuilder.prepare()`（`Sources/swift-section/Commands/DiffCommand.swift:82-87`）；`AnySwiftEvolutionInterfaceBuilder.prepare()` 用 for 循环逐版本 `await`（`Sources/SwiftInterface/AnySwiftEvolutionInterfaceBuilder.swift:96-100`）。2026-09-02 的实测（debug，SwiftUI 三个归档 cache）：单版本索引 202 s 墙钟 / 182 CPU 秒，单线程；三版本三进程并行 396 s 墙钟，约 2 倍加速。85% 的时间在 `SwiftDiffableInterfaceBuilder.prepare()` 的逐定义 `index(in:)`。

### 3. 「全库 async 化」不是答案

2026-09-03 的调研结论：把剩下的同步模块也改成 async 只是再套一层壳，且撞硬墙——`deinit`、属性 getter、`Hashable` / `Codable`、`for … where` 子句不能 `await`；MachOKit 与 Swift 运行时调用是同步的；`Node` 与三个 Definition 是非 `Sendable` 的 class；协作线程 512 KB 栈让 async 化后探测 100% 不通过；符号扫描改逐个 `await` 反而比现在的批量内联慢。收益在「并行」和「让 async 代码跑在大栈上」，不在「挂起」。

## 前期调研

- **SE-0417 任务执行器偏好**（Swift 6.0 实现，运行时 macOS 15 / iOS 18 / tvOS 18 / watchOS 11 / visionOS 2）：`withTaskExecutorPreference(_:operation:)` 内的 `nonisolated async` 函数、子任务与默认 actor 都跑在指定执行器上；非结构化 `Task {}` 不继承。本包部署下限 macOS 10.15 / iOS 13（`Package.swift:975`），需要 `#available` 门控。
- **上游探测机制与本提案的契合**：探测看的是剩余栈空间而非线程身份，所以任何 16 MB 线程上 `execute` / `executeAsync` 都直接内联（`StackSafeExecutor.swift:84-86,118-120`）。上游已有 `LargeStackThreadPool`（按 QoS 分五个子池、`pthread_create` + `pthread_attr_setstacksize` 建线程、`NSCondition` 停车，`:358-746`）；`@_spi(Internals) public enum StackSafeExecutor`（`:41-42`）。已登记问题：打印器 768 层上限 × 每层约 11.6 KB ≈ 8.9 MB，超过 8 MB worker（上游 `Documentations/KnownIssues.md` #4）——上游提案 0014 给执行器线程开 16 MB。
- **swift-demangling 版本**：本仓库钉 0.6.0；0.6.1 的 QoS 改动让 dump 慢 3–4 倍（2026-09-02 二分）；0.6.2 含分池修复，2026-09-03 用户实测速度已恢复；**0.6.3 已于 2026-09-03 打 tag 推到远端（tag 指向 `8f32e30`，含提案 0014 的实现 `eaf7e76`）**。
- **上游 0.6.3 的实际接口**（由 swift-demangling 会话确认，与本提案详细设计一致）：`@_spi(Internals) import Demangling` 后用 `StackSafeExecutor.taskExecutor`，类型 `LargeStackTaskExecutor: TaskExecutor`，`@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)`；`withTaskExecutorPreference(StackSafeExecutor.taskExecutor) { … }` 或 `Task(executorPreference: StackSafeExecutor.taskExecutor, priority: …) { … }`（`executorPreference` 在 `priority` 之前）；非 Darwin 平台没有这个符号。上游落地时用户批准了四处修订，接入侧无需改动：优先级映射直接用 `JobPriority` 原始值（它本身就是 Darwin QoS 类数值，`unspecified` 归 `DEFAULT`）；提交只用稳态额度（每类 `max(2, 核数)`），`enqueue` 从不阻塞；池建不出线程时回退到一次性 16 MB 专用线程，再回退到 `DispatchQueue.global(qos:)`，绝不在 `enqueue` 里就地跑；执行器线程 16 MB——实测 8 MB 线程上打印器 380 层、remangler 200 层先于计数器 SIGBUS，16 MB 上同深度完整完成、计数器先触发（打印器 383 层起 `<<too complex>>`，remangler 260 层起 `.tooComplex`），所以 `KnownIssues` #4 在执行器路径上对打印器与 remangler 关闭；`TypeDecoder` 需要约 30 MB、仍会先爆栈（它本就不经 `StackSafeExecutor`）。上游文档：`Documentations/StackSafety.md` 第八节。
- **接入时要守的两条上游契约**：非结构化 `Task {}` 不继承偏好，库入口若在内部起 `Task` 必须显式传 `executorPreference`；一个 job 阻塞线程等同类另一个 job 会耗尽该类 worker，契约与协作线程池相同——`SharedCache` 的 `NSCondition` 等待正是这种阻塞，跨版本并行的并发上限因此不应超过核数。
- **跨版本并行的安全性**：`MachOFile.identifier` 按 LC_UUID 键控（`MachOKitExtensions/Sources/MachOKitExtensions/MachORepresentableWithCache.swift:16-33`），五个 `SharedCache` 单例全部按此键分片；本仓库描述符读取走 `MemoryMappedFile`（`Sources/MachOReading/Extensions/MachOFile+.swift:21-31`）；demangler 池按核数扩。三进程实测已证明可并行；进程内并行只多了共享 `SharedCache` 字典锁与 `PerImageCacheEvictionRegistry` 的 `NSLock`，都是短临界区。
- **版本内并行为什么不做**：MachOKit 自己的读取有 124 处 `fileHandle.seek` + `read`（`MachOFile.swift`、`DyldCache.swift`、`_DyldCacheFileRepresentable.swift` 等）共用一个句柄，两个线程交错就读错位置；`index(in:)` 的 `guard !isIndexed` 是非原子的检查加赋值（`Sources/SwiftDeclaration/Components/Definitions/TypeDefinition.swift:166`、`ExtensionDefinition.swift:176`、`ProtocolDefinition.swift:158`）。前者不在本仓库，需要 MachOKit 改 mmap 读或每个分片独立 `MachOFile` 实例，另起提案。
- **内存**：`evolution --interface` 路径 N 个索引器本来就同时常驻，约 190 MB / 版本；lineage / JSON 路径现在逐版本释放（三版本峰值 308 MB），并行后同时常驻的索引器数等于并发上限。
- **已有的真挂起点**（并行改造不会碰）：`SymbolIndexStore.prepareWithProgress` 的 `AsyncStream`（`SymbolIndexStore.swift:1264-1276`）、上游 `executeAsync` 的 continuation、`TypeIndexing` 的 actor。
- **顺带发现**：`SwiftDeclarationIndexer.swift:782` 的 `await symbolIndexStore.memberSymbols(...)` 等的是同步函数，是空的 `await`；`Utilities/ConcurrentMap.swift` 零调用方。

## 提议方案

1. **执行器由上游提供，本仓库在库入口自装偏好。** 新增一个小工具（放 `MachOSymbols`，它已 `@_spi(Internals) import Demangling` 且位于所有消费者之下）：

   ```swift
   public enum LargeStackTaskExecution {
       /// Process-wide switch; hosts that manage their own executor set it to false.
       @Mutex public static var isEnabled: Bool = true

       /// Runs `body` with the demangler's large-stack task executor as the task
       /// executor preference when the runtime has one; otherwise runs `body`
       /// unchanged. Output is identical either way; only where the work runs differs.
       public static func run<Success: Sendable>(_ body: () async throws -> Success) async rethrows -> Success
   }
   ```

   以下入口在函数体最外层包一次 `LargeStackTaskExecution.run`：`SwiftDeclarationIndexer.prepare()` / `updateConfiguration(_:)`；`SwiftInterfaceBuilder.prepare()` / `printRoot()`；`SwiftDiffableInterfaceBuilder.prepare()`；`AnySwiftEvolutionInterfaceBuilder.prepare()` / `printAnnotatedInterface()` / `annotatedBlocks()`；`SwiftDiffableInterfaceRenderer.printAnnotatedInterface(format:)` / `annotatedDiffBlocks()`；`SwiftDeclarationPrinter.printTypeDefinition` / `printProtocolDefinition` / `printExtensionDefinition` / `printDefinition`（RuntimeViewer 逐类型打印绕过 `printRoot` 的路径）；`SwiftDump` 的 `Dumpable.dump(using:in:)` 家族。已在该执行器上的嵌套包裹不产生跳转。宿主零改动。
2. **macOS 15 / iOS 18 以下静默回退**：`run` 里 `#available` 不满足或执行器不可用就直接执行 `body`，行为与今天完全一致。
3. **跨版本并行**：`AnySwiftEvolutionInterfaceBuilder.prepare(maximumConcurrentPreparations:)`（默认 `min(版本数, activeProcessorCount)`），用 `withThrowingTaskGroup` 按窗口并发、结果按版本序落位；`DiffCommand` 两个 builder 用 `async let`；`EvolutionCommand` 的 lineage 输入加载同样按窗口并行；CLI 增加 `--jobs N`（`--jobs 1` 即串行）。事件 handler 的 stderr 输出会交错，属可接受。
4. **前置条件**：上游提案 0014 已随 0.6.3 落地（2026-09-03）；本提案获准后第一步把 swift-demangling pin 抬到 0.6.3（跳过 0.6.1），并在同一份 `Package.resolved` 下做一次 0.6.0 vs 0.6.3 的 SwiftUICore `dump` / `interface` 计时作为基线。

### 非目标

- 版本内逐定义并行（等 MachOKit 侧的读取线程安全，另起提案）。
- `SharedCache` / `SymbolIndexStore` 的 async 建表路径（2026-09-03 评估收益小，不做）。
- 恢复符号扫描的多路并行（扫描只占导出约 1%）。
- 抬部署下限。
- 任何输出格式变化。

## 详细设计

### `LargeStackTaskExecution.run`

```swift
@_spi(Internals) import Demangling

public enum LargeStackTaskExecution {
    @Mutex public static var isEnabled: Bool = true

    public static func run<Success: Sendable>(_ body: () async throws -> Success) async rethrows -> Success {
        if isEnabled, #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *) {
            return try await withTaskExecutorPreference(StackSafeExecutor.taskExecutor, operation: body)
        }
        return try await body()
    }
}
```

`StackSafeExecutor.taskExecutor` 由上游 0.6.3 以 `@_spi(Internals)` 提供（上游提案 0014）。`withTaskExecutorPreference` 要求 `Success: Sendable`：`SemanticString`、`[[EvolutionLine]]`、`[[DiffLine]]`、`Void` 均满足。

### 入口包裹

每个入口的改动形态一致，以 `printRoot` 为例：

```swift
public func printRoot() async throws -> SemanticString {
    try await LargeStackTaskExecution.run {
        try await printRootContents()
    }
}
```

`@Dependency` 的 task-local 在执行器上正常传播（不再有 pthread 跳转），`SharedCache` 的 `NSCondition` 等待与 `os_unfair_lock` 会占住执行器线程，与今天占住协作线程等价。

### 跨版本并行

```swift
extension AnySwiftEvolutionInterfaceBuilder {
    public func prepare(maximumConcurrentPreparations: Int = ProcessInfo.processInfo.activeProcessorCount) async throws
}
```

实现：`withThrowingTaskGroup` 中最多 `maximumConcurrentPreparations` 个在飞，每个子任务 `try await versionUnit.prepare()`；子任务继承执行器偏好。`prepare()` 无参形态保留为默认值调用。`DiffCommand`：

```swift
async let oldPrepared: Void = oldBuilder.prepare()
async let newPrepared: Void = newBuilder.prepare()
try await (oldPrepared, newPrepared)
```

### 验证

- 渲染 A/B（`Scripts/run-rendering-ab-verification.py`）逐字节：执行器开 / 关各一次。
- 计时表：SwiftUI 与 SwiftUICore 的 `dump` 与 `interface`，执行器关 vs 开；`evolution` 三版本 `--jobs 1` vs 默认。
- 测试：`LargeStackTaskExecution.run` 在支持的系统上把体跑在上游执行器（以上游提供的探测 / 计数钩子断言零跳转）、不支持时原样执行；并行 `prepare` 与串行 `prepare` 产出的 snapshot 逐字节相同；`--jobs` 解析。

## 替代方案考量

- **全库 async 化**：见动机 §3，否决。
- **把打印批次改回同步再包 `withLargeStack`**：不依赖 macOS 15，但砍掉现有 async API，RuntimeViewer 全部调用点重写。否决。
- **本仓库自建执行器**：不等上游发版，但进程里两套大栈线程池，栈策略分散在两个仓库。2026-09-03 用户选上游。
- **宿主自己装偏好**：更显式，但每个宿主都要改，漏装就回到逐次跳转。用户选库入口自装。
- **SE-0392 自定义 `SerialExecutor` 的 actor 给 macOS 14 兜底**：多一套机制维护，覆盖的只是一个系统版本。用户选静默回退。
- **默认串行、`--jobs` 显式打开**：内存行为与今天一致，但默认拿不到加速。用户选默认并行、上限取核数。

## 影响

### 源码兼容性（source compatibility）

**纯新增**：`LargeStackTaskExecution`、`prepare(maximumConcurrentPreparations:)`、CLI `--jobs`。所有既有签名不变；入口包裹对调用方透明。

### ABI 兼容性

不适用 —— 本库以 SPM 源码分发，使用方每次重新编译。

### 下游影响

本仓库：`MachOSymbols`、`SwiftIndexing`、`SwiftInterface`、`SwiftPrinting`、`SwiftDump`、`swift-section`。依赖：swift-demangling ≥ 0.6.3。

跨仓库：RuntimeViewer、MachOKitUI、SymbolViewer 无需改动即受益；RuntimeViewer 若自行管理执行器可置 `LargeStackTaskExecution.isEnabled = false`。

### 文档与示例

AGENTS.md（`SwiftInterface` / `SwiftIndexing` 条目补执行器一句；测试环境节补「协作线程 512 KB」的对策）；`Documentations/Internal/Reviews/2026-07-31-node-store-migration-review.md:128` 那条待办标记已解决；`Node+.swift` 过期注释修正；演进账本；Changelog。

## API 演进与废弃策略

无废弃项。`prepare()` 无参形态保留。

## 落地步骤

1. 抬 swift-demangling pin 到 0.6.3（上游 0014 已 Implemented），跑一次基线计时（SwiftUI / SwiftUICore dump 与 interface）作为对照。
2. 库内所有在 `prepare` / `printRoot` 等入口内部起的非结构化 `Task {}` 逐一核对，显式传 `executorPreference`。
3. `MachOSymbols` 加 `LargeStackTaskExecution` 与测试。
4. 逐入口包裹（索引器 → interface builder → printer 入口 → diff / evolution → dump），每一步全量测试。
5. 跨版本并行：库 API、`DiffCommand`、`EvolutionCommand`、`--jobs`，串行 / 并行 snapshot 等价测试。
6. 渲染 A/B 逐字节 + 计时表写入实现说明。
7. 文档同批：AGENTS.md、评审记录待办、`Node+.swift` 注释、演进账本、Changelog 与 `Version.swift`。

**收尾时判断**：实现说明——写（执行器为什么按剩余栈探测就能生效、哪些入口包裹了、计时数据）；术语——「大栈执行器」视落地时是否在多处出现再决定是否入术语表。

## 决策日志

| 日期 | 变更 | 说明 |
|------|------|------|
| 2026-09-03 | Created as Draft | 用户问「整个库都使用 async 环境是否可行」；调研结论是全库 async 化不可取，收益在大栈执行器与并行 |
| 2026-09-03 | 范围：执行器 + 跨版本并行 | 澄清提问第一轮：版本内并行另起提案（卡在 MachOKit 共享 FileHandle） |
| 2026-09-03 | 执行器归上游 swift-demangling | 同轮：复用 `LargeStackThreadPool`，进程内一个池；上游提案 0014 |
| 2026-09-03 | 库入口自装偏好；macOS 15 以下静默回退；默认并行上限取核数 | 第二轮 |
| 2026-09-03 | 上游提案由本人在 sibling 仓库起草；上游发版号 0.6.3 | 第三轮与收尾确认；用户告知 0.6.2 已实测恢复 |
| 2026-09-03 | 上游 0.6.3 已发版，接口与四处修订对齐 | swift-demangling 会话通知：tag `8f32e30`、实现 `eaf7e76`；`StackSafeExecutor.taskExecutor` / `LargeStackTaskExecutor`；优先级映射改用 `JobPriority` 原始值、只用稳态额度、双级回退、16 MB 实测深度。状态仍为 Draft，等用户置 Accepted 后再抬 pin 与开工 |
| 2026-09-03 | Accepted → In Progress | 用户指示「基于上一个 PR 实现 async 提案」，视为批准；分支自 ABI 提案的分支切出，第一步抬 swift-demangling pin 到 0.6.3 |
| 2026-09-03 | 落地偏差：`isEnabled` 初值读环境变量 | 提案只有静态开关；加 `MACHO_SWIFT_SECTION_LARGE_STACK_EXECUTOR=0` 是为了让渲染 A/B 与计时用同一个二进制比较开 / 关，宿主不必重编 |
| 2026-09-03 | 落地偏差：并行用通用 `concurrentMap(maximumConcurrency:)` 而非 `async let` | `DiffCommand` 与 evolution 的 lineage 输入同样需要窗口化，一个 `Utilities` 帮手三处复用，`--jobs 1` 与默认走同一条代码路径 |
| 2026-09-03 | 落地偏差：CLI 的 `dump` 循环不再额外包一层 | 六个 `Dumpable.dump` 已各自包裹，CLI 逐类型进出执行器约一万跳、零点几秒，远小于原来逐符号跳转 |
| 2026-09-03 | 核对：库内零处非结构化 `Task {}` | 唯一的 `withTaskGroup` 在 `TypeIndexing.TypeDatabase`，结构化、继承偏好；落地步骤 2 无需改动 |
| 2026-09-03 | 验证：全量 1637 测试通过；计时 −16% ~ −23%（单版本）、2.0×（三版本 evolution）；四种配置输出逐字节一致 | 数据见实现说明「实测数据」；0.6.0 → 0.6.3 仅抬 pin 持平，证明 0.6.1 的回归未带入 |
| 2026-09-03 | 收尾判断：写实现说明；「大栈执行器」入术语表 | 实现说明记录探测机制为何免改调用点、入口清单与嵌套免费、回退与开关、并行安全性与不做版本内并行的原因、计时表；术语在 AGENTS.md / 提案 / 实现说明 / 账本多处出现，登记 `Documentations/Glossary.md` |
