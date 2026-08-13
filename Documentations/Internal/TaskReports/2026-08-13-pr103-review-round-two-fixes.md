# PR #103 第二轮 review：15 条发现的四问、裁决与实现

- **日期**：2026-08-13
- **分支**：`feature/node-store-migration`（PR #103 head，基线 `aa38ff5`）
- **相关**：第一轮见 [2026-08-09-pr103-review-fix-implementation.md](2026-08-09-pr103-review-fix-implementation.md) 与 [Roadmaps/2026-08-09-pr103-review-findings.md](../../../Roadmaps/2026-08-09-pr103-review-findings.md)

---

## 问题

对 PR #103 跑第二轮 max 级 code review，产出 15 条发现。按 CLAUDE.md 的「发现必答四问」逐条查证（能否复现 / main 是否也有 / 值不值得修 / 以前修过吗），再决定修复清单。

第一轮已修/已裁决的条目（`ReviewAdjudications.md` A1–A6、`Roadmaps/2026-08-09` 的 B1/H1–H4/M1–M6/L1–L4）不重复审。

## 调研

### 四问的关键产出

四问不是形式：它推翻了初版结论中的三条，且**每一条都是靠查证而非推理翻的**。

- **F1（diff 头行被吞）定性改了**。初版说「main 上读存储属性、`try?` 恒成功，是本 PR 引入」。实际 main 的 `printTypeHeader` 本身就含 `try await typeDefinition.index(in:)` 与 `try await renderTypeDeclarationHeader(...)`，两者都会抛——初版只盯着 `for:` 参数换了什么，漏看了函数体其余的 `try`。**是基线既有缺陷**，本 PR 只是多加了一个（实践中几乎不抛的）materialization 项。
- **F7（`Symbol.nlist` 移除）破坏面比初判小**。新旧初始化器第三参都有默认值，`Symbol(offset:name:)` 两边都编译；真正破的只有显式传 `nlist:` 与读 `.nlist`。
- **F15（`cls` 缩写）撤回「新引入」的定性**。main `TypeDefinition.swift:202` 已是 `if case .class(let cls)`，PR 只换了绑定形式、沿用旧名。

另有两条经查证降级：**F2** 的竞态在当前所有已知调用方结构上都触发不到（RuntimeViewer 的 `prepare` 只调一次，`updateConfiguration` 因 `showCImportedTypes` 硬编码 false 永不进 re-prepare 分支），降为防御性；**F13** 无法构造触发场景，且 main 上分歧完全相同，记入已裁决清单。

### 四问查到的历史事实

- **F2/F5/F8** 所在的 `PerImageCacheEvictionRegistry` 本身就是第一轮 M6 的修复（代码注释里写明）。本轮发现的是 M6 修法引入的新形态：计数器可被重复注册撑住、claim 判据只覆盖三份缓存中的一份。
- **F3** 的同一函数里就有第一轮 H4 的修复注释（"a harness that cannot fail is worse than no harness"）。本轮是同一根因的第二个实例。第一轮已把「新验证工具无自检」列为三大共因之一。
- **F6** 有公开 Issue **#102**（OPEN），它正是本 PR 那 5 个新 catch 调用点的动机。Issue 作者明确提了三条建议——① 保留部分结果 ② 失败时派发事件 ③ 库不要 print 到 stdout——**本 PR 只做了 ①**。
- **F12** 由 `aeed373`（2026-05-07，早于 tag 0.14.1）引入，是已知的结构性 flaky，「至今未根治」。

### 交叉复核

把 15 条结论交给同项目的另一个会话独立复核。它的四点实质修正全部被采纳（F1 定性、F2 降级、F10 论点恢复、F5 修法保留），其中两条是我查证不足：

- **F10** 我曾因「未核实上游实现」而撤掉一个论点（无参数 kind 即使走 transient 路径也解析到进程级 `NodeFactory` 单例）。复核方在上游 `DemangleInterface.swift:56-67` 找到了白纸黑字的文档契约，**论点成立，应恢复**——且它直接影响修法：不能简单加强 `!==` 断言，否则会假失败。
- **F5** 我说「修法现成，用 `StructuralNodeReferenceKey`」说过头了。该类型只包 `NodeReference`，而查询侧是裸 `Node`，没有零成本包装。复核方还指出这处**并不违反** AGENTS.md 那条硬规则（规则禁的是「裸 `NodeReference` 做键」，此处根本没有 node 键字典）。

## 最终方案

批准清单分三批。B3（注册竞态）被 B2 的 `ObjectIdentifier` 方案吸收，不单独实现。

| 批 | 条目 | 内容 |
|---|---|---|
| A | A1 | A/B 验收脚本：双边失败但退出码不同时计入差异 |
| A | A2 | 库不再写 stdout；`printCatchedThrowing` 派发 `.definitionPrintFailed` |
| A | A3 | diff 头行渲染失败时丢弃整条声明 |
| B | B1 | opaque 查询从桶内线性扫描改为结构化哈希一次探测 |
| B | B2 | 缓存回收资格拆三位；注册改 identity-keyed（吸收 B3） |
| C | C1 | 提案 0001 兼容性一节如实描述 `nlist` 破坏 |
| C | C2 | eviction 测试采样改 `#require` + 新增非 indexer 场景用例 |
| C | C8 | F13 / `updateConfiguration` no-op 记入已裁决清单 |

## 实际执行

### 每条修复都先证明测试会红

按规矩「先写复现测试并确认修复前失败」。三处的失败实录：

- **A1**：回退脚本修复后 `exit=1`，正是 `testBothSidesFailingWithDifferentExitCodesCountsAsADifference` 与 `testDifferingExitCodesFailARunWhoseOtherPairsAreIdentical` 两条红。
- **A2**：把 helper 临时改回旧行为（`print(error)` + 不派发）后两条红，且症状与 Issue #102 报告的完全一致——`printFailureNames → []`（零事件）、stdout 捕获到 `offsetOutOfBounds`。
- **A3**：回退 `header` 修复后 `unrenderableTypeHeaderDropsTheWholeDeclaration` 红（输出多出了本该丢弃的内容）。
- **B2**：把三个 claim 临时改回全部从 symbol store 采样后，`indexerDoesNotEvictCachesItDidNotBuild` 的两条断言红（两份非 indexer 建的缓存被误清），另两条测试不受影响。

注意 A2/B2 的验证**不能**用 `git stash` 做：stash 掉实现会让调用点编译失败，那样的 `exit=1` 是编译错误而非测试失败，不构成证据。改用「临时把实现改回旧行为、保持签名可编译」。

### 横向排查

A2 确认为真后按规矩全库搜同类，另找到 **4 处** `print(error)`，全部在生成 interface 的路径上，都会污染输出：`Node+OpaqueType.swift:85`、`MultiPayloadEnumDescriptorCache.swift:48`、`SwiftInterfaceBuilderDependencies.swift:31,42`、`SwiftInterfaceBuilder.swift:98`。这几处都够深、拿不到 dispatcher，统一改写 stderr。现在 `Sources/` 下 `print(error)` 归零。

F15 的 `cls` 改成 `classWrapper`（10 处引用）。`MetadataProtocol.swift` 另有 6 处 `cls`，但该文件**完全未被本 PR 改动**，留给单独的清理提交。

## 验证

- **全量回归**：1413 个测试 / 266 个 suite / `swift test` 退出码 **0**（`--skip IntegrationTests`）。
- **A/B 脚本自测**：新增 `Scripts/test-run-rendering-ab-verification.py`，5 条，仅用标准库，`python3` 退出码 0。
- **两轮依赖 pin**：先在 `swift-demangling` `6eb3fc7` 上确认自身改动为绿，再挪到 `5d2b476` 复跑，以便出问题时能分清是自身改动还是依赖变更。

退出码一律取 `swift test` 自身的，不看任何摘要——`FULL SUITE EXIT=` 由命令显式追加进日志。

## 偏差与踩坑

### 1. 增量构建的 stale object 让「构建通过」失去意义

B1 改了 `SymbolIndexStore.Storage` 的字段结构。AGENTS.md 早就写明这类改动需要 `swift package clean` 重建，我没照做，代价是两层假象：

1. `swift build` 连续报成功；
2. 全量测试跑到 484 个用例后 **SIGSEGV**（signal 11），零断言失败。

`clean` 之后才暴露真正的编译错误：B1 把 `StructuralNodeReferenceKey.reference` 从 `NodeReference` 改成了 `NodeReference?`，破坏三个既有调用点（`DefinitionBuilder.swift:162/175`、`ProtocolDumper.swift:124`），增量构建一直在链接旧 object 所以从未报错。

**修法**：`reference` 恢复非可选，lookup-only 形态走 `preconditionFailure`。注释里写清了它与 `PackedNameReference` 的区别——后者是二进制输入驱动、必须降级不得 trap，这里是本模块自己 API 的误用防护。

**教训**：改 `MachOSymbols` 的 struct 布局后应当立刻 clean，而不是等回归报怪症状。

### 2. sibling 依赖是共享可变状态

构建中途撞上 `swift-demangling` 的 worktree 被另一个会话半改（`maxTypeSize` 未定义、`input file was modified during the build`）。没有碰对方工作区，改为建一个 detached 的只读 worktree 指向已推送的 tip，并把软链改指过去：

```bash
git -C /Volumes/Code/Personal/swift-demangling worktree add --detach /tmp/claude/pinned/swift-demangling <tip>
```

原软链目标是 `/Volumes/Code/Personal/swift-demangling/.claude/worktrees/swift-demangling`，一行命令可恢复。

### 3. 上游同期修掉了「catch 兜不住」的根因

`swift-demangling` 在 `5d2b476` 修了畸形符号导致的 SIGTRAP / 整数溢出 / 死循环（116 万条模糊语料重扫，trap 与 hang 归零）。这与 A2 是同一条线的两端：**在此之前，`printCatchedThrowing` 就算 catch 了也拦不住进程级信号**。两边合上之后 per-definition catch 才真正成立。

同期确认 `printSemantic`（`Node+.swift:87` 直接调 `DemanglingPrinter<Target, Self>.print`）**零改动**：引擎静态入口逐字节未变，`StackSafeExecutor` 保护仍在；新增的 `runPrintWalk(using:)` 写死 `Target == String`，不是它的替代路径。已把这一点连同「静态派发遮蔽」的复发形状写进该处注释。
