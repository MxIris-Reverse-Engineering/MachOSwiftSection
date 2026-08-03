# 2026-08-02 `feature/node-store-migration`（PR #97）代码审查

本文记录 2026-08-02 对 PR #97 跑的一轮 `/code-review max` 审查，以及 08-02～08-03 对其发现的逐条裁决。

与 [2026-07-31 那轮](2026-07-31-node-store-migration-review.md) 的关系：本轮是**独立的一次审查事件**，15 条发现中多数与上一轮重合。本文只详述**本轮新增的 8 条**与**本轮产生的状态变更**；重合条目在第五节的对照表里指回上一轮，不重复论述，也不重新计量——上一轮已有实测数据的条目一律以那份数据为准。

与 [`NodeStoreMigrationOpenIssues.md`](../NodeStoreMigrationOpenIssues.md) 的分工不变：那份是按技术主题组织的长期台账，本文是一次审查事件的记录。

## 审查方式

多智能体审查，分维度 finder 出候选 → 每条派独立 verifier 做对抗性验证（默认倾向证伪）→ 第三轮补充扫描（8 个候选存活 2 个）→ 归并去重。

规模：66 个改动文件（+3371 / −592）→ 归并后 15 条，另有 3 条因输出条数上限被挤出但同样确认为真。

对比基线：`git diff main...feature/node-store-migration`。

## 一、本轮新发现（8 条）

以下 8 条在 2026-07-31 记录与既有台账中**均无**。每条都在本次会话中逐条核实到代码行。

### 1. 打印器递归预算从 768 降到 512 ✅ 已闭环

`Package.swift` 把 swift-demangling 指向 `branch: "feature/node-store"` 期间，打印器的递归深度上限随之从 `0.4.5` 的 768 变成分支上的 512（且判断条件是 `printDepth < 512`，实际上限 511）。

后果不止是显示截断。`node.print(using: .interfaceTypeBuilderOnly)` 的结果在多处被当作**字典键**使用——`SymbolIndexStore.swift` 的 `typeInfoByName` / `memberSymbolRowsByKind[kind][name]`、`DefinitionName.name`、`ClassDumper` 的名字相等判断。SwiftUI 里 `ModifiedContent<ModifiedContent<…>>` 这类深嵌套链若在 512～768 之间截断，会得到以 `<<too complex>>` 结尾的字符串；**两个不同类型在同一深度截断就会塌到同一个键上，成员被合并**。测试套件里没有任何以 `too complex` 为内容的基线守着这条。

**状态：已随上游 0.5.0 关闭。** 上游把上限恢复为 768，并在源码注释里记下了原因与禁止再降的约束（"Downstream consumers reported `<<too complex>>` on ordinary SwiftUI and similarly generic-heavy modules under the 512 limit … Do not lower this again without corpus evidence gathered from downstream workloads."）。本仓库随依赖升级到 `from: "0.5.0"` 后自动获得，无需本地改动。

### 2. `indexExtensions` 丢失 `await`，从任务挂起退化为线程阻塞

`Sources/SwiftIndexing/SwiftDeclarationIndexer.swift:685`。

- `main:659`：`let name = await node.print(using: .interfaceTypeBuilderOnly)`——`node` 是 `Node`，绑定到 `Node.print(using:) async`，走 `StackSafeExecutor.executeAsync`（`withCheckedContinuation`，**释放线程**）。
- 本分支：`node` 变成 `NodeReference`，而 `NodeReference` / `DemanglingNode` 只暴露同步 `print`，于是 `await` 被静默去掉，改走 `DemanglingPrinter.print` → `runOnLargeStack` → `DispatchSemaphore.wait()`——**阻塞一条协作线程池的线程**。

这个循环对每个 extension target 执行一次，位于 `async` 的索引流程内。`NodeReference` 上不存在 async 版 `print`，所以调用点看不出任何退化痕迹。

### 3. `withLargeStack` 包住整趟 sweep，会占住一条线程整块时长

`Sources/MachOSymbols/SymbolIndexStore.swift:352`。

这是**对上一轮那条修复本身的观察**，不是否定它：上一轮把每符号一次线程往返摊销成整批一次（实测 1317 ms → 701 ms），方向正确。但 `buildStorageImpl` 现在返回 `StackSafeExecutor.withLargeStack { self.buildStorageSweep(...) }`，在 512 KB 栈的线程上探测必然失败，于是**调用线程在信号量上被卡住整趟 sweep 的时长**（数秒）。

而 `SharedCache.resolve` 是刻意把构建放在锁外的，好让不同镜像并行构建；于是同时准备 N 个镜像 = N 条协作线程池线程各被停数秒。池大小约等于核数，镜像数超过核数时无关任务也被拖住。`SwiftDeclarationIndexer.prepare()` 是 `async`，`prepareWithProgress` 可从 `Task` 抵达，所以这条路径真实可达。

正确形态是第三种：走异步入口（挂起而非阻塞），或使用专用线程。

### 4. `NodeReference(interning:)` 在批量路径上被逐个调用（26 处）

分布：`SwiftDeclaration/Extensions.swift` 14 处、`SwiftIndexing/SwiftDeclarationIndexer.swift` 6 处、`SwiftSpecialization/` 4 处、`SwiftDeclaration/Components/Definitions/ProtocolDefinition.swift` 1 处、`MachOSymbols/StructuralNodeReferenceKey.swift` 1 处。

上游对该构造器的文档原话是"一次调用一块 arena，所以这是批量场景下的错误工具——去重与紧凑都是 arena 的属性，给每棵树各开一块 arena 就把两者都放弃了"，并给出实测：300 个引用指向 3 个唯一符号时，逐个 interning 是 300 条目 / 59,700 字节，共用一个 builder 是 3 条目 / 541 字节。

连带副作用：没有两个名字共享 arena，于是 `structurallyEquals` 的 `store ===` 快路径**永不触发**，每次名字相等判断都要走完整棵树。

修法与 `TypeDefinition.index` 对字段类型树的做法一致——每个镜像共用一个 builder。

> 与 `main` 的关系：`main` 没有这个形态，但有它自己的病（全局 `NodeCache` 只涨不落），而那正是本次迁移要治的。所以这是**代价而非退步**，只是这个代价可以不付。

### 5. `buildPipelineStaysOffGlobalNodeCache` 的断言本身不成立

`Tests/MachOSymbolsTests/SymbolIndexStoreFixtureTests.swift:53`。

该测试对 `firstTransientTree.first { $0.children.isEmpty }`（前序首个叶子）断言 `firstLeaf !== secondLeaf`。但 `demangleAsNodeTransient` 的上游文档明确声明：结果"不是规范化的，但也**不是实例互异的**——无参数种类（`.asyncAnnotation`、`.throwsAnnotation`、`.labelList` 等）会解析到进程级 `NodeFactory` 单例"。

取样行 `sampleRow` 取的是 `rootNodeIndexByTableRow.firstIndex(where: { $0 != nil })`，**依赖 fixture 的符号顺序**。若该行恰是 ObjC thunk 或 merged function，前序首个叶子就是 `NodeFactory.objCAttribute` / `.mergedFunction` 那个单例，两次取到同一实例，测试在没有任何东西出错的情况下变红。重建 `SymbolTestsCore` 或升级工具链都可能翻转它。

（该测试"没有断言它命名的那个不变量"是上一轮第 14 条，本条是**另一个**问题：它现有的那个断言也是错的。）

### 6. 两个测试跨 `shared` 调用断言 NodeStore 身份，中途可被驱逐

同文件 `:169`、`:187`：`#expect(referenceAgain == reference)`，而 `NodeReference.==` 要求 `store === store`。

该条目按 Mach-O 标识存放在 `SharedCache` 中，有三个驱逐点：`SharedCache.swift:121` 的 `remove(for:)`（由 `SwiftDeclarationIndexer.deinit` 调用），以及 `SharedCache.init` 注册的 `memoryWarningHandler` / `memoryCriticalHandler` 里的 `storageByIdentifier.removeAll()`。`Tests/SwiftInterfaceTests/SymbolTableRetentionTests.swift` 使用**同一个** `SymbolTestsCore` fixture，而所有测试 target 链接进同一个 `swift test` 包、swift-testing 并行调度 suite（`@Suite(.serialized)` 只在自身 suite 内串行）。两次调用之间发生驱逐就会重建出新 store，测试变成不可复现的红，且看起来像 NodeStore 回归。

修法：断言改用 `structurallyEquals`，或在两次调用之间持有 storage。

### 7. dyld 缓存框架形状判定无锚点，rank 0 内又回到枚举顺序依赖

`Sources/MachOExtensions/DyldCache+.swift:73`：`if enclosingDirectories.contains("\(name).framework")`——这是**对全部路径成分的成员检查**，不是"二进制的直接父目录"。

于是 `SwiftUI.framework/Versions/A/SwiftUI` 与 `…/Versions/B/SwiftUI`，以及任何嵌在该框架目录下、叶名相同的辅助二进制，**都拿 rank 0**。而 `accumulateBestMatch` 的 `guard rank < (rankedMatch?.rank ?? Int.max) else { continue }` 永远不会用一个 0 替换已有的 0，所以胜出者又变成"缓存先枚举到的那个"——**这正是排名机制被引入来消除的非确定性**。新增的 `leafInsideForeignFrameworkDoesNotScoreBestRank` 只覆盖了*外来*框架目录，这个形状没有测试。

修法：锚定在 `enclosingDirectories.last`（允许中间夹一层 `Versions/<x>`）。

（上一轮第 5 条讲的是 `:133` 缺少提前退出导致全遍历，与本条不是同一个缺陷。）

### 8. `ClassDumper.distributedFunctionNodes` 未记忆化，每个 actor 类求值两次

`Sources/SwiftDump/Dumper/ClassDumper.swift:77` 是一个 `private var … : Set<Node>` 计算属性，在 `:101`（`try? distributedFunctionNodes) ?? []).isEmpty == false`）和 `:192`（`let distributedFunctionNodes = (try? self.distributedFunctionNodes) ?? []`）各求值一次。每次都重建整个 thunk 符号数组，并为每个 thunk materialize 两棵树。

## 二、本轮已闭环

### 1. swift-demangling 依赖改回版本要求 ✅

`Package.swift:215`：`branch: "feature/node-store"` → `from: "0.5.0"`。

上一轮已把"钉在分支"判定为**开发期的预期状态**（见 2026-07-31 记录第五节），合并时换回版本要求即可。上游 `feature/node-store` 现已合入 `main` 并发布 `0.5.0`，因此该状态可以结清。

验证：

- `0.5.0` 的提交正是 swift-demangling `main` 的顶端（`caacfb9`），与本机兄弟检出同一提交且该检出工作区干净——所以对它的本地构建等同于对 `0.5.0` 源码构建。
- 在**没有兄弟目录**的干净检出中实测 `swift package resolve`，结果为 `swift-demangling resolved at 0.5.0`。这是 CI 与下游消费者实际走的路径，也正是钉在分支时会解析失败的那条路径。
- `swift build`：0 errors / 2 warnings。
- `Package.swift` 中已无任何 `branch:` 形式的依赖。

### 2. 打印器递归预算 ✅

见第一节第 1 条，随上述依赖升级自动关闭。

## 三、本轮裁决为"无需处理"

按项目约定，判定为误报或不值得修的发现在此留档；后续审查先对照本节与既有台账，理由仍成立的直接跳过。

### 1. `Symbol` 删除公开成员未升版本、未写 changelog —— 不修

审查将其列为合并阻塞（对应上一轮第 11 条 / 台账第 8 条同源）。**裁定：不升版本、不写 changelog。**

理由（维护者裁决，2026-08-03）：`nlist` 唯一被消费的信息就是 `isExternal`，而该位已经作为 `Symbol.isExternal` 独立公开，语义与文档俱在。核实结论：

- 包内已无任何 `.nlist` 引用。
- 新的 `init(offset:name:isExternal:)` 给 `isExternal` 带了默认值，因此旧的 `Symbol(offset:name:)` 调用形式**照常编译**，真正断裂的只有显式写 `nlist:` 标签的形式，面比初判窄。
- `TypeName` / `ProtocolName` / `ExtensionName` 丢 `Codable` 是上游删除 `Node: Codable` 的连带结果，已在 2026-07-31 记录中论证过是有意为之。

### 2. 两个公开查询 API 的字典键从结构相等翻成身份相等 —— 不修

对应上一轮第 13 条 / 台账第 3 条。**裁定：不修**（维护者裁决，2026-08-03）。

理由：`SymbolIndexStore` 在类型层面就是 SPI——`SymbolIndexStore.swift:13-14` 上有 `@_spi(ForSymbolViewer)` 与 `@_spi(Internals)`。成员要被访问必须先能命名该类，而命名它必须带对应的 `@_spi(...) import`，所以 SPI 性由类继承而来，逐个方法标注是多余的。既然契约只对包内与已知的 SPI 消费方成立，只要保证包内正确即可。

核实包内确实正确：

- `memberSymbols(of:excluding:in:)` 包内唯一调用点是 `SwiftDeclarationIndexer.swift:663`，在 `:684` 只做 `for (node, memberSymbols) in memberSymbolsByName` 遍历，全程无下标查询；且返回字典的键全部出自同一个 `storage.nodeStore`，同 store 内下标相等本就是正确的去重语义。
- `allOpaqueTypeDescriptorSymbols(in:)` 在 `Sources/` 与 `Tests/` 中**零调用点**。

## 四、更正

### 1. 更正本轮自身：`memberSymbols` 的"O(1) 退化"不成立

本轮报告将 `SymbolIndexStore.swift:757` 描述为"从 O(1) 字典命中退化成线性扫描 + 全树比对"，并在会话中一度被判定为"四条性能问题里唯一白丢的一条"。**该判定错误，已撤回。**

上一轮已就同一位置作出带实测的裁定（2026-07-31 记录第六节 + 第三节）：

- `main` 那次"哈希查找"并不免费——`Node.hash(into:)` 是 `hasher.combine(children)` 递归，**哈希一次就要走完整棵树**（已在 `swift-demangling` `0.4.5` 的 `Node+Hashable.swift` 中逐字核对）。
- 桶里装的是"同一类型名下的不同 type node"，实测 6,720 个桶中 **99.60% 只有 1 个元素**，最大 6。

所以实际是"一次全树哈希"换成"一次全树结构比对"，量级相当，不存在倍数退化。台账第 5 条建议的旁路索引仍是合理优化，但**不应按回归对待**。

### 2. 更正本轮自身：Package.swift 依赖不构成"合并阻塞"

本轮把它列为阻塞项，但上一轮第五节已明确判定为开发期预期状态。本轮重复报出而未先对照既有裁决清单，属流程遗漏。结论上无害（该状态本来就该在合并前结清，且现已结清），但计入"应先查裁决清单"的教训。

### 3. 台账第 12 条（rebase 前提）再次确认过期

上一轮第 15 条已指出该条前提过期。本轮复测确认：分支落后 `main` 仅 2 个提交（`fed0acf` / `f8c6992`），且二者只改动 `.github/workflows/macOS.yml`；以合并基点为准，两侧改动文件**零交集**，所述 `AGENTS.md` 冲突不存在。

该条压着的**仍然成立**的注意事项照旧保留：`main` 的 `TransformerOptionGroup` 与本分支的 `DemangleResolver` / `printSemantic` / `FieldDefinition.typeNode` 改动之间的交互从未被跑过。

## 五、与既有记录的对照

| 本轮发现 | 2026-07-31 记录 | 既有台账 | 关系 |
| --- | --- | --- | --- |
| 打印深度 768→512 | — | — | 本轮新发现，已闭环（上游 0.5.0） |
| 依赖钉分支 | 五节（判定无需处理） | — | 同一事项，本轮结清 |
| `Symbol` 删公开成员 | 11 | 第 8 条（部分） | 同一问题，本轮裁决不修 |
| 公开查询 API 键语义 | 13 | 第 3 条 | 同一问题，本轮裁决不修 |
| `indexExtensions` 丢 `await` | — | — | **本轮新发现** |
| `withLargeStack` 卡整块 | 1（该条的修复本身） | 第 6 条 | **本轮新发现**，是对既有修复的新观察 |
| 26 处 `NodeReference(interning:)` | — | — | **本轮新发现** |
| 测试 `firstLeaf !==` 断言不成立 | 14（另一角度） | — | **本轮新发现** |
| 测试跨 `shared` 断言 store 身份 | — | — | **本轮新发现** |
| dyld `:73` 无锚点判定 | — | — | **本轮新发现** |
| `distributedFunctionNodes` 未记忆化 | 7（同类，另一站点） | — | **本轮新发现** |
| dyld `:133` 全遍历 | 5（已判定非退化） | — | 同一问题，沿用既有判定 |
| 持锁 demangle / 失败名不缓存 | 3、4 | 第 9 条 | 同一问题，沿用既有实测定性 |
| build sweep 串行 | 1 | 第 6 条 | 同一问题 |
| 打印路径每次跨线程 | 2（已判定为上游刻意交易） | — | 同一问题，沿用既有判定 |
| `memberSymbols` 线性扫 | 六节（已裁定量级可忽略） | 第 5 条 | 同一问题，**本轮判定被撤回**，见第四节 |
| `ABIKey` 每 key materialize | 9（实测占 0.8%） | 第 7 条 | 同一问题，沿用既有实测 |
| `ProjectEvolutionLog` 撞号 + 死链 | — | 第 12 条（提及） | 已复测**仍然存在**：两个 `## 20.`（353 / 384 行）、348 行链接少了实际文件名中没有的 `dyld-` 前缀 |

## 六、待处理清单增量

上一轮第四节的 17 条清单继续有效（除本文第三节裁决为不修的两条、第二节闭环的一条外）。本轮在其上新增：

**建议合并前修**

1. `indexExtensions` 丢失 `await`（第一节第 2 条）——一行改动能否恢复取决于 `NodeReference` 是否补 async `print`；若上游不补，需在渲染循环层面另作安排。

**可排期**

2. `withLargeStack` 占住整条线程（第一节第 3 条）——与上一轮第 1、2 条同属"线程跳转形态"课题，宜合并设计。
3. 26 处 `NodeReference(interning:)` 改为每镜像共用 builder（第一节第 4 条）。
4. dyld `:73` 判定锚定到直接父目录（第一节第 7 条）——**这条是正确性问题（非确定性），优先级高于同文件 `:133` 的性能问题**。
5. `distributedFunctionNodes` 记忆化（第一节第 8 条）。

**测试**

6. 两条脆弱断言（第一节第 5、6 条）——与上一轮第 14 条同文件，宜一并处理。

**文档**

7. `ProjectEvolutionLog.md` 的重复 `## 20.` 与死链。既有台账建议"rebase 之后再补演进日志小节"，但撞号已在本分支内部成型，与 rebase 无关，可以先修。
