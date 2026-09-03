# 2026-07-31 `feature/node-store-migration` 代码审查

本文记录 2026-07-31 对 `feature/node-store-migration` 做的一轮代码审查：**结论、实测数据、以及待处理清单**。

与 [`NodeStoreMigrationOpenIssues.md`](../NodeStoreMigrationOpenIssues.md) 的分工：那份是按技术主题组织的长期遗留问题台账；本文是**一次审查事件的记录**，包含它自己的实测数据和当时的判断。两者重叠的条目在第六节逐条对照，避免两边各说各话。

## 审查方式

多智能体并行审查，6 个 finder 角度（逐行扫描 / 删除行为审计 / 跨文件追踪 / 语言陷阱 / 包装类型正确性 / 清理类）各自独立出候选，再对每个 `(文件, 行)` 位置派一个独立 verifier 做对抗性验证（默认倾向证伪），最后归并去重。

规模：63 个改动文件 → 57 条候选 → 34 个 verifier → 50 条完成验证（43 条保留、7 条被证伪）→ 归并后 15 条。

对比基线：`git diff origin/main...origin/feature/node-store-migration`。

## 一、本轮已闭环

### 1. `SemanticString.write(_:context:)` 不再是 witness，语义标注被静默丢弃 ✅

`NodePrinterTarget` 的 `write(_:context:)` 要求在上游改成了 `@autoclosure () -> NodePrintContext?`，而 `SwiftDeclarationRendering/Extensions/Node+.swift` 里 `SemanticString` 的实现仍是即时求值形态。Swift 认为签名不匹配，**不报错也不警告**，直接改用协议自带的默认实现——而那个默认实现把 context 丢掉、退回 `write(content)` → `append(string, type: .standard)`。

后果是所有经 demangler 打印的 token 都变成无标注的 `.standard`：终端着色全部失效，`replacingTypeNameOrOtherToTypeDeclaration()`（只重写 `.type(_, .name)` / `.other`）变成空操作，声明头部丢失类型声明标注，RuntimeViewer 的高亮与类型跳转随之失效。**输出文字逐字节相同**，所以整个测试套件全绿。

同一处改动里旁边的 `pushTypeReferenceScope` 已经跟着改成 `@autoclosure` 了，唯独这一个漏掉。

**修复**：参数改为 `@autoclosure () -> NodePrintContext?`，`guard let context = context()` 求值一次。

**防回归**：上游在同一版里**删除了这两个要求的协议默认实现**（只保留无参数的 `popTypeReferenceScope`，并在注释中说明原因："它不带参数，没有近似签名可以被吞掉"）。所以此后签名写错是硬编译错误，编译器本身就是守卫，不需要额外写测试。

### 2. 三个 Name 类型的 `Codable` 与其"线路兼容"承诺 ✅

`TypeName` / `ProtocolName` / `ExtensionName` 的手写 `Codable` 注释声称"与历史 `node: Node` 编码保持线路兼容"。上游在同一版里**删除了 `Node: Codable`**（理由：mangled 符号本身就是这棵树的序列化形式——更小、由 Swift ABI 定义所以跨版本稳定、往返时重新 demangle 会重建 interning 而不是按路径数展开），该承诺随之作废，且成为编译错误。

**处理**：直接删除三个类型的 `Codable` 一致性与全部手写实现，而非改写编码。依据是这些类型本就不适合 `Codable`，且确认无人使用——`DefinitionName` 协议不要求它，`AssociatedTypeWitnessProjection`（唯一相关的 `Codable` 类型）只装字符串，仓库内外均无编解码这三个类型的地方。

`AGENTS.md` 中相应描述已改为说明"刻意不再是 `Codable`"及其原因，并指出将来若需持久化应走 `mangleAsString` / `demangleAsNode`。

## 二、实测：打印路径的线程跳转

这一条单列，因为它是本轮唯一做了定量测量的问题，而**审查报告最初对它的量级判断是错的**。

### 机制（代码事实）

`swift-demangling` 的 `Sources/Demangling/Utils/StackSafeExecutor.swift`：

| 位置 | 内容 |
| --- | --- |
| L58 | `minimumRemainingStackSize = 2 * 1024 * 1024` |
| L204-211 | `currentThreadHasSufficientStack` = 当前栈指针 − 栈底 ≥ 2MB |
| L128-146 | `executeWithUncheckedSendability`：够则内联，否则 `runOnLargeStack` |
| L226-239 | `runOnLargeStack`：提交线程池 + `DispatchSemaphore.wait()` |

`NodePrinter.swift` L90-95：`DemanglingPrinter.print` 的函数体就是 `StackSafeExecutor.executeWithUncheckedSendability { ... }`。

### 实测：非主线程恒跳，主线程不跳

探针 target 在 `write` 中记录**遍历实际执行所在的线程 ID**，与调用者线程 ID 对比：

```
[main thread]                             总栈 524 KB  剩余 522 KB  ≥2MB: false
  caller 17785076 → walk 17785088         HOPPED: true
[Swift Concurrency cooperative worker]    总栈 524 KB  剩余 522 KB  ≥2MB: false
  caller 17785080 → walk 17785090         HOPPED: true
[libdispatch global worker]               总栈 524 KB  剩余 522 KB  ≥2MB: false
  caller 17785083 → walk 17785089         HOPPED: true
```

**更正（2026-07-31 复核）**：上表第一行标着 `[main thread]` 却报 524 KB，与 macOS 主线程 8 MB 的事实矛盾——那次测量并没有跑在真正的主线程上（`swift-testing` 的 `@Test` 默认不在主线程）。直接用 C 复核 `StackSafeExecutor` 所依据的那两个 `pthread` 调用：

```
main thread          reported_size=8176 KB   remaining=8168 KB   >=2MB: YES (inline)
libdispatch worker   reported_size= 524 KB   remaining= 523 KB   >=2MB: no  (HOP)
```

所以准确的结论是：**非主线程（cooperative worker、libdispatch worker）恒跳，主线程不跳**。上游的探测逻辑本身没有问题，`pthread_get_stacksize_np` 在主线程上返回的是真实的 8 MB。

这个区别影响面很大：从主线程直接渲染（例如 RuntimeViewer 的 UI 线程）根本不付这笔钱；付钱的是跑在 worker 上的路径——而 `buildStorageImpl` 的符号 sweep 正是这种。原文"三种线程上下文全部换线程，无一例外"应作废。

### 实测：代价

2000 次打印。对照组是把同样的循环包进一次 `StackSafeExecutor.withLargeStack`（批内实测 `hopped: false`，证明确实内联了）：

| 场景 | 每次调用 | 一次 withLargeStack | 倍数 | 每次固定开销 |
| --- | --- | --- | --- | --- |
| 小树 · debug | 90.9 ms | 25.9 ms | 3.51x | 32.5 µs |
| 大树 · debug | 744.6 ms | 647.2 ms | 1.15x | 48.7 µs |
| 小树 · release | 29.1 ms | 12.8 ms | 2.28x | 8.2 µs |
| 大树 · release | 337.8 ms | 296.2 ms | **1.14x** | 20.8 µs |

大树 = 从测试二进制中取的最长真实符号（916 字符）。

**更正**：审查报告原文称 "interface generation slows by a large multiple"（慢好几倍），**不成立**。真实情况是每次打印固定多付 8–21 µs（release），树越大被稀释得越厉害，大树上只有 ~14%。

### 未验证的部分

- **"阻塞协作线程导致并发池饿死"在打印路径上仍未实测**。上表测的是单线程吞吐，不是池饱和。相邻的 demangle 路径已在第三节实测过并发争用（8 线程仅 1.97x，而完全无锁的路径本身也有 1.67x），可作旁证但不能直接代入打印路径——两者用的是同一个 executor，但打印的单次工作量更大。
- 真实 interface 导出中符号树大小的分布未知，因此整体影响落在 1.14x–2.28x 之间的何处没有数据。

### 这是上游的刻意交易，不是本次迁移的缺陷

比对本分支依赖的 `swift-demangling` 与 `main` 依赖的 `0.4.3`，两条路径的来历完全不同：

| | `0.4.3`（仓库 `main`） | `feature/node-store`（本分支） |
| --- | --- | --- |
| demangle | 过 executor，每次跳 | 过 executor，每次跳 |
| 打印 | **无任何栈保护，直接递归** | 过 executor，每次跳 |
| 本仓库 build sweep | `concurrentMap` 并行，摊薄跳转 | 串行，不摊薄 |

- **demangle 的跳转一直存在**：`0.4.3` 的 `DemangleInterface.swift:15` 就是 `StackSafeExecutor.execute`。仓库 `main` 靠 `concurrentMap` 摊薄，本分支改成串行后暴露出来。
- **打印的跳转是新的**：`0.4.3` 的 `NodePrinter.printRoot` 是无保护的实例方法，`main` 的 `printSemantic` 就是裸递归。上游 `7b86137` 把实例级 `printRoot` 改成 internal，只留两个强制过 executor 的公开入口，理由写在提交信息里——"so a tree's surviving depth can no longer depend on the calling thread's remaining stack"。

也就是说，打印路径这笔开销是上游**用性能换栈安全**换来的：在此之前，深嵌套泛型在 512 KB 的 worker 上打印是真的会栈溢出崩溃（这条线最早的提交 `df96bae fix: prevent stack overflow in NodePrinter on non-main threads` 修的就是它，那层保护在后续重构中丢失，到 `0.4.3` 时 `NodePrinter` 又是裸的）。上游在同一批改动里给出了摊销手段 `withLargeStack`，并在其文档注释中点名本仓库这类场景："Use this at a batch boundary — indexing every symbol of a binary, say — so the whole batch pays for at most one thread hop instead of one per call."

### 修法与落地

`withLargeStack` 必须包住**循环**才有意义：它的收益是 `(批内调用次数 − 1) × 单次跳转成本`，包住单次调用则付一次、省一次，净收益为零。全仓库符合条件的同步循环只有一处，已落地：

- **`SymbolIndexStore.buildStorageImpl`**（本次改动）：原函数体整体移入 `buildStorageSweep`，外层薄壳包一次 `withLargeStack`。两个调用方（`buildStorage` 与带进度的异步入口）同时受益，每符号一次线程往返降为整批一次。

  实测收益（release，10 万个真实 Swift 符号，取自本仓库构建产物；同一串行循环，唯一变量是有无批量边界）：

  | 运行线程 | 无批量边界 | 包 `withLargeStack` | 差异 |
  | --- | --- | --- | --- |
  | libdispatch worker（512 KB，sweep 实际所在） | 1317.2 ms | 701.5 ms | **1.88x，省 615.7 ms** |
  | 主线程（8176 KB） | 145.8 ms / 2 万符号 | 145.2 ms | 无差别（噪声内） |

  每符号省 6.2 µs。值得注意的是跳转成本（615.7 ms）几乎与 demangle 本身（701.5 ms）等价——**近一半时间花在线程往返上**。主线程两组数据一致，再次确认探测通过时批量边界不产生任何作用，也印证上文对原实测表的更正。
- **`Node+.swift` 的 `printSemantic` 注释**（本次改动）：原注释断言 `print(_:options:)` "runs the recursion inline against a stack floor and pays for a worker only for a tree that actually reaches it"，与代码相反——它内部就是 `executeWithUncheckedSendability`，与 `execute` 是同一段逻辑，仅少了 `Sendable` 约束。注释已改为如实描述，并说明为何摊销点不在此处。**代码未动**。
- **渲染循环暂不处理**：打印侧的循环在 `SwiftDeclarationPrinter` 里，是 `async`，同步的 `withLargeStack` 无法包裹。真要摊销需要自定义一个跑在 8 MB 线程上的 `SerialExecutor`，或把打印批次改成同步——两者都是独立的重构。先量清楚真实导出中的调用次数与总开销，再决定是否值得。
  **已解决（2026-09-03，提案 `large-stack-executor-and-cross-version-parallelism`）**：走的是第三条路——上游 swift-demangling 0.6.3 提供 16 MB 线程的 `TaskExecutor`，本库的 async 入口经 `LargeStackTaskExecution.run` 把整个 task 放到它上面，探针在每个入口都通过，打印路径零跳转；见 `Documentations/Internal/LargeStackTaskExecutorAdoption.md`。

> 探针为一次性测量代码，测完已删除。若需长期守护该性质，应整理为正式 benchmark。

## 三、实测复现（2026-08-01）

清单中每一条可测量的条目都写了复现代码实际跑过。复现代码为一次性程序（临时 instrumentation + 三个临时测试文件），数据落表后已全部删除，仓库只保留第二节的三处正式改动。

样本：SwiftUI（iOS 18.5 模拟器，93 MB，185,988 个符号行）、当前 macOS dyld shared cache（3,649 个镜像）。

| 条目 | 审查报告原本的说法 | 实测结果 | 判定 |
| --- | --- | --- | --- |
| 四.1 build sweep | "大框架首次打开慢数倍" | 10 万符号：1317 ms → 701 ms（包 `withLargeStack` 后） | **成立**，跳转部分已修，**1.88x** |
| 四.3 失败名重试 | "把其他线程全堵在后面" | 单线程 5000 次：失败名 43.4 ms vs 缓存命中 6.9 ms（**6.3x**）；8 线程争用 1.97x，而无锁路径本身也有 1.67x | 机制**成立**，但"堵住其他线程"**未复现**——瓶颈是重复计算，不是锁 |
| 四.5 dyld 全遍历 | 迁移退化 | framework 名 4.73 ms vs plain dylib 39.71 ms（**8.4x**），未命中 38.6 ms | 代价**成立**，但**不是退化**：排名机制是本分支刻意引入的正确性修复 |
| 四.6/四.7 materialize | "约 10^5 次瞬时建树" | SwiftUI 全量导出：37,166 次调用、1,047,919 个节点、839 ms，占导出总时长（107.9 s）的 **0.8%** | 次数比估计**少一个量级**，**不构成性能问题** |
| 内存 10 符号表钉住 | — | 185,988 行 × 32 B = 5.8 MB，加 16.6 MB 名字字符串 ≈ **21 MB**；实测 `Storage` 释放后名字仍可读。导出后长期存活 9,872 个值，只引用 9,506 行（表的 5.1%） | **成立，量级严重；已修（2026-08-02）** |
| API 11 公开成员删除 | — | `nlist` 属性与 `init(offset:name:nlist:)` 已删；`Version.swift` 无改动；`Changelogs/` 无新条目 | **三点全部成立** |
| API 12 `isExternal` 死代码 | — | 185,988 行中 `isExternal == true` 的有 **0** 行 | **成立** |
| API 13 身份键 | — | 同一 mangled name 经两个 mini store，`structurallyEquals` 为真，裸 `NodeReference` 键查询 **MISS**，`StructuralNodeReferenceKey` 命中 | **成立** |
| 测试 14 不变量无断言 | — | 把 sweep 换回 `demangleAsNode`，`MachOSymbolsTests` **19 个测试全绿** | **成立，且比原文更严重**——不只那一个测试抓不住，整个 target 都抓不住 |
| 台账第 5 条 桶扫描 | "O(1) 退化成线性扫描 + 逐候选全树比对" | 6,720 个桶中 **99.60% 只有 1 个元素**，最大 6（`SwiftUI.Coordinator`） | 机制**成立**，量级**可忽略** |

三条需要修改原判断：

1. **四.3 的危害说错了方向**。失败的 demangle 是**快速失败**（demangler 在开头就拒绝），比一次成功的 demangle 还便宜；8 线程并发下失败路径 1.97x、无锁路径 1.67x，锁几乎不构成额外争用。真正的问题是它**永不收敛**——每次调用重跑一遍，而缓存命中路径与表内命中一样快（6.87 ms vs 6.79 ms，说明 `Mutex` 本身近乎免费）。修法仍是缓存失败结果，但理由从"解除锁争用"改成"消除重复计算"。

2. **四.5 不是退化**。`main` 的 `first(where:)` 命中即停确实更快，但它拿到的可能是错的镜像——叶名在 shared cache 里不唯一，`swift-section --dyld-shared-cache -n SwiftUI` 曾解析到没有 Swift 元数据的 accessibility bundle，输出空 dump 还 exit 0。排名机制由本分支的 `7e5dfcc` / `cfe40f8` 引入来修这个 bug，全遍历是它的代价。优化空间真实存在（按叶名预建索引，把 O(全部镜像) 降到 O(同名镜像)），但这是新优化，不是回退。

3. **四.6/四.7 不该按性能问题排序**。0.8% 的占比意味着即使把 `materialize` 全部消灭，导出也快不了 1%。它仍是个设计一致性问题（迁移的目标是消除建树，打印路径却还在建），但不应占用性能预算。

> 顺带一个不在清单内、值得单独查的观察：SwiftUI 全量 interface 导出耗时 **107.9 秒**，而其中 `materialize` 只占 0.8%。其余 99% 的去向本轮没有测量。

## 四、待处理清单

按建议优先级排列。标注 ⚠️ 的是本轮新发现（既有台账中没有）。定性以第三节实测为准。

### 性能

1. **build sweep 由并行改为串行**（`SymbolIndexStore.swift`）。原为 `symbolArray.concurrentMap`，现为单趟顺序循环。
   - **跨线程往返部分已修**：sweep 循环已包进 `StackSafeExecutor.withLargeStack`（见第二节"修法与落地"），每符号一次线程往返降为整批一次。
   - **串行本身仍未解**，且恢复 `concurrentMap` 不可行——`NodeStoreBuilder.intern` 要求顺序 interning，并行会破坏 hash-consing 的索引分配。要拿回并行需要另行设计（例如分片 builder 后归并），属独立课题。
   - 注：既有台账第 6 条描述此问题时称"不是打印路径用的 `executeWithinStackBudget`"，但**该入口在当前上游版本中并不存在**。该前提需要更正。

2. **打印路径每次调用跨线程 + 阻塞**（`Node+.swift`）。**重新定性：这不是本次迁移的缺陷**，而是上游 `7b86137` 用性能换栈安全的刻意交易——`0.4.3` 的打印路径完全没有栈保护，深树在 512 KB 线程上会崩（详见第二节）。原建议的"恢复内联调用"**不可行且不应做**：上游已把实例级 `printRoot` 收为 internal，正是为了堵死这条路。
   - 本次只修正了 `printSemantic` 上与代码相反的注释，代码未动。
   - 摊销需要在渲染循环处做，而该循环是 `async`，`withLargeStack` 包不进去。待复现量出真实代价后再决定是否为它引入自定义 `SerialExecutor`。

3. ⚠️ **demangle 失败的符号名永不缓存，且在持锁状态下重试**（`SymbolIndexStore.swift:848`）。`buildStorageImpl` 对 demangle 失败的名字仍保留表行但 root index 为 `nil`，于是 `demangledNodeReference` 永远走不到快速路径、落到 `lateDemangledNode`，而后者按契约不缓存失败。`demangledOverrideSymbol` 会为每个类的每个方法遍历候选符号，每遇到一个不可 demangle 的符号就取一次 per-image 锁重跑 demangle（其本身还要跨线程阻塞），把其他线程全堵在后面。迁移前该 miss 路径完全不加锁。

4. **`lateDemangledNode(forName:)` 在持锁期间 demangle**（`SymbolIndexStore.swift:245`）。既有台账第 9 条，判定为 PLAUSIBLE（机制确定，触发条件依赖并发时序）。注意其临界区合并是**刻意的**（防止两个并发 miss 冻结出两份 mini store），修复时要保住该保证。

5. ⚠️ **dyld 缓存按名字查找丢失提前退出**（`DyldCache+.swift:112`）。`accumulateBestMatch` 只在 `bestMatchRank`（0，仅原生 `<name>.framework` 能拿到）时提前返回。其余情况（plain dylib、bundle，即 rank 2/4）要遍历主缓存加全部子缓存的约 4000+ 个镜像并逐个构造 `MachOFile`，而迁移前 `first(where:)` 命中即停。`FullDyldCache.machOFile(by:)`（L133/186）继承同样的全遍历。

6. ⚠️ **打印器每个成员都 materialize 一整棵树**（`SwiftDeclarationPrinter.swift:438`）。`printVariable` / `printFunction` / `printSubscript`（L438/448/458）、扩展 where 子句循环（L261）、`+Members.swift`（L42/65）各调一次 `.materialize()`，而该方法"每次调用都返回新实例"。SwiftUI 规模的 interface 导出约 10^5 次瞬时建树——这恰是本次迁移要消灭的动作。

7. ⚠️ **`demangledNode(for:in:)` 丢失 per-symbol 记忆化**（`SymbolIndexStore.swift:856`）。旧实现返回 `demangledNodeBySymbol` 里缓存的实例，新实现是 `demangledNodeReference(for:in:)?.materialize()`，每次重建。`MetadataReader.demangleSymbol(for:in:)` 直接转发它，且仍在 dump 路径的逐符号循环中被调用（`ClassDumper:271,455`、`ProtocolDumper:151`、`ProtocolConformanceDumper:113,176`）。

8. **`structuralHash` 每个文本节点分配一个 `String`**。既有台账第 4 条。**修复位置在上游**（应哈希零拷贝的 `textUTF8` 而非 `text`），本仓库无法绕开。

9. **`ABIKey.make` 每个 key materialize 整棵树**。既有台账第 7 条。

### 内存

10. ⚠️ **`DemangledSymbol` 钉住整张 per-image 符号表**（`DemangledSymbol.swift:12`）。`Storage.demangledSymbol(atRow:)` 交出的每个值都持有共享的 `[Symbol]` 缓冲（SwiftUI 约 20 万行，每行 32 字节加一个堆分配的 mangled name 字符串，合计数十 MB），而这些值按值散布在声明模型各处（`Accessor.symbol`、`FunctionDefinition.symbol`、`TypeDefinition.deallocatorSymbol` / `destructorSymbol`）。

    后果直接冲击本 PR 新增的 `removeSubIndexer(_:)`——该接口的存在理由正是"让 per-image 内存真正被回收"，但只要调用方还留着**一个** `FunctionDefinition` 或 `Accessor`，整张表及其全部名字字符串就释放不掉。迁移前 `DemangledSymbol` 内联单个 `Symbol`（一个字符串），同样的残留只钉住几十字节。

    `AGENTS.md` 只记录了 `NodeStore` 的"活声明保活其 store"模型，符号表这层钉住是新增且未记录的。

    **已修（2026-08-02）**：新增 `DemangledSymbol.detachedFromSharedTable()`，把引用的行复制进单行表。在**存入模型的六处**调用——`DefinitionBuilder` 的四个构造点（variables / subscripts 的 `Accessor`，allocator / function 的 `FunctionDefinition`）与 `TypeDefinition` 的 `deallocatorSymbol` / `destructorSymbol` 两处赋值。查询路径不动：共享表对"吐几十万个值随即丢弃"仍是正确取舍，问题只在存下来的那几千个。

    实测（SwiftUI iOS 18.5，一次全量导出后）：长期存活 9,872 个值，引用 9,506 个不同行，占 185,988 行表的 5.1%——用约 0.6 MB 的小分配换回约 19.9 MB 的保留。

    公开 API 只增不改：`detachedFromSharedTable()` 是新方法，`Accessor` / `FunctionDefinition` 的 `@MemberwiseInit` 构造器签名一字未动，仓库外调用方不受影响。

    回归测试 `Tests/SwiftInterfaceTests/SymbolTableRetentionTests.swift` 随修复一并保留：它索引并导出 `SymbolTestsCore`，断言模型中每一个存下来的 `DemangledSymbol` 的 `retainedSymbolTableRowCount == 1`。修复前该测试失败（530 个存储符号全部引用 9,348 行的共享表），修复后通过。新增的构造点若忘记 detach，它会立刻变红。

    横向排查：全仓库 `DemangledSymbol` 类型的存储属性只有五处，四处即上述已修字段，第五处 `DemangledSymbolWithOffset.base` 只出现在 `index(in:)` 的局部变量里，不长期存活。

### 对外 API

11. ⚠️ **`Symbol` 删除公开成员但未升版本、未写 changelog**（`Symbol.swift:17`）。删掉了公开的 `nlist` 属性与 `init(offset:name:nlist:)`，仓库外调用方升级后编译失败，而 `Version.swift` 未升、`Changelogs/` 无条目。

12. **`Symbol.isExternal` 在符号表里恒为 `false`**。既有台账第 8 条，与上一条同源：采集局部符号的循环已用 `where … && !symbol.nlist.isExternal` 过滤，导出符号循环走 `isExternal: false` 默认值，故 `if !symbol.isExternal` 守卫是死代码，且字段注释与实际不符。

13. **两个公开查询 API 的字典键从结构相等翻成身份相等**。既有台账第 3 条。本轮复核**确认其严重性低于初判**：`allOpaqueTypeDescriptorSymbols(in:)` 在整个仓库（含 `main`）**零调用方**；`memberSymbols(of:excluding:in:)` 的唯一调用方（`SwiftDeclarationIndexer.swift:684`）是遍历而非下标查询；真正的不透明类型解析路径 `opaqueTypeDescriptorSymbol(for:in:)` 已在 `db7105b` 中被刻意改为结构化查找。残留风险仅为"将来有人下标查询时静默拿到空"。

### 测试与文档

14. ⚠️ **迁移的核心不变量没有断言**（`SymbolIndexStoreFixtureTests.swift:42`）。`buildPipelineStaysOffGlobalNodeCache` 只是自己调了两次 `demangleAsNodeTransient` 比对结果，**完全没有断言 `buildStorage` 的行为**。把 `buildStorageImpl` 改回 `demangleAsNode`（即 Stage-1 那个回归），该测试照样绿。唯一能捕获的断言在 `Tests/IntegrationTests/` 的 `NodeCache.shared.count` 增量里，而 `AGENTS.md` 禁止 agent 与 CI 运行该目录。同一缺口也覆盖 `MetadataReader` / `RuntimeFieldLayoutBackend` / `TypedDumper` / `ClassHierarchyDumper` 的 `Node.createTransient` 回归——`AGENTS.md` 把它列为硬规则，但背后没有测试。

15. **既有台账第五节（第 12 条）的前提已过期**。该节称本分支落后 `main` 五个提交、`AGENTS.md` 冲突，需"先 rebase 再谈合并"。实测 `git log origin/feature/node-store-migration..origin/main` 为空，分支 `AGENTS.md` 已同时包含 `main` 的 `--enum-layout-template` 章节与新的 NodeStore 段落，所述冲突不存在。

    但同一节压着一条**仍然成立**的注意事项：`main` 的 `TransformerOptionGroup` 与本分支的 `DemangleResolver` / `printSemantic` / `FieldDefinition.typeNode` 改动之间的交互从未被跑过。该注意事项需要在修订该节时保留，否则会随过期前提一起被读成"已处理"。

### 代码卫生

16. **`ProtocolConformanceDumper` 里 `case .symbol` 分支仍在 materialize**。既有台账第 10 条。

17. **两处 `throws` 是迁移残留**。既有台账第 11 条。

## 五、明确判定为"无需处理"

- **`Package.swift` 将 swift-demangling 指向 `branch: "feature/node-store"`**。审查将其报为阻断合并的缺陷（下游按版本依赖会解析失败、构建不可复现）。经确认这是**开发期的预期状态**——本库与其 demangling 依赖正在同步迁移，合并时会换回 `from:` 版本要求，期间接受上述代价。不作为问题跟踪。

## 六、与既有台账的对照

| 本文条目 | `NodeStoreMigrationOpenIssues.md` | 关系 |
| --- | --- | --- |
| 一.1（`write` witness） | — | 本轮新发现，已闭环 |
| 一.2（`Codable`） | — | 本轮新发现，已闭环 |
| 二 / 四.2（打印路径跳转） | — | 本轮新发现，附实测；已重新定性为上游刻意交易而非迁移缺陷；同时更正台账第 6 条的 `executeWithinStackBudget` 前提 |
| 四.1 | 第 6 条 | 同一问题；跳转部分已修（`withLargeStack`），串行部分仍未解 |
| 四.3、四.5、四.6、四.7 | — | 本轮新发现，均已实测（见第三节） |
| 四.4 | 第 9 条 | 同一问题 |
| 四.8 | 第 4 条 | 同一问题 |
| 四.9 | 第 7 条 | 同一问题 |
| 内存 10 | — | 本轮新发现 |
| API 11 | — | 本轮新发现（台账第 8 条只覆盖 `isExternal` 死代码，未覆盖公开成员删除） |
| API 12 | 第 8 条 | 同一问题 |
| API 13 | 第 3 条 | 同一问题，本轮补充了严重性复核 |
| 测试 14 | — | 本轮新发现 |
| 文档 15 | 第 12 条 | 指出该条前提已过期 |
| 卫生 16、17 | 第 10、11 条 | 同一问题 |

### 结论冲突（已裁定 2026-07-31）

既有台账**第 5 条**称 `memberSymbols(of:for:node:)` "从 O(1) 退化成线性扫描 + 逐候选全树比对"。本轮有 4 条同类候选指向该位置，全部被 verifier 证伪，理由是"原本是一次哈希查找"这一前提与代码不符。

**裁定：台账的机制描述成立，verifier 的证伪理由不成立。** 逐字核对两侧代码：

- `main`（`SymbolIndexStore.swift:536`）：`memberSymbolsByKind[$0]?[name]?[node]`——确实是三层哈希查找。verifier 所称"前提与代码不符"这句话本身与代码不符。
- 本分支（`SymbolIndexStore.swift:728`）：`rowsByTypeNodeIndex.elements.first(where: { storage.nodeStore.reference(at: $0.key).structurallyEquals(node) })`——线性扫描 + 每候选一次结构遍历。

**但量级判断上 verifier 的结论方向是对的，理由不同**：被扫描的桶装的是"同一类型名下的不同 type node"，正常情况只有 1 个元素；且 `main` 那次哈希查找本身也要遍历整棵 node 树计算结构哈希，本来就不是免费的 O(1)。所以实际是"一次全树哈希"换成"一次全树结构比对"，量级相当，不存在台账所称的倍数退化。

处置：台账第 5 条保留机制描述，删除"倍数退化"的措辞。桶大小已实测：6,720 个桶中 99.60% 只有 1 个元素，最大 6（见第三节）。

（本轮其余被证伪的 3 条均为风格类：`DefinitionBuilder` 重复构造 key、两处多余 `throws`、`StructuralNodeReferenceKey` 的模块归属。其中后两条与台账第 11 条、既有讨论重合，故仍列在本文第四节。）
