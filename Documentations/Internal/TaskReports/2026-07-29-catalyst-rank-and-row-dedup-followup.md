# 2026-07-29 补完前一轮修复自身的两处缺口

## 问题

2026-07-28 那批修复（见 [2026-07-28-review-verification-and-fixes.md](2026-07-28-review-verification-and-fixes.md)）落地后又跑了一轮代码审查，12 条结论里有**两条指向那批修复本身**——都属于"已经宣称修好，实际只修了一部分"，因此比其余 10 条更该先处理。

### 缺口一：Catalyst 降级只覆盖 framework 形态

`matchRank` 里 `/System/iOSSupport` 的判断被写进了 `<name>.framework` 分支**内部**。既不在 `<name>.framework` 下、叶名又以 `.dylib` 结尾的镜像根本走不到那句，于是原生与 Catalyst 两份同名 dylib 双双落在 2 级，胜负重新取决于枚举顺序。

本机实测碰撞（已用 `ls` 确认两个文件都存在）：

```
/System/Library/Frameworks/OpenGL.framework/Versions/A/Libraries/libGLVMPlugin.dylib
/System/iOSSupport/System/Library/Frameworks/OpenGLES.framework/Versions/A/Libraries/libGLVMPlugin.dylib
```

另有 `/System/iOSSupport/usr/lib/swift/libswift{QuickLook,HomeKit,PencilKit}.dylib`，逐个查过**没有**原生同名物，属于"将来会踩"。

### 缺口二：`appendRowIfAbsent` 线性扫描

去重实现是 `symbolRowsByOffset[offset]?.contains(row)`，对桶线性扫描。注释断言"桶实际上只有一两行"，但没有任何东西保证——不同符号名合法共享地址正是桶为数组的原因，退化偏移（0，或 stripped / dyld 缓存镜像里被大量别名的地址）能攒到上千行，那样整趟采集是 O(n²)。

## 调研

### 缺口一：惩罚项应当正交于形态分类

审查建议"把支持根判断提成一次性惩罚项，在形态分类之前施加"。但"之前/之后"不是要点，**是否作用于所有形态**才是。而且惩罚项与形态的**主次关系**必须想清楚：

若让支持根作主键（原生任何形态 < Catalyst 任何形态），那么一个原生 `.axbundle` 会压过 Catalyst 的 framework 二进制——而没有 Swift 元数据的 accessibility bundle 抢赢 framework，正是整套排序机制最初要解决的问题。所以**形态必须是主键，支持根是同形态内的次级裁决**。

### 缺口二：新行不可能已经在桶里

重复只有两个成因，各自都能 O(1) 判定，根本不需要通用去重：

- 原始偏移 == 规范偏移 → 比较两个偏移即可（原本就有这个守卫）。
- 同名同址条目折叠到同一行 → 只有**本来就存在的行**才可能出现在桶里。新行索引取自 `symbolTable.count`，严格大于此前发出的所有行号，所以任何桶都装不下它。

导出符号那趟循环带 `tableRowByName[...] == nil` 前置条件，必然走新行分支，因此完全不进检查。

## 最终方案

1. **`matchRank` 拆成两步打分**：形态基准分 × `rankStepsPerPathShape`(2) + 支持根 `catalystSupportRootPenalty`(1)。乘 2 拉开间距，保证惩罚项永远不会把某形态顶到下一形态的分位上。全序：

   | 排名 | 含义 |
   | --- | --- |
   | 0 | 原生 canonical framework（唯一能拿 `bestMatchRank`） |
   | 1 | Catalyst framework |
   | 2 | 原生 plain dylib |
   | 3 | Catalyst plain dylib |
   | 4 | 原生 bundle / 其他 |
   | 5 | Catalyst bundle / 其他 |

   `bestMatchRank` 仍然只有原生 canonical framework 能达到，所以 `accumulateBestMatch` 拿到 0 级就提前退出这件事依然成立。

2. **`canonicalRow` 返回 `(row, isNewRow)`**，`registerRow` 透传，`appendRow` 增加 `mayAlreadyBeListed` 参数，只在该参数为真时才扫桶。

## 实际执行

- `Sources/MachOExtensions/DyldCache+.swift` —— 新增 `rankStepsPerPathShape` / `catalystSupportRootPenalty` 两个常量（后者的文档注释写明"限定在单一形态里"正是第一版的错误）；`matchRank` 的 `.name` 分支重写为先算 `pathShapeRank` 再叠加惩罚。
- `Sources/MachOSymbols/SymbolIndexStore.swift` —— `canonicalRow` 改签名，`appendRowIfAbsent` 更名 `appendRow(_:atOffset:mayAlreadyBeListed:)`，两个采集循环相应更新；注释重写为解释两个成因各自如何被 O(1) 挡掉，并说明为什么退化偏移场景现在一次都不扫。
- `Tests/MachOCachesTests/DyldCacheImageSearchTests.swift` —— 新增两个用例：`catalystPlainDylibLosesToItsNativeNamesake`（用真实的 `libGLVMPlugin` 双路径）、`supportRootPenaltyNeverCrossesAShapeBoundary`（钉住"惩罚不跨形态"这条不变量）。

## 验证

- `swift build` 通过。
- `swift test --filter DyldCacheImageSearchTests`：11 个用例全过（原 9 + 新 2）。
- `swift test --skip IntegrationTests`：1280 测试 / 146 issue，**失败测试名集合与既有基线逐条一致（19 个）**。测试总数从 1275 增至 1280，正是本分支累计新增的 5 个用例。
- 端到端：`swift-section dump --uses-system-dyld-shared-cache -n SwiftUI` 与上一轮验证过的输出**逐字节一致**（109387 行）。

## 偏差说明

无。两条缺口都按计划闭环，且都有测试钉住。

其余 10 条审查结论按用户要求仍然只记录不修，清单见 [../NodeStoreMigrationOpenIssues.md](../NodeStoreMigrationOpenIssues.md) 第二节起——其中四条的修复位置在上游 `swift-demangling`，本仓库这侧绕不开。
