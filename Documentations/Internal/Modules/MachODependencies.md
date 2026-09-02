# MachODependencies 模块

> 模块参考文档（module reference），随代码维护。读者：维护者。
> 提案：[0017-macho-dependencies-module](../../Evolutions/0017-macho-dependencies-module.md)。

## 模块定位

MachODependencies 回答一个问题：**一个二进制链接了哪些镜像，去哪里把它们找出来。** 它只读 `LC_LOAD_DYLIB` 家族的 load command，不碰 Swift metadata，因此和 `MachOCaches` / `MachOReading` 一样位于 MachO* 基础层，由 `MachOFoundation` 统一 re-export——凡是 `import MachOSwiftSection` 的模块都直接可用，不必再加 import。

它取代了两套各自为政的实现：`SwiftLayout` 里文件私有的传递闭包（BFS + bare name 去重 + cache 一次性索引），和 `SwiftInterface` 里绑定在 `SwiftInterfaceBuilderDependencies` 上的一层直接依赖加载（按 install path 精确匹配）。两处现在都是薄包装，各自的语义保持不变：静态布局要传递闭包，`__C` 类型归属只要直接依赖。

下游消费者：`SwiftLayout.ImageUniverse`（三个 `dependencyClosure` 工厂）、`SwiftInterface.SwiftInterfaceBuilderDependencies`（供 TypeIndexing）、`swift-section interface --resolve-c-module-names`。

## 文件 → 子系统对照

| 子系统 | 文件 |
|---|---|
| 1. 搜索路径与失败记录 | `DependencySearchPath`（含 `DependencySearchPathError` / `DependencySearchPathLoadFailure`） |
| 2. load name 归一 | `DependencyLoadName` |
| 3. 定位器 | `DependencyLocating`（协议 + `InProcessDependencyLocator`）、`FileDependencyLocator` |
| 4. 闭包遍历 | `DependencyClosure`（含 `DependencyTraversal`） |

## 1. 搜索路径

`DependencySearchPath` 三种：显式 Mach-O 文件、显式 dyld shared cache 文件、宿主系统的 cache。**`@rpath` / `@loader_path` / `@executable_path` 不展开**——一个不在 cache 里的依赖（sibling framework、测试 helper）必须由调用方以 `.machOFile(path:)` 显式给出。这是从 SwiftLayout 阶段 3 继承的 MVP 边界，未变。

打不开的搜索路径**不抛错**，记进 `DependencySearchPathLoadFailure`（附原始 error；系统 cache 不可用时是 `systemDyldSharedCacheUnavailable`）。理由有二：一条坏路径不该让整个解析失败；本模块在事件层（`SwiftIndexEvents`）之下，无法派发事件，只能把失败当数据回传，由上层决定落点——`SwiftInterfaceBuilderDependencies` 把它们派发为 `renderingDegraded(.dependencyLoad)` 事件，CLI 经 `ConsoleEventHandler` 落到 stderr。

## 2. load name 归一（`DependencyLoadName.bareImageName(of:)`）

load name → bare image name：取末段路径、去**第一个**扩展名（`libobjc.A.dylib` → `libobjc`，`libc++.1.dylib` → `libc++`）。这条规则是**与 MachOKit 的契约**：`MachOImage(name:)` 对进程内每个镜像的路径做同样的归约再比较。把未归一的 load name（dyld 报告的都是绝对路径）直接喂给它永远匹配不到——`SwiftInterfaceBuilderDependencies` 的 `MachOImage` 版初始化器就是这么写的，从诞生起解析结果一直为空，仓库内无人调用所以没被发现（`DependencyLoadNameTests.bareImageNameIsWhatMachOImageLookupMatches` 与 `SwiftInterfaceBuilderDependenciesTests.imageInitializerResolvesTheMappedDirectDependencies` 锁定）。

bare name 同时是所有依赖集合的**去重键**：同一个库会被不同镜像以不同拼写链接（sibling 用 `@rpath/…`，系统框架用绝对路径），只有 bare name 跨拼写稳定。

## 3. 定位器

`DependencyLocating<MachO>` 只有一个方法 `locate(loadName:)`，收到的是 load command 里的**原始拼写**，归一由实现自己做。这让遍历与「镜像从哪来」解耦：进程内、磁盘搜索路径、测试里手搭的表，都是一个实现。

- **`InProcessDependencyLocator`**：归一后走 `MachOImage(name:)`。系统框架天然从 cache 解析；`@rpath` 依赖只要已映射进进程也能解析；弱链接但未映射的（如 `libswiftCoreAudio`）解析不到，进 `unresolvedLoadNames`。
- **`FileDependencyLocator`**：两步查找，顺序固定：
  1. **install path 精确匹配**——系统框架的 load name 就是 cache 镜像的 `imagePath`，命中即是编译器自己的答案。显式文件同时以「传入的磁盘路径」和「文件的 install name（`LC_ID_DYLIB`，通常 `@rpath/…`）」两种拼写登记，因为 `MachOFile.imagePath` 是 install name 而非磁盘路径。
  2. **bare name 排序兜底**——`@rpath/…` 或 cache 不认识的路径拼写落到这里。cache 里 leaf name 不唯一：macOS cache 在 `/System/iOSSupport` 下带着 Mac Catalyst 版 SwiftUI，iOS cache 有同名 `.axbundle`。候选按 MachOKitExtensions 的 `DyldCacheImageSearchMode.matchRank` 排序（canonical framework > 普通 dylib > bundle，support root 降级），取最优。**旧的 SwiftLayout 定位器是「枚举顺序首写者胜」**，在 macOS cache 上可能选中 Catalyst 构建——这是合并时消除的潜在错配（`FileDependencyLocatorTests.bareNameFallbackPrefersTheNativeCanonicalFramework` 锁定）。`matchRank` 对多点 leaf（`libc++.1.dylib`）返回 `nil`，此时记为最差 rank 但仍可解析。
  
  cache 索引**首次查询时一次性建成**（一遍 `machOFiles()`，同时建 install path 表与 bare name 最优表），之后 O(1)。逐次 `machOFile(by:)` 是 `O(依赖数 × cache 大小)` 的全扫描，阶段 3 实测 551 镜像闭包要 21 秒。`NSLock` 保护惰性索引，定位器可跨任务共享。

  fat 显式文件取与 root 同架构的 slice（`preferredCPUType`），没有再退到第一个——旧两处实现都无条件取 `.first`。

## 4. 闭包遍历（`DependencyClosure`）

`DependencyClosure(root:traversal:locator:)` 是唯一的遍历实现，两个便利初始化器只是选定位器：`init(root: MachOImage, traversal:)` 与 `init(root: MachOFile, searchPaths:, traversal:)`。

- **`.direct`** 只走 root 自己的 load command；**`.transitive`** BFS 递归。
- **顺序是契约的一部分**：direct 为 load command 顺序，transitive 为 BFS（root 的直接依赖全部在前）。`SwiftLayout.ImageUniverse` 按这个顺序惰性索引依赖、命中即停；DFS 会把 Foundation 整棵子树排在 root 的第二个 Swift 依赖前面（`DependencyClosureTests.inProcessTransitiveClosureExtendsTheDirectPrefixBreadthFirst` 锁定 direct 是 transitive 的前缀）。
- 按 bare name 去重，root 自身排除（以 root 的 `imagePath` 归一后预置进 visited 集合）。
- 定位不到的 load name 进 `unresolvedLoadNames`（按遇到顺序，同样按 bare name 去重），遍历继续。`images` 与 `unresolvedLoadNames` 恰好是 root 直接依赖的二分（direct 模式下，`DependencyClosureTests.inProcessDirectClosureResolvesMappedDependencies` 锁定）。

**为什么 SwiftInterface 保持 `.direct`**：TypeIndexing 按依赖清单逐模块生成 SourceKit 接口，成本随清单线性增长；OS 框架的传递闭包有几百个镜像，会退回提案 0009 之前「全 SDK 生成」的开销。要传递集合的宿主自己构造 `DependencyClosure(…, traversal: .transitive)` 再喂 `init(closure:)`。

## 消费入口速查

```swift
// 静态布局：传递闭包（默认）
let universe = try ImageUniverse.dependencyClosure(root: machOFile, searchPaths: [.machOFile(path: helperPath), .systemDyldSharedCache])
// 或先建闭包再共享
let closure = DependencyClosure(root: machOFile, searchPaths: [.systemDyldSharedCache])
let universe = try ImageUniverse.dependencyClosure(closure)
let providerDependencies = SwiftInterfaceBuilderDependencies(closure: closure) // 注意：这里是传递集合

// __C 归属：直接依赖
let providerDependencies = SwiftInterfaceBuilderDependencies(machO: machOFile, searchPaths: [.systemDyldSharedCache], eventHandlers: [ConsoleEventHandler()])
providerDependencies.unresolvedLoadNames // 精确报告解析不到的依赖
```

已废弃（保留一个版本）：`SwiftLayout.LayoutDependencySearchPath`（typealias）、`SwiftInterface.DependencyPath`（case 拼写不同，经 `searchPath` 转换）与 `SwiftInterfaceBuilderDependencies.init(machO:paths:eventHandlers:)`。

## 测试锚点

- `Tests/MachODependenciesTests/DependencyLoadNameTests.swift` — 归一规则表 + 与 `MachOImage(name:)` 的契约。
- `Tests/MachODependenciesTests/DependencyClosureTests.swift` — direct / transitive 语义、BFS 前缀、去重、未解析报告、坏搜索路径不抛、自定义定位器收到原始 load name。
- `Tests/MachODependenciesTests/FileDependencyLocatorTests.swift` — 宿主 cache 上的精确路径优先与 Catalyst 降级（无宿主 cache 时跳过）。
- `Tests/SwiftInterfaceTests/SwiftInterfaceBuilderDependenciesTests.swift` — 薄包装的 direct 语义、image 版非空回归、`init(closure:)` 保留调用方遍历。
- `Tests/SwiftLayoutTests/DependencyClosureLayoutTests.swift` — 端到端：闭包驱动的跨模块字段偏移（未改动）。

## 已知边界

- `@rpath` 等不展开（见 §1）。
- 依赖种类不过滤：load / weak / reexport / upward / lazy 全收。
- cache 的 bare name 兜底对多点 leaf 名（`libc++.1.dylib`）只能给最差 rank。
- `MachODependenciesTests` 不在 CI 的 filter 子集里，只在本地全量跑。

## 相关文档

- [StaticLayoutDependencyClosure.md](../StaticLayoutDependencyClosure.md) — SwiftLayout 阶段 3 的原始设计与「落地实测」（惰性索引、BFS、一次性 cache 索引等结论的出处）。
- [TypeIndexingPipeline.md](../TypeIndexingPipeline.md) — 直接依赖清单在 `__C` 归属管线里的用法。
