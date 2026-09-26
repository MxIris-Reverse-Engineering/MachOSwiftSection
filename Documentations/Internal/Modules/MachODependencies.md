# MachODependencies 模块

> 模块参考文档（module reference），随代码维护。读者：维护者。
> 提案：[0017-macho-dependencies-module](../../Evolutions/0017-macho-dependencies-module.md)。

## 模块定位

MachODependencies 回答一个问题：**一个二进制链接了哪些镜像，去哪里把它们找出来。** 它只读 `LC_LOAD_DYLIB` 家族的 load command，不碰 Swift metadata，因此和 `MachOCaches` / `MachOReading` 一样位于 MachO* 基础层，由 `MachOFoundation` 统一 re-export——凡是 `import MachOSwiftSection` 的模块都直接可用，不必再加 import。

它取代了两套各自为政的实现：`SwiftLayout` 里文件私有的传递闭包（BFS + bare name 去重 + cache 一次性索引），和 `SwiftInterface` 里绑定在 `SwiftInterfaceBuilderDependencies` 上的一层直接依赖加载（按 install path 精确匹配）。两处现在都是薄包装，各自的语义保持不变：静态布局要传递闭包，`__C` 类型归属只要直接依赖。

下游消费者：`SwiftLayout.ImageUniverse`（三个 `dependencyClosure` 工厂）、`SwiftInterface.SwiftInterfaceBuilderDependencies`（供 TypeIndexing）、`swift-section interface --resolve-c-module-names`、`SwiftIndexing.SwiftDeclarationIndexer`（一个 `SharedDependencyClosure` 同时喂 property-wrapper catalog 与 `SwiftInspection.ObjCAncestorResolver`——独立文件的 ObjC 祖先链，提案 `objc-ancestor-dependency-closure`）。

## 文件 → 子系统对照

| 子系统 | 文件 |
|---|---|
| 1. 搜索路径与失败记录 | `DependencySearchPath`（含 `DependencySearchPathError` / `DependencySearchPathLoadFailure`） |
| 2. load name 归一 | `DependencyLoadName` |
| 3. 定位器 | `DependencyLocating`（协议 + `InProcessDependencyLocator`）、`FileDependencyLocator`、`DependencyPlatforms`（平台守卫） |
| 4. 闭包遍历 | `DependencyClosure`（含 `DependencyTraversal`）、`SharedDependencyClosure`（一次求值多方共享） |

## 1. 搜索路径

`DependencySearchPath` 四种：显式 Mach-O 文件、显式 dyld shared cache 文件、宿主系统的 cache、**system root**（`.systemRoot(path:)`，2026-09-13 提案 `standalone-file-thunk-resolution` 加入）。system root 是一棵目录树，绝对 install name 直接拼在它下面找文件——iOS 26 及更早的模拟器运行时把系统框架当文件放在 `RuntimeRoot` 里，就是这个形状；`@rpath/…` 这类相对名字永远不在 root 下找。定位器对 system root 不预扫描，第一次问到某个 load name 时才打开对应文件、按根镜像的架构挑切片、记住结果；不是目录的 root 记为 `systemRootIsNotADirectory` 失败。

两个便利入口：`DependencySearchPath.inferred(forRoot:)` 从根文件在磁盘上的位置推断搜索路径——沿祖先目录向上找带 `System/Library/Caches/com.apple.dyld/`（iOS 家族与 iOS 27+ 模拟器：`dyld_sim_shared_cache_arm64`）或 `System/Library/dyld/`（macOS）且里面有本架构主 cache 文件的目录，命中即给 `.dyldSharedCache`；没有再看根文件路径是否以自己的 install name 结尾，是就把前缀当 `.systemRoot`；文件系统根目录本身永远不算（宿主 cache 归 `.systemDyldSharedCache`）。`DependencySearchPath(classifyingPath:)` 按形状归类一个用户给的路径：目录 → system root，主 cache 文件名（`dyld_shared_cache_*` / `dyld_sim_shared_cache_*`，不含 `.01` / `.map` 等后缀）→ cache，其余 → Mach-O 文件；`swift-section` 的 `--dependency-search-path` 用它。**`@rpath` / `@loader_path` / `@executable_path` 不展开**——一个不在 cache 里的依赖（sibling framework、测试 helper）必须由调用方以 `.machOFile(path:)` 显式给出。这是从 SwiftLayout 阶段 3 继承的 MVP 边界，未变。

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

  **平台守卫**（2026-09-21，提案 `objc-ancestor-dependency-closure`）：宿主的 macOS cache 是每个 root 的默认搜索路径，而它在 `/System/iOSSupport` 下带着 Catalyst 版的 UIKit / SwiftUI——iOS root 链的 `/System/Library/Frameworks/UIKit.framework/UIKit` 没有精确匹配，裸名兜底又没有原生版可以压过它，于是拿到的是同名类、不同平台的镜像（ObjC 祖先的 selector 集合、instance size 都是另一个平台的）。定位器构造时接收 root 的平台集合（`DependencyPlatforms.platforms(of:)`：全部 `LC_BUILD_VERSION` 的平台，zippered 镜像两个；没有则按 `LC_VERSION_MIN_*` 推；空集合放行），一次性建 cache 索引时把集合不相交的镜像直接跳过——精确路径与裸名两步一起受约束（`/usr/lib/libobjc.A.dylib` 这种两边都精确匹配的也拒）。显式文件与 system root 是调用方自己给的，不过滤。被拒的 load name 落进闭包的 `unresolvedLoadNames`，没有另起通道。`DependencyClosure(root: MachOFile, …)` 自动传 root 的平台（`FileDependencyLocatorTests.cacheImagesOfAnotherPlatformAreNotCandidates` 锁定）。副作用：iOS 二进制在 macOS 宿主上不带搜索路径时，布局引擎与 `__C` 归属也不再拿到 Catalyst 镜像——诚实降级，给 `--dependency-search-path <RuntimeRoot>` 即恢复。

  fat 显式文件取与 root 同架构的 slice（`preferredCPU`：先比 `cpu.type` + 掩掉 capability 位后的 `cpu.subtype`，能分开 arm64 / arm64e；再只比 type；最后 `.first`——旧两处实现都无条件取 `.first`）。注意 MachOKit 的 `CPU ==` 比的是原始值，versioned-ABI 的 arm64e 切片会和普通 arm64e 判不等，所以不能直接比 `header.cpu`。

## 4. 闭包遍历（`DependencyClosure`）

`DependencyClosure(root:traversal:locator:)` 是唯一的遍历实现，两个便利初始化器只是选定位器：`init(root: MachOImage, traversal:)` 与 `init(root: MachOFile, searchPaths:, traversal:)`。

- **`.direct`** 只走 root 自己的 load command；**`.transitive`** BFS 递归。
- **顺序是契约的一部分**：direct 为 load command 顺序，transitive 为 BFS（root 的直接依赖全部在前）。`SwiftLayout.ImageUniverse` 按这个顺序惰性索引依赖、命中即停；DFS 会把 Foundation 整棵子树排在 root 的第二个 Swift 依赖前面（`DependencyClosureTests.inProcessTransitiveClosureExtendsTheDirectPrefixBreadthFirst` 锁定 direct 是 transitive 的前缀）。
- 按 bare name 去重，root 自身排除（以 root 的 `imagePath` 归一后预置进 visited 集合）；**再按镜像身份去重**（`MachORepresentableWithCache.identifier`，文件是 `LC_UUID` 键）——文件定位器把一个显式文件登记在磁盘路径、install name、bare name 三种拼法下，root 若以两个 load name 链到同一个二进制，只按 bare name 去重会把它收两次（`sameImageReachedUnderTwoLoadNamesIsCollectedOnce` 锁定）。
- 定位不到的 load name 进 `unresolvedLoadNames`（按遇到顺序，同样按 bare name 去重），遍历继续。`images` 与 `unresolvedLoadNames` 恰好是 root 直接依赖的二分（direct 模式下，`DependencyClosureTests.inProcessDirectClosureResolvesMappedDependencies` 锁定）。

**`SharedDependencyClosure<MachO>`**（2026-09-21）：包一个 `() -> DependencyClosure` 的求值，首次读 `closure` 时求值一次、锁保护、之后直接返回。给同一个 root 的多个惰性消费者用——indexer 里 property-wrapper catalog 与 ObjC 祖先解析器各自都在第一次跨镜像查询时才要闭包，各自建就是各自把搜索路径里的 cache 整扫一遍。求值闭包里可以顺手派发 `searchPathLoadFailures`（indexer 就是这么做的），本模块自己仍不派发。

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
- `Tests/MachODependenciesTests/FileDependencyLocatorTests.swift` — 宿主 cache 上的精确路径优先与 Catalyst 降级（无宿主 cache 时跳过）；平台守卫（`LC_BUILD_VERSION` 读取、`areCompatible` 规则、iOSSimulator root 在宿主 cache 上一无所获、zippered root 可取 Catalyst 镜像）。
- `Tests/SwiftInterfaceTests/ObjCMemberRecoveryTests.swift` — 端到端：独立文件的 ObjC 祖先链经闭包走到 libobjc 的 `NSObject`。
- `Tests/SwiftInterfaceTests/SwiftInterfaceBuilderDependenciesTests.swift` — 薄包装的 direct 语义、image 版非空回归、`init(closure:)` 保留调用方遍历。
- `Tests/SwiftLayoutTests/DependencyClosureLayoutTests.swift` — 端到端：闭包驱动的跨模块字段偏移（未改动）。

## 已知边界

- `@rpath` 等不展开（见 §1）。
- 依赖种类不过滤：load / weak / reexport / upward / lazy 全收。
- cache 的 bare name 兜底对多点 leaf 名（`libc++.1.dylib`）只能给最差 rank。
- 平台守卫只看 cache 镜像；一个 x86_64 时代的模拟器 root 只有 `LC_VERSION_MIN_IPHONEOS`，推成 `.iOS`，会与真机 cache 相容——历史格式的边角，未处理。
- `MachODependenciesTests` 不在 CI 的 filter 子集里，只在本地全量跑。

## 相关文档

- [StaticLayoutDependencyClosure.md](../StaticLayoutDependencyClosure.md) — SwiftLayout 阶段 3 的原始设计与「落地实测」（惰性索引、BFS、一次性 cache 索引等结论的出处）。
- [TypeIndexingPipeline.md](../TypeIndexingPipeline.md) — 直接依赖清单在 `__C` 归属管线里的用法。
