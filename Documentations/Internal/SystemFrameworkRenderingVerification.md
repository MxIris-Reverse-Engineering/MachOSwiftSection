# 系统框架渲染 A/B 验证（大重构必跑）

对 demangling / 打印 / 索引 / reader 栈做**任何大重构**后，都必须用真实系统框架跑一遍本流程：同一批输入、两个检出（基线 + 重构分支）、release CLI，逐字节比对 dump 与 interface 输出。fixture（SymbolTestsCore）覆盖的是构造出来的形态，真实 OS 框架才覆盖规模（10 万行级输出）、历史 metadata 格式（iOS 15 时代）与三种 reader 路径的全量组合。

**入口脚本**：[`Scripts/run-rendering-ab-verification.py`](../../Scripts/run-rendering-ab-verification.py)

```bash
Scripts/run-rendering-ab-verification.py <基线检出> <重构检出> \
    [--output-root 目录] [--frameworks A,B,...] \
    [--baseline-scratch 目录] [--candidate-scratch 目录] [--skip-image-part]
```

脚本自动构建两侧 release CLI、跑完三部分、输出逐对 IDENTICAL/DIFFERS 表格；有任何差异以非零码退出。

## 框架清单

SwiftUI、SwiftUICore、SwiftData、Combine、ActivityKit、WidgetKit——**输入源里不存在的直接略过**（例如 iOS 15.5 没有 SwiftUICore/SwiftData/ActivityKit；macOS 15.5 cache 的 ActivityKit 只有 iOSSupport/Catalyst 副本，脚本会自动改用该路径）。

## 三个 reader 部分与输入源回退规则

| 部分 | 首选输入 | 目标不存在时的回退 |
| --- | --- | --- |
| **DyldCache**（cache 内 MachOFile） | 归档 cache：`/Volumes/DyldSharedCaches/macOS/26.6` 与 `15.5` 的 `dyld_shared_cache_arm64e` | **当前系统的 dyld shared cache**（`--uses-system-dyld-shared-cache -p <镜像路径>`，不传文件参数） |
| **MachOFile**（磁盘上的普通 Mach-O） | iOS 15.5 / 18.5 / 26.5 模拟器 runtime 的框架二进制 | **当前环境已安装的全部 iOS 模拟器 runtime**（脚本自动发现 `/Library/Developer/CoreSimulator/Profiles/Runtimes` 与 `/Library/Developer/CoreSimulator/Volumes/*/…/Runtimes` 下的 `*.simruntime`） |
| **MachOImage**（进程内） | 当前系统（dlopen + `MachOImage(name:)`），经 `RenderingVerificationTests` harness | 无回退（永远是当前系统） |

## 关键调用细节（踩过的坑）

- **跑之前先确认归档目录真的存在**：`ARCHIVED_CACHE_DIRECTORIES` 是写死的两条路径，对不上时脚本**不报错**，只打印一行 `No archived cache found - falling back to the current system's dyld shared cache.` 就降级成只跑当前系统 cache——跨版本语料整段消失，而最终报告照样是「全部一致」。2026-09-17 撞上一次：归档卷把带 build 号的 `26.5.2_25F84` / `15.5_24F74` 改成了纯版本号，且 `26.5.2` 目录下已不再放 cache（换成 `26.6.2`）。常量随之改为 `26.6.2` 与 `15.5`。2026-09-18 再撞一次：`26.6.2` 目录已改名为 `26.6`（旁边新增 `27.0`），常量改为 `26.6`。跑之前 `ls /Volumes/DyldSharedCaches/macOS/` 对一眼，比事后从报告里发现少了一条腿便宜。
- **cache 镜像用 `-p` 全路径而非 `-n` 名字**：SwiftUI / WidgetKit / ActivityKit 在 macOS cache 里有 `/System/iOSSupport/` 下的 Catalyst 副本，按名字查有歧义。
- **模拟器二进制要显式 `-a arm64`**：iOS 15.5 / 18.5 的模拟器框架是 fat（x86_64 + arm64），CLI 遇 fat 文件不指定架构会直接报错退出；26.5 起是 thin arm64，加该参数也无害，所以脚本一律加。
- **MachOImage 部分借用 `RenderingVerificationTests`**（`Tests/IntegrationTests/SwiftInterface/`）：该 harness 的注释明言其设计用途就是「run on two checkouts … and diff」。这是 AGENTS.md「agent 不得运行 IntegrationTests」规则的**唯一例外**，仅限本流程。
- **`RV_OPTS` 不含 `expandedFieldOffsets`**：harness 注释记录了它在 SwiftUI 级深嵌套泛型的 MachOImage 路径上会触发既有的栈溢出。
- **MachOImage 两侧必须在同一次开机会话内运行**：`memberAddress` 注释里的地址来自 dyld shared cache 的 per-boot slide，跨重启比对必然全线假差异。
- **两个检出绝不共用 SwiftPM scratch**（AGENTS.md 环境漂移检查的血泪教训：混入另一分支的陈旧目标文件会制造链接错误或假输出）；agent 会话另按全局规约使用独立 scratch 路径。
- **兄弟依赖对齐**：跑之前确认两个检出各自解析到预期的 sibling 内容（例如基线 main pin 了 `exact: "0.4.5"`，则 `/Volumes/Code/Personal/swift-demangling` 需在 0.4.5 tag 上：`git -C ../swift-demangling tag --points-at HEAD`）。sibling 内容错位会把 A/B 变成「比较两个不同的依赖版本」。
- **脚本的进度行经 Python 的 stdout，重定向进文件时会被整块缓冲**：跑完之前日志里只有子进程（`swift build`）的输出，看不到任何一对的进度，盯日志会误以为卡住。后台跑要 `python3 -u`，或者直接看 `--output-root` 下 `<场景>/<侧>/*.txt` 的落盘情况（每一对两侧都落盘后就可以先 `cmp`，不必等收尾）。2026-09-18 撞上一次。
- **interface 输出一律走 `-o` 落盘**：进度日志（带墙钟时间戳）走 stdout，不会混进被比对的文件。

## 并发、基线缓存与按腿筛选（2026-09-21 起）

一轮完整 A/B 原本约 55 分钟：两侧 release 构建串行（各 7–9 分钟），78 对渲染串行（合计约 40 分钟，单个 SwiftUI interface 在 release 下 50–105 秒）。2026-09-21 落地 ObjC 成员表时连跑了四轮，每轮基线一行没变却都重渲染，脚本因此加了三样东西：

- **`--jobs N`**（默认 `min(6, CPU 数)`）：CLI 渲染对经线程池并发起子进程，每对独立进程、独立输出文件，完成顺序与比对无关；两侧 release 构建也并行（各自 scratch，互不相干）。一个 SwiftUI interface 进程占 1–2 GB 内存，按内存定 N。MachOImage 部分仍是每侧一个 `swift test`，两侧并行、内部串行。**跑 A/B 时别同时跑测试套件**：`SharedCacheTests` 的墙钟并行度断言会被挤成假失败。
- **基线渲染缓存**（`--baseline-cache PATH`，默认 `~/Library/Caches/MachOSwiftSection/RenderingABBaseline`；`--no-baseline-cache` 关）：基线侧的每个 CLI 渲染按「基线检出的 HEAD commit + 场景 + 框架 + 子命令 + 完整参数 + 输入文件身份（路径、大小、mtime；当前系统 cache 用 OS 版本与内核版本）」做 key，命中就把 `.txt` / `.skip` / `.log` 拷回输出目录并在进度行标 `cached`。**基线检出有未提交改动就整轮禁用缓存**（打印一行说明），因为那时 HEAD 不代表它的内容。候选侧永远重渲染；MachOImage 部分永远不缓存——`memberAddress` 注释带 per-boot slide。同一基线换四轮候选，渲染时间减半。
- **`--scenarios a,b,...`**：只跑点名的腿（`cache-15.5` / `cache-current-system` / `sim-iOS-18.5` / `machoimage-current` …），修完一处只回查受影响的腿。零对比对的兜底照旧生效：筛选打错名字会落到「zero pairs were compared」的失败，不会静默通过。

三样都不碰 `compare_all_pairs` 与 `.skip` 标记的写法，harness 自己的单元测试（`Scripts/test-run-rendering-ab-verification.py`）在改动后重跑为绿。

## 验收标准与差异排查

- 验收：**所有配对逐字节一致**（`cmp`）。
- 出现 DIFFERS 时：先在**同一侧**把该场景连跑两遍排除非确定性（2026-08-03 基线确认 dump / interface 输出均确定），再做归因；一侧成功一侧失败（MISSING-ON-*）同样按差异处理。
- 两侧以**相同退出码**失败的场景记为 SKIPPED（脚本会列出），例如某框架在旧 runtime 里根本不存在。

## 已知的双侧一致现象（非回归）

- ~~**iOS 15.5 模拟器的 interface 输出只有几十行**~~——**已于 2026-08-03 在 `feature/node-store-migration` 修复**（`LC_DYLD_INFO` opcode bind 回退 + printRoot 逐项降级，见[任务报告](TaskReports/2026-08-03-legacy-dyld-info-bind-support.md)）。修复落地后，旧格式二进制（部署目标 < macOS 12 / iOS 16）的 interface 输出与**未含该修复的基线**（如当前 main）会**合理地不一致**——修复侧多出完整的类型与 conformance；对含修复的两个检出做 A/B 时该场景恢复严格逐字节对比。基线侧的历史症状（只剩全局函数、成百条 `offsetOutOfBounds`）与根因记录在任务报告里。

## 基线运行记录（2026-08-03，main ↔ feature/node-store-migration）

- 附带 smoke：fixture（SymbolTestsCore）dump 6031 行、interface 3636 行，双侧一致（interface 仅时间戳日志行差异，归一化后一致）。
- DyldCache：macOS 26.5.2_25F84 + 15.5_24F74 × 6 框架 × dump+interface，**24 对全部逐字节一致**（最大 SwiftUI dump 109,387 行）。
- MachOFile：iOS 15.5（3 框架）/ 18.5 / 26.5（各 6 框架）模拟器 × dump+interface，**30 对全部逐字节一致**。
- MachOImage：当前系统（macOS 26.5，arm64e cache），六框架 in-process + 当前 cache 文件双路，全选项（除 `expandedFieldOffsets`），**24 对全部逐字节一致**（最大 interface-SwiftUI-file 7.2 MB；harness 单侧耗时 ~14–16 分钟）。
- **合计 78 对，零差异**。运行细节与偏离见 [TaskReports/2026-08-03-system-framework-rendering-ab.md](TaskReports/2026-08-03-system-framework-rendering-ab.md)。
