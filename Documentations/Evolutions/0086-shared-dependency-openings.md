# 0086 - 依赖定位器共享同一路径的打开，不再按根重开 cache 与显式文件

- **状态**: Implemented
- **创建日期**: 2026-11-06
- **最后更新**: 2026-11-06
- **所属愿景**: 无
- **关联提案**: 无。起因见演进账本第 122 节的后续第一条；当时不共享的理由见第 120 节；落地记在第 124 节
- **实现分支 / PR**: `feature/shared-dependency-openings`，已合进 `next`
- **配套文档**: [Modules/MachODependencies.md](../Internal/Modules/MachODependencies.md)

## 摘要

`FileDependencyLocator` 每建一个，就把搜索路径里的 dyld cache（`.dyldSharedCache(path:)`，根所在的那份与 `cachedHost` 除外）整个打开一次（`FullDyldCache(url:)`，macOS 27 是八十几个文件），把每个 `.machOFile(path:)` 文件也打开一次。定位器又是按根建的：静态布局、索引器的共享闭包、thunk 分析、ObjC 祖先、属性包装器目录、interface 依赖，最多六个使用方各建一个。打开数于是随根数成倍增长：DockHelper 配对一份归档的 macOS 27.0 cache 跑一次 `interface --emit-offset-comments`，那份 cache 的 80 个文件峰值共开着 369 个描述符，单个文件最多 7 个。RuntimeViewer 离线读一个配对非本机 cache 的 bundle 时，每个 bundle 镜像都是一个根，倍数还要再乘上去。改成同一路径在进程里只打开一次，还有人在用就复用。

## 方案

- **cache**：MachODependencies 内部加一张按路径共享打开的表。键是主 cache 文件的标准化路径加文件身份（设备号、inode、大小、修改时间；文件被换掉就开新的），值弱引用 `FullDyldCache`。定位器遇到 `.dyldSharedCache(path:)` 先查表：那份还活着（还有镜像引用它）就用它；否则开一份，先把它不加锁的懒状态读好（映射表、带滑动信息的映射表、symbol cache，与 `cachedHost` 的做法相同）再放进表。
- **显式文件**：`.machOFile(path:)` 与系统根下的文件同理，按标准化路径、文件身份和首选 CPU 共享挑好的那个 slice，弱引用。**分两步落地**：cache 这一半先做；显式文件等 MachOKit 去掉独立文件的 `cache` 探测（`fix/standalone-file-cache-probe`）发版之后再做。
- **不变的**：查找顺序与结果，`cachedHost` 与根所在 cache 的特例，`DyldCacheImageDirectory` 的数据目录；`FileDependencyLocator` 与 `DependencySearchPath` 的公开接口不变，下游不用改。
- **没问就定的假设**：
  - **弱引用，不常驻。** 定位器建完闭包就释放，缓存定位器没用，要缓存的是打开本身；常驻又会让 `evolution` 跨几十份 cache 时每份都一直开着（第 80 节常驻过 51 份宿主 cache、4,182 个文件）。
  - **共享 `MachOFile` 是安全的。** 读取走 MachOKit 的内存映射，并发读没问题；cache 里的镜像在构造时就给了 `_cache`，之后不再写懒状态。独立文件的 `cache` 探测原先会写 `_cache`，MachOKit 0.55.101（`fix/standalone-file-cache-probe`）去掉了这个探测，显式文件的共享排在它之后落地。
  - **RuntimeViewer 的目录照旧自己开配对的 cache。** 定位器之间共用一份之后，一个进程里这份 cache 最多开两次（目录一次、定位器一次），不值得为省这一次加公开 API。
- **验证**：上面那条命令，这份 cache 上同时开着的描述符 369 → 205，单个文件最多 7 → 4（MachOKit 的打开、Swift 与 ObjC 读取层的映射；预估的「3 个以内」偏少，见决策日志），输出逐字节一致；新测试：两个根各自的依赖闭包里，同一个 cache 镜像来自同一个 `FullDyldCache`，同一路径的显式文件是同一个实例；放掉全部引用后再查，会重新打开。
- **落地步骤**：
  1. ✅ cache 这一半：`SharedDyldCacheOpeningTests` 先红（两个定位器共用一份打开；六个定位器在 256 个描述符下都能定位到镜像），再在 MachODependencies 加共享打开表（`SharedDyldCacheOpenings`）、`FileDependencyLocator` 改用它；`Modules/MachODependencies.md` 与账本同批。
  2. ✅ 显式文件这一半：`SharedMachOFileOpeningTests` 先红（两个定位器各拿一个实例；300 个定位器在 256 个描述符下有的打不开文件），再加 `SharedMachOFileOpenings`，`.machOFile(path:)` 与系统根下的文件都改用它；文档同批。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-11-06 | 创建为 Draft | 修描述符耗尽时横向排查到的同类问题：依赖定位器按根重开配对的 cache 与显式文件。用户要求另起一批、先给方案 |
| 2026-11-06 | 共享表放在 MachODependencies 内部，不做成 MachOKitExtensions 的公开 API | 用户选定。不加公开接口、RuntimeViewer 不用改；配对的 cache 在一个进程里最多开两次，可以接受 |
| 2026-11-06 | cache 先做，显式文件等 MachOKit 的独立文件探测修复发版后再做 | 用户选定。cache 这一半不依赖那个修复；共享独立文件的 `MachOFile` 要等它去掉并发时会写共享状态的探测 |
| 2026-11-06 | 用户批准，开始实现 cache 这一半 | 叠在本地 `next`（0bdfd80d）上：它含描述符耗尽的修复与 MachOKit 0.55.101 / MachOKitExtensions 1.3.1，都还没推送。同日 MachOKit 0.55.101 已发，显式文件那一半的前提满足，开不开工另问用户 |
| 2026-11-06 | 同一个定位器的搜索路径里同一份打开只加一次 | 两次点名同一个 cache 文件，原先各开一份、各查一遍，结果相同；共用之后是同一个实例，查一遍即可 |
| 2026-11-06 | 实测：每个文件最多 4 个描述符，不是预估的 3 个以内 | DockHelper 配对归档的 27.0 cache 跑一次 `interface`：这份 cache 上同时开着的描述符 369 → 205，单个文件最多 7 → 4（改动前 4–7，改动后 2–4），输出逐字节一致。这次运行只建了两个定位器（静态布局、ObjC 祖先解析），改动前它们各开一份，改动后共用一份；剩下的是 MachOKit、Swift 读取层与 ObjC 读取层各自的映射。根越多，省得越多 |
| 2026-11-06 | cache 这一半实现完成，待用户看过后收尾 | 全量 2,793 个测试只红既有的 `ThunkOnlyObjCMemberTests` 4 条；分支变基到已推送的 `next` 4b08e02a 上。显式文件那一半的前提（MachOKit 0.55.101）已满足，开工另问用户 |
| 2026-11-06 | 用户同意开工显式文件这一半 | MachOKit 0.55.101 去掉了独立文件的 `cache` 探测，共享独立文件的 `MachOFile` 不再有并发写 |
| 2026-11-06 | 显式文件按文件身份加 CPU 的原始值取键；挑 slice 的规则搬进共享表；系统根下的文件一并共享 | 原始值做键，只差能力位的两个 CPU 会各开一份，只是少共享；同一个文件挑出的 slice 只取决于 CPU，所以挑 slice 放在共享表里。系统根文件与显式文件是同一种「按路径读 Mach-O」，分开处理只会留下同类问题 |
| 2026-11-06 | 显式文件这一半实现完成，待用户看过后收尾 | `MachODependenciesTests` 38 条全过；全量见账本 |
| 2026-11-06 | 落地为 0086，状态改 Implemented | 用户在 RuntimeViewer 里离线打开 Dock.app 验证通过。两步都已实现，没有后续项。不另写使用指南或实现说明：公开接口不变，没有调用方要守的新约定，设计与取舍已写进配套的 Modules/MachODependencies.md 第 3 节；没有新术语 |
