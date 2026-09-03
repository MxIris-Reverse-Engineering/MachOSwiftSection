# 大栈任务执行器接入与跨版本并行

提案：[draft-large-stack-executor-and-cross-version-parallelism](../Evolutions/draft-large-stack-executor-and-cross-version-parallelism.md)。上游执行器本体：swift-demangling 提案 0014（`Documentations/StackSafety.md` 第八节）。本文记录落地后的形态、那些从签名上看不出来的决策，以及计时数据。

## 改了什么

| 之前 | 之后 |
|---|---|
| 打印路径每次 `printSemantic` / demangle / remangle 都由 `StackSafeExecutor` 探测调用线程剩余栈；协作线程 512 KB 永远不过，每次调用跳到 8 MB 池线程再用信号量停住（release 实测每次 8–21 µs） | 库的 async 入口用 `LargeStackTaskExecution.run` 把整段 task 放到 swift-demangling 0.6.3 的 16 MB `LargeStackTaskExecutor` 上；探针在每个入口都通过，全程原地执行，零跳转 |
| swift-demangling pin `0.6.0 ..< 0.7.0`（实际锁在 0.6.0，因为 0.6.1 的 QoS 改动慢 3–4 倍） | pin `0.6.3 ..< 0.7.0`，跳过 0.6.1 / 0.6.2 |
| `AnySwiftEvolutionInterfaceBuilder.prepare()` 逐版本串行 `await`；`DiffCommand` 先 old 后 new；`EvolutionCommand` 的 lineage 输入逐个加载 | `prepare(maximumConcurrentPreparations:)`（默认核数、`1` 即旧顺序）；`diff` / `evolution` 的输入按窗口并行索引，CLI 新增 `--jobs N` |
| 无通用的「限并发 map」 | `Utilities` 的 `Collection.concurrentMap(maximumConcurrency:_:)`：窗口化 task group，结果按源序，首错重抛 |
| `Node+.swift` 的注释引用上游已不存在的 `executeWithUncheckedSendability` | 改为如实描述 `execute` 与执行器路径的关系 |

输出不变：渲染 A/B 逐字节一致（见「实测数据」）。

## 从签名看不出来的决策

### 执行器为什么不用改 demangler 的任何调用点

`StackSafeExecutor` 的探针（`currentThreadHasSufficientStack`）用 `pthread_get_stackaddr_np` / `pthread_get_stacksize_np` 算调用线程剩余栈是否 ≥ 2 MB，看的是**栈**不是**线程身份**。所以只要 task 跑在一条 16 MB 线程上，`execute` / `executeAsync` 的探针在每一层都通过、直接内联——同步被调方（`printSemantic`、`demangleAsNodeTransient`、remangle）一并受益，一个调用点都不用碰。这也是为什么本库这边的改动只有「包一层」：`withTaskExecutorPreference(StackSafeExecutor.taskExecutor) { body }`。

### 为什么在库入口自装，而不是让宿主装

宿主漏装一处就回到逐次跳转，而且每个宿主（RuntimeViewer、MachOKitUI、SymbolViewer、CLI）都得改。库入口自装后宿主零改动；想自己管执行器的宿主置 `LargeStackTaskExecution.isEnabled = false`。这是提案第二轮澄清时用户的选择。

### 包了哪些入口

| 模块 | 入口 |
|---|---|
| `SwiftIndexing` | `SwiftDeclarationIndexer.prepare()`（`updateConfiguration(_:)` 经它） |
| `SwiftInterface` | `SwiftInterfaceBuilder.prepare()` / `printRoot()`；`SwiftDiffableInterfaceBuilder.prepare()`；`AnySwiftEvolutionInterfaceBuilder.prepare(maximumConcurrentPreparations:)` / `printAnnotatedInterface()` / `annotatedBlocks()`（pack façade 委托）；`SwiftDiffableInterfaceRenderer.printAnnotatedInterface(format:)` / `annotatedDiffBlocks()` |
| `SwiftPrinting` | `SwiftDeclarationPrinter.printTypeDefinition` / `printProtocolDefinition` / `printExtensionDefinition` / `printDefinition`（RuntimeViewer 逐类型导出绕过 `printRoot` 的路径） |
| `SwiftDump` | 六个 `Dumpable.dump(using:in:)` 遵循者（`Struct` / `Class` / `Enum` / `Protocol` / `ProtocolConformance` / `AssociatedType`） |

**嵌套免费**：`printRoot` 里再进 `printTypeDefinition`、父类型的嵌套子类型循环再进 `printTypeDefinition`，都是「已在执行器上再包一层」。SE-0417 的 `withTaskExecutorPreference` 在当前执行器就是目标执行器时不切换，`nestedRunsStayOnTheSameThread` 钉住线程不变。CLI 的 `dump` 循环按类型逐个调 `dump`，每个类型进出执行器各一跳，SwiftUICore 五千余类型约一万跳、总计零点几秒，远小于原来每个符号一跳，故 CLI 侧没有再包一层。

**壳 + 体的拆分**：`printExtensionDefinition` 与 `printDefinition` 原本函数体就是整段逻辑（后者还是 `@SemanticStringBuilder`），result builder 的函数体不能直接套一个 `run { }` 闭包再 return，所以拆成非 builder 的壳（过滤 + `run`）与 builder 的体（`printExtensionDefinitionContents` / `printDefinitionContents`），与提案 0016 拆 `printIncluded…` 的手法相同。注意 `printIncludedExtensionDefinition` 这个名字已被 0016 的 builder 体占用，新壳体用了 `…Contents` 后缀。

### 非结构化 `Task {}` 的核对结果

SE-0417：非结构化 `Task {}` 不继承执行器偏好。核对 `Sources/` 全部：库内**零处**非结构化 `Task`（唯一的 `withTaskGroup` 在 `TypeIndexing.TypeDatabase`，是结构化子任务，继承偏好）。`childTasksInheritTheExecutor` 钉住子任务继承这一前提，跨版本并行靠它。以后若在包裹的入口内起 `Task {}`，必须显式传 `executorPreference:`。

### 静默回退、`isEnabled` 与环境变量

`run` 里 `#available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)` 不满足、非 Darwin、或 `isEnabled == false`，都直接 `try await body()`——与接入前完全一致的行为（跳转照付）。`isEnabled` 的初值读环境变量 `MACHO_SWIFT_SECTION_LARGE_STACK_EXECUTOR`（等于 `"0"` 即关），用途是让渲染 A/B 与计时能用**同一个二进制**比较开 / 关两种状态，宿主不必为此重编。它是提案未列出的一个小补充。

### 主 actor 调用方

本包的库 target 没有开启 SE-0461 `NonisolatedNonsendingByDefault`（`Package.swift` 里定义了这些 upcoming feature 常量，但只有测试 target 接 `testSettings`，且它几乎为空），所以库的 async 入口是经典 `nonisolated`：从 `@MainActor` 调用会离开主 actor。接入前它落在协作线程（512 KB，逐次跳转），接入后落在执行器线程——对 RuntimeViewer 这类从主线程发起导出的宿主是纯收益。若将来开启 SE-0461，主 actor 调用会留在主线程（主 actor 有自己的 executor，偏好不生效），主线程栈 8 MB 探针本就通过，也无损失；从默认 actor 调用则仍在执行器上（SE-0417：默认 actor 继承偏好）。

### 跨版本并行为什么安全、上限为什么取核数

各版本是不同文件：`MachOFile.identifier` 按 LC_UUID 键控，五个 `SharedCache` 单例全部按此分片；描述符读取走 `MemoryMappedFile`；demangler 池按核数扩。2026-09-02 已用三个进程并行证明可行，进程内并行只多了 `SharedCache` 字典锁与 `PerImageCacheEvictionRegistry` 的 `NSLock`，都是短临界区。窗口上限取核数的原因来自上游契约：一个 `prepare` 是整段 task，占住执行器的一条线程直到结束；执行器每个 QoS 类的稳态额度是 `max(2, 核数)`，窗口超过它只会排队，不会更快。`parallelPreparationMatchesSerialPreparation` 钉住并行与串行的接口、结构流、evolution JSON 逐字节一致。

### 版本内并行为什么不做

MachOKit 自己的读取有上百处 `fileHandle.seek` + `read` 共用一个句柄（`MachOFile.swift`、`DyldCache.swift` 等），两个线程交错就读错位置；`index(in:)` 的 `guard !isIndexed` 是非原子的检查加赋值。前者不在本仓库，需要 MachOKit 改 mmap 读或每个分片独立 `MachOFile` 实例，另起提案。

### `concurrentMap(maximumConcurrency:)` 的错误语义

窗口化 `withThrowingTaskGroup`：先提交 `window` 个，每完成一个再提交一个，结果按源序落位。首个错误经 `group.next()` 抛出，task group 在作用域退出时取消并等待在飞的子任务（`prepare` 不检查取消，所以在飞的会跑完，结果丢弃），**尚未启动的元素永远不启动**（`theFirstFailureIsRethrownAndPendingElementsNeverStart`）。哪个错误先到是调度决定的——串行时固定是最旧版本的错误，并行时不一定；只影响错误报文，不影响成功路径。

### `--jobs` 在 CLI 校验而库端 clamp

命令行上的 `--jobs 0` 是笔误，`ValidationError("--jobs must be at least 1.")` 立刻报；库 API 的 `maximumConcurrentPreparations` 小于 1 则按 1 处理（`preparationWindowIsClampedNotValidated`），因为宿主可能直接把「核数 - 1」之类的算式传进来，为一个下界抛错不值得。

## 实测数据

release 二进制，宿主 dyld cache（macOS 26.5.2，10 核 Apple Silicon），每项跑两次取两次的值；四个配置的输出逐字节一致（`cmp`）。

**单版本 `dump` / `interface`（`--uses-system-dyld-shared-cache -n <image>`，秒）**

| 配置 | SwiftUICore dump | SwiftUICore interface | SwiftUI dump | SwiftUI interface |
|---|---|---|---|---|
| swift-demangling 0.6.0（ABI 分支，接入前） | 48.8 / 48.6 | 56.4 / 57.0 | 79.4 / 79.9 | 87.5 / 89.4 |
| 0.6.3 仅抬 pin（接入前） | 48.5 / 48.4 | 55.8 / 56.2 | 77.2 / 79.7 | 89.3 / 89.6 |
| 0.6.3 + 执行器**关**（`MACHO_SWIFT_SECTION_LARGE_STACK_EXECUTOR=0`） | 48.6 / 48.7 | 56.4 / 55.7 | 78.0 / 79.7 | 88.4 / 89.7 |
| 0.6.3 + 执行器**开**（默认） | **40.6 / 40.4** | **47.0 / 47.1** | **61.3 / 60.2** | **71.2 / 70.9** |

执行器带来 16–23% 的墙钟缩短（SwiftUICore −17% / −16%，SwiftUI −23% / −20%）；0.6.0 → 0.6.3 本身无差别（0.6.1 的回归已在 0.6.2 修掉）。剩下的时间是索引与打印本身——跳转只是每次调用的固定开销，它在 SwiftUI 这种符号更多的镜像上占比更大。

**三版本 `evolution`（SwiftUI，归档 cache 15.5 / 26.5.2 / 27.0-beta.6，秒）**

| 配置 | `--interface` | lineage 报告 |
|---|---|---|
| 执行器关 + `--jobs 1`（接入前的形态） | 306.7 | 282.4 |
| 执行器开 + `--jobs 1` | 242.6 | 233.8 |
| 执行器开 + 默认并行（3 个版本同时） | **151.9** | **139.4** |

并行本身 1.6–1.7×（三版本不等长，最慢的那个定墙钟），叠加执行器 2.0×；`--jobs 1` 与默认的输出逐字节一致。

**渲染 A/B**（`Scripts/run-rendering-ab-verification.py`，基线 = ABI 分支 `feature/self-contained-abi-layer`，候选 = 本分支；基线 swift-demangling 0.6.0、候选 0.6.3，其余 pin 一致）：执行器**开**与**关**（`MACHO_SWIFT_SECTION_LARGE_STACK_EXECUTOR=0`）各跑一轮，**两轮均 78 对输出逐字节一致，0 差异**。覆盖当前系统 dyld cache（归档 cache 目录名与脚本期望不符，按文档回退到系统 cache）、模拟器运行时 iOS 15.5 / 18.5 / 18.6 / 26.5、进程内 MachOImage 三条路径的 dump 与 interface。脚本自己记录的墙钟也印证了收益：候选侧 SwiftUI dump 60 s / interface 71 s 对基线 80 s / 88 s，关掉执行器后候选与基线持平（48 s vs 48 s）。

## 测试锚点

- `LargeStackTaskExecutionTests`（MachOSymbolsTests）：执行器线程栈 ≥ 16 MB 且线程名前缀 `swift-demangling.task-executor.`；`execute` / `executeAsync` 在体内不跳线程；嵌套 `run` 不换线程；子任务继承；`isEnabled = false` 时留在调用线程；值与错误透传。
- `BoundedConcurrentMapTests`（SwiftInterfaceTests）：源序、窗口不超、窗口 1 严格串行、窗口内真并发（rendezvous，超时即失败）、首错语义、空输入。
- `SwiftEvolutionInterfaceBuilderTests.parallelPreparationMatchesSerialPreparation` / `preparationWindowIsClampedNotValidated`。
- `DiffCommandValidationTests` / `EvolutionCommandValidationTests`：`--jobs` 解析与下界校验。

## 已知限制

- 执行器只在 macOS 15 / iOS 18 起可用；以下系统行为不变。
- `KnownIssues.md` #4（上游）在执行器路径上对打印器与 remangler 关闭，`TypeDecoder`（需约 30 MB）仍会先爆栈——它本就不经 `StackSafeExecutor`。
- 事件 handler 的 stderr 输出在并行 `prepare` 时会交错。
- 并行 `prepare` 期间同时常驻的索引器数等于窗口大小，内存峰值随之上升（`evolution --interface` 路径本来就全部常驻，lineage / JSON 路径从「逐版本释放」变为「窗口内同时常驻」）。
