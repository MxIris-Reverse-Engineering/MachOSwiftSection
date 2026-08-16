# PR #103 第四轮 review：降级上报统一走事件

**日期**：2026-08-16
**分支**：`fix/event-based-diagnostics` → `feature/node-store-migration`
**提案**：[0005](../../Evolutions/0005-event-based-degradation-reporting.md) ｜ **实现说明**：[EventBasedDegradationReporting.md](../EventBasedDegradationReporting.md)

## 问题

第四轮 max 级 review 产出 15 条发现。最刺眼的一条**推翻了第三轮修复本身**：批次 2 为了「让丢弃可观测」，把 `print(error)` 换成了 `FileHandle.standardError.write(_:)`。那个重载是 Objective-C 桥接，写失败时抛 `NSFileHandleOperationException` —— Swift 接不住 ObjC 异常，**进程当场 abort**。库 9 处 + CLI 5 处共 14 处。

## 调研

### 交叉复核（同项目另一会话）

15 条交由另一会话独立复核，全程 `git show` / `git grep` / `git log -S` / `git blame` 对 PR 头与 merge base 逐行取证，另做了两个可执行实验。结论：**9 真 / 1 误报 / 2 属实但不值得修**，外加 3 条补充裁决。

复核的**减法**和加法一样有价值：

- **`Codable` 移除被判误报。** 我原判「静默移除、无任何记录」。复核查到 7/31 的 commit 完整记录了决策与理由（mangled symbol 本身就是这棵树的序列化：更小、跨工具链稳定、往返保共享），**同批更新了 AGENTS.md**（明文 "deliberately NOT Codable"），并对本地 RuntimeViewer 全仓 grep 确认**零 `Codable` 消费者**。真实残留只有文档欠账（迁移计划里写的仍是相反的话）。
- **符号表按名查找**：机制六环全真，但我漏了一步——miss 后 late path 重新 demangle 的输入与 main 拿到的名字**完全相同**，结论逐位等价、无输出差异。且第一轮已作为 below-the-cut 记录过，当时就判了不上桌。
- **多 payload enum 全有或全无**：唯一真缺陷窗（段存在但读到一半 throw）下 **main 行为逐字等价**，是基线旧问题而非本 PR 的「修复层级不足」。

### 我自己也需要更正三处

1. 写 stderr 是 **9 处**不是 8 处（正文写八、清单列九，清单对）。
2. 我举的 `| head` 例子**不是有效论据**：那种情况进程先死于 `SIGPIPE`(141)，换成 `print` 一样死。增量危害只在 stderr 被关和 `SIG_IGN` 宿主两种场景，两者均已实验证实（退出码 134）。
3. 「`printEnumCase` 也会静默消失」不实——它不走带 dispatcher 的路径，落到 stderr 兜底。静默消失只限存储属性。

### 用户提出的替代方案

用户问「全部换成 `@Loggable` / `#log` 可不可行」，随后追问「全部走 Event 不行吗」。

- **全换 os_log 不可行**：CLI 用户在终端、`2>err.txt`、CI 日志里**一个字都看不到**，直接违背 issue #102 的报告场景（他抱怨的正是 CI/管道日志）。
- **全走事件**：库侧 9 处可以且正确；CLI 侧 5 处不该走——CLI **就是**宿主，给自己派发事件再自己接住是空转，且其中 2 处是 stdout 产品输出（JSON），根本不是诊断。

## 最终方案

**库代码一律不写进程流。** 降级派发 `SwiftIndexEvents`，落点由宿主装的 `Handler` 决定。配套三件事缺一不可（少任何一件就是把 crash 换成静默）：

1. `Dispatcher.dispatch` 零 handler 时落 **os_log 地板**；
2. diff 渲染器的 printer 改为**共享 indexer 的 dispatcher**（此前 `.init(in:)` 构造、事件发进空数组）；
3. `ConsoleEventHandler` 从 **stdout** 改到 stderr（它是 CLI 的默认 sink 却在写产品输出流）。

CLI 侧 5 处只换安全写法（`fputs` / `fwrite`）。

## 实际执行

### 与提案的四处偏离

全是实现时撞到的硬约束，不是改主意（详见提案「实施中偏离提案的地方」与实现说明「四条走不通的近路」）：

| 计划 | 实际 | 原因 |
|---|---|---|
| 两处也走事件 | 闭包注入 + 日志地板 | `SwiftDeclaration` **依赖** `SwiftDeclarationRendering`，反向引用成环 |
| builder 存 `[Handler]` | 注入 `Dispatcher` | `Handler` 非 `Sendable`，存不进 `Sendable` 的 builder。结果更好：indexer 与 printer 共用一个 |
| 退役 `StandardStreamCapture` | 连私有 stdout 捕获一起改源码扫描 | 同类隐患，且会被并行 suite 的输出假失败 |

### 一次自己造成的弯路：误判 `@Loggable` 不可用

给 `SwiftDeclaration` 加 `OSToolbox` product 依赖（因为宏的声明文件在那个目录下），SPM 报 product 不存在，我据此判定「这里用不了 `@Loggable`」，临时改用裸 `os_log` 并把这个结论写进了四处文档。

**判定是错的**：项目里所有 `@Loggable` 用法都是经 **`FoundationToolbox`** 拿到宏的。三处已全部改回 `@Loggable` / `#log`，四处文档同步更正。

顺带确认两件事：宏自带的 `#available` 回退**已经覆盖**了「`os.Logger` 要 macOS 11 而本包下限 10.15」，不需要手写；泛型类型（`OpaqueTypeRewriter<MachO>`）不能直接标注（展开成 static stored property），走**协议式** `@Loggable` —— 项目里 `NestedSpecializationLogging` 早有同形先例，访问级别按遵循者范围收紧（同文件用 `fileprivate`，跨文件才 `internal`），但**不能用 `private`** —— 它会把成员一并压到 `private`，而 `#log` 在遵循者内部展开、看不见。

该约定已写进 **AGENTS.md 新增的 Logging 一节**（全项目日志一律 `@Loggable` + `#log`，禁用 `os.Logger` / 裸 `os_log` / `OSLog(subsystem:category:)`），这样下一个人不必重走这条弯路。

### 单侧 header 的语义修正

`guard let old = ..., let new = ...` 从左到右短路，旧侧失败时新侧根本没渲染。改为两侧各自渲染后决议，且必须用**三态** `HeaderOutcome`（`absent` / `rendered` / `failed`）——第一版用 `SemanticString?` 把「这侧不存在」和「渲染失败」混同，测试当场抓到：`.added` 路径拿空串顶替了失败侧。

## 验证

- 三个受影响套件 **11 tests 全绿**；
- 危险写法清零（`grep` 剩余 4 处命中全是注释）；
- 全量套件（`--skip IntegrationTests`）退出码 0。

### 测试暴露的两个真实缺陷

值得单独记，因为都是**测试先红才发现的**：

1. **`HeaderOutcome` 三态**（见上）——`SemanticString?` 的两态设计在 `.added` 路径直接错。
2. **测试注入撞了 key。** `FinalClassTest` 本来就嵌在 `Classes` 下，往同一个 host 再 append 一个借它名字的 corrupt 定义，`matchByKey` 是 first-wins，注入要么被忽略、要么配对成两侧都有——测的根本不是打算测的路径。改为：`.added` 用一个 host 下不存在的 donor 名（`GenericStructNonRequirement`）并**前置断言它确实不存在**，两侧路径则**替换**旧侧的真实条目而非追加。

### 自查发现的完整性缺口

改完库侧后自查「CLI 各入口是否真的装了 sink」，发现 **`diff` 路径一个都没装**：`DiffCommand` 的两个 builder 和共用的 `ABISnapshotInputLoader` 都是裸构造。事件全都正确派发，却因为没有 sink 而全部落到 os_log 地板 —— **CLI 操作者一行看不到，比改之前还退一步**。只有 `InterfaceCommand` 原本就装了。三处补齐。

教训写进实现说明的维护须知：地板保证「不至于全哑」，但**不替代正确配置**，而且忘记装 sink 不会报错。

### 环境陷阱各踩一次

- **worktree 无 fixture**：`Tests/Projects/SymbolTests/DerivedData` 是 gitignored 的每机器产物，新 worktree 里没有，11 个测试瞬间全红（含不依赖 fixture 的纯逻辑用例——因为 suite 基类 setup 就失败了）。确认 PR 分支与 main 的 fixture **源码零差异**后，符号链接主仓库的 DerivedData。
- **管道吃掉退出码**：第一次判定基线「编译通过」用的是 `swift build | grep` 的退出码，那是 grep 的。改为落盘后单独判 `$?`，才看到真实的 6 处编译错误。AGENTS.md 对 xcsift 有同样警告，这次是 grep 版本。

## 分歧与遗留

- **补了一行不在范围内的修复**：`ProtocolConformanceDumper.swift` 缺 `@_spi(Internals) import MachOSymbols`（第一部分阻断项之一，用户说暂不处理）。但它是**编译前提**——不补就无法验证任何改动。补的是一行 import，同目录另外五个 dumper 都有，`eb25e31d` 自己的 commit message 也说了该加。
- **源码扫描的基线债务清单**：扫描暴露了一批既有的 `print(` 调用（descriptor wrapper、layout 分析层等），**不在本次范围**，记入显式的**只减不增**清单——新增违规会失败，存量不动。
- **本轮未修**：缓存驱逐两条（[2][3]）、A/B 脚本 skip 无痕（[12]）、以及判为不值得修的两条与三条补充。`Codable` 的文档欠账（迁移计划反转条目、0002 源码兼容节补列、changelog）亦未做。
