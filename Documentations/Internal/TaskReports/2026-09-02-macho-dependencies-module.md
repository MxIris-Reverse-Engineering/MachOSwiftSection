# 2026-09-02 依赖闭包下沉为 MachODependencies 模块

## 问题

用户要求「把目前的依赖闭包抽出来，方便给其他功能使用」。现状：仓库里有两套互不复用的「找依赖二进制」实现——`SwiftLayout/ImageUniverse+DependencyClosure.swift` 的传递闭包（BFS 递归、bare name 去重、dyld cache 一次性索引；遍历函数与 `MachOFileDependencyLocator` 都是文件私有，只有 `LayoutDependencySearchPath` 公开），以及 `SwiftInterface/SwiftInterfaceBuilderDependencies.swift` + `DependencyPath.swift`（一层直接依赖、按 install path 精确匹配 cache 镜像，供 TypeIndexing 的 `--resolve-c-module-names`）。提案 [0017](../../Evolutions/0017-macho-dependencies-module.md)。

## 调研

- 两套实现的规则不一致：SwiftLayout 按 bare name（`MachOImage(name:)` 语义），cache 索引「枚举顺序首写者胜」——在 macOS cache 上同名的 Mac Catalyst 构建（`/System/iOSSupport/…/SwiftUI`）可能先被枚举到；SwiftInterface 按 `imagePath` 精确匹配，`@rpath/…` 依赖永远解析不到。MachOKitExtensions 已有 `DyldCacheImageSearchMode.matchRank(forImagePath:)`（canonical framework > dylib > bundle，support root 降级）可直接复用。
- SwiftInterface 的 `MachOImage` 版初始化器把完整 load path（MachOKit `Dylib.name` 是 "library's path name"）喂给按 bare name 比较的 `MachOImage(name:)`，从诞生起解析结果恒为空。`git log` 追到它随 `SwiftInterface` 拆分（47b5961f）一起出现，仓库内与下游（RuntimeViewer / MachOKitUI / SymbolViewer）均无调用方，所以没被发现。
- TypeIndexing 按依赖清单逐模块生成 SourceKit 接口（提案 0009 把「全 SDK 生成」改成「只生成依赖过滤选中的模块」），因此 SwiftInterface 那套**必须**保持只取直接依赖。
- 默认输出不经闭包：`SwiftDeclarationPrinter.staticFieldLayoutProvider()` 只在 `printFieldOffset` / `printTypeLayout` / `printEnumLayout` / `printExpandedFieldOffsets` 任一开启时才构建 provider；渲染 A/B 脚本的 dump / interface 不传这些 flag。
- 下游三个仓库都不用 `LayoutDependencySearchPath` / `DependencyPath` / `SwiftInterfaceBuilderDependencies`，公开 API 改名的源码兼容风险为零，但仍按库项目惯例保留 deprecated 转发一个版本。
- 本 worktree 复制了集成 worktree 的 `.package.env`，但 agent 的 shell 不读它，`USING_LOCAL_DEPENDENCIES` 实为 unset，所有构建都走远程 pin（两侧 `workspace-state.json` 均为 `remoteSourceControl`）；`.worktrees/` 下的依赖符号链接仍按 `create-worktree` skill 递归补齐（新增 `swift-objc-dump`、`FrameworkToolbox`）。

## 澄清提问（一轮两题，均选推荐项）

1. 范围：**两套合并**（共享模块同时提供 direct / transitive，SwiftInterface 改薄包装保持 direct 语义）vs 只抽 SwiftLayout 一套。
2. 落点：**本仓库新建 `MachODependencies` target**（MachOFoundation re-export）vs 放 sibling 包 MachOKitExtensions。

未问而定：模块与类型命名；匹配规则取并集（install path 精确优先、bare name 排序兜底）；fat 显式文件取 root 同架构 slice；deprecated 转发保留一个版本；依赖种类不过滤；`@rpath` 不展开。

## 实际执行

1. 新 target `Sources/MachODependencies/`（只依赖 MachOKit + MachOKitExtensions）：`DependencySearchPath`（含 `DependencySearchPathError` / `DependencySearchPathLoadFailure`）、`DependencyLoadName.bareImageName(of:)`、`DependencyLocating` + `InProcessDependencyLocator`、`FileDependencyLocator`（两级查找，cache 索引 `NSLock` 保护一次性建成）、`DependencyClosure`（`DependencyTraversal.direct / .transitive`，`images` / `unresolvedLoadNames` / `searchPathLoadFailures`）。`MachOFoundation` 加 `@_exported import`，同时作为独立 library product。
2. `SwiftLayout`：三个 `ImageUniverse.dependencyClosure` 工厂改薄包装，新增 `dependencyClosure(_ closure:)`；`LayoutDependencySearchPath` → deprecated typealias。
3. `SwiftDeclarationRendering`：`StaticLayoutDependencyResolution.dependencyClosure(searchPaths:)` 关联值换成 `[DependencySearchPath]`。
4. `SwiftInterface`：`SwiftInterfaceBuilderDependencies` 改薄包装（`init(closure:)`、`init(machO:searchPaths:eventHandlers:)`、`unresolvedLoadNames`；`searchPathLoadFailures` 继续派发 `renderingDegraded(.dependencyLoad)` 事件，subject 保持裸路径）；`DependencyPath` + 旧 init 标 deprecated 转发；`MachOImage` 版改走闭包（顺带修 bug）。
5. CLI `interface --resolve-c-module-names`：改用新 init，新增按 `unresolvedLoadNames` 逐项点名的 warning。
6. 测试：新 `Tests/MachODependenciesTests/`（三文件）、`Tests/SwiftInterfaceTests/SwiftInterfaceBuilderDependenciesTests.swift`；`IntegrationTests/TypeNameProviderTests` 改用新 init。
7. 文档：提案（轻量档三段 + 决策日志）、模块参考 `Internal/Modules/MachODependencies.md`、`Modules/README.md` 与 `Documentations/README.md` 索引、AGENTS.md（模块图 + 基础模块条目 + SwiftLayout 条目）、Glossary（「bare image name」「dependency closure」）、`StaticLayoutDependencyClosure.md` 迁移指引、演进账本第 55 节、本报告。不升版本，不动 Changelog。

## 验证

- 定向套件：`MachODependenciesTests`（3 套件 15 测试）+ `SwiftInterfaceBuilderDependenciesTests`（3）+ 既有 `DependencyClosureLayoutTests`（4）+ `FieldLayoutRendererReaderSpecializationTests`（4）——26 测试 6 套件全绿（`swift test --filter …`，退出码 0）。宿主 cache 存在，`FileDependencyLocatorTests` 的 Catalyst 精确路径分支实际执行。
- 全量（`swift test --skip IntegrationTests`）与 release 双侧输出对比：见文末「验证结果补记」。

## 与计划的偏离

- 提案写的是「`SwiftInterface` 派发 `unresolvedLoadNames` 事件」的可能性；实现只透出数据、不新增事件 case（`Payload.unhandledFailureDescription` 是有意的穷举 switch，加 case 要动 `SwiftDeclaration`），由 CLI 自己打 warning。
- `DependencyClosure` 的 `MachOFile` 便利初始化器不再 `throws`（旧 `ImageUniverse.dependencyClosure(root:searchPaths:)` 的 `throws` 其实从不抛，失败全是 `try?` 吞掉的）；`ImageUniverse` 工厂仍 `throws`，因为 root 的 `ImageReference` 构建会抛。

## 验证结果补记

- 全量 `swift test --skip IntegrationTests`：1612 测试 / 301 套件，仅 `SharedCache.resolve under Swift Concurrency` 的 `differentKeysParallelViaTaskGroup` / `differentKeysParallelViaAsyncLet` 失败——已知 flaky（用墙钟断言并行度，全量跑假失败），单独重跑两者通过。
- 带布局注释的双侧对比（release 二进制，宿主 dyld cache）：`dump --emit-field-offsets --emit-type-layout --emit-enum-layout` 与 `interface --emit-offset-comments --emit-type-layout --emit-enum-layout` 对 SwiftUI（142067 / 138936 行）、SwiftUICore、SwiftData、Combine 共 8 组输出**逐字节一致**。这是闭包真正参与的路径；默认输出不经闭包，未跑完整渲染 A/B 脚本（与 0016 的做法一致）。
- **一次差点误判的性能回归**：首轮计时候选版慢 2.5 倍（SwiftUICore 60s → 145–197s）。逐项排查：闭包内容与顺序几乎相同（604 镜像，仅 `libcrypto` / `libssl` 两个多点号 dylib 的版本选择不同），闭包构建 < 0.2s；最终发现两侧 scratch 各自新鲜解析远程 pin，候选版拿到了当天新发布的 swift-demangling **0.6.1** 与 FrameworkToolbox **0.11.0**，基线是 0.6.0 / 0.10.0。把候选版的 `Package.resolved` 换成基线的重建后，SwiftUICore 计时 51 / 52 s 对 52 / 52 s，**完全持平**。结论：回归来自上游版本（0.6.1 / 0.11.0 之一，未再二分），与本次改动无关；A/B 双侧必须共用同一份 `Package.resolved`，此教训已补进 AGENTS.md 的环境漂移条目。
- 本 worktree 的 `Package.resolved`（gitignored）现与集成 worktree 一致（swift-demangling 0.6.0 / FrameworkToolbox 0.10.0）。

