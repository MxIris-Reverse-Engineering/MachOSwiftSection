# 2026-08-06 - main 退回 0.14.1 基线，四个 SwiftLayout 修复重新接线

- **日期**: 2026-08-06
- **分支**: `rewind/main-onto-0.14.1`（基线 `3396cfd` = tag `0.14.1`），完成后重写 `main`
- **备份**: `backup/main-before-0.14.1-rewind`（分支 + 同名带日期 tag
  `backup/main-before-0.14.1-rewind-2026-08-06`），本地与 `origin` 双份，均指向重写前的
  main tip `621f6fa`
- **关联**: [ProjectEvolutionLog.md](../ProjectEvolutionLog.md) 第 30 节（回退当时记为第 26
  节，随后的 rebase 按编年把 node-store 四节移回 23–26，本节顺延为 30——见下方第 7 节）

## 1. 问题

维护者判断 PR #97（`feature/node-store-migration`，2026-08-04 合入）进 main 过早，要求：

1. main 回到 `0.14.1` 发布点；
2. **保留**合并之后落在 main 上的四个 SwiftLayout / rendering 修复；
3. node-store 的工作整体退回 feature 分支等待合适时机；
4. 全程不得丢数据。

## 2. 调研

### 历史结构

```
621f6fa  docs: record the nested field-offset cycle guard          ┐
22f093c  fix(rendering): nested field-offset cycle guard           │ 要保留的
4eeb3b4  fix(SwiftLayout): generic MPE spare-bits                  │ 四个提交
bb8ed31  fix(SwiftLayout): foreign C struct + ObjC ivar slide      ┘
7262f1d  Merge PR #97 (feature/node-store-migration)               ← 要撤销的
3396cfd  (tag: 0.14.1) build(deps): pin MachO forks to exact       ← 目标基线
```

### 关键判断：四个修复与 node-store 的耦合度

- **源码无耦合**：四个提交对 `Sources/` 的改动只落在 `SwiftLayout/`（6 文件）与
  `SwiftDeclarationRendering/`（2 文件），diff 里没有任何一处引用 node-store 引入的
  API（`NodeReference` / `demangleAsNodeTransient` / `NodeStore` / `createTransient` /
  `InternedNodeReferenceCache` / `StructuralNodeReferenceKey` /
  `detachedFromSharedTable`）。
- **唯一硬耦合在 `Package.swift`**：合并把 `swift-demangling` 的 pin 从
  `0.4.5 ..< 0.5.0` 改为 `0.5.1 ..< 0.6.0`（0.5.x 重塑 `NodePrinterTarget`、删除
  `Node: Codable`），并启用 `MachOSymbolsTests`、补了三处 target 依赖。退回基线即退回
  0.4.x 的 demangler API——这既是回退能成立的前提，也是「不能只退一半」的原因。
- **版本号无需改动**：`Version.swift` 在 `621f6fa` 与 `3396cfd` 上同为 `"0.14.1"`，
  node-store 合并从未 bump 过版本。

### 只读预演

在动任何分支前，用 `git merge-tree --write-tree`（纯内存三方合并，不碰工作区）预演了
两条路径：

```bash
# A: revert merge，保留后四个提交
git merge-tree --write-tree --merge-base=7262f1d HEAD 3396cfd
# B: 把后四个提交移植到 0.14.1
git merge-tree --write-tree --merge-base=7262f1d 3396cfd 621f6fa
```

两条路径的结论一致：**代码文件全部自动合并，唯一冲突是
`Documentations/Internal/ProjectEvolutionLog.md`**（追加式日志）。这把「会不会陷进大
规模冲突」这个最大不确定性在动手前就消掉了。

## 3. 最终方案

选 **cherry-pick 重写**（路径 B），而非 revert merge。理由：

- `git revert -m 1 <merge>` 会在历史里留下「这些改动已被处理过」的记录，将来把
  `feature/node-store-migration` 重新合回 main 时 Git **不会**再带回那些代码，必须先
  revert the revert——这是最容易踩的坑，而 node-store 明确是要回来的。
- 重写后 main 与 feature 分支之间重新有了完整 diff，重开 PR 即可，无需任何特殊处理。

数据安全靠三重保险：备份分支 + 备份 tag（本地与远程双份）+
`feature/node-store-migration` 保持在 `621f6fa` 不动。三者中任意一个存活，
node-store 的全部工作与被重写掉的 merge 提交都可完整还原。

## 4. 实际执行

1. **先备份再动手**：`backup/main-before-0.14.1-rewind` 分支与带日期 tag 建在
   `621f6fa`，`git push` 到 origin，`git ls-remote` 确认远程已收到。
2. **独立 worktree**：`git worktree add /tmp/claude/Workspace/machoswiftsection-rewind
   -b rewind/main-onto-0.14.1 3396cfd`。主检出全程不动（它被 pin 用于对比测试）。
   worktree 内没有 `.package.env`（gitignored），`USING_LOCAL_DEPENDENCIES` 因而为
   false，依赖走远端 pin——这正是需要的：本地 sibling `swift-demangling` 是 **0.5.1**，
   与 0.14.1 的代码不兼容，走本地依赖会构建失败。`swift package update` 后
   `Package.resolved` 确认解析到 **0.4.5**。
3. **四次 cherry-pick**，冲突全部集中在 `ProjectEvolutionLog.md`，且形态单一：
   cherry-pick 会把 node-store 的第 23–26 节连同目标节一起拖回来。处理方式是只留目标
   节、丢掉 node-store 四节，并把保留下来的三节顺延编号：
   - 第 27 节（SwiftLayout 普查 + foreign struct / ObjC 滑动）→ **第 23 节**
   - 第 28 节（泛型 fixed MPE spare-bits）→ **第 24 节**
   - 第 29 节（嵌套字段偏移环守卫）→ **第 25 节**
   正文内一处「第 27 节留档的硬骨头 ③」交叉引用同步改为「第 23 节」。
4. **失效元数据修正**：第 24、25 节的「对应版本」原本写作「main，`bb8ed31` 之后」/
   「main，`4eeb3b4` 之后」，这两个 SHA 在新历史里已不存在，改为不依赖 SHA 的
   「未发版（main，0.14.1 之后，紧接第 23/24 节）」。
   各 TaskReport 正文里对旧 SHA 的**历史叙述**（如「rebase 到 main（`4eeb3b4`）」）
   一律保留原貌——那是对当时事实的记录，不该改写；旧 SHA 均可通过备份分支解析。
5. **fixture 二进制重建**：`22f093c` 新增了 fixture 源码
   `RecursiveIndirectFieldLayout.swift`，worktree 内无 `DerivedData`（gitignored），
   按 AGENTS.md 的命令重建，并用 `strings` 确认新类型已编入。

## 5. 验证

- **全量构建**：`swift build`（远端 0.4.5 依赖）**0 错误 0 警告**，178.84s。这是本次
  回退最关键的一条证据——四个修复确实不依赖 node-store，源码层面的无耦合判断在编译器
  层面得到证实。
- **fixture 构建**：`SymbolTestsCore` Release 构建成功，`strings` 命中
  `RecursiveIndirectFieldLayout` / `ValueSpec`。
- **全量测试**：`swift test --skip IntegrationTests` — **1293 项测试 / 249 个套件全部通过**
  （826.76s）。四个提交各自新增的套件都在其中并通过：`ForeignStructTopLevelLayoutTests`、
  `ObjCAncestorSlideLayoutTests`、`GenericSpareBitsEnumLayoutTests`、
  `RecursiveNestedFieldOffsetTreeTests`、`RecursiveNestedFieldOffsetExpansionTests`。
  项数低于 node-store 分支上的 1304 项属预期——`MachOSymbolsTests` 等随该分支一并退出
  了 main 的测试矩阵。
- **CLI 版本**：构建产物 `swift-section --version` 输出 `0.14.1`。
- **文档链接**：四个提交涉及的全部 `.md` 内部链接扫描无死链。
- **AGENTS.md 基线核对**：新分支的 AGENTS.md 不含任何 node-store 描述（`NodeStore-backed`
  等四个特征串计数为 0），确认已回到 0.14.1 基线并叠加了 SwiftLayout 的两行更新。

## 6. 偏差与遗留

- ProjectEvolutionLog 的节号在回退期间两条历史不一致（备份分支第 27/28/29 节 = 回退后
  main 的第 23/24/25 节），这是选择重写历史的已知代价，也是唯一一处需要人工照顾的地方。
  **已于同日随 rebase 处理完毕**，见下条。
- node-store 分支带来的能力（符号索引 NodeStore 化、性能批次、旧格式 `LC_DYLD_INFO`
  bind 支持、系统框架渲染 A/B 验证流程）在回退期间不在 main 上。其中「大重构必跑 A/B
  验证」这条 AGENTS.md 规则也随之回退——它是 node-store 分支引入的。

## 7. 后续：同日把 node-store 分支 rebase 到重写后的 main 上

回退完成后，`feature/node-store-migration` 随即以

```bash
git rebase --onto main 439ecca f31711c
```

落到新 main 上。选这个区间而非 `git rebase main <branch>` 的理由：`439ecca..f31711c`
恰好是 node-store 的**纯工作线**（36 个提交、0 个 merge），四个已 cherry-pick 的
SwiftLayout 修复位于 `f31711c` **之上**，因而天然被排除——不必依赖 patch-id 去重（它们
的 `ProjectEvolutionLog.md` 部分已被改过，patch-id 本来就对不上，会误判为新提交）。

- **唯一冲突**：`Package.swift` 的 swift-demangling pin，出现在第 22/36 个提交
  （`cf368cc build: track swift-demangling's feature/node-store branch`）。取 node-store
  侧（`branch: "feature/node-store"`）以保持该提交原本的语义演进，后续的 `1234f41`
  （0.5.0）与 `2d69c63`（0.5.1）照常覆盖它，终态回到 `from: "0.5.1"`。
- **ProjectEvolutionLog 按编年恢复原样**：node-store 四节回到 23–26（工作时间
  08-02~08-03），SwiftLayout 三节回到原本的 27–29（08-04~08-06），本次回退的记录成为
  第 30 节。注意这里自动合并**不会**报冲突却会留下重复编号（两侧各有 23–26 节），是
  需要人工核对的语义问题，不是文本冲突。此后重新合入 main 不再需要重新编号。
