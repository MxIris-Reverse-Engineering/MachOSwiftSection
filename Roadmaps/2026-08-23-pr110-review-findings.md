# PR #110 review findings（TypeIndexing 重启 + 补充映射，2026-08-23）

并行 review 会话（machoswiftsection-27）对 PR #110（`feature/type-indexing-revival` → `next`）的 15 条发现，已按四问逐条核实。本表是原始清单与处置状态；「不修 / 误报」的终审条目收录进 [ReviewAdjudications.md](../Documentations/Internal/ReviewAdjudications.md)（A15 起；两线合并时因与 PR #111 的 A13/A14 撞号顺移）。

核实背景：PR 分支全套测试全绿（1466 tests / 276 suites），但 1–7 条没有一条会被当时的测试抓到——新代码测试只覆盖了纯函数部分，装配与分发路径是空白。

## 该修（7 条）

| # | 位置 | 问题 | 状态 |
|---|---|---|---|
| 1 | `Package.swift`（依赖 flag 分支） | `USE_CUSTOM_OBJC_SECTION=0` 切到 p-x9 上游后 `ObjCIndexing`/`ObjCMetadataSource` product 不存在，整包解析失败（基线 next 上该 flag 完整可用，因当时 TypeIndexing 被注释掉——本次新引入的硬回归） | **待定**（用户批复未点名；候选修法：flag=0 时条件剔除 TypeIndexing target/product + define 门控 CLI 使用点） |
| 2 | `SupplementaryAPINotes.swift`（原 `Bundle.module`） | SwiftPM 生成的 resource accessor 在 bundle 缺失时 fatalError（候选路径只有 main bundle 旁 + 编译期烧死的构建目录），`build-executable-product.sh` 只分发裸二进制 → 分发出去一用就崩 | **已解决（2026-08-23）**：按用户裁定移除整个内置资源层（「不要内置资源，让用户自己提供」），补充映射纯用户自备，resource bundle 及其分发问题结构性消失 |
| 3 | `InterfaceCommand.swift`（provider 装配） | 非 macOS 二进制的依赖按 install name 精确匹配宿主 dyld cache 基本全 miss → 功能静默不干活（只剩 APINotes 兜底），无任何提示 | **已修（2026-08-23）**：依赖解析结果为空时 fputs stderr 警告 |
| 4 | `ModuleInterfaceIndexer.swift` | submodule 生成失败 catch 后仍无条件 `cache.store(entry)`，残缺条目永久固化（缓存无完整性标记；next 旧实现的 `indexComplete` 标记在重写中丢失） | **已修（2026-08-23）**：partial entry 本轮照常返回但不写缓存；加 `InterfaceGenerator` 注入缝 + 3 条回归测试 |
| 5 | `TypeDatabase.swift` `moduleName(forImagePath:)` | 前导点名字是扩展名剥除的不动点（`.hidden` → `.hidden`），`while name.contains(".")` 死循环，100% CPU 无日志 | **已修（2026-08-23）**：不动点守卫 + `leadingDotImagePathsTerminate` 回归测试（修复前以 `swift -e` 最小复现证实 5 轮不动点） |
| 6 | `InterfaceCommand.swift`（`--supplementary-apinotes`） | 路径不存在 / YAML 解析失败只进 os_log，CLI 用户拼错路径看到一次「完全正常」的运行 | **已修（2026-08-23)**：CLI 预检（存在性 + 单文件试解析）fputs stderr 警告；目录内坏文件仍走库内 skip-and-log |
| 7 | `TypeDatabase.swift` `index()` | task group `for await` 按完成序产出 + 注册后写覆盖 → SDK searchPaths 优先序丢失，同名归属跨两次运行可不同（缓存命中改变时序） | **已修（2026-08-23）**：`entriesInDiscoveryOrder` 重排回发现序 + 回归测试 |

## 观察成立但结论修订（5 条）

| # | 位置 | 核实结论 | 状态 |
|---|---|---|---|
| 8 | `TypeDatabase.swift` Ref 剥除 | 不加 `moduleNamesByTypeName[cName] == nil` 守卫——97d9f39a 已实测双 mangling 形态并存，「剥后名存在于索引」是有意判据；且 SDK 全部 80 个 apinotes 的 6145 条目中零个以 `Ref` 结尾（review 会话实证），守卫反而有关掉 CF 剥除的风险 | **不修**（守卫），见 Adjudications A15 |
| 9 | provider 模块过滤器 | 真正漏的只有 Darwin（`libSystem.B.dylib` → `libSystem`，无 `Darwin.apinotes`）；CoreFoundation 直接依赖命中、ObjectiveC 走 APINotes 兜底 | 待办：`libobjc→ObjectiveC` / `libSystem→Darwin` 别名表，中低优先级 |
| 10 | `SDKIndexer.discover` 开销 | 量级实测约 3 万条目（review 原文 ">100k" 夸大 3 倍）、全缓存命中时 ~0.5–1.5s 固定成本；`@concurrent` 在重写中被去掉属实 | 待办：GUI 宿主接入时把发现步骤移出主线程 / 恢复并发，CLI 无所谓 |
| 11 | interface 输出 import 列表 | `CoreFoundation.X` 无对应 `import CoreFoundation`——但基线上 `__C.X` 同样无对应 import（`__C` 被 filterModules 排除），非本次引入，且换成真模块名后形式反而更好 | **不修**，见 Adjudications A16 |
| 12 | `TypeDatabase` actor 重入 | `unindexedDependencies.removeFirst()` 后 await 的重入点存在，但库内打印是顺序 await、无并发调用方，路径不可达 | **暂不修**，见 Adjudications A17（复审条件：出现并发消费方） |

## 可不修（3 条）

| # | 位置 | 核实结论 | 状态 |
|---|---|---|---|
| 13 | 补充 APINotes 的全局覆盖面 | 补充文件条目可覆盖任意同名 SDK 条目——机制真实，但这同时是「修正官方数据错误」的通道（提案 0010 有意语义），且实测无现实冲突 | **不修**，见 Adjudications A18 |
| 14 | `NodePrintable.printModule` 重复查询 | `or` 第二参数是 `@autoclosure`，只在 miss 时多一次查询，非「绝大多数引用」 | **不修**（微优化），见 Adjudications A19 |
| 15 | `TypeNameResolvable.swiftName` 换签名 | 源码破坏真实（旧签名 conformer 静默失效），但「RuntimeViewer 有自己的 resolver」无证据——RV 只用库自带 provider | 待办：加 deprecated 旧签名转发，随下一批 API 清理 |
