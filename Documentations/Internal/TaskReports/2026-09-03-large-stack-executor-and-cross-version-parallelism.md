# 2026-09-03 大栈任务执行器接入与跨版本并行

## 问题

用户问「整个库都使用 async 环境是否可行」。核实结果：306 个 async 函数、72 个公开 async 入口，但除 `TypeIndexing` 的两个 actor 外没有 actor，真正会挂起的地方只有三处；真正的开销在打印路径——每次 `printSemantic` 都由 swift-demangling 的 `StackSafeExecutor` 探测调用线程剩余栈，协作线程 512 KB 永远不过，每次调用跳到 8 MB 池线程再用信号量停住（release 每次 8–21 µs，1.14–2.28×）。索引侧已用同步 `withLargeStack` 摊掉；打印循环是 async，包不住。此外 diff / evolution 的多版本 `prepare` 串行，而各版本彼此独立。

## 调研

- 全库 async 化不可取：`deinit` / getter / `Hashable` / `for … where` 不能 `await`；MachOKit 与运行时调用同步；`Node` 与三个 Definition 是非 `Sendable` 的 class；async 化后协作线程 512 KB 让探测 100% 不通过；符号扫描改逐个 `await` 反而比批量内联慢。收益在「并行」和「让 async 代码跑在大栈上」。
- 上游探测看的是**剩余栈**不是线程身份，所以 16 MB 线程上的 task 每个入口都内联——只需一个 `TaskExecutor`（SE-0417，macOS 15 / iOS 18 起）。上游已有 `LargeStackThreadPool`（按 QoS 分池、`pthread_attr_setstacksize`）可复用。
- swift-demangling 版本线：0.6.1 的 QoS 改动慢 3–4 倍（2026-09-02 二分）；0.6.2 分池修复、用户实测恢复；0.6.3 含执行器（提案 0014，`StackSafeExecutor.taskExecutor`，`@_spi(Internals)`）。
- 跨版本并行安全：`MachOFile.identifier` 按 LC_UUID 键控，`SharedCache` 全按此分片，描述符读取走 mmap；三进程并行实测约 2 倍。版本内并行卡在 MachOKit 共享 `FileHandle` 的 seek + read。
- 库内非结构化 `Task {}`：零处。

## 澄清提问（完整档，四轮 + 收尾）

1. 范围：执行器 + 跨版本并行；版本内并行另起提案。
2. 执行器归上游 swift-demangling，进程内一个池（后改为分池共码）。
3. 库入口自装偏好；macOS 15 以下静默回退；默认并行上限取核数。
4. 上游提案由本人在 sibling 仓库起草；执行器线程 16 MB、跳转池 8 MB；`@_spi(Internals)`；发版 0.6.3。
5. 收尾：用户确认「其他没问题」，0.6.2 已实测恢复；之后指示「基于上一个 PR 实现 async 提案」，视为 Accepted。

## 最终方案

见提案与实现说明。要点：`MachOSymbols.LargeStackTaskExecution.run` 包住索引器 `prepare`、interface builder 的 `prepare` / `printRoot`、diffable builder 的 `prepare`、evolution builder 的 `prepare` / 两个渲染入口、diff renderer 的两个入口、printer 的四个逐定义入口、六个 `Dumpable.dump`；`AnySwiftEvolutionInterfaceBuilder.prepare(maximumConcurrentPreparations:)`（默认核数）；`diff` / `evolution` 的输入按窗口并行，CLI `--jobs`；`Utilities.concurrentMap(maximumConcurrency:)`；pin 抬到 0.6.3。

## 实际执行

worktree `.worktrees/MachOSwiftSection-LargeStackExecutor`，分支 `feature/large-stack-executor-and-cross-version-parallelism`，基于 `feature/self-contained-abi-layer`（ABI 提案的分支，PR #121 未合并时堆叠）。

1. **抬 pin**：`"0.6.3" ..< "0.7.0"`，`Package.resolved` 解析到 0.6.3（`8f32e30`）；其余 pin 不动。同一份 `Package.resolved` 下先做 0.6.0 vs 0.6.3 的 release 计时（见下）。
2. **`LargeStackTaskExecution`**（`Sources/MachOSymbols/LargeStackTaskExecution.swift`）：`isEnabled`（`@Mutex`，初值读 `MACHO_SWIFT_SECTION_LARGE_STACK_EXECUTOR`）、`isSupported`、`run`。`withTaskExecutorPreference` 在当前工具链接受非 `Sendable` 的 `operation`（用 `swiftc -typecheck -swift-version 6 -strict-concurrency=complete` 探针确认），所以 `run` 的 `body` 不必 `@Sendable`——各入口闭包捕获非 `Sendable` 的 Definition class 才能过编译。
3. **逐入口包裹**：按提案清单。`printExtensionDefinition` / `printDefinition` 拆壳 + 体；`printIncludedExtensionDefinition` 名字已被提案 0016 的 builder 体占用（首次编译撞名），壳体改名 `…Contents`。
4. **并行**：`Utilities/BoundedConcurrentMap.swift`；evolution builder 的 `prepare` 加参数；pack façade 跟随；`DiffCommand` 两侧、`EvolutionCommand` 两条路径都走 `concurrentMap`；`--jobs` 校验 ≥ 1。
5. **测试**：`LargeStackTaskExecutionTests`（6）、`BoundedConcurrentMapTests`（7）、evolution builder 的并行等价 + clamp（2）、`DiffCommandValidationTests`（3）、`EvolutionCommandValidationTests` 加 `--jobs`（2）；CI filter 加入五个套件。首次跑：`EvolutionLine` 的属性是 `content` 不是 `text`，改后 32 个全过。
6. **文档同批**：实现说明、术语表、AGENTS.md（`MachOSymbols` / `SwiftIndexing` / `SwiftInterface` 条目 + 测试环境节）、`Modules/SwiftInterface.md`、README 索引、评审记录待办标记已解决、`Node+.swift` 过期注释、演进账本、Changelog 0.19.0 + `Version.swift`。

## 验证

- 新增 / 改动的五个套件 32 个测试通过；全量 `swift test --skip IntegrationTests`：**1637 个测试、305 个套件全部通过**（385 s），含以往偶发的 `SharedCache` 并发墙钟测试。
- 计时（release，宿主 cache；详表见实现说明）：SwiftUICore dump 48.6 → 40.5 s、interface 56 → 47 s；SwiftUI dump 79 → 61 s、interface 89 → 71 s（执行器关 → 开，−16% 到 −23%）；0.6.0 → 0.6.3 仅抬 pin 持平。三版本 SwiftUI `evolution --interface` 306.7 s（关 + `--jobs 1`）→ 242.6 s（开 + `--jobs 1`）→ 151.9 s（开 + 默认并行）；lineage 282.4 → 233.8 → 139.4 s。
- 输出：单版本四种配置（0.6.0 / 0.6.3 pin-only / 执行器关 / 执行器开）的 dump 与 interface 逐字节一致；evolution 的 `--jobs 1` 与默认并行、执行器开与关逐字节一致。
- 渲染 A/B（`Scripts/run-rendering-ab-verification.py`，基线 = ABI 分支，候选 = 本分支）：执行器开、关各一轮，**两轮均 78 对逐字节一致，0 差异**（当前系统 cache、模拟器运行时 iOS 15.5 / 18.5 / 18.6 / 26.5、进程内 MachOImage）。

## 与计划的偏差

- `isEnabled` 初值读环境变量（提案只有静态开关）——为 A/B 与计时服务。
- 并行用通用 `concurrentMap(maximumConcurrency:)` 而非 `async let`。
- CLI `dump` 循环不再额外包一层（逐类型跳转代价可忽略）。
- 主 actor 段落：库 target 未开启 SE-0461，async 入口从 `@MainActor` 调用会离开主 actor 落到执行器线程（实现说明已按事实写）。

## Review 修复批次（2026-09-04）

并行 review 会话对 PR #122 给出 15 条发现（原文与处置见 [Roadmaps/2026-09-04-pr122-review-findings.md](../../../Roadmaps/2026-09-04-pr122-review-findings.md)）。最严重的一条已被审查者独立复现：`concurrentMap` 用 `addTask`，取消后剩余元素全部启动。修复：`addTaskUnlessCancelled`、被拒即抛 `CancellationError`（不能返回残缺数组，`result!` 会崩）。其余四条真缺陷是测试层面的：执行器线程断言没挡 `isEnabled`、环境变量只认 `"0"`、并行等价测试先串行焐热缓存、窗口断言退化成串行也绿。用户三项裁定：Dispatcher 进程级递归锁串行化 handler 调用、lineage 默认窗口保持核数、stderr 加输入标签（`ConsoleEventHandler(label:)` + `eventHandlersPerVersion`）。审查者对 F9「重复门」的修法在实际中不可行（`#available` 必须出现在使用点），登记 A32；`TypeDatabase` 的同形 `addTask` 缺注入缝写不出复现测试，登记 A33。

验证：受影响 7 个套件 43 个测试通过；突变检查——把 `addTaskUnlessCancelled` 改回 `addTask`、去掉 dispatcher 锁、测试 guard 只看 `isSupported`，并在 `MACHO_SWIFT_SECTION_LARGE_STACK_EXECUTOR=0` 下跑对应四个测试：`cancellationStopsSubmittingPendingElements`（元素 1 启动、不抛错）、`aHandlerSharedByConcurrentDispatchersIsNeverEnteredConcurrently`（handler 被并发进入）、`bodyRunsOnAnExecutorThreadWhenSupported` 与 `demanglerEntriesInsideTheBodyDoNotHop`（环境变量关闭时假红）四个测试共 7 处失败；改回后同一环境下全绿。全量 `swift test --skip IntegrationTests` 结果见下一行。全量 1649 测试 / 307 套件，仅 `SharedCache.resolve under Swift Concurrency` 的两个墙钟并行度断言在全量并行时假失败（已知），单独重跑通过。

