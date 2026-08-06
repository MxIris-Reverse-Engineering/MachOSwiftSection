# 2026-08-06 - 嵌套字段偏移展开的环守卫（DVTIconKit "死循环"）

- **日期**: 2026-08-06
- **分支**: `fix/nested-field-offset-cycle-guard`；开发基线 `3396cfd`（当时落后 origin/main
  四个提交），完成后 rebase 到 `main`（`4eeb3b4`）并合入
- **关联文档**: [NestedFieldOffsetCycleGuard.md](../NestedFieldOffsetCycleGuard.md)

## 1. 问题

用户在 RuntimeViewer 里对 Xcode 的 `DVTIconKit` 生成 Swift interface 时应用挂住，提供
日志 `/Users/JH/Desktop/RuntimeViewer.log`（2504 行，含 lldb 线程转储），问："这一直
死循环，最新的 MachOSwiftSection 和 swift-demangling 有解决这个问题吗，原因是什么"。

## 2. 调研

### 日志分析

- 第 155 行 `Generating Swift interface for: DVTIconKit.GeneratedIconIconSpec` 之后立即
  开始刷 `walkNestedExpandedFieldOffsets reached nested field-offset depth limit 16 —
  truncating expansion of …`，共 1362 条且仍在增长。
- 截断类型只有九个，计数为 66 / 87 / 87 / 118 / 153 / 153 / 205 / 206 / 271——线性递推
  增长，是**路径计数**而非节点计数的形状。
- 线程转储：约 20 条线程堵在 `NodeCache.createInterned` 的 `__psynch_mutexwait`，帧里
  清一色 `__NSThread__start__` ← `StackSafeExecutor.executeOnLargeStackThreadThrowing`，
  来源是 `SymbolIndexStore.buildStorageImpl` 的 `concurrentMap`。

### 环的证实（从二进制符号直接读种类）

```
$ nm -a DVTIconKit | grep -oE "GeneratedIconPrimitive(Reference|Value)Spec[VOC]Mn"
_$s10DVTIconKit31GeneratedIconPrimitiveValueSpecOMn        ← O = enum
_$s10DVTIconKit35GeneratedIconPrimitiveReferenceSpecVMn    ← V = struct
```

enum 的 case 有 `value` / `array` / `switch` / `condition` / `reference`；二进制 import
了 `swift_allocBox` / `swift_projectBox`，即确有 indirect case。struct 持有
`Optional<ValueSpec<String>>`，enum 的 `reference` case payload 是该 struct——环成立。
值类型字段图想成环**只能**经过 indirect case（内联自包含是无限大小，编译不过）。

### 两个根因

1. `walkNestedExpandedFieldOffsets` 只有 `depth >= 16` 守卫，无 visited 集。深度上限
   约束深度，环爆炸的是路径数。
2. `walkNestedEnumPayloadFieldOffsets` 不检查 `isIndirectCase`——而同文件的
   `enumPayloadSize`(699) / `enumPayloadExtraInhabitantCount`(717) 都检查了。indirect
   payload 是堆 box 指针，下钻既打印出不存在的偏移，也是环得以闭合的原因。

### 放大器（属 swift-demangling，非本次修复范围）

每访问一个节点做 2–3 次**未缓存** demangle（`demangleTypeUncached` 在
`staticallyBoundMetatype` / `resolveNestedMetatype` / `substitutedNestedTypeNode` 三处）。
用户本地 swift-demangling(`04c959b`) 每次 demangle 都 new 一个 8MB 栈 `Thread` + 信号量
阻塞，并把每个 node 塞进全局 `NodeCache` 的一把 mutex。

### 「最新版有没有解决」

- **swift-demangling**：本地落后 origin/main 约 45 个提交（整个 node-store 迁移）。新版
  `StackSafeExecutor` 改线程池且栈够就 inline 跑，新增 `demangleAsNodeTransient`
  完全不进全局 `NodeCache`。→ **放大器已解决**。
- **MachOSwiftSection**：本地落后 4 个提交。PR #97 对 `RuntimeFieldLayoutBackend` 的改动
  逐行核对，只有 `Node.create`→`createTransient`、`demangleAsNode`→`demangleAsNodeTransient`
  （同样是绕开全局缓存）。**递归本体一行没改**。→ **根因未解决**。

结论回给用户：升级后会快很多，但根因仍在。用户回"把真正原因修了"。

## 3. 最终方案

两条独立实现（运行时 `RuntimeFieldLayoutBackend`、静态 `SwiftLayout.NestedFieldOffsetTree`）
各加两道守卫：

1. **`indirect` case 报告但不下钻**——与 class 引用同等对待（打印节点，无子节点）。
   实际消除爆炸的是这一道。
2. **路径作用域的已打开类型集合**——运行时按 `ObjectIdentifier(metatype)`，静态按打印
   类型名（区分 `Box<Int>`/`Box<String>`；名字在 `makeNode` 里本就要算，零额外开销）。
   纵深防御，防解析误判造成的假环。

深度上限保留，继续兜"无环但很深"；钉值测试不动。

**关键取舍：按路径而非全局。** 同一类型经不同字段到达时两处都必须完整展开（`String`
挂在两个属性下是两棵真实子树），全局 visited 会让输出残缺。

## 4. 实际执行

1. fixture 新增 `Tests/Projects/SymbolTests/SymbolTestsCore/RecursiveIndirectFieldLayout.swift`
   （项目用 Xcode 16 文件系统同步组，加文件无需改 pbxproj），重建 `SymbolTestsCore`。
2. 改两个源文件。
3. 新增两个回归套件（运行时 4 个测试 / 静态 4 个测试）。
4. **验证修复前失败**：`git stash push` 只暂存两个源文件（保留 fixture 与测试）后重跑。
5. 恢复修复，重跑通过。
6. 全量 `swift test --skip IntegrationTests`，处理副作用（见下）。
7. 横向排查 + 文档。

### 副作用一：baseline 偏移漂移（预期）

加 fixture 文件使所有类型 descriptor offset 位移，`StructTests` /
`ProtocolConformanceTests` 6 个 issue。按 AGENTS.md 的既定流程
`swift package --allow-writing-to-package-directory regen-baselines` 重生成，
59 文件 96 增 96 删，**全部是 `descriptorOffset` 变化，无语义漂移**（上游 `4eeb3b4`
加 fixture 时同样表现）。

### 副作用二：撞上一个无关的既有缺陷（已回避，非本次引入）

fixture 最初写成 `public indirect enum ValueSpec<Value>`（整个 enum indirect），
`WholeTypeLayoutVsRuntimeTests` 报 `ReferenceSpec` runtime 40 / static 56。

**隔离验证**：stash 掉两个源文件后同样失败 → 与本次修复无关。

**定性**：整个 enum `indirect` ⇒ 每个 payload 都装箱 ⇒ 布局与 `Value` 无关 ⇒
argument-independent 泛型 multi-payload enum。本仓库 `SwiftLayout` 直到上游 `4eeb3b4`
才为这类 enum 采用编译器记录的 spare-bits 布局（`EnumLayoutBridge` 的
`environment.isEmpty` 与 `!descriptor.isGeneric` 两道门，见
[2026-08-05-generic-fixed-mpe-spare-bits.md](2026-08-05-generic-fixed-mpe-spare-bits.md)）。
即：**在落后 4 个提交的基线上必然撞到，上游已修**。

**处理**：改为逐 case `indirect`（`literal(Value)` 保持内联 ⇒ 布局重新依赖实参 ⇒ 离开
那条轴）。附带两个好处：更贴近 `DVTIconKit`（那边也只有递归 case 装箱）；能验证守卫读
的是**每个 case 的标志位**而非整个 enum 的属性。未在此基线上顺手修 MPE 缺陷——它不是
"真正原因"，且上游已有经过完整调研的修复。

### 副作用三：snapshot 覆盖率不变量

`SymbolTestsCoreCoverageInvariantTests` 要求每个 fixture 分类配一个 snapshot 测试。
补 `recursiveIndirectFieldLayoutSnapshot` 并录制快照（快照正确反映逐 case `indirect`）。

### 副作用四：两个既有快照漂移（预期，无语义变化）

- `unsafePointersSnapshot`：`EnumOverUnsafeRawPointerFieldTest.pointerEnum` 的
  getter/setter 两行**位置**变了，内容逐字相同——fixture 重建导致的符号顺序漂移。
- `interfaceSnapshot`：**纯新增 57 行 0 删除**，即我的 fixture 类型本身。

两者都用 stash 法验证过与本次修复无关（修复前后表现一致）。`SNAPSHOT_TESTING_RECORD=all`
在本仓库使用的 swift-snapshot-testing 版本上不生效，改用删除快照文件让其自动重录，
重录后逐行核对 diff 确认只有上述两类变化。

interfaceSnapshot 新增的那段同时是修复效果的实证：`ReferenceSpec` 四个字段的偏移
（0x0 / 0x10 / 0x28 / 0x40）完整且有界，`ValueSpec` 的两个 `indirect` case 正确标注
且未展开出虚构的嵌套字段。

## 5. 验证

**修复前**（stash 两个源文件，保留 fixture + 测试）：8 个测试 **6 个失败，925 个 issue**，
运行时路径展开 **892 行**。失败信息直接打印出环：

```
type repeats on one path:
  ValueSpec<String> → ReferenceSpec → Optional<ValueSpec<String>> → ValueSpec<String>
```

**修复后**：两个套件 8/8 通过，运行时路径降到几十行。全量
`swift test --skip IntegrationTests`：**1287 个测试 / 246 个套件**，唯一失败是
`SharedCacheTests.concurrentCallsForDifferentKeysRunInParallel`——时序 flaky
（断言并行耗时 < 0.8s，实测 0.8209s，超 2.6%；串行基准 1.6s，说明仍然是并行的），
与本次改动无关（未触及 `SharedCache`），单独重跑 3 次均通过（0.205s）。

## 6. 与计划的偏离

- 原计划只改运行时路径；排查中发现静态 `NestedFieldOffsetTree` 是同构缺陷（同样只有
  `guard depth < depthLimit`、同样不检查 `isIndirectCase`），按"修的是这一类不是这一个"
  一并纳入。
- 原计划为路径环守卫单独写测试，实际**做不到**：值类型的环只能经 indirect case，而
  indirect 守卫会先切断。已在设计文档里如实标注为"端到端覆盖、无独立测试"，未用人工
  hack 制造假覆盖。
- 开发期未升级依赖（核心修复不依赖它）；**合入 main 时被迫升级**。见下节。

## 7. 合入 main

rebase 到 `main`（`4eeb3b4`）：源码与文档全部干净合并（我改的位置与上游 PR #97 的
`Node.create`→`createTransient` 不重叠），冲突只在 59 个 ABI baseline 文件——两边都在
改同一批偏移。baseline 是 fixture 二进制的机械产物，因此不手工调和，而是重新生成。

**这一步暴露了一个必要前置**：`main` 依赖 swift-demangling node-store 迁移引入的
`NodeReference`，而本地 checkout 停在 `04c959b`（落后 45 个提交），`main` 在本地根本
编译不过，`regen-baselines` 直接失败。加之上游 `4eeb3b4` 也改过 fixture 源
（`GenericFieldLayout.swift`），fixture 必须重建、baseline 必须重算——所以升级
swift-demangling 不是可选的验证步骤，而是完成合并的前置条件。

处理：本地 swift-demangling 由 detached `04c959b` 切到 `main`（`985c9b7`，纯
fast-forward，工作区干净）。回退点 `04c959b1b5f2cc8c9baca522cd0fedabb45f73a0`。
**副作用**：RuntimeViewer 的 Debug workspace 也引用这份本地 checkout，其构建依赖随之
变化——不过这本来就是与 MachOSwiftSection `main` 一致的状态，升级前的组合（旧
demangling + 新 MachOSwiftSection）反而是不自洽的。

随后重建 fixture、重新生成 baseline（59 文件相对 main 96 增 96 删，逐行核对**全部**是
offset 类字段，非 offset 变化 0 行），全量测试通过。

## 8. 遗留

- **DAG（无环但高度共享）仍按路径展开**：真实类型图共享分支很浅，暂未观察到问题；若
  出现，正确解法是 memoization，与 2026-05-16 打印路径的方案同构。
- **静态路径 key 是打印类型名**：两个不同类型若打印出完全相同的全限定名会被误判为同一
  个。运行时路径按 metatype 指针，无此问题。
