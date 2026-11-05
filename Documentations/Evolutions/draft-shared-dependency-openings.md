# Draft - 依赖定位器共享同一路径的打开，不再按根重开 cache 与显式文件

- **状态**: Draft
- **创建日期**: 2026-11-06
- **最后更新**: 2026-11-06
- **所属愿景**: 无
- **关联提案**: 无。起因见演进账本「2026-11-06 读 dyld cache 时每个文件只映射一次」一节的后续第一条；当时不共享的理由见第 120 节
- **实现分支 / PR**: `feature/shared-dependency-openings`（未开始实现）
- **配套文档**: [Modules/MachODependencies.md](../Internal/Modules/MachODependencies.md)

## 摘要

`FileDependencyLocator` 每建一个，就把搜索路径里的 dyld cache（`.dyldSharedCache(path:)`，根所在的那份与 `cachedHost` 除外）整个打开一次（`FullDyldCache(url:)`，macOS 27 是八十几个文件），把每个 `.machOFile(path:)` 文件也打开一次。定位器又是按根建的：静态布局、索引器的共享闭包、thunk 分析、ObjC 祖先、属性包装器目录、interface 依赖，最多六个使用方各建一个。打开数于是随根数成倍增长：DockHelper 配对一份归档的 macOS 27.0 cache 跑一次 `interface --emit-offset-comments`，那份 cache 的 80 个文件峰值共开着 369 个描述符，单个文件最多 7 个。RuntimeViewer 离线读一个配对非本机 cache 的 bundle 时，每个 bundle 镜像都是一个根，倍数还要再乘上去。改成同一路径在进程里只打开一次，还有人在用就复用。

## 方案

- **cache**：MachODependencies 内部加一张按路径共享打开的表。键是主 cache 文件的标准化路径加文件身份（设备号、inode、大小、修改时间；文件被换掉就开新的），值弱引用 `FullDyldCache`。定位器遇到 `.dyldSharedCache(path:)` 先查表：那份还活着（还有镜像引用它）就用它；否则开一份，先把它不加锁的懒状态读好（映射表、带滑动信息的映射表、symbol cache，与 `cachedHost` 的做法相同）再放进表。
- **显式文件**：`.machOFile(path:)` 与系统根下的文件同理，按标准化路径、文件身份和首选 CPU 共享挑好的那个 slice，弱引用。
- **不变的**：查找顺序与结果，`cachedHost` 与根所在 cache 的特例，`DyldCacheImageDirectory` 的数据目录；`FileDependencyLocator` 与 `DependencySearchPath` 的公开接口不变，下游不用改。
- **没问就定的假设**：
  - **弱引用，不常驻。** 定位器建完闭包就释放，缓存定位器没用，要缓存的是打开本身；常驻又会让 `evolution` 跨几十份 cache 时每份都一直开着（第 80 节常驻过 51 份宿主 cache、4,182 个文件）。
  - **共享 `MachOFile` 是安全的。** 读取走 MachOKit 的内存映射，并发读没问题；cache 里的镜像在构造时就给了 `_cache`，之后不再写懒状态。独立文件的 `cache` 探测会写 `_cache`，另一个会话正在 MachOKit 的 `fix/standalone-file-cache-probe` 去掉这个探测，显式文件的共享排在它之后落地。
  - **RuntimeViewer 的目录照旧自己开配对的 cache。** 定位器之间共用一份之后，一个进程里这份 cache 最多开两次（目录一次、定位器一次），不值得为省这一次加公开 API。
- **验证**：上面那条命令，每个文件的描述符从最多 7 个降到 3 个以内（MachOKit 的打开、Swift 与 ObjC 读取层的映射各一个）；新测试：两个根各自的依赖闭包里，同一个 cache 镜像来自同一个 `FullDyldCache`，同一路径的显式文件是同一个实例；放掉全部引用后再查，会重新打开。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-11-06 | 创建为 Draft | 修描述符耗尽时横向排查到的同类问题：依赖定位器按根重开配对的 cache 与显式文件。用户要求另起一批、先给方案 |
