# 0017 - 依赖闭包下沉为 MachODependencies 模块：两套依赖加载合一

- **状态**: Implemented
- **作者**: JH
- **创建日期**: 2026-09-02
- **最后更新**: 2026-09-02
- **所属愿景**: 无
- **关联提案**: [0009-type-indexing-revival](0009-type-indexing-revival.md)（`SwiftInterfaceBuilderDependencies` 的消费者 TypeIndexing 为何只能吃直接依赖）
- **实现分支 / PR**: `feature/macho-dependencies-module`（worktree `.worktrees/MachOSwiftSection-MachODependencies`）→ `next`
- **配套文档**: [Internal/Modules/MachODependencies.md](../Internal/Modules/MachODependencies.md)（模块参考）、[Internal/TaskReports/2026-09-02-macho-dependencies-module.md](../Internal/TaskReports/2026-09-02-macho-dependencies-module.md)（任务报告）

## 摘要

仓库里目前有**两套**「找依赖二进制」的实现，互不复用、规则也不一致：

- `SwiftLayout/ImageUniverse+DependencyClosure.swift` —— **传递闭包**：BFS 递归解析每个镜像的 `LC_LOAD_DYLIB`，按 bare name 去重，dyld cache 首查时一次性建索引。搜索路径枚举 `LayoutDependencySearchPath` 是公开的，但遍历函数与 `MachOFileDependencyLocator` 都是文件私有，别的功能拿不到。
- `SwiftInterface/SwiftInterfaceBuilderDependencies.swift` + `DependencyPath.swift` —— **只取一层直接依赖**，按 install path 精确匹配 cache 镜像，供 TypeIndexing 的 `--resolve-c-module-names` 使用。绑定在接口构建器的类型上。

本提案新建底层 target **`MachODependencies`**（只依赖 MachOKit + MachOKitExtensions + Utilities，不碰 Swift metadata），把「搜索路径 → 定位器 → 遍历（直接 / 传递）→ 依赖镜像集合 + 未解析清单」抽成独立可复用的 API；上述两处消费者改为薄包装，各自语义保持（layout 传递、interface 直接）。默认输出逐字节不变。

## 方案

### 新模块 API（`Sources/MachODependencies/`）

- `DependencySearchPath`：`.machOFile(path:)` / `.dyldSharedCache(path:)` / `.systemDyldSharedCache`，沿用 SwiftLayout 的拼写。
- `DependencyLoadName.bareImageName(of:)`：load name（`@rpath/Foo.framework/Versions/A/Foo`、`/usr/lib/swift/libswiftCore.dylib`）→ bare name（`Foo`、`libswiftCore`）。规则与 MachOKit `MachOImage(name:)` 完全一致（末段路径去首个扩展名），这是与 MachOKit 的契约。
- `DependencyLocating<MachO>` 协议 + 两个实现：`InProcessDependencyLocator`（经活动 dyld，`MachOImage(name:)`，**先归一 bare name**）、`FileDependencyLocator`（显式文件 + dyld cache，cache 首查时一次性建索引，避免 `O(依赖数 × cache 大小)`）。
- `DependencyTraversal`：`.direct` / `.transitive`。
- `DependencyClosure<MachO: MachORepresentableWithCache>`：`root`、`images`（解析顺序：direct 为 load command 顺序，transitive 为 BFS；按 bare name 去重、不含 root）、`unresolvedLoadNames`、`searchPathLoadFailures`。便利构造 `init(root: MachOImage, traversal:)`、`init(root: MachOFile, searchPaths:, traversal:)`；底层 `init(root:traversal:locator:)` 供注入自定义定位器与测试。
- `MachOFoundation` 加 `@_exported import MachODependencies`（与其它 MachO* 基础 target 一致），下游模块零 import 变更即可用；同时作为独立 library product 暴露。

### 匹配规则（合并时必须二选一，取并集）

- 定位顺序：**install path 精确匹配优先**（SwiftInterface 现行规则）→ **bare name 排序匹配兜底**（SwiftLayout 现行规则，但改用 MachOKitExtensions 的 `DyldCacheImageSearchMode.matchRank`：canonical framework > 普通 dylib > bundle，`/System/iOSSupport` 下的 Catalyst 构建降级）。SwiftLayout 现行的 cache 索引是「枚举顺序首写者胜」，macOS cache 上同名 Catalyst 构建可能先被枚举到——潜在错配，合并后消除。
- fat 依赖文件取与 root 同架构的 slice，没有再退到第一个（两处现行都是无条件 `.first`）。
- 定位不到**不抛错**：记入 `unresolvedLoadNames`；搜索路径本身加载失败记入 `searchPathLoadFailures`。模块位于事件层之下，只回传数据、不落日志，由上层决定报告方式。

### 既有消费者

- **SwiftLayout**：`ImageUniverse.dependencyClosure(root:searchPaths:)` / `(root:)` 改为构造 `DependencyClosure` 再把 `images` 喂给既有的 `dependencyClosure(root:dependencyImages:)`；`ImageUniverse` 本身（惰性索引、五个 resolve seam）**不动**。`LayoutDependencySearchPath` 保留为 deprecated typealias。
- **SwiftDeclarationRendering**：`StaticLayoutDependencyResolution.dependencyClosure(searchPaths:)` 关联值换成 `[DependencySearchPath]`（typealias 保证源码兼容）。
- **SwiftInterface**：`SwiftInterfaceBuilderDependencies` 变薄包装——新增 `init(machO:searchPaths:eventHandlers:)` 与 `init(closure:)`，旧 `init(machO:paths:eventHandlers:)` 与 `DependencyPath` 标 deprecated 并转发；`searchPathLoadFailures` 继续派发 `renderingDegraded(.dependencyLoad)` 事件；新增 `unresolvedLoadNames` 透出。**保持只取直接依赖**——TypeIndexing 按依赖清单逐模块生成 SourceKit 接口，换成传递闭包就退回提案 0009 之前「全 SDK 生成」的开销。`MachOImage` 版改走 `DependencyClosure(root:traversal: .direct)`，顺带修一个静默 bug：现行把完整 load path 喂给按 bare name 匹配的 `MachOImage(name:)`，结果永远解析为空（MachOKit `Dylib.name` 是 "library's path name"，`MachOImage(name:)` 比较的是末段去扩展名）。仓库内与下游（RuntimeViewer / MachOKitUI / SymbolViewer）均无该 init 的调用方。
- **CLI** `interface --resolve-c-module-names`：改用新 init；「resolved no dependency images」警告改为按 `unresolvedLoadNames` 精确提示。

### 测试

- 新 `MachODependenciesTests`：bare name 归一；in-process direct（含 `SymbolTestsHelper` 命中——即上述 bug 的回归测试）与 transitive（direct ⊂ transitive、BFS 前缀、去重）；offline 显式路径 + 系统 cache；无搜索路径时全部进 `unresolvedLoadNames`；坏路径进 `searchPathLoadFailures` 且不抛；host cache 上 install path 精确优先与 `iOSSupport` 降级。
- 既有 `SwiftLayoutTests.DependencyClosureLayoutTests` 作端到端锚点不动；`SwiftInterfaceTests` 加 direct 语义与 image 版非空的锚点。
- 验证：`swift build`、相关 filter 套件、全量（跳 IntegrationTests）；渲染 A/B（默认输出不经闭包——`SwiftDeclarationPrinter` 只在 `--emit-field-offsets` 等布局注释开启时才构建 provider）+ 手工对一个系统框架跑 `dump --emit-field-offsets` 前后 diff。

### 文档

新 `Internal/Modules/MachODependencies.md`（模块参考：定位规则、一次性 cache 索引、BFS 顺序为何对惰性消费者重要、install name ≠ 磁盘路径、`MachOImage(name:)` 的 bare name 契约）；`Modules/README.md` 与 `Documentations/README.md` 登记；AGENTS.md 模块图与条目；`StaticLayoutDependencyClosure.md` 加迁移指引；Glossary 登记「依赖闭包」「bare name」；ProjectEvolutionLog 落地时加节；任务报告。不动 Changelog（不升版本）。

### 未问而定的假设

1. 模块名 `MachODependencies`、类型名如上；产品同时作为独立 library 暴露。
2. deprecated 过渡保留一个版本再删（无下游使用者，成本极低）。
3. 依赖种类不过滤（load / weak / reexport / upward / lazy 全收，与现行一致）。
4. `@rpath` / `@loader_path` / `@executable_path` 仍不展开（与现行一致，列为后续）。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-09-02 | Created as Draft | 用户：「把目前的依赖闭包抽出来，方便给其他功能使用」 |
| 2026-09-02 | 两套实现合并；落点为本仓库新 target `MachODependencies` | 用户在澄清一轮中选定（备选：只抽 SwiftLayout 一套；放 sibling 包 MachOKitExtensions） |
| 2026-09-02 | SwiftInterface 保持只取直接依赖 | TypeIndexing 的接口生成成本随依赖清单线性增长（提案 0009） |
| 2026-09-02 | 匹配规则取并集：精确路径优先、bare name 排序兜底 | 修 Catalyst 同名错配，两侧现行行为都是新规则的子集 |
| 2026-09-02 | 走轻量档 | 无破坏性 API（旧名 deprecated 转发），用户未要求升档 |
| 2026-09-02 | Draft → Accepted | 用户批准（「开个worktree开工」），提案 0016 已落地，本案落地时编号取 0017 |
| 2026-09-02 | `SwiftInterface` 只透出 `unresolvedLoadNames`，不新增事件 case | `Payload.unhandledFailureDescription` 是有意的穷举 switch，加 case 要动 `SwiftDeclaration`；CLI 自己打 warning 已够用 |
| 2026-09-02 | Accepted → Implemented | 26 定向测试 + 全量 1612 测试（仅 2 个已知 flaky 并发用例，单独跑通过）全绿；带布局注释的 dump / interface 对 SwiftUI / SwiftUICore / SwiftData / Combine 双侧逐字节一致；同依赖版本下耗时持平。配套文档：模块参考 `Modules/MachODependencies.md`；术语「bare image name」「dependency closure」已登记 Glossary。落地 `next` 时取号（0016 已占，预计 0017）并在同一 commit 改名 |
| 2026-09-02 | 落地 `next` 取号 0017 | 远程共享分支 `Evolutions/` 最大号为 0016（`origin/next`），+1；文件改名与全部互链同批（PR 分支上完成） |
