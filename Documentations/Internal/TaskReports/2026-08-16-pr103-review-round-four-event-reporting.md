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

### 跨 suite 的 fixture 互斥（发现 [10] 的修复）

`PerImageCacheEvictionTests` 头注释声称跑在「no other suite indexes」的镜像上。**成因值得记**：这话对每一个用 `MachOFileName` 命名该镜像的 suite 都成立，但 `SwiftLayoutTests.DependencyClosureLayoutTests` 是**手工拼路径**进来的，按 fixture 枚举名搜索永远搜不到它。

试过并否掉的两条：

- **`.serialized`**：文档明说 "does not affect the execution of a test relative to its peers or to unrelated tests"，只管容器内。
- **自定义全局 actor**（用户提议）：测试全是 `async`，`await` 会让出 actor —— actor 保证「无并发」而非「无交错」，而 clear-then-assert 需要的是后者。

最终用 `TestScoping` trait（Swift 6.1+），它的 scope 包住整个测试体、含所有挂起点。

**实测确定的两个关键点**（写了个临时探针跑一次，比读文档可靠）：

1. `provideScope` **只在测试函数层调用，从不在 suite 层** —— 所以非重入锁不会自我嵌套死锁。文档只说「取决于 test 和 testCase 的值」，没展开。
2. `testCase` **恒为 `some`**，连非参数化测试也是，不能拿它区分层级。

顺带证实了默认确实并行：探针的 enter/exit 顺序完全交错。

**Swift 6 严格并发的一处妥协**：测试体是非 `Sendable` 闭包，传进 actor 方法会被拒（`sending value of non-Sendable type … risks causing data races`）。于是把**锁状态**（`acquire`/`release`，在 actor 上）和**临界区**（body，留在调用方隔离域）拆开。释放走显式 catch 而非 `defer` —— `defer` 里不能 `await`。

**测试自带反证**：同 key 8 个并发抢 → 最大并发持有者 == 1；不同 key 6 个并发 → > 1。结构与 yield 次数完全相同，只有 key 不同。第二条通过才使第一条有意义 —— 否则 `== 1` 可能只因为根本没并发而平凡成立。

### 缓存驱逐两条（发现 [2][3]）

**[2] 三个缓存独立认领 ⇒ 驱逐可能一个字节都不省。** 备忘录的值是指向驻留仓库的 `NodeReference`，而仓库自己的文档写着 "Eviction reclaims nothing while external references survive"。所以「扔仓库、留备忘录」这个组合不是部分成功，是**完全无效**。修法是在 `Claims` 上加 `normalized`：扔仓库 ⇒ 强制扔备忘录（单向蕴含，反向不成立 —— 备忘录走不要求仓库走）。这恢复的是 8/9 存在、8/13 拆分 claim 时被移除的绑定，而解释它的注释一直留在原地。

**[3] 采样在锁外 ⇒ TOCTOU。** `registerLiveIndexer` 改收采样**闭包**，在锁内调用。但只改这一半不够 —— 驱逐动作原本在 `deregisterLiveIndexer` 返回、锁已释放之后执行，那是**第二个窗口**。所以 `deregisterLiveIndexer` 也改收驱逐闭包，在同一临界区内执行。锁内调用外部代码是安全的：三个驱逐都不回调本 registry（`NSLock` 不可重入，回调会死锁，已在注释里写明这个前提）。

#### 一个被否定的怀疑

我一度怀疑**采样位置本身太晚**：`prepare()` 在 259 行，注册在 321 行，中间隔着子 indexer 的 prepare 和四个 section 读取，那些工作若填了缓存，采样就永远是"都在"、永远不认领。**诊断否定了这个猜想** —— 清空后直接 prepare、再释放，三个缓存都被正确认领并清除。那些 section 读取不填这两个缓存。

#### 教训：测试红了，但红错了地方

第一版绑定测试确实红了，我差点当作验证通过。实际上红的是**另一条断言**：我假设 `MetadataReader.demangleContext` 只填备忘录，而它**两个都填**。于是 indexer 采样到"仓库已在"、正确地不认领，我的断言才是错的 —— **产品代码没问题，测试前提错了**。

要不是加了一轮状态诊断（打印清空/预填/prepare/释放四个时刻的三缓存状态），我会用一个测着别的东西的测试来"证明"修复有效。

修正后的测试用**生产里真实可达**的路径构造目标组合：内存压力驱逐会清仓库而不清备忘录，正是需要的 `仓库缺席 + 备忘录在场`。红相确认落在正确的断言（备忘录未被清），绿相 5 tests 全过。

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
