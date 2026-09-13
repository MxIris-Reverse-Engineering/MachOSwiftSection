# 不透明类型解析进度看板

- **最后更新**：2026-09-14
- **一句话现状**：编译器把 `some` 类型写进二进制的三种写法（指向描述符的指针、要执行的 accessor thunk、按名字引用别的镜像的描述符）离线都能读了；手头全部样本里 kind-9 引用剩 0 处，按名引用只剩方法签名里成员符号的原样打印；macOS 27.0 的新 cache 格式打不开是当前最大的缺口，归 MachOKit。
- **这份文档是什么**：一张活的看板，每批落地时更新「批次」「样本」「待办」三张表；原理讲解看 [AccessorThunkResolutionExplained.md](AccessorThunkResolutionExplained.md)，每批为什么这样做看各自的提案。

## 三种写法，各自的状态

| 编译器的写法 | 什么时候出现 | 现在怎么读 | 状态 |
|---|---|---|---|
| 指向 opaque 描述符的指针（symbolic reference） | 绝大多数 witness 与字段 | 读描述符里的 underlying type，代入泛型实参，嵌套展开 | 0028 之前就有，稳定 |
| kind-9 accessor 引用：一段要执行的 thunk | `if #available` 两支返回不同类型（SE-0360）、`~Copyable` 字段 | 反汇编，符号求值（寄存器里装类型表达式），跟进本镜像内没名字的被调函数，跨镜像调用经 bind 名 / rebase 地址 / 跳板认到底 | 第 1–6 批，见下表 |
| 按名字引用别的镜像的描述符（GOT bind） | 独立文件里的 witness 用到别的框架的 `some` 结果 | 重新 mangle 出描述符符号，按搜索路径定位镜像，在那个镜像里展开 | 第 7 批 |

兜底原则贯穿三条路：认不出就留 `accessor function at N` 或 `<<opaque return type of …>>` 占位，绝不给一个真实但错误的类型。

## 样本实测

口径：`swift-section dump` / `interface` 输出里 `accessor function at`（kind-9 未读）与 `opaque return type of`（按名引用剩余）的行数。全部用第 7 批的 release 二进制测于 2026-09-13。

| 样本 | kind-9 未读 | 按名引用剩余 | 备注 |
|---|---|---|---|
| macOS 14.7 / 15.0 / 15.5 cache，SwiftUI（+ SwiftUICore） | 0 | 0 | 这些构建里没有 SE-0360 thunk，分支注释 0 条 |
| macOS 26.0 / 26.3 / 26.6 cache，SwiftUI + SwiftUICore | 0 | 0 | SwiftUI 各 15 / 17 / 17 条分支注释 |
| macOS 26.6.2 宿主 cache，SwiftUI + SwiftUICore | 0 | 0 | oracle 测试在它上面跑 |
| iOS 26.3.1 设备 cache（arm64e），SwiftUI + SwiftUICore | 0 | 0 | 第 6 批之前 7 / 2 未读、0 条注释 |
| iOS 27 模拟器 cache（24A434、24A5380i），SwiftUI + SwiftUICore | 0 | 6 行方法签名 | 第 4 批起模拟器也进 cache |
| iOS 26.5 模拟器独立文件，SwiftUI dump / interface | 0 | 6 行方法签名 | 第 7 批之前 dump 215 行、interface 189 条 witness 印错 |
| iOS 26.5 模拟器独立文件，SwiftUICore | 0 | 0 | |
| iOS 18.5 模拟器独立文件，SwiftUI | 0 | 6 行方法签名 | |
| 现场编译的三个 fixture（跨镜像 bind、合并 accessor、跨镜像 opaque 引用） | 0 | 0 | 每台机器都能跑 |
| **macOS 27.0 cache（`dyld_shared_cache_arm64e_x1`）** | **打不开** | — | magic `dyld_v1arm64ex1`，MachOKit 不认，见待办 |

剩下的 6 行方法签名是 `ButtonStyleContent` 几个方法的参数类型提到了另一个函数的 opaque 返回类型，属于成员符号的原样打印，不经类型展开，不算未解。

## 批次

| # | 提案 | 做了什么 | 关键数字 | 状态 |
|---|---|---|---|---|
| 1 | [0028](../Evolutions/0028-offline-opaque-accessor-thunk-resolution.md) | 反汇编 thunk，按形状认版本检查与 `csel` / `cbz` 两种选择 | SwiftUI 裸地址 17 → 5 | 已合并 `next` |
| 2 | 0028 收尾 | 读不出的引用不再吞掉整棵树；两支进模型与输出注释；进程内路径 | 进程内 5 / 17 | 已合并 `next` |
| 3 | [0029](../Evolutions/0029-thunk-type-construction-evaluation.md) | 符号求值器替代形状匹配；字段记录接入 | SwiftUI 17 → 0，dump 6 → 0 | 已合并 `next` |
| 4 | [0030](../Evolutions/0030-standalone-file-thunk-resolution.md) | 回退收紧；跨镜像 bind 经依赖镜像；system root 搜索路径与推断；CLI `--dependency-search-path`；带符号的专用 accessor；修导出表偏移与 `__swift5_types` bind 记录 | iOS 26.5 模拟器 SwiftUI 5 → 0，SwiftUICore 4 → 2 | 已合并 `next`（2026-09-14） |
| 5 | [0031](../Evolutions/0031-merged-accessor-inline-evaluation.md) | 求值器跟进本镜像内没名字的被调函数；`blr`；bind 槽当函数引用 | SwiftUICore 两边 2 → 0 | 已合并 `next`（2026-09-14） |
| 6 | [0032](../Evolutions/0032-cache-stub-islands-and-unmodelled-instructions.md) | 设备 cache 的跳板不管在哪都认；不认识的条件跳转放弃（`brk` 落点例外）、不认识的指令作废寄存器、PAC 保值 | iOS 设备 cache 7 / 2 → 0 | 已合并 `next`（2026-09-14） |
| 7 | [0033](../Evolutions/0033-by-name-opaque-reference-expansion.md) | 跨镜像 bind 的描述符重新 mangle、定位镜像、在那个镜像里展开；顺带消掉 interface 把 conformer 印成 witness 的错误 | iOS 26.5 SwiftUI dump 215 → 6，interface 189 条 witness 改对 | 已合并 `next`（2026-09-14） |

第 4–7 批于 2026-09-14 按顺序合进 `next`（合并提交 `90541b34` / `3936e64a` / `c385f942` / `66ef730a`），提案编号 0030–0033，分支已删。

## 待办与已知限制

按重要性排。「归属」写谁的改动。

| 优先级 | 事项 | 归属 | 备注 |
|---|---|---|---|
| 高 | macOS 27.0 cache 打不开：magic `dyld_v1arm64ex1`（新架构串 `arm64ex1`，无空格填充），header mapping 偏移 0x228 → 0x238 | MachOKit（兄弟仓库）`DyldCacheHeader._cpuType` / `_cpuSubType` 查表 | 加 magic 之后 subcache、镜像表、slide info 有没有新格式要试了才知道；文件名 `_x1` 后缀也让 `DependencySearchPath.isMainCacheFileName` 不认 |
| 高 | x86_64 不支持 | `SwiftThunkAnalysis` 解码器只有 ARM64 | Intel 二进制的 thunk 全部占位 |
| 中 | 依赖镜像找不到时，interface 把未展开的按名引用节点印成 conformer 自己 | `SwiftPrinting` 的 `printOpaqueType` | 只印节点的实参表；能定位的引用现在都展开，第三方 app 没给搜索路径时仍会触发。修法：印不出就印 `<<opaque return type of …>>` |
| 中 | zippered 构建的 8 参数版本检查（`__isPlatformOrVariantPlatformVersionAtLeast`）认不出 | `AccessorThunkAnalyzer` 的四立即数形状识别 | 后果是把一支当唯一答案、丢掉分支注释，不是错类型；没有样本，纯预防 |
| 低 | 被跟进的函数在栈上建实参缓冲区时读不出（写回式 `stp` / `ldp` 让栈模型作废） | 求值器 | 目前没有样本 |
| 低 | class 类型的 metadata 实参不命名（`MetadataNaming` 只认 struct / enum / optional） | 求值器命名层 | 目前的样本实参都是 struct |
| 低 | 进程内路径拒绝泛型 conformer、class conformer 没接 | `InProcessAccessorFunctionResolution` | 离线路径已覆盖这些，进程内只是补充 |
| 低 | 模拟器里的第三方 app 推断不到运行时的 cache，要靠 `--dependency-search-path` | CLI / 宿主 | 宿主（RuntimeViewer）知道设备对应的运行时，可以自己传 |
| 记录 | `_swift_runtimeSupportsNoncopyableTypes` 的 GOT 槽在 cache 文件里是 0，标志判定不了 | 求值器 | 靠「条件为假先跑」拿到支持那一支；改成读 cache 的 patch table 才能判定，不值得 |
| 记录 | `CacheImageResolver.image(containing:)` 按「最大不超过的加载地址」归属，会把镜像间区域归给前一个镜像 | `SwiftThunkAnalysis` | 无害，索引落空后走跳板识别 |
| 已否决 | 换成完整的模拟执行（Unicorn 或自写解释器） | — | 用户决定保留符号求值继续打补丁，见第 6 批提案的决策日志 |

## 怎么复测

- **单元与集成**：`swift test --filter '^SwiftThunkAnalysisTests\.'`（含宿主 cache 门控、模拟器门控、归档 iOS cache 门控的套件）；`swift test --filter '^SwiftInterfaceTests\.CrossImageOpaqueReferenceTests'`；最重要的是 `ConstructedThunkOracleTests`，它要求宿主 cache 上每条 kind-9 witness 的离线读法逐字等于 runtime 执行 thunk 的答案，换 macOS 就自动重验。
- **输出计数**：release 构建后对一份二进制跑 `swift-section dump`，数 `accessor function at` 与 `opaque return type of` 的行数；cache 文件用 `--dyld-shared-cache <cache> -n SwiftUI`，宿主 cache 用 `--uses-system-dyld-shared-cache -p <镜像路径>`，模拟器独立文件直接给路径（iOS 18.5 是 fat，加 `-a arm64`）。归档 cache 在 `/Volumes/DyldSharedCaches/<平台>/<版本>/`。
- **回归口径**：改动只应让目标样本的目标行变化，其余输出逐字节一致；每批的任务报告里都有这张 diff 表。

## 相关文档

- 原理讲解：[AccessorThunkResolutionExplained.md](AccessorThunkResolutionExplained.md)
- 演进账本里的七节：[ProjectEvolutionLog.md](ProjectEvolutionLog.md)
- 任务报告：[09-11 首批](TaskReports/2026-09-11-offline-accessor-thunk-resolution.md)、[09-11 收尾](TaskReports/2026-09-11-accessor-thunk-resolution-follow-up.md)、[09-12 求值器](TaskReports/2026-09-12-thunk-type-construction-evaluation.md)、[09-13 独立文件](TaskReports/2026-09-13-standalone-file-thunk-resolution.md)、[09-13 合并 accessor](TaskReports/2026-09-13-merged-accessor-inline-evaluation.md)、[09-13 stub island](TaskReports/2026-09-13-cache-stub-islands.md)、[09-13 按名引用](TaskReports/2026-09-13-by-name-opaque-reference-expansion.md)
