# 0032 - cache 里的 stub island，和不认识的指令不再被跳过

- **状态**: Implemented
- **创建日期**: 2026-09-13
- **最后更新**: 2026-09-14
- **所属愿景**: 无
- **关联提案**: [merged-accessor-inline-evaluation](0031-merged-accessor-inline-evaluation.md)（本提案从它切出）、[0029](0029-thunk-type-construction-evaluation.md)（求值器与解码器）
- **实现分支 / PR**: `feature/cache-stub-islands`，从 `feature/merged-accessor-inline-evaluation` 切出
- **配套文档**: [任务报告](../Internal/TaskReports/2026-09-13-cache-stub-islands.md)、[AccessorThunkResolutionExplained.md](../Internal/AccessorThunkResolutionExplained.md)

## 摘要

合并 accessor 那批做完后做了一次跨版本普查（macOS 14.7 / 15.0 / 15.5 / 26.0 / 26.3 / 26.6 与 iOS 27 模拟器 cache 全部 0 未读），唯一没过的是 **iOS 26.3.1 设备 cache（arm64e）**：SwiftUI 7 未读、SwiftUICore 2 未读、0 条分支注释。原因不在编译器而在 cache 布局：设备 cache 的跨镜像调用不经过 GOT 槽，`bl` 到镜像 `__TEXT` 之外的一段 **stub island**——

```asm
adrp x16, page
add  x16, x16, #imm
br   x16                    ; target computed, nothing loaded from a slot
```

island 不属于任何镜像，可能再链到下一个 island。`MachOThunkEnvironment.resolveCallee` 只认「从 GOT 槽 `ldr`」的 stub，镜像外地址又在 cache 的镜像表里查不到，于是每一次跨镜像调用都判 `.unknown`，凡是碰到的那一支都留占位。

用户在「换成完整的模拟执行」和「保留现有实现继续打补丁」之间选了后者。趁这次一起堵上求值器里两处「不认识就跳过」的隐患，它们是同一类问题（对新版本的指令形状没有诚实退路）：

1. **不认识的条件跳转被当成直行**。`b.cond`、`tbz` / `tbnz` 解码成 `.unmodelled`，求值器跳过它继续走，等于永远不跳。今天的 thunk 里没有，哪天编译器用了，那一支会读错而不是留占位。
2. **不认识的指令不作废它写的寄存器**。`ldr x0, [x8, x9]`（寄存器偏移）、`add x0, x8, x9, lsl #3` 这类解码成 `.unmodelled` 后，x0 里的旧值原样留着，可能一路被当成结果。

目标：iOS 26.3.1 设备 cache 的 SwiftUI / SwiftUICore 未读 7 / 2 → 0；其余所有输出逐字节不变；上面两类隐患变成诚实的放弃。

## 方案

### 1. stub island：算出来的跳转目标，认到底

位置：`Sources/SwiftThunkAnalysis/Resolution/MachOThunkEnvironment.swift` 的 `resolveCallee(at:)`。

- 新增 `stubIslandTarget(at:)`：解码目标处最多 4 条指令，形状必须是「若干 `adrp` / `add` 把地址算进一个寄存器，然后 `br` / `braa` 那个寄存器」，中间没有内存读、没有调用；用现成的 `ThunkRegisterTracker` 取 `br` 时寄存器里的地址。
- `resolveCallee` 的两处「否则未知」都改成：先试 island，认出来就对 island 的目标递归 `resolveCallee`（`islandHops` 参数，上限 8，防链式 island 打转）。镜像外的地址走「镜像表查不到 → 试 island」，镜像内的地址走「GOT stub 认不出 → 试 island」——本镜像里也可能有算地址而不读槽的 stub。
- 认出的 accessor 照旧记在 `accessorOriginsByAddress[调用地址]`，node builder 不用改。

### 2. 不认识的条件跳转：那一支放弃

位置：`Instructions/ThunkInstruction.swift`、`CapstoneThunkDecoder.swift`、`Analysis/ThunkTypeEvaluator.swift`、`AccessorThunkProgram.swift`。

- `ThunkOperation` 新增 `case conditionalBranchNotModelled(target: UInt64)`；解码器把带条件码的 `b.cond`、`bc.cond` 与 `tbz` / `tbnz` 归到它（`cbz` / `cbnz` 照旧建模）。
- `decodeFunction` 的函数边界规则把它当成条件跳转看待（目标在窗口内就把函数延伸过去），否则一个 `b.cond` 跳过 `ret` 的函数会被截断。
- 求值器遇到它：记一条新的 `ThunkAnalysisLimitation.conditionalBranchNotModelled(mnemonic:)`，这次运行到此为止（结果 `nil`，不算 `ret` 离开）。分析器现有规则会把带限制的 thunk 整个报成占位，和 `csel` 条件码不认识时一样。
- `ThunkRegisterTracker.apply` 对它什么都不做（它不写寄存器）。

### 3. 不认识的指令：作废它写的寄存器

- `ThunkOperation.unmodelled` 改成 `case unmodelled(writtenRegisters: [ThunkRegister])`，解码器从 Capstone 的寄存器访问表（`registerNamesAccessed.written`，`x0`–`x30` / `w0`–`w30` / `sp` / `fp` / `lr`）填进去；没有 detail 就空表。
- 求值器和 `ThunkRegisterTracker` 对 `.unmodelled` 作废这些寄存器；写了 `sp` 就作废整个栈模型。`pacibsp` / `autibsp` / `stlr` / `eor` 这类今天遇到的指令要么不写通用寄存器、要么写的寄存器后面用不到，行为不变。

### 4. 测试

- `CapstoneThunkDecoderTests`（新文件，真字节）：`b.ne` / `bc.eq` / `tbz` / `tbnz` 解码成 `conditionalBranchNotModelled` 并带目标；`ldr x0, [x8, x9]` 与 `add x0, x8, x9, lsl #3` 解码成 `unmodelled(writtenRegisters: [x0])`；`decodeFunction` 遇到跳过 `ret` 的 `b.ne` 不截断。
- `ThunkTypeEvaluatorTests`：不认识的条件跳转让运行放弃并记限制；不认识的指令作废目标寄存器（旧值不再当结果）；写 `sp` 作废栈。
- `AccessorThunkAnalyzerTests`：某一支含不认识的条件跳转时整个 thunk 报限制、无候选。
- 归档 cache 门控的 `ArchivedIOSCacheThunkTests`（`/Volumes/DyldSharedCaches/iOS/26.3.1/dyld_shared_cache_arm64e` 存在才跑）：SwiftUI 的 `BGTaskSchedulerWrapper.observedTasks` 读成 `Mutex<Set<String>>`，`Drag.LazyItem<A>.state` 读成 `Mutex<…State>`，SwiftUICore 两个合并 accessor 字段读成 `Mutex<…>`，全部 witness 无未读。
- 回归：定向套件、全量 `--skip '^IntegrationTests\.'`；release CLI 重跑 iOS 26.3.1 SwiftUI / SwiftUICore（目标 0 / 0）、七份标准输出与跨版本普查（全部逐字节不变）。

### 5. 文档

AGENTS.md 的 `SwiftThunkAnalysis` 条目加第六批一段；[AccessorThunkResolutionExplained.md](../Internal/AccessorThunkResolutionExplained.md) 第二步补 island、第一步补「不认识的指令怎么办」、已知降级表更新；ProjectEvolutionLog 新一节；任务报告；索引。README 与术语表不动。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-09-13 | Created as Draft，直接 In Progress | 用户在「完整模拟执行」与「保留实现继续打补丁」之间选了后者（「那还是保留之前的实现吧，继续打补丁」），补丁范围是上一轮回复里列的两项加一项同类隐患 |
| 2026-09-13 | island 按形状认（`adrp` / `add` 算地址后 `br`），不是让求值器跟进镜像外的任意代码 | 跟进镜像外的任意函数会走进 libswiftCore 的 runtime 内部，某条路径把实参原样返回就会给出一个真实但错误的类型；island 只是跳板，认形状够用且无此风险 |
| 2026-09-13 | 不认识的条件跳转是「放弃这一支」而不是「两种策略各跑一遍」 | 策略跑两遍的前提是知道哪一支对应什么条件；不认识的跳转连它测什么都不知道，两个答案里挑不出对的 |
| 2026-09-13 | `.unmodelled` 带上写入的寄存器表 | Capstone 的 detail 模式本来就给寄存器访问表；比逐条补指令语义便宜，且对未来任何指令都成立 |
| 2026-09-13 | 直行落点是 `brk` 的条件跳转按跳走处理 | 第一版对所有不认识的条件跳转一律放弃，宿主 cache 整体退化：arm64e 每个函数尾声都是 `autibsp; eor; tbz x16, #62, Lret; brk`，thunk 一到尾声就放弃。落到陷阱不是活着的程序会走的路，跳走是唯一路径，这条规则对任何 `brk` 落点都成立 |
| 2026-09-13 | PAC 指令（`pacia` / `autda` / `xpaci` 一家）建模为保值 | 「不认识的指令作废它写的寄存器」把 `pacia x16, x17` 写的 x16 作废了，而 arm64e thunk 正是先给 accessor 指针签名再 `mov x3, x16`，宿主 cache 的合并 accessor 字段因此退化。签过名的指针对我们仍是同一个指针 |
| 2026-09-13 | 「认跳板」对任何地址都做，stub 与 island 走同一条 `hopping` | 探针发现 iOS 设备 cache 里 SwiftUI 的跨镜像调用既有 island 也有读 GOT 槽的 stub，且都在镜像之外、GOT 槽也合并在镜像外；原来的 stub 识别只对镜像内地址做，镜像外一律 `.unknown` |
| 2026-09-13 | 归档 cache 测试对 SwiftUICore 两个字段只钉类型自身拼写 | iOS 构建把私有嵌套类型印成 `…Definition.Storage`，macOS 构建带判别符 `(Storage in _DD01…)`；两边都对 |
| 2026-09-13 | 能力标志槽为 0 的事实只记录不处理 | macOS 与 iOS 的 cache 文件里 `_swift_runtimeSupportsNoncopyableTypes` 的 GOT 槽都是原始 0（弱引用加载时才填），标志判定不了；「条件为假」先跑、正好是支持那一支，答案正确，第二次跑出的 `() + 8` 命不了名。改成读 cache 的 patch table 才能判定，不值得 |
| 2026-09-13 | macOS 27.0 的 cache（`dyld_shared_cache_arm64e_x1`）打不开，记录、不在本提案处理 | 用户让看这份新 cache。它的 magic 是 `dyld_v1arm64ex1`（新架构串 `arm64ex1`，16 字节 magic 里不再有空格填充），header 的 mapping 偏移 0x228 → 0x238。MachOKit 的 `DyldCacheHeader._cpuType` / `_cpuSubType` 按 magic 字面量查表，查不到就抛 `invalidCpuType`，连 header 都过不去。这是 MachOKit（兄弟仓库）的改动，得单独做；加了 magic 之后 subcache、镜像表、slide info 有没有新格式，要试了才知道 |
| 2026-09-14 | In Progress → Implemented | 四个分支按顺序合进 `next`（合并提交 `66ef730a`），落地时取编号 0032；用户指示「把相关分支全部合并进 next 推送，然后把分支删掉」 |
