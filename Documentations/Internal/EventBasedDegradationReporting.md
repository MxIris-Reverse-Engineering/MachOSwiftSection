# 降级上报走事件：分层、兜底契约，以及几条走不通的近路

> 对应提案：[0005](../Evolutions/0005-event-based-degradation-reporting.md)。提案是决策快照，这篇记实现 —— 尤其是那些「看起来更简单、实际走不通」的路，免得下次维护重走一遍。

## 一句话契约

**库代码不写进程流。** 渲染失败、索引跳过、依赖加载不上，一律派发 `SwiftIndexEvents`；落点由宿主装的 `Handler` 决定。库唯一允许的直接输出是 `#log`（写进统一日志），且只作为「没有 sink 时不至于全哑」的地板。

> 写法一律 `@Loggable` + `#log`，泛型类型走协议式 `@Loggable`。全项目约定见 AGENTS.md 的 **Logging** 一节；本文下面第 1 / 1b 条记的是踩过的坑。

判断落点的两条硬约束，是这套分层存在的全部理由：

- **stdout 绝对不能碰。** CLI 把生成的 Swift / JSON 流到 stdout，往那儿写一个字节就污染了产品输出。issue #102 实测过：一次丢掉 8375 个定义的运行，唯一信号是嵌在几百万字符接口里的一句 `unexpected(at: 8)`。
- **stderr 对 GUI 宿主是错的。** RuntimeViewer 这类宿主没有有意义的 stderr，它按 subsystem/category 过滤统一日志。反过来 os_log 对 CLI 是错的 —— 终端、`2>err.txt`、CI 日志里都是空的。

**这个分歧在库里选不对，只能由宿主决定。**

## 三层落点

```
库代码 ──dispatch──▶ SwiftIndexEvents.Dispatcher
                          │
              ┌───────────┴───────────┐
        有 handler                零 handler
              │                       │
      宿主决定去哪            reportUnhandled → os_log
   (OSLogEventHandler /            「地板」
    ConsoleEventHandler)
```

- **GUI 宿主**装 `OSLogEventHandler` → 统一日志，过滤器照旧工作。
- **CLI** 装 `ConsoleEventHandler` → **stderr**（这次从 stdout 改过来的，见下）。
- **谁都没装** → `Dispatcher` 自己落 os_log。

### 兜底为什么在 `Dispatcher` 而不是各调用点

调用点判断不了自己有没有 sink —— `.init(in:)` 构造的 printer 和装了 handler 的 printer 类型完全一样。这个判断只有 `Dispatcher` 做得了。放调用点的结果就是改之前的样子：一半有兜底、一半没有，而**有兜底的那一半还是死代码**（`printField` / `printEnumCase` 传的 `eventDispatcher` 是非可选存储属性，`if let` 永远成立，`else` 分支从这两个调用点不可达 —— 而注释点名的正是这条路径）。

### `unhandledFailureDescription` 是白名单，不是反向 `default`

`Dispatcher` 靠它区分「这是损失，要落地板」和「这是进度，丢了无所谓」。写成穷举 `switch` 而不是 `default: nil`，是为了**让新增失败事件时编译器逼你表态** —— 反过来写的话，新加的失败 case 会静默地不受地板保护，而那正是这套机制要防的回归类型。`PrintFailureEventTests.everyFailureEventIsRecognizedByTheFloor` 钉住这条。

### `dispatch` 里必须一次读出 handlers

`handlers` 是 `@Mutex` 包装的，**每次访问都过一次锁**。先判空再遍历是两个临界区，中间可以被清空 —— 事件既没到 handler 也没到地板。所以是 `let currentHandlers = handlers` 一次读，再分支。

## 四条走不通的近路

### 1. `@Loggable` 的 product 是 `FoundationToolbox`，不是 `OSToolbox`

宏的声明文件在 `Sources/OSToolbox/Macros/LoggableMacro.swift`，所以第一反应是给 target 加 `OSToolbox` product 依赖 —— SPM 报 `product 'OSToolbox' … not found`，据此很容易误判成「这里用不了 `@Loggable`」。

**实际上项目里所有用法都是经 `FoundationToolbox` 拿到宏的**（`RuntimeFieldLayoutBackend`、`SymbolIndexStore` 都只 import 它）。加 `.product(name: "FoundationToolbox", package: "FrameworkToolbox")` 即可。

这也顺带解决了部署下限问题：本包部署到 **macOS 10.15 / iOS 13**，低于 `os.Logger` 的 macOS 11 / iOS 14，而 `@Loggable` 展开时自带 `#available` 回退到 `os_log`。所以**不要**为了绕开下限而手写 `os.Logger` 或裸 `os_log`。

### 1b. 泛型类型的 `@Loggable`：加在协议上

`@Loggable` 应用在**类型**上时展开成 static **stored** property，泛型类型不支持 —— `OpaqueTypeRewriter<MachO>` 会报 `static stored properties not supported in generic types`。

应用在**协议**上时展开的是 extension 里的**计算**属性，任何遵循者（泛型与否）都能用 `#log`：

```swift
@Loggable(.internal, subsystem: "…", category: "OpaqueTypeRewriter")
protocol OpaqueTypeRewriteLogging {}

private final class OpaqueTypeRewriter<MachO: …>: Node.Rewriter, OpaqueTypeRewriteLogging { … }
```

`SwiftSpecialization` 的 `NestedSpecializationLogging` 是同一形状（把深度限制诊断挂到 `TypeDefinition` 上）。

**协议必须是 internal**：`private` 协议会把 extension 成员一并压到 `private`，而 `#log` 在遵循者内部展开，那里看不见 —— 症状是 `'logger' is inaccessible due to 'private' protection level` 加一条 `does not conform to protocol`。

### 2. `SwiftDeclarationRendering` 够不到事件类型

`Node+OpaqueType` 和 `MultiPayloadEnumDescriptorCache` 都在这个模块，而 **`SwiftDeclaration`（事件所在）依赖它** —— 反向 import 直接成环。

- `Node+OpaqueType` 走**闭包注入**：`OpaqueTypeDegradationReporter = @Sendable (any Error) -> Void`。接口路径（`SwiftDeclarationPrinter+Headers`）注入一个 dispatch 闭包，`SwiftDump` 路径没有事件机制，传 nil 落 os_log。
- `MultiPayloadEnumDescriptorCache` 是 `SharedCache` 子类，没有注入点，直接 os_log。

这不算破例：os_log 就是 `Dispatcher` 地板的同一个落点，区别只在有没有 sink 可接。

### 3. 不能把 `[Handler]` 存进 builder

原计划是 `SwiftDiffableInterfaceBuilder` 留住 `eventHandlers` 再传给两个 printer。**`SwiftIndexEvents.Handler` 不是 `Sendable`**，存进 `Sendable` 的 builder 编译不过。

改成给 `SwiftDeclarationPrinter` 加一个 package 级、接受现成 `Dispatcher` 的初始化器，renderer 传 `indexer.eventDispatcher`。**结果比原计划好**：diff 路径的 indexer 和 printer 共用一个 dispatcher，宿主装一次 handler 两边都覆盖。

代价是 `SwiftDeclarationIndexer.eventDispatcher` 和 `SwiftDeclarationPrinter.eventDispatcher` 从 internal 提升为 `package`。

### 4. 「不写 stdout」不能用 fd 重定向来测

原来有两个进程级 fd 重定向的测试工具（共享的 `StandardStreamCapture` 和 `PrintFailureEventTests` 里一个私有的 stdout 捕获）。**这条路根本安全不了**：

`swift test` 把所有 test target 链进**一个进程**，而 swift-testing 的 `.serialized` 只在 **suite 内部**串行。两个 suite 同时重定向同一组 fd 就会交错，后果不止是断言乱套：

- suite A `dup2(pipeA.write, 2)` 之后，suite B 的 `savedB = dup(2)` **拿到的是 pipeA 写端的副本**；
- A 恢复并关闭自己的写端时，`savedB` 还持有一份 → **pipeA 永远等不到 EOF**，A 的排空循环无限阻塞 → **整轮 `swift test` 挂死**；
- B 恢复时把 fd 2 指向已经没人读的 pipeA → 此后整轮 stderr 全部消失。

而且只要有别的 suite 往 stdout 写一个字节，捕获断言就假失败。

改为**源码扫描**：遍历 `Sources/` 下所有非宿主模块（`swift-section` / `MachOTestingSupport` 除外 —— CLI 是宿主，stderr/stdout 都是它的合法通道），匹配 `FileHandle.standardError` / `FileHandle.standardOutput` / 裸 `fputs(` / 裸 `print(`。

**扫描必须能识别「裸调用」**：`node.print(using:)` 是本库的渲染 API，`printer.printRoot(...)` 也是 —— 简单 `contains("print(")` 会大面积误伤。`containsBareCall(to:in:)` 检查 `print(` 前一个字符不是字母/数字/`.`/`_`。配套的 `theStreamWriteScannerDiscriminates` 同时钉正例和反例，因为**一个只会返回「没找到」的扫描器等于没有扫描器**。

覆盖面反而比 fd 版本大：从「测试恰好驱动的那一条路径」变成「所有模块所有行」。这和本 PR 早先给 NodeStore 不变式做的是同一笔交易。

## 宿主必须真的装 sink —— 接上事件只是一半

改完库侧才发现：**`diff` 路径的 CLI 命令一个 handler 都没装**。`DiffCommand` 的两个 builder 和 `ABISnapshotInputLoader`（`snapshot` / `evolution` / `diff` 的快照输入共用）都是 `SwiftDiffableInterfaceBuilder(in:)` 裸构造。

后果很隐蔽：事件全都正确派发了，但没有 sink，于是全部落到 os_log 地板 —— **CLI 操作者一行也看不到**，比改之前（写 stderr）还退了一步。只有 `InterfaceCommand` 一开始就装了 `ConsoleEventHandler`。

三处都补上了 `eventHandlers: [ConsoleEventHandler()]`。

**这是这套分层的固有代价，值得单独记：** 地板保证「不至于全哑」，但**它不替代正确配置**。新增一条 CLI 入口时，装 sink 是必做项 —— 忘了不会报错，只会安静地把诊断挪进统一日志。

## 顺带修掉的两个行为 bug

**`ConsoleEventHandler` 原本写 stdout。** 它是 CLI 的默认 handler，却用 `print(...)` —— 装上它，issue #102 的第三条诉求当场破功。现在所有输出收敛到一个私有 `report(_:)`，落 stderr。

**diff 渲染器单侧 header 失败会删掉两侧。** `renderType` 原本是

```swift
guard let oldHeader = await header(old, ...),
      let newHeader = await header(new, ...)
else { return [] }
```

guard 子句**从左到右求值、遇第一个 nil 即停**，所以旧侧失败时新侧根本没渲染；返回 `[]` 又把整个声明连同成员和嵌套子节点从**两侧**一起删了 —— 而新侧其实是好的。跨版本 diff 里「旧二进制某类型渲染不出来」恰恰是常规情形。

现在两侧**各自渲染完**再交给 `resolveHeaders`：两侧都成功就照常；**一侧成功就用它顶替失败侧**（有效的声明行 + 完整的成员 diff 都保住）；两侧都失败才丢弃（没有可打印的声明行）。失败无论如何都已经 dispatch 出去了，而且**带上了声明名** —— 旧的 stderr 消息不指名任何声明，操作者只知道「有东西没了」，不知道是什么。

## 危险写法：为什么 `FileHandle.write(_:)` 不能用

`-[NSFileHandle writeData:]` 在写失败时**抛 Objective-C 异常** `NSFileHandleOperationException`。Swift 接不住 ObjC 异常，进程当场 abort。

实测（两个可执行实验，退出码 134）：

- **stderr 被关闭** → `EBADF` → 直接 raise；
- **宿主忽略 `SIGPIPE`**（RuntimeViewer 这类 GUI）→ 管道断了 → raise。

`… 2>&1 | head` **不是**有效例证：那种情况下进程先死于 `SIGPIPE`(141)，换成 `print` 一样死。增量危害只有上面两种。

安全写法：`fputs(_, stderr)`；写 `Data` 用 `fwrite`（`FileHandle.write(contentsOf:)` 是会抛 Swift 错误的正确重载，但它要 macOS 10.15.4，**高于本包的 10.15 下限**）。

清点：库 9 处 + CLI 5 处，共 14 处，已全部换掉。其中 `SnapshotCommand` 那两处写的是 **stdout 产品输出**（JSON），不是诊断 —— 同样中招，因为用了同一个重载。

## 维护须知

- **新增失败事件时**，记得在 `unhandledFailureDescription` 里加分支，否则它不受地板保护（穷举 switch 会提醒你，但别机械地塞进 `return nil` 那一组）。
- **新增 `Payload` case 是源码破坏**，对没写 `default` 的穷举 switch 而言。仓库内命中两处（`OSLogEventHandler`、`SwiftIndexEventReporter`），下游 RuntimeViewer 需实测确认。
- **别在库模块里写流**，源码扫描测试会拦住；真有正当理由（新的宿主类模块）就往 `hostModules` 白名单里加，并在这里记一笔为什么。
- **新增 CLI 入口时记得装 `ConsoleEventHandler`**。没有测试拦这个 —— 忘了不报错，诊断只是安静地改去统一日志。
