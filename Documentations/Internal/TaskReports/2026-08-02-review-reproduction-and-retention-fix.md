# 2026-08-02 审查清单逐条复现，修掉线程跳转与符号表钉住

## 问题

[2026-07-31 的审查报告](../Reviews/2026-07-31-node-store-migration-review.md)留下 17 条待处理项，按性能 / 内存 / 对外 API / 测试与文档分组，另有一条「结论冲突（需要人工裁定）」悬而未决。清单本身是多智能体审查归并出来的，条目有优先级排序但**没有任何一条做过实测**——唯一的量化数据是打印路径的线程跳转，而报告自己也标注了「审查报告最初对它的量级判断是错的」。

用户的要求分两段：性能第一条（build sweep 的线程跳转）可以直接改，其余全部先做复现。也就是说这一轮的产出不是「修完 17 条」，而是**把每条的真伪与量级钉死**，让后续投入落在真问题上。

## 调研

### 一、清单条目的逐条核实

抽查了 8 条优先级最高的，全部属实，没有误报。核实方式一律是逐字比对 `origin/main` 与本分支的同一处代码，不采信报告的转述：

| 条目 | 核实结论 |
| --- | --- |
| build sweep 串行化 | `main` 是 `symbolArray.concurrentMap { try? demangleAsNode($0.name) }`，本分支是单趟顺序循环 |
| 每次 demangle / 打印跨线程 | `demangleAsNodeTransient` 与 `DemanglingPrinter.print` 内部都走 `StackSafeExecutor` |
| `Node+.swift` 注释 | 声称 `print(_:options:)` 会内联，而上游 `NodePrinter.swift:91` 是无条件 `executeWithUncheckedSendability`——注释写反了 |
| demangle 失败重试 | `demangledNodeReference` 命中表行但 root index 为 `nil` 时掉进 `lateDemangledNode`，后者在锁里重跑且不缓存失败 |
| `isExternal` 死代码 | 采集循环已用 `!symbol.nlist.isExternal` 过滤，导出符号走默认值 |
| `Symbol` 删公开成员 | `nlist` 属性与 `init(offset:name:nlist:)` 已删，`Version.swift` 未升，`Changelogs/` 无条目 |
| `DemangledSymbol` 钉住符号表 | `symbolTable: [Symbol]` 是数组引用，每个值 retain 整个 buffer |
| 不变量无测试 | `buildPipelineStaysOffGlobalNodeCache` 只调用了两次 `demangleAsNodeTransient` 自比，完全没有观察 `buildStorage` |

### 二、「结论冲突」的裁定

台账第 5 条称 `memberSymbols(of:for:node:)` 从 O(1) 退化成线性扫描，而本轮 4 条同类候选被 verifier 全部证伪，理由是「原本是一次哈希查找这一前提与代码不符」。

裁定：**台账的机制描述成立，verifier 的证伪理由不成立**。`main` 的 `SymbolIndexStore.swift:536` 就是 `memberSymbolsByKind[$0]?[name]?[node]`，三层哈希查找，verifier 那句话本身与代码不符。

但量级上 verifier 的方向碰巧对，理由不同：被扫描的桶装的是「同一类型名下的不同 type node」，且 `main` 那次哈希查找本身也要遍历整棵 node 树算结构哈希——所以是「一次全树哈希」换成「一次全树结构比对」，不存在台账所称的倍数退化。实测印证了这一点（见下）。

### 三、线程跳转的来历——这是本轮最重要的发现

报告把打印路径的跳转列为迁移缺陷，建议「恢复内联调用」。查 `swift-demangling` 的提交历史后发现这个定性是错的。

`StackSafeExecutor` 改过 8 次，最近三次围绕「什么时候该内联」反复：

- `6fa6d95` 改成按剩余栈字节判断，worker 给 64 MB，同时引入 `withLargeStack` 作为批量边界；
- `7718889` 把内联门槛提到 worker 自己的栈大小，于是主线程也每次跳——刻意为之，为了让「一棵树能打印多深」不取决于调用线程；
- `7b86137` 把上一步**回退**了，因为 64 MB 门槛让 LLDB 里 `po` 死锁（`po` 只跑当前线程，永远等不到 worker）、优先级反转。改回 8 MB worker + 2 MB 门槛。

同一个提交里写死了打印必须过 executor：

> The only public ways to print are `NodePrinter<Target>.print(_:using:)` and the SPI `DemanglingPrinter.print(_:options:)`, both routed through the executor, so a tree's surviving depth can no longer depend on the calling thread's remaining stack.

再往前查，`0.4.3`（`main` 依赖的版本）的 `NodePrinter.printRoot` 是**没有任何栈保护**的实例方法，`main` 的 `printSemantic` 就是裸递归——代价是深嵌套泛型在 512 KB 的 worker 上打印会真的栈溢出崩溃（这条线最早的提交 `df96bae fix: prevent stack overflow in NodePrinter on non-main threads` 修的正是它，保护在后续重构中丢失）。

所以两条路径的来历完全不同：**demangle 的跳转一直存在**（`0.4.3` 的 `DemangleInterface.swift:15` 就是 `StackSafeExecutor.execute`，`main` 靠 `concurrentMap` 摊薄），**打印的跳转是上游新引入的、用性能换栈安全的刻意交易**。上游在同一批改动里给出了摊销手段 `withLargeStack`，文档注释直接点名本仓库这类场景，而仓库内**零处**使用。

### 四、探测逻辑本身没有问题

报告的实测表三行都写「总栈 524 KB」，包括主线程——与 macOS 主线程 8 MB 的事实矛盾。直接用 C 复核 `StackSafeExecutor` 依据的那两个 `pthread` 调用：

```
main thread          reported_size=8176 KB   remaining=8168 KB   >=2MB: YES (inline)
libdispatch worker   reported_size= 524 KB   remaining= 523 KB   >=2MB: no  (HOP)
```

主线程报 8176 KB，走内联。所以正确结论是「非主线程恒跳，主线程不跳」，原表第一行那次测量并没有跑在真主线程上。这个区别影响面很大：从主线程直接渲染（例如 RuntimeViewer 的 UI 线程）根本不付这笔钱。

## 最终方案

### 改动一：build sweep 套批量边界

`withLargeStack` 的收益是 `(批内调用次数 − 1) × 单次跳转成本`，所以它必须包住**循环**——包住单次调用则付一次省一次，净收益为零。全仓库符合条件的同步循环只有 `SymbolIndexStore.buildStorageImpl` 一处。

打印侧的循环在 `SwiftDeclarationPrinter` 里，是 `async`，同步的 `withLargeStack` 包不进去，本轮不动。

`Node+.swift` 的注释改成如实描述，**代码不动**——在 `printSemantic` 里包一层是零收益。

### 改动二：存入模型的 `DemangledSymbol` 先 detach

共享 `[Symbol]` 表对「吐几十万个值随即丢弃」是正确取舍（每个值保持 32 字节），对「存进声明模型长期存活的几千个」是错误取舍（一个存活值钉住整表）。方案是在**存入点**转换，查询路径不动。

选构造点而不是改 `Accessor` / `FunctionDefinition` 的 init：后者要把 `@MemberwiseInit(.public)` 换成手写 init，而那个 init 是公开 API 的一部分，签名写错会让仓库外调用方编译失败。构造点只有 6 处且有测试守护，风险低得多。

## 实际执行

### 代码

- `Sources/MachOSymbols/SymbolIndexStore.swift` —— 原 `buildStorageImpl` 的函数体整体移入新的 `buildStorageSweep`，外层薄壳包一次 `StackSafeExecutor.withLargeStack`。两个调用方（`buildStorage` 与带进度的异步入口）同时受益。
- `Sources/SwiftDeclarationRendering/Extensions/Node+.swift` —— 重写 `printSemantic` 的文档注释：说明 `print(_:options:)` 与 `execute` 是同一段逻辑（仅少了泛型 `Target` 无法满足的 `Sendable` 约束）、这笔开销是上游 `7b86137` 的刻意交易、摊销点在批量边界而不在此处。
- `Sources/MachOSymbols/DemangledSymbol.swift` —— 新增 `detachedFromSharedTable()`（复用现成的 `init(symbol:demangledNode:)`，把行复制进单行表）与 `package` 级的 `retainedSymbolTableRowCount`（供测试区分两种形态，不进公开 API）。
- `Sources/SwiftDeclaration/Components/Definitions/DefinitionBuilder.swift` —— 四个构造点调用 detach：variables 与 subscripts 的 `Accessor`、allocator 与 function 的 `FunctionDefinition`。
- `Sources/SwiftDeclaration/Components/Definitions/TypeDefinition.swift` —— `deallocatorSymbol` / `destructorSymbol` 两处赋值调用 detach。

公开 API 只增不改，`@MemberwiseInit` 生成的构造器签名一字未动。

### 测试

`Tests/SwiftInterfaceTests/SymbolTableRetentionTests.swift` 随修复一并保留：索引并导出 `SymbolTestsCore`，断言模型里每一个存下来的 `DemangledSymbol` 的 `retainedSymbolTableRowCount == 1`。测试先于修复写好并确认失败：

```
10+ of 530 stored symbols still reference the 9348-row shared table
```

修复后通过。将来新增构造点忘记 detach，它立刻变红。

### 横向排查

全仓库 `DemangledSymbol` 类型的存储属性只有五处：四处即上述已修字段，第五处 `DemangledSymbolWithOffset.base` 只出现在 `index(in:)` 的局部变量里，不长期存活。无遗漏同类。

## 验证

### 实测数据（复现代码为一次性程序，数据落表后已删除）

样本：SwiftUI（iOS 18.5 模拟器，93 MB，185,988 个符号行）、当前 macOS dyld shared cache（3,649 个镜像）。

| 条目 | 报告原本的说法 | 实测 | 判定 |
| --- | --- | --- | --- |
| build sweep | 「大框架首次打开慢数倍」 | 10 万符号：1317 ms → 701 ms | 成立，**1.88x**，跳转成本几乎与 demangle 本身等价 |
| 失败名重试 | 「把其他线程全堵在后面」 | 失败名 43.4 ms vs 缓存命中 6.9 ms（6.3x）；8 线程争用 1.97x，而无锁路径本身也有 1.67x | 机制成立，**锁争用未复现** |
| dyld 全遍历 | 迁移退化 | framework 4.73 ms vs plain dylib 39.71 ms（8.4x） | 代价成立，**不是退化** |
| materialize | 「约 10^5 次瞬时建树」 | 37,166 次、1,047,919 节点、839 ms，占导出总时长（107.9 s）的 **0.8%** | 次数少一个量级，**不构成性能问题** |
| 符号表钉住 | — | 9,872 个存活值引用 9,506 行，占表的 5.1%；约 21 MB → 约 2 MB | 成立，**已修** |
| `isExternal` | — | 185,988 行中 `true` 的有 0 行 | 成立 |
| 身份键 | — | 裸 `NodeReference` 键 MISS，`StructuralNodeReferenceKey` 命中 | 成立 |
| 不变量无测试 | — | 把 sweep 换回 `demangleAsNode`，`MachOSymbolsTests` **19 个测试全绿** | 成立，比原文更严重 |
| 桶扫描（台账第 5 条） | 「O(1) 退化成线性扫描」 | 6,720 个桶中 **99.60% 只有 1 个元素**，最大 6 | 机制成立，量级可忽略 |

### 需要改判断的三条

1. **失败名重试的危害说反了方向**。失败的 demangle 是快速失败（demangler 在开头就拒绝），比一次成功的 demangle 还便宜；8 线程并发下失败路径 1.97x、完全无锁路径 1.67x，锁几乎不构成额外争用。真正的问题是它**永不收敛**——每次调用重跑一遍。修法不变，理由从「解除锁争用」改成「消除重复计算」。顺带测出 `Mutex` 本身近乎免费：缓存命中的 off-table 路径 6.87 ms 与表内命中 6.79 ms 无差别。

2. **dyld 那条不是退化**。排名机制由本分支的 `7e5dfcc` / `cfe40f8` 引入，修的是「叶名在 shared cache 里不唯一」——`swift-section --dyld-shared-cache -n SwiftUI` 曾解析到没有 Swift 元数据的 accessibility bundle，输出空 dump 还 exit 0。全遍历是这个正确性修复的代价。优化空间真实存在（按叶名预建索引），但那是新优化不是回退。

3. **materialize 不该按性能问题排序**。0.8% 的占比意味着即使全部消灭也快不了 1%。它仍是设计一致性问题（迁移的目标是消除建树，打印路径却还在建），但不应占用性能预算。

### 测试

`swift test --skip IntegrationTests`：**1304 个测试全部通过**（含新增的回归测试）。

## 偏差

### 一、一个假警报花了一轮排查

第一次跑全套时红了 148 个，全部是 ABI baseline 偏移不匹配。stash 掉改动后用同一 scratch path 重跑，失败**完全一样**（同样的偏移 285532 vs 269112），确认与本轮改动无关。

按 AGENTS.md 的环境漂移条目诊断：fixture 源码里有 `AccessorFunctionReferences.swift`（提交 `51d52c3`），而 7 月 26 日构建的二进制里 `strings | grep -c` 查出来 0 处——是 fixture 二进制比源码旧。重建后全套转绿。

排查过程中我先说成「baseline 旧」，方向说反了，随后用 mtime 与 `strings` 更正。

### 二、方案沟通绕了四轮

最初把改动描述成「给批量渲染入口套 `withLargeStack`」，没有给出 `文件:行号`。用户理解成要改 `Node+.swift` 的 `printSemantic`——而那里恰好有一段注释明确写着「不要在这里包 `StackSafeExecutor`」，所以建议听起来像是要推翻它。用户连问四轮才对齐到 `SymbolIndexStore` 的 sweep 循环，而他从第一轮起的直觉（「这不是加不加都一样吗」）一直是对的。

教训是：讨论改动方案时第一句就要给出具体位置和「明确不动的地方」，原理放在后面；用户反复追问同一个技术点时，优先怀疑是位置没对齐，而不是原理没讲透——换一种方式重讲原理只会加深误解。

### 三、两处技术假设被数据推翻

- 假设失败的 demangle 比成功的慢（因为要「重跑」），实测相反——快速失败更便宜。第一版复现代码据此写了 `#expect(failing > cached)`，直接红了。
- 第一版复现里挑的「可 demangle 但不在表里」的名字（`$sSi4main1AVSgSayADGSgtcfC`）其实 demangle 不了，导致两组对照实际上都是失败路径。改成从候选列表里挑第一个真正合法的才拿到干净数据。

两次都是先写断言再看数据导致的，正确顺序应当是先测量再决定断言什么。

## 未处理

清单剩余条目全部保留在[审查报告](../Reviews/2026-07-31-node-store-migration-review.md)第四节，定性已按本轮实测更新。其中三条有明确后续方向：

- **build sweep 的串行本身**——恢复 `concurrentMap` 不可行（`NodeStoreBuilder.intern` 要求顺序 interning），要拿回并行需要分片 builder 后归并，属独立课题。
- **打印路径的摊销**——需要自定义一个跑在 8 MB 线程上的 `SerialExecutor`，或把打印批次改成同步。先有 0.8% 这个数打底，优先级不高。
- **`Version.swift` 未升 + 无 changelog**——`Symbol` 删了公开成员，发布前必须补。

另有一个不在清单内、值得单独查的观察：SwiftUI 全量 interface 导出耗时 **107.9 秒**，而 `materialize` 只占 0.8%，其余 99% 的去向本轮没有测量。
