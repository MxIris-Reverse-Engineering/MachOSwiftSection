# 2026-07-31 `feature/node-store-migration` 代码审查

本文记录 2026-07-31 对 `feature/node-store-migration` 做的一轮代码审查：**结论、实测数据、以及待处理清单**。

与 [`NodeStoreMigrationOpenIssues.md`](../NodeStoreMigrationOpenIssues.md) 的分工：那份是按技术主题组织的长期遗留问题台账；本文是**一次审查事件的记录**，包含它自己的实测数据和当时的判断。两者重叠的条目在第五节逐条对照，避免两边各说各话。

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

### 实测：跳转率 100%

探针 target 在 `write` 中记录**遍历实际执行所在的线程 ID**，与调用者线程 ID 对比：

```
[main thread]                             总栈 524 KB  剩余 522 KB  ≥2MB: false
  caller 17785076 → walk 17785088         HOPPED: true
[Swift Concurrency cooperative worker]    总栈 524 KB  剩余 522 KB  ≥2MB: false
  caller 17785080 → walk 17785090         HOPPED: true
[libdispatch global worker]               总栈 524 KB  剩余 522 KB  ≥2MB: false
  caller 17785083 → walk 17785089         HOPPED: true
```

三种线程上下文全部换线程，无一例外。512 KB 栈的前提成立（实测 524 KB），2 MB 门槛永远过不去，**内联快速路径一次都没走到过**。

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

- **"阻塞协作线程导致并发池饿死"没有实测**。上表测的是单线程吞吐，不是池饱和。该结论目前仅由代码推导，需要构造多个并发渲染任务观察实际并行度才能确认。
- 真实 interface 导出中符号树大小的分布未知，因此整体影响落在 1.14x–2.28x 之间的何处没有数据。

### 修法

`StackSafeExecutor.withLargeStack` 包住批量渲染入口即可消除，实测有效（对照组即是）。上游该函数的文档注释也正是这么规定的："Use this at a batch boundary — indexing every symbol of a binary, say — so the whole batch pays for at most one thread hop instead of one per call." 仓库内目前**零处**使用。

同时 `printSemantic` 上的文档注释断言 `print(_:options:)` "runs the recursion inline against a stack floor and pays for a worker only for a tree that actually reaches it"，与实测相反，应一并修正。

> 探针为一次性测量代码，测完已删除。若需长期守护该性质，应整理为正式 benchmark。

## 三、待处理清单

按建议优先级排列。标注 ⚠️ 的是本轮新发现（既有台账中没有）。

### 性能

1. **build sweep 由并行改为串行，且每符号无条件跨线程往返**（`SymbolIndexStore.swift:431`）。原为 `symbolArray.concurrentMap`，现为单趟顺序循环，且每个符号额外付一次线程池提交 + 信号量等待，无并行摊薄。大框架（SwiftUI 数十万符号）首次打开慢数倍。**影响最大的一条。**
   - 注：既有台账第 6 条描述此问题时称"不是打印路径用的 `executeWithinStackBudget`"，但**该入口在当前上游版本中并不存在**，且第二节已实测证明打印路径同样每次跳转。该前提需要更正。

2. **打印路径每次调用跨线程 + 阻塞**（`Node+.swift:78`）。见第二节。注意原建议的"恢复内联调用"**已不可行**——上游把 `NodePrinter<Target>` 改成了空 enum（无构造器），`print(_:options:)` 是唯一公开走法。

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

## 四、明确判定为"无需处理"

- **`Package.swift` 将 swift-demangling 指向 `branch: "feature/node-store"`**。审查将其报为阻断合并的缺陷（下游按版本依赖会解析失败、构建不可复现）。经确认这是**开发期的预期状态**——本库与其 demangling 依赖正在同步迁移，合并时会换回 `from:` 版本要求，期间接受上述代价。不作为问题跟踪。

## 五、与既有台账的对照

| 本文条目 | `NodeStoreMigrationOpenIssues.md` | 关系 |
| --- | --- | --- |
| 一.1（`write` witness） | — | 本轮新发现，已闭环 |
| 一.2（`Codable`） | — | 本轮新发现，已闭环 |
| 二 / 三.2（打印路径跳转） | — | 本轮新发现，附实测；同时更正台账第 6 条的 `executeWithinStackBudget` 前提 |
| 三.1 | 第 6 条 | 同一问题 |
| 三.3、三.5、三.6、三.7 | — | 本轮新发现 |
| 三.4 | 第 9 条 | 同一问题 |
| 三.8 | 第 4 条 | 同一问题 |
| 三.9 | 第 7 条 | 同一问题 |
| 内存 10 | — | 本轮新发现 |
| API 11 | — | 本轮新发现（台账第 8 条只覆盖 `isExternal` 死代码，未覆盖公开成员删除） |
| API 12 | 第 8 条 | 同一问题 |
| API 13 | 第 3 条 | 同一问题，本轮补充了严重性复核 |
| 测试 14 | — | 本轮新发现 |
| 文档 15 | 第 12 条 | 指出该条前提已过期 |
| 卫生 16、17 | 第 10、11 条 | 同一问题 |

### 结论冲突（需要人工裁定）

既有台账**第 5 条**称 `memberSymbols(of:for:node:)` "从 O(1) 退化成线性扫描 + 逐候选全树比对"。本轮有 4 条同类候选指向该位置，**全部被 verifier 证伪**——理由是"原本是一次哈希查找"这一前提与代码不符，且所称的倍数不存在。两方结论直接冲突，本文不作判断，需要人工核对后决定保留哪一方。

（本轮其余被证伪的 3 条均为风格类：`DefinitionBuilder` 重复构造 key、两处多余 `throws`、`StructuralNodeReferenceKey` 的模块归属。其中后两条与台账第 11 条、既有讨论重合，故仍列在本文第三节。）
