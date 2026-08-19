# 2026-08-03 PR #97 审查发现逐条裁决

## 问题

2026-08-02 对 PR #97（`feature/node-store-migration`）跑了一轮 `/code-review max`，产出 15 条发现 + 3 条被输出条数挤出但同样确认为真的条目。需要按项目约定对每一条作出判断（能否复现 / `main` 是否也有 / 值不值得修 / 以前是否修过），而不是只把清单转交出去。

## 调研

### 一、先查既有裁决记录（本次最大的教训）

本轮开局没有先对照既有记录，直接按审查报告的排序向维护者汇报，导致两条结论出错：

1. **`Package.swift` 钉在上游分支**被报为"合并阻塞"，而 `Reviews/2026-07-31-node-store-migration-review.md` 第五节早已把它裁决为"开发期的预期状态，合并时换回 `from:` 即可，不作为问题跟踪"。
2. **`memberSymbols` 线性扫描**被我判定为"四条性能问题里唯一白丢的一条、`main` 是干净的 O(1)"，而同一份记录的第六节已就该位置作出带实测的相反裁定。

项目 `CLAUDE.md` 明确要求"每次 code-review 先对照已裁决清单"，本轮违反了这条。

### 二、逐条核实

| 核实项 | 方法 | 结果 |
| --- | --- | --- |
| 上游 `0.5.0` 是否存在且含 NodeStore | `git ls-tree 0.5.0 -- Sources/Demangling/Store/` | 存在，6 个文件齐全 |
| `0.5.0` 与 `main` 的关系 | `git rev-list -n1 0.5.0` vs `git rev-parse main` | 同一提交 `caacfb9`，`0.5.0..main` 为空 |
| 打印深度是否仍是 512 | `git grep maxPrintDepth 0.5.0` | **已恢复 768**，并附禁止再降的注释 |
| `structuralHash` 是否已修 | 读 `0.5.0` 的 `structuralDigest()` / `nodeContents` | 已改为迭代 + 记忆化，但 `String` 分配**仍在** |
| `demangleAsNodeTransient` 执行器 | `grep -A8` `DemangleInterface.swift` | 仍是 `StackSafeExecutor.execute`，**未修** |
| `main` 的 `Node.hash` 是否结构性 | 读 `0.4.5` 的 `Node+Hashable.swift` | `hasher.combine(children)` 递归——**哈希一次走完整棵树** |
| `main` 的 `memberSymbols` 实现 | `git show main:…SymbolIndexStore.swift` | `memberSymbolsByKind[$0]?[name]?[node]` |
| `main` 的 `buildStorage` 形态 | 同上 | `concurrentMap`，无 `withLargeStack` |
| `main` 的 `ABIKey.make` | `git show main:…ABIKey.swift` | 直接 `mangleAsString(node)`，无 materialize |
| 索引器是否丢了 `await` | `main:659` vs 分支 `:685` | `await node.print` → 同步 `node.print`，**确认** |
| `distributedFunctionNodes` 求值次数 | `grep` `ClassDumper.swift` | `:77` 计算属性，`:101` / `:192` 各求值一次，**确认** |
| `interning` 站点数 | `grep -rn "NodeReference(interning:"` | **26 处**（审查报告称 22，偏低） |
| `SymbolIndexStore` 是否类型级 SPI | 读 `SymbolIndexStore.swift:13-14` | `@_spi(ForSymbolViewer)` + `@_spi(Internals)`，**是** |
| 两个公开查询 API 的包内调用点 | `grep` `Sources/` `Tests/` | `excluding:` 重载唯一调用点只遍历；`allOpaqueTypeDescriptorSymbols` **零调用点** |
| `Symbol` 是否还有 `.nlist` 引用 | `grep -rn "\.nlist"` | 包内已无；`isExternal` 公开且带默认值 |
| 分支落后 `main` 多少 | `git rev-list --left-right --count` | 领先 27 / 落后 2，两个提交只动 workflows |
| 演进日志撞号与死链 | `grep "^## [0-9]"` + `ls TaskReports/` | 两个 `## 20.`、348 行死链，**均仍在** |

## 最终方案

1. 改一行依赖：`branch: "feature/node-store"` → `from: "0.5.0"`。这是既有裁决里"合并时该做的事"，因上游发版而变得可做。
2. 打印深度一条随之自动关闭（上游已修），不在本仓库改任何代码。
3. 两条由维护者裁决为"不修"的（`Symbol` 删公开成员、公开查询 API 键语义）就地留档，不删除条目，便于后续审查跳过。
4. 撤回本轮自己的两条错误结论，并把纠正写进台账本体——因为台账第 5 条的措辞正是把我误导到"白丢"结论的来源，只写在审查记录里挡不住下一个人。
5. 其余 8 条新发现与既有清单合并，写成本轮的审查事件记录。
6. **不动代码修复**：所有待修项均未在本批次动手，等维护者决定顺序。
7. **不动 `ProjectEvolutionLog.md`**：撞号与死链已确认仍在，但修它属于独立的一次文档整理，不夹带进本批次。

## 实际执行

| 文件 | 改动 |
| --- | --- |
| `Package.swift` | 依赖要求由 `branch:` 改为 `from: "0.5.0"`（唯一的代码改动，1 行） |
| `Documentations/Internal/Reviews/2026-08-02-node-store-migration-pr97-review.md` | 新增。本轮审查事件记录：8 条新发现、2 条闭环、2 条裁决不修、3 条更正、与既有两份记录的对照表、待处理清单增量 |
| `Documentations/Internal/NodeStoreMigrationOpenIssues.md` | 第 3 条标记为已裁决不修并写明依据；第 4 条补上游 `0.5.0` 的核对状态；第 5 条改写措辞并就地写清"不要当回归"的两条实测依据；第 12 条拆成"已过期部分"与"仍然成立的两条"；开头补两份审查记录的链接与冲突时的取舍规则 |
| `Documentations/README.md` | 更新台账条目的描述（原描述把第 3 条列为"仍然打开"） |

## 验证

- `swift build --scratch-path /tmp/claude/SwiftPM/MachOSwiftSection-node-store`：**success**，0 errors / 2 warnings。
- 兄弟检出工作区干净且 HEAD 正是 `0.5.0` 所在提交，故上述构建等同于对 `0.5.0` 源码构建。
- **无兄弟目录的干净检出**中 `swift package resolve`：`swift-demangling resolved at 0.5.0`。这是 CI 与下游消费者实际走的解析路径，也正是钉在分支时会失败的那条。
- `git ls-remote --tags`：`0.5.0` 已推送到远端。
- `Package.swift` 中已无任何 `branch:` 形式的依赖。

## 偏差

1. **没有先查既有裁决清单**，导致两条结论出错（见「调研」第一节）。两条都在向维护者汇报之后才被发现并当场更正。这是本次最该记住的一条：`Reviews/` 与本台账都必须在动笔前读完，而不是发现冲突后再回头补。
2. **一次工具使用失误**：用非递归的 `ls Sources/Demangling/` 判断兄弟检出是否含 `NodeStore`，而该文件在 `Store/` 子目录下，于是错误地得出"主检出编不过"的结论并汇报了出去。后经 `git log` + 递归列目录更正。教训是"文件不存在"这类否定结论要用递归查找或 `git ls-tree` 坐实，不能靠一次浅层列目录。
3. **审查报告的 `interning` 站点数偏低**（报 22，实为 26）。数量级不影响结论，但记录在案以说明报告中的计数需要复核。
4. **未修任何待处理项**。本批次刻意只做裁决与留档；修复顺序待维护者决定。
