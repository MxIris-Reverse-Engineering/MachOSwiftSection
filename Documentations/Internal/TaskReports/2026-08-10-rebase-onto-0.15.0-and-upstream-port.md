# 2026-08-10 — rebase 到 0.15.0，并把分支成果移植到上游 MachOKitExtensions

## 问题

用户要求把 `feature/node-store-migration` rebase 到最新的 `main`，并删掉 PR 用的 worktree。

`main` 已经从 rebase 基点 `a8968fa5` 走到 `aa38ff50`（`release: 0.15.0`），中间四个 commit 做了两件结构性的事：

1. `6550d22d` 把整个 `Sources/MachOExtensions/`（19 个文件）抽到上游独立包 `MachOKitExtensions`，本仓库改为依赖它；抽出去的理由写在 `Package.swift` 的依赖声明注释里——本包依赖 `MachOObjCSection`，ObjC 侧无法反向依赖包内 target，否则构成包级循环，所以这层扩展必须独立成包。
2. 同一批把 `OutputTransformer` 改名为 `SwiftOutputTransformer`，其中通用部分上移到 `swift-semantic-string`。

## 调研

先把冲突面量清楚，而不是直接开 rebase：

- 分支自 merge base 起有 70 个 commit；两边改动的**文件重叠只有 5 个**：`Package.swift`、`Sources/MachOSymbols/Symbol.swift`、`Sources/MachOSymbols/SymbolIndexStore.swift`、`Sources/MachOExtensions/MachOFile+.swift`、`Sources/MachOExtensions/DyldCache+.swift`。
- 两个 `MachOSymbols` 文件上 `main` 只改了一行 import（`MachOExtensions` → `MachOKitExtensions`），属于最轻的冲突。
- 两个 `MachOExtensions` 文件是 **modify/delete**：`main` 删了整个模块，分支改了它们。
- 关键一步是**逐字节比对上游包**：拉下 `MachOKitExtensions` 的 `MachOFile+.swift`，与 merge base 的版本**完全一致**；`DyldCache+.swift` 也只差访问级（`package` → `public`）和一处 `URL` 写法。也就是说上游停在抽取当时的状态，分支上这五个 commit 的成果上游一件都没有：
  - `17ad4358` + `6647359e`：dyld cache 镜像匹配排序（跨 subcache 累积，修的是 axbundle 抢赢 framework 本体）
  - `5c74ad67`：legacy `LC_DYLD_INFO(_ONLY)` bind 支持
  - `c36a3a2e`：bind 解码器按段界 bound（PR #103 的 H3）
  - `b3bffa0d`：`isBind` 补同源回退（M4）

结论：直接按「接受 main 的删除」解冲突，会静默丢掉这五个 commit。这一点提交给用户裁决，用户选择「先移植上游再 rebase」。

顺带核了 PR #103 的 B1：上游 `swift-demangling` 确实已经打出 `0.5.1` tag，但 tag 内容里 `Sources/Demangling/Store/` 只有 `NodeStore.swift` 和 `NodeStoreBuilder.swift`，既没有 `SharedNodeStore`，`NodeStoreBuilder` 里也没有 `reserveCapacity(expectedSymbolCount:)`。**tag 号对上了，内容没跟上，B1 未解。**

## 最终方案

1. 把四块改动移植到 `MachOKitExtensions`，移植以**分支 tip 的文件状态**为准（不逐 commit 搬）——这样 rebase 时中间 commit 的 hunk 全部可以安全丢弃。
2. rebase 71 个 commit，两个 `MachOExtensions` 文件一律按 `main` 的删除解。
3. 收尾遗留引用：三处 `import MachOExtensions` 改名；两个测试 target 的依赖从 `.target(.MachOExtensions)` 换成 `.product(.MachOKitExtensions)`。
4. 同批次更新文档。

## 实际执行

**移植（上游包）**。`MachOFile+.swift` 因为与 merge base 一致，直接套用分支的完整 delta。`DyldCache+.swift` 需要两处适配：访问级 `package` → `public`；上游不依赖 `FoundationToolbox`，没有 `String.lastPathComponent` / `deletingPathExtension` 扩展，改用 Foundation 的 `URL` 惯用法取叶名，与上游既有写法一致。上游包单独 `swift build` 通过。

**rebase**。71 个 commit，7 处 modify/delete 冲突（`17ad4358`、`6647359e`、`337600ab`、`48cd362f`、`5c74ad67`、`b3bffa0d`、`c36a3a2e`），一律 `git rm`；两处一行 import 冲突取 `main` 的模块名 + 分支的 `@_spi(Internals)`。中途遇到一次瞬时 `index.lock` 冲突（外部进程持有，随即消失），`--continue` 即恢复。rebase 前建了 `backup/pre-main-rebase-2026-08-10` 作为后路，且 `origin` 上仍是 rebase 前的 `aa0a4128`。

**测试环境**。踩到三个坑，都值得记：

1. `.claude/worktrees/` 下缺 `MachOKitExtensions` 软链，本地依赖静默回落远端 `0.1.0`（不含移植）。
2. `swift-semantic-string` 的软链指向的兄弟 worktree 还没有 `OutputTransformer` product，导致 manifest 直接报错。
3. **SwiftPM 的 manifest 求值缓存**：补好软链后 `swift build` 仍然解析到远端，`workspace-state.json` 里 `machokitextensions` 一直是 `remoteSourceControl`；单独跑一次 `swift package resolve --manifest-cache none` 能翻成 `fileSystem`，但下一次不带该 flag 的 `swift test` 又翻回去。最终对每条构建/测试命令都加 `--manifest-cache none`，并用 `description.json` 里的源文件路径确认编的确实是本地包，才拿到可信结果。

**验证**。上游包 `swift build` 通过；本仓库 `swift test --skip IntegrationTests` **退出码 0，1408 tests / 264 suites 全通过**（按项目约定只认原始退出码，不认 xcsift 摘要）。

## 与方案的差异

无功能性差异。相对预估多做了一件事：`AGENTS.md` 在 `main` 上就已经因为抽包而过时（依赖图和模块列表仍写着 `MachOExtensions`，而 `main` 那批没有同步文档），分支又把 `LC_DYLD_INFO` 的说明写进了同一条目，rebase 后等于指向一个本仓库已不存在的模块。因此把该条目改写为「上游包 + 本仓库测试仍钉住的两条行为」，并顺带修正了 `StaticFieldOffsetComputation.md` / `StaticLayoutDependencyClosure.md` 里指向 `Sources/MachOExtensions/` 的失效路径。历史性文档（任务报告、review 清单、changelog、提案）保持原貌不改。

## 遗留

- 上游 `MachOKitExtensions` 的移植**尚未提交发版**：本会话的 git 操作被 worktree 隔离限制在本仓库内，无法在该仓库执行 commit / tag / push。远端仍是 `0.1.0`。
- B1 未解（`swift-demangling` 的 `0.5.1` 缺 `SharedNodeStore` 与 `reserveCapacity`）。
- 上述两条都决定了 CI 依旧不可用，本地验证只能走 `USING_LOCAL_DEPENDENCIES=1` + 兄弟目录 + `--manifest-cache none`。
- 分支已被改写历史，`origin/feature/node-store-migration` 仍指向 rebase 前的 `aa0a4128`；更新 PR #103 需要 force-push，按规程必须先走 fetch → `git cherry HEAD @{u}` → 实质 commit 检查，并由用户知情确认。
