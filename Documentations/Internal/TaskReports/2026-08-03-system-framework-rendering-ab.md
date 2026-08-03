# 2026-08-03 系统框架渲染 A/B 验证与流程固化

## 问题

性能批次（同日五提交）落地后，维护者要求用真实系统框架对 `feature/node-store-migration` 做全面输出对等验证，覆盖三种 reader 路径：DyldCache 用两份归档 cache（macOS 26.5.2_25F84 / 15.5_24F74），MachOFile 用 iOS 15.5 / 18.5 / 26.5 模拟器 runtime，MachOImage 直接测当前系统；框架集 SwiftUI / SwiftUICore / SwiftData / Combine / ActivityKit / WidgetKit，缺席即略过。随后追加要求：把这套测试记成「大重构必跑」流程，目标输入不存在时 DyldCache 回退当前系统 cache、MachOFile 回退现有模拟器 runtime；脚本用 Python 写。

## 调研

- CLI 无进程内 MachOImage 模式；`Tests/IntegrationTests/SwiftInterface/RenderingVerificationTests.swift` 正是维护者为「两个检出 diff 输出」设计的 harness（dlopen + `MachOImage(name:)`，image/file 双路，全 metadata 选项），且 main 与 feature 上逐字节相同——MachOImage 部分直接双侧复用它（IntegrationTests 禁跑规则的唯一例外，已在 AGENTS.md 登记）。
- cache 内镜像按名字查有歧义（SwiftUI / WidgetKit / ActivityKit 有 `/System/iOSSupport` 的 Catalyst 副本；macOS 15.5 的 ActivityKit **只有** Catalyst 副本），需 `-p` 全路径。
- iOS 15.5 / 18.5 模拟器框架是 fat 二进制（x86_64+arm64），CLI 直接报错要求 `-a`；26.5 起是 thin。首轮模拟器矩阵因此双侧全体瞬间失败，补 `-a arm64` 重跑。
- main 侧环境核对：主仓库 `Package.swift` 的 `exact: "0.4.5"` / `exact: "0.1.6"` pin 与兄弟检出（swift-demangling detached@0.4.5、swift-semantic-string@0.1.6）恰好对齐；main 用全新独立 scratch（`MachOSwiftSection-main`）从零构建，规避此前 scratch 混用事故模式。

## 方案

双侧 release CLI（各自独立 scratch）对同一批输入渲染 dump + interface，输出经 `-o` 落盘（时间戳进度日志走 stdout 不进文件），逐对 `cmp`。三部分顺序：cache 矩阵 + 模拟器矩阵（脚本并行双侧）→ `RenderingVerificationTests`（`RV_OPTS` 去掉 `expandedFieldOffsets`，harness 注释记录其在 SwiftUI 级 MachOImage 上的既有栈溢出；双侧同一次开机会话内运行，保证 memberAddress 地址可比）。

## 实际执行

- 前置 smoke：fixture（SymbolTestsCore）dump 6031 行 / interface 3636 行，双侧一致（interface 仅时间戳行差异，归一化后一致）；dump 连跑两遍验证输出确定性。
- **DyldCache**：2 cache × 6 框架 × dump+interface = **24 对全部逐字节一致**（最大 SwiftUI dump 109,387 行）。
- **MachOFile**：iOS 15.5（3 框架）/ 18.5 / 26.5（各 6 框架）× dump+interface = **30 对全部逐字节一致**。
- **MachOImage**：当前系统（macOS 26.5）六框架 image+file 双路全选项 = **24 对全部逐字节一致**（最大 interface-SwiftUI-file 7.2 MB；单侧 836–966 秒）。
- **合计 78 对，零差异。**
- 流程固化：`Scripts/run-rendering-ab-verification.py`（先写 zsh 版，按维护者要求改写为 Python 并删除 zsh 版）+ `Documentations/Internal/SystemFrameworkRenderingVerification.md` + `Documentations/README.md` 索引行 + AGENTS.md「大重构必跑」段落与 IntegrationTests 例外登记 + 演进日志第 25 节。

## 验证

- 逐对 `cmp` 全绿（上文数字）；`--uses-system-dyld-shared-cache -p <路径>`（无文件参数）的回退调用形式实测可用；脚本 `py_compile` + `--help` 通过。
- 两个 harness 测试进程均正常退出（`Test run … passed`）。

## 偏离与教训

- **fat 二进制首轮全灭**：模拟器矩阵首轮未带 `-a`，双侧同码瞬间失败——失败形态对称所以无害，但暴露了「脚本先在小输入上单侧试跑一次」的价值；修正后的脚本一律显式 `-a arm64`。
- **iOS 15.5 的 interface 输出只有几十行**（双侧一致）：索引器对 iOS 15 时代 metadata 批量报 `ContextDescriptorWrapper` 解析错误，类型全部掉光只剩全局函数；dump 路径不受影响（SwiftUI 15.5 dump 4.6 万行）。records 为已知既有限制，非迁移回归。
- ActivityKit 在当前 macOS 26.5 是原生框架（in-process dlopen 成功），不再是 iOSSupport 专属——「缺席即略过」的判定要按实际探测，不能按旧记忆硬编码。
