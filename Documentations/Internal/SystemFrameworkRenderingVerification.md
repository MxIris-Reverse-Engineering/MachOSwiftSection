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
| **DyldCache**（cache 内 MachOFile） | 归档 cache：`/Volumes/DyldSharedCaches/macOS/26.5.2_25F84` 与 `15.5_24F74` 的 `dyld_shared_cache_arm64e` | **当前系统的 dyld shared cache**（`--uses-system-dyld-shared-cache -p <镜像路径>`，不传文件参数） |
| **MachOFile**（磁盘上的普通 Mach-O） | iOS 15.5 / 18.5 / 26.5 模拟器 runtime 的框架二进制 | **当前环境已安装的全部 iOS 模拟器 runtime**（脚本自动发现 `/Library/Developer/CoreSimulator/Profiles/Runtimes` 与 `/Library/Developer/CoreSimulator/Volumes/*/…/Runtimes` 下的 `*.simruntime`） |
| **MachOImage**（进程内） | 当前系统（dlopen + `MachOImage(name:)`），经 `RenderingVerificationTests` harness | 无回退（永远是当前系统） |

## 关键调用细节（踩过的坑）

- **cache 镜像用 `-p` 全路径而非 `-n` 名字**：SwiftUI / WidgetKit / ActivityKit 在 macOS cache 里有 `/System/iOSSupport/` 下的 Catalyst 副本，按名字查有歧义。
- **模拟器二进制要显式 `-a arm64`**：iOS 15.5 / 18.5 的模拟器框架是 fat（x86_64 + arm64），CLI 遇 fat 文件不指定架构会直接报错退出；26.5 起是 thin arm64，加该参数也无害，所以脚本一律加。
- **MachOImage 部分借用 `RenderingVerificationTests`**（`Tests/IntegrationTests/SwiftInterface/`）：该 harness 的注释明言其设计用途就是「run on two checkouts … and diff」。这是 AGENTS.md「agent 不得运行 IntegrationTests」规则的**唯一例外**，仅限本流程。
- **`RV_OPTS` 不含 `expandedFieldOffsets`**：harness 注释记录了它在 SwiftUI 级深嵌套泛型的 MachOImage 路径上会触发既有的栈溢出。
- **MachOImage 两侧必须在同一次开机会话内运行**：`memberAddress` 注释里的地址来自 dyld shared cache 的 per-boot slide，跨重启比对必然全线假差异。
- **两个检出绝不共用 SwiftPM scratch**（AGENTS.md 环境漂移检查的血泪教训：混入另一分支的陈旧目标文件会制造链接错误或假输出）；agent 会话另按全局规约使用独立 scratch 路径。
- **兄弟依赖对齐**：跑之前确认两个检出各自解析到预期的 sibling 内容（例如基线 main pin 了 `exact: "0.4.5"`，则 `/Volumes/Code/Personal/swift-demangling` 需在 0.4.5 tag 上：`git -C ../swift-demangling tag --points-at HEAD`）。sibling 内容错位会把 A/B 变成「比较两个不同的依赖版本」。
- **interface 输出一律走 `-o` 落盘**：进度日志（带墙钟时间戳）走 stdout，不会混进被比对的文件。

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
