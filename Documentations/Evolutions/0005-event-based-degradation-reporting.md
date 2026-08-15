# 0005 - 降级上报统一走事件：库侧不再自选落点，Dispatcher 兜底零 handler

- **状态**: Implemented
- **作者**: JH
- **创建日期**: 2026-08-16
- **最后更新**: 2026-08-16
- **所属愿景**: 无
- **关联提案**: 无直接依赖。落在 [0002](0002-declaration-model-descriptor-slimming.md) 让 wrapper materialization 变 throwing 之后——降级点变多正是本案的直接触发条件
- **实现分支 / PR**: `fix/event-based-diagnostics` → `feature/node-store-migration`（PR #103）
- **配套文档**: 待实现后补 `Documentations/Internal/EventBasedDegradationReporting.md`

## 摘要

库模块里 9 处「渲染失败了，写一行 stderr 接着走」的降级上报，全部改为派发 `SwiftIndexEvents` 事件；落点由宿主装的 handler 决定，库不再自选。配套三件事：`Dispatcher` 在零 handler 时有兜底（否则事件等于扔进黑洞）、`SwiftDiffableInterfaceBuilder` 把 `eventHandlers` 真正传给它的两个 printer、`ConsoleEventHandler` 从 stdout 改到 stderr。CLI 侧 5 处不参与本案，只把会抛 Objective-C 异常的 `FileHandle.write(_:)` 换成 `fputs`。

## 动机

三件事凑到了一起，单独修任何一件都不彻底。

**一、写 stderr 的那个重载会终止宿主进程。** 9 处用的都是 `FileHandle.standardError.write(Data(...))`。`-[NSFileHandle writeData:]` 在写失败时抛 `NSFileHandleOperationException`，Swift 接不住，进程当场 abort。触发条件是真实的：stderr 被关闭（`EBADF` 直接 raise），或宿主忽略 `SIGPIPE`（RuntimeViewer 这类 GUI）。两种场景都已实测复现，退出码 134。而这条路径很热——`printType` 每个 enum case 走一次，issue #102 记录过一次真实运行里有 8375 个失败定义。

**二、库不该替宿主决定诊断去哪。** os_log 对 GUI 宿主是对的（GUI 没有有意义的 stderr，RuntimeViewer 那边确实在用日志过滤器看这些，`RuntimeFieldLayoutBackend` 已经这么做了），但对 CLI 是错的（命令行工具的 os_log 输出去统一日志系统，终端和 `2>err.txt` 都是空的，CI 日志里什么都没有）。反过来 stderr 对 CLI 是对的、对 GUI 是浪费。**这个分歧无法在库里选对**，只能由宿主决定——而这正是 `SwiftIndexEvents` 早就搭好的分层。

**三、这 9 处兜底之所以存在，是因为某些路径的 sink 从来没接上。** `SwiftDiffableInterfaceRenderer` 的两个 printer 用 `.init(in:)` 构造，handler 数组是空的；它的公开初始化器压根不收 handlers；而 `SwiftDiffableInterfaceBuilder.init` 明明收了 `eventHandlers`，却只把它给了 indexer。于是「派发事件」在 diff 路径上等于什么都没做，只好退回写 stderr。修 sink 才是治本。

## 前期调研

### 现状代码怎么走的

`Dispatcher.dispatch` 是 `for handler in handlers { handler.handle(event: event) }`。handlers 为空时循环零次直接返回——**没有任何信号**。

失败上报因此分裂成两条路：

- `dispatchingCatchedThrowing`（`SwiftDeclarationPrinter` 的私有方法，用非可选的 `eventDispatcher`）无条件 dispatch，没有兜底。它的三个调用方 `printVariable` / `printFunction` / `printSubscript` 被 diff renderer 以零 handler 的 printer 调用，失败静默。
- `printCatchedThrowing`（package 级自由函数，dispatcher 和 context 都是可选）有 `else` 分支写 stderr。但 `printField` / `printEnumCase` 传进去的 `eventDispatcher` 是**非可选**的存储属性，`if let` 永远成立，那个 `else` 从这两个调用点不可达——兜底在它自己注释点名的那条路径上是死代码。

### 验证过什么

- 两个可执行实验：closed-fd 与 `SIGPIPE` 被 `SIG_IGN` 两种宿主下，raising `FileHandle.write` 实测 abort（exit 134），`fputs` 对照组存活。
- `swift-section interface <binary> 2>&1 | head` 场景下进程先死于 `SIGPIPE`（141），`print` 也一样死——所以管道**不是**本案的增量危害，前两种才是。这一条纠正了首轮 review 的举例。
- `ConsoleEventHandler.definitionPrintFailed` 落点实为 stdout（`SwiftIndexEventsHandlers.swift:223` 的 `print(...)`）。若 CLI 直接装它，issue #102 的第三条诉求当场破功。
- `resolveOpaqueType(in:)` 的调用方之一 `SwiftDeclarationPrinter+Headers.swift:252` 手上就有 `eventDispatcher`——`Node+OpaqueType` 那处不是「拿不到 dispatcher」，是现在没传。

## 提议方案

**1. `Dispatcher` 负责零 handler 兜底。** `dispatch` 在 handlers 为空且事件属于失败类时，走 os_log 上报（`@Loggable` / `#log`，安全、不会 abort、GUI 宿主可见、CLI 可用 `log stream` 查）。非失败类事件（进度、started/completed）零 handler 时照旧丢弃——它们本来就是可选遥测。

这一处改动同时消灭 9 个调用点的 fallback 分支：调用点只管 dispatch，不再需要知道有没有 sink。

**2. 9 处库侧 stderr 全部改为 dispatch。** 缺少对应事件的位置新增**一个**通用降级事件而不是五个专属事件：

```swift
case renderingDegraded(context: DegradationContext, error: any Error)
```

`DegradationContext` 带一个来源枚举（`opaqueTypeRewrite` / `multiPayloadEnumIndex` / `dependencyLoad` / `subclassMap` / `extraDataProvider`）和一个可选名字。已有专属事件的位置（`definitionPrintFailed`）继续用专属的。

**3. 把 sink 接上。** `SwiftDiffableInterfaceBuilder.init` 的 `eventHandlers` 同时传给两个 printer；`SwiftDiffableInterfaceRenderer` 的公开初始化器新增 `eventHandlers` 参数（默认空，源码兼容）。

**4. `ConsoleEventHandler` 改写 stderr**，用 `fputs`。它是 CLI 的默认 handler，issue #102 的第三条诉求由它兑现。

**5. `resolveOpaqueType(in:)` 加 dispatcher 参数**，往下传给 `OpaqueTypeRewriter` 的初始化器（`visit(_:)` 是 override 改不了签名，但 rewriter 是自己的类，构造时注入）。

**6. CLI 侧 5 处只换安全写法。** `DiffCommand:231` / `EvolutionCommand:113` / `SnapshotCommand:51` 换 `fputs`；`SnapshotCommand:37-38` 是往 stdout 写 JSON 的产品输出，不是诊断，同样换掉危险重载但不改语义。

### 非目标

- **不改事件的语义分层**：`SwiftIndexEvents` 的现有 case 划分、handler 协议形状均不动。
- **不引入新的日志依赖**：os_log 兜底复用项目已在用的 `FoundationToolbox` 的 `@Loggable` / `#log`，不新增 package 依赖。
- **不动 CLI 的输出契约**：stdout 仍然只有生成的 Swift / JSON，stderr 仍然只有诊断。
- **不修本轮 review 的其余发现**：缓存驱逐两条、A/B 脚本、符号表按名查找等各自独立，不搭本案的车。

## 详细设计

### `Dispatcher.dispatch` 的兜底

```swift
public func dispatch(_ event: Payload) {
    let currentHandlers = handlers
    guard currentHandlers.isEmpty else {
        for handler in currentHandlers { handler.handle(event: event) }
        return
    }
    reportUnhandledFailure(event)
}
```

`reportUnhandledFailure` 对失败类事件走 `#log(.error, ...)`，其余 case 直接返回。**一次性读出 `handlers` 再判空**——`@Mutex` 每次访问都过一次锁，分两次读会让「读到非空、再读变空」成为可能。

### 为什么兜底放 Dispatcher 而不是每个调用点

调用点不知道自己有没有 sink（`.init(in:)` 构造的 printer 和装了 handler 的 printer 类型完全一样），这个判断只有 Dispatcher 做得了。放调用点就是现在这个局面：一半有兜底一半没有，且有兜底的那一半还是死代码。

### 死代码的处置

`printCatchedThrowing` 的 `dispatchingTo:` / `context:` 两个可选参数在本案后失去意义（所有调用点都有 dispatcher）。保留参数但去掉 `else` 分支，还是收敛成非可选，留到实现时按调用点实际情况定——两种都不影响外部，该函数是 package 级。

### 风险与接受的约束

- **`Payload` 加 case 对下游 `switch` 是源码破坏**，但仅限没写 `default` 的穷举 switch。仓库内两个 handler 都有 `default: break`；下游 RuntimeViewer 需实测确认。
- **os_log 兜底在 CLI 场景下用户看不见**，这是刻意的：CLI 应该装 `ConsoleEventHandler`，兜底只保证「忘了装 handler 时不至于完全静默」，不替代正确配置。
- **兜底会让此前静默的路径开始出声**。diff 路径上那些一直被吞掉的失败会突然可见——这是修复的目的，但首次运行可能出现大量输出，需要在 changelog 里提示。

## 替代方案考量

- **全部换成 `@Loggable` / `#log`**：库侧 9 处直接走 os_log。被否——CLI 用户在终端、`2>err.txt` 和 CI 日志里都看不到任何东西，比现状更糟，直接违背 issue #102 的报告场景（他抱怨的正是 CI/管道日志）。落点必须可由宿主决定。
- **全部换成 `fputs`，不动架构**：一行一处，风险最低。被否——只解决 crash，不解决「库替宿主选落点」和「diff 路径 sink 从未接上」，[4][5][6] 三条静默丢失原样保留，且 `StandardStreamCapture` 那个会挂死 `swift test` 的 fd 重定向工具还得继续维护。
- **给每个降级点加专属事件 case**（5 个新 case）：语义最精确。被否——公开 API 面扩大 5 倍，而这些位置的消费方式完全一致（记一笔、继续走），一个带来源枚举的通用 case 足够；日后某个来源真需要结构化字段再单独拆。
- **让 `Dispatcher` 默认自带一个 handler**：省掉 `dispatch` 里的分支。被否——「默认 handler 可被 `removeAllHandlers()` 移除」会让兜底重新变成黑洞，而兜底的全部意义就是不可移除。

## 影响

### 源码兼容性（source compatibility）

- `SwiftIndexEvents.Payload` 新增一个 case：对写了 `default` 的 `switch` 无影响；穷举 switch 需补分支。
- `SwiftDiffableInterfaceRenderer` 公开初始化器新增带默认值的 `eventHandlers` 参数：源码兼容。
- `resolveOpaqueType(in:)` 是 package 级，签名改动不影响外部。
- `ConsoleEventHandler` 落点从 stdout 变 stderr：**行为变更**，依赖它输出在 stdout 的脚本会受影响。这正是 issue #102 要求的修正，需在 changelog 明写。

### ABI 兼容性（条件项）

不适用——纯 SPM 源码分发，未开 library evolution，下游从源码重编译。

### 下游影响

RuntimeViewer 是已知消费者：它装的是 `OSLogEventHandler`，本案对它是纯增益（此前静默的降级现在有事件了）。需实测确认它没有对 `Payload` 的穷举 switch。

### 文档与示例

- `AGENTS.md` 的 `SwiftDeclaration` / `SwiftPrinting` 段落需说明「降级一律走事件，库不写流」。
- 新增 `Documentations/Internal/EventBasedDegradationReporting.md` 记录分层与兜底契约。
- `Documentations/Internal/ProjectEvolutionLog.md` 追加本轮工作段。

## API 演进与废弃策略

`printCatchedThrowing` 的 `dispatchingTo:` / `context:` 若收敛为非可选，因其为 package 级可直接改，无需废弃周期。公开面只增不改。

## 落地步骤

1. `Dispatcher.dispatch` 兜底 + `renderingDegraded` 事件 + `DegradationContext` 类型
2. `ConsoleEventHandler` 改 stderr
3. 9 处库侧 stderr → dispatch（含 `resolveOpaqueType` 签名改动）
4. `SwiftDiffableInterfaceBuilder` / `SwiftDiffableInterfaceRenderer` 接 sink
5. CLI 侧 5 处换 `fputs`
6. 测试改造：断言事件而非捕获 stderr；`StandardStreamCapture` 及其三个使用方随之退役
7. 文档同批次落盘

## 实施中偏离提案的地方

四处，都是实现时撞到的硬约束，不是改主意。

**一、兜底用 `os_log` 而不是 `@Loggable` / `#log`。** 提案写「复用项目已在用的 `@Loggable`」，实现时发现 `SwiftDeclaration` 用不了：那个宏在 `OSToolbox` 里，而项目依赖的是**远端** `FrameworkToolbox 0.4.x`，它不暴露 `OSToolbox` product（本地开发版仓库有，所以最初判断错了）。退回 `os.Logger` 也不行 —— 它要 macOS 11 / iOS 14，而本包部署到 macOS 10.15 / iOS 13。`os_log` 自 macOS 10.12 起可用，两个限制都不沾。行为等价（同一套 subsystem/category，RuntimeViewer 的日志过滤器照常匹配）。

**二、`SwiftDeclarationRendering` 里的两处够不到事件类型。** `Node+OpaqueType` 和 `MultiPayloadEnumDescriptorCache` 都在这个模块，而 `SwiftDeclaration`（事件所在）**依赖**它 —— 反向引用会成环。前者改为闭包注入（`OpaqueTypeDegradationReporter`，接口路径注入 dispatch 闭包、`SwiftDump` 路径落 os_log），后者没有注入点，直接落 os_log。这不算破例：os_log 正是 `Dispatcher` 兜底的同一个落点，区别只在有没有 sink 可接。

**三、printer 改为可注入 dispatcher，而不是让 builder 存 handlers。** 提案写「builder 把 `eventHandlers` 传给两个 printer」，但 `SwiftIndexEvents.Handler` 不是 `Sendable`，存进 `Sendable` 的 `SwiftDiffableInterfaceBuilder` 编译不过。改成给 `SwiftDeclarationPrinter` 加一个 package 级、接受现成 `Dispatcher` 的初始化器，renderer 传 `indexer.eventDispatcher`。结果更好：diff 路径的 indexer 和 printer 共用一个 dispatcher，宿主装一次 handler 两边都覆盖。`SwiftDeclarationIndexer.eventDispatcher` 与 `SwiftDeclarationPrinter.eventDispatcher` 因此从 internal 提升为 `package`。

**四、「不写 stdout」的测试从 fd 重定向改为源码扫描。** 提案第 6 步只说退役 `StandardStreamCapture`，但 `PrintFailureEventTests` 还有一个**私有**的 stdout 捕获，同样是进程级 fd 重定向、同样会被并行 suite 的输出干扰。改为扫描 `Sources/` 下所有非宿主模块的流写入（附带扫描器自检，含「不得误伤 `node.print(using:)` 这类本库渲染 API」的判别用例）。覆盖面反而更大 —— 从「测试恰好驱动的那一条路径」变成「所有模块」，和本 PR 早先给 NodeStore 不变式做的同一笔交易。

`printCatchedThrowing` 的 `dispatchingTo:` 按提案里留的口子收敛为**非可选**，`context:` 保持可选并新增 `degradationSource:`（默认 `.typeNodeRendering`）；`stderr` 的 `else` 分支随之删除。

## 决策日志

- **2026-08-16**：本轮 PR #103 review 的两轮结论收敛后创建；用户批准方案，状态直接置 `Accepted`。
- **2026-08-16**：实施完成，状态置 `Implemented`。四处偏离见上节；14 处危险写法（库 9 + CLI 5）清零，`StandardStreamCapture` 退役。
