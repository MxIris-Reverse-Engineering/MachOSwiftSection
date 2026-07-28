# 2026-07-28 代码审查结论复核与修复

## 问题

对 PR #97（`feature/node-store-migration`）跑了一轮多角度代码审查，产出 15 条"已验证"结论。其中相当一部分围绕栈安全展开，指控本分支把上游的栈保护弄丢了、把非阻塞调用换成了阻塞调用。这些结论的严重性排序直接决定要改什么，因此在动手前先逐条复核证据。

## 调研

### 关键发现：审查基于错误的上游分支

审查假定的上游是 `swift-demangling` 的 `main`。实际链接的是：

```
node-store-migration/.claude/worktrees/swift-demangling
  -> swift-demangling/.claude/worktrees/symbol-store   # perf/stack-safe-executor-reuse (c928554)
```

`perf/stack-safe-executor-reuse` 相对 `main` 多了三个提交，恰好推翻了审查的成本模型：

- `ea4101b` 引入 `LargeStackThreadPool`：大栈 worker 长期复用、空闲 30 秒退休。审查反复出现的"每次调用 spawn 一条 8 MB 栈 Thread"从此不成立。
- `ea4101b` / `ac30584` 引入 `StackSafeExecutor.executeWithinStackBudget`：在小栈线程上**内联**跑递归并对照栈地板，只有真正触底才回退到 worker。
- `c928554` 把栈安全下沉进打印器引擎（`DemanglingPrinter.print(_:options:)` 静态入口），提交信息里**点名** MachOSwiftSection 的 `printSemantic` 是当初漏掉保护的调用点。

### 与 `feature/stack-budget-guard` 的关系

用户指向的 `feature/stack-budget-guard`（6fa6d95）与 `perf/stack-safe-executor-reuse` **互不为祖先**，共同基点是 `ea2ec28`。两者是同一问题的两套设计：

| | `perf/stack-safe-executor-reuse` | `feature/stack-budget-guard` |
| --- | --- | --- |
| 线程池 | 有 | 有（且能识别自身 worker） |
| `executeWithinStackBudget` | 有 | **无** |
| `DemanglingPrinter.print` 静态入口 | 有 | **无** |
| `StackBudget`（按剩余栈字节限深，替换 MaxDepth 常量） | 无 | 有 |
| `materializeNode` 迭代化 | 无（递归） | **有**（显式栈） |

`git merge-tree` 显示两者在 `StackSafeExecutor.swift`、`NodePrinter.swift`、`Remangler.swift` 三个文件上正面冲突。因此"把依赖切到 `feature/stack-budget-guard`"不是换个符号链接的事，需要上游先合并两条线。

### 逐条复核结论

| 审查结论 | 复核结果 |
| --- | --- |
| `await node.print` → `node.print` 是退化 | **伪阳性，方向相反**。同步 `print` 现在走 `executeWithinStackBudget`，典型输入内联执行；异步 `print` 在小栈上无条件走线程池 + continuation。去掉 `await` 减少了一整轮派发 |
| "每次 spawn 一条 8 MB 线程" | **错**。线程池复用，真实代价是提交 + 信号量阻塞 |
| `printSemantic` 包 `StackSafeExecutor.execute` | **成立但理由要改**。加回保护是对的（上游提交信息证实原先确实没有保护），错在用了钝的 `execute` 而非引擎自带的预算入口 |
| `lateDemangledNode` 持锁 demangle | **结构成立、代价高估**。`os_unfair_lock` 期间确有 `semaphore.wait()`，但线程复用后开销小得多，且注释写明这是刻意的原子性权衡（防止同一名字分裂到两个 mini store）。降为低优先级 |
| impl-offset 回退表只填 `methodDescriptors` | **成立但是旧账**。逐行比对 `main`，完全一致，非本 PR 引入 |
| 公开查询 API 字典键语义从结构相等翻成身份相等 | **成立但无现实触发者**。扫过 RuntimeViewer 的 `main` 与 `feature/node-store-adoption`，两条分支都没有调用这两个 API |
| `intern` 递归脱离栈保护 | **成立**。`main` 的 `demangleAsNode` 把 `NodeCache.shared.intern` 包在 `execute` 内，`demangleAsNodeTransient` + `builder.intern` 则在调用者栈上裸递归。注意上游 `NodeStoreBuilder.demangle` 自身就是这个形状。两条分支的 `StackBudget` 都没覆盖它 |
| `materialize` 无栈保护 | **成立，且 `feature/stack-budget-guard` 已修**（改成显式栈遍历） |
| Catalyst 平局 | **成立，已实测**。`/System/iOSSupport/System/Library/Frameworks/SwiftUI.framework` 存在，两棵框架树下 74 个同名框架 |

## 最终方案

只改三处，其余按上表分类处理（伪阳性丢弃、旧账另计、`intern` 栈保护交上游）。

1. **`printSemantic` 换用引擎预算入口** —— `DemanglingPrinter<SemanticString, Self>.print(self, options:)` 取代 `StackSafeExecutor.execute { printer.printRoot(self) }`。保护不减，但小栈线程上不再每次派发加阻塞。
2. **`registerRow` 按桶去重** —— 原守卫只挡 `canonicalOffset == rawOffset`，挡不住"两个同名符号落在同一地址折叠到同一行"。改成检查目标桶是否已含该行。
3. **dyld 缓存镜像选择** —— 三件事一起改：
   - `matchRank` 拆分 0 级：`/System/iOSSupport` 下的 Catalyst 变体降到 1 级，dylib 与其他各自后移一位。只有原生框架能拿 `bestMatchRank`，而拿到该级才允许提前退出。
   - 子缓存列表改读 `mainCache.subCaches`（子缓存头的该数组恒为空，直接打开子缓存时兄弟一个都扫不到）。
   - 用 `scannedCacheURLs` 去重：`mainCache` 在自身即主缓存时返回 `self`，原先会把主缓存整个扫两遍。

## 实际执行

- `Sources/SwiftDeclarationRendering/Extensions/Node+.swift` —— 换入口，文档注释改写为解释"为什么不是 `StackSafeExecutor.execute`"。
- `Sources/MachOSymbols/SymbolIndexStore.swift` —— 新增 `appendRowIfAbsent(_:atOffset:)`，`registerRow` 改为两次调用它；注释补齐重复的两个独立成因。
- `Sources/MachOExtensions/DyldCache+.swift` —— 新增 `catalystSupportRootDirectoryName`（声明为 `Substring`，与 split 出来的路径分量同类型，避免逐次桥接），`matchRank` 拆级，`machOFile(by:)` 加 `scanReachedBestMatch(in:)` 局部函数统一去重并改读 `mainCache.subCaches`。
- `Tests/MachOCachesTests/DyldCacheImageSearchTests.swift` —— 新增三个用例：Catalyst 变体匹配但拿不到最佳级、它仍优于 dylib 与 bundle、它不会因为支持根而不再匹配。

## 验证

- `swift build`：改前基线通过（71.7s），改后通过。
- `swift test --skip IntegrationTests`：改前 1275 测试 / 146 issue，改后 1275 测试 / 146 issue，**失败测试名集合逐条一致（19 个）**。这批失败是分支既有状态，与本次改动无关。
- `swift test --filter DyldCacheImageSearchTests`：9 个用例全过（含 3 个新增）。
- `swift test --filter 'DyldCacheImageSearchTests|MachOSymbolsTests'`：23 个用例 / 3 个 Suite 全过。
- 端到端：`swift-section dump --uses-system-dyld-shared-cache -n SwiftUI` 改前改后输出逐字节一致（109387 行）。说明本机的枚举顺序原本就恰好偏向原生框架——这正是问题所在，修复把结果从"碰巧对"变成"构造上对"。

## 偏差说明

- **依赖分支未切换。** 两条上游分支互相冲突，切换会丢掉 `executeWithinStackBudget` 与静态打印入口（也就是本次第 1 项修复所依赖的东西）。需要上游先合并，本仓库无法单方面决定。
- **`intern` 递归的栈保护未处理**，按分工交上游。
- **`registerRow` 去重与子缓存遍历没有单元测试**：前者是 `buildStorageImpl` 内的局部函数，要构造带同名同址别名符号的 fixture；后者需要一份真实的分片共享缓存。两者都不是纯路径运算，无法像 `matchRank` 那样直接钉住。
- **演进日志未更新。** 分支落后 `main` 五个提交，`main` 已发布 0.14.0 并新增 `## 20.`，与本分支的 `## 20.` 撞号；此时追加小节只会加深冲突。应在 rebase 并重编号之后一并处理。
