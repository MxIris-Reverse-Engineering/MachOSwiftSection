# 2026-09-13 cache 里的 stub island，和不认识的指令不再被跳过

对应提案：[cache-stub-islands-and-unmodelled-instructions](../../Evolutions/0032-cache-stub-islands-and-unmodelled-instructions.md)（前五批见 [2026-09-11 首批](2026-09-11-offline-accessor-thunk-resolution.md)、[2026-09-11 收尾](2026-09-11-accessor-thunk-resolution-follow-up.md)、[2026-09-12 求值器](2026-09-12-thunk-type-construction-evaluation.md)、[2026-09-13 独立文件](2026-09-13-standalone-file-thunk-resolution.md)、[2026-09-13 合并 accessor](2026-09-13-merged-accessor-inline-evaluation.md)）。

## 问题

用户问「这会不会每个版本都不同，现在的实现能应对新版本么」。用最终的 release CLI 在归档卷上普查：macOS 14.7 / 15.0 / 15.5 / 26.0 / 26.3 / 26.6 的 SwiftUI 与 SwiftUICore 全部 0 未读（26.x SwiftUI 各 15–17 条分支注释，15.x 及更早没有这种 thunk），iOS 27 模拟器 cache 也是 0；**iOS 26.3.1 设备 cache（arm64e）** SwiftUI 7 未读、SwiftUICore 2 未读、0 条分支注释。用户在「换成完整的模拟执行」和「保留现有实现继续打补丁」之间选了后者。

## 调研

- 探针反汇编 iOS 设备 cache 上 `observedTasks` 与 `.tag` 的 thunk：每个跨镜像 `bl` 的目标都在 SwiftUI `__TEXT` 之外（`__TEXT` 结束于 `0x18d100fe0`，目标在 `0x18d13d000`–`0x18d149000`），代码是 `adrp x16 / add x16 / br x16`——stub island，目标直接算出来，什么都不读；也有读 GOT 槽的 `adrp x17 / add x17 / ldr x16, [x17] / braa` 型 stub，同样在镜像外。GOT 槽本身也合并在镜像外的一片区域（`0x1e5a3xxxx`，SwiftUI 的 `__DATA_CONST` 在 `0x1e6288a70`），但 cache 范围的偏移换算读得到。
- `CacheImageResolver.image(containing:)` 是「最大的不超过目标的镜像加载地址」，把这些镜像间区域归给前一个镜像；查它的 accessor 索引落空，无害。
- 本镜像内无符号的本地函数（`observedTasks` 的 `bl 0x18cb14e80`，剥了符号的专用 accessor `Mutex<Set<String>>`）靠上一批的跟进；它内部再 `bl` 一个合并函数体、`blraa x4` 调 libswiftCore 的 `Set` accessor、再经 stub 调 libswiftSynchronization 的 `Mutex` accessor。
- 能力标志 `_swift_runtimeSupportsNoncopyableTypes` 的 GOT 槽在 macOS 与 iOS 的 cache 文件里都是原始 0（弱引用由 dyld 加载时填）；求值器判定不了，靠两种策略，先跑的「条件为假」正好是支持那一支。

## 最终方案

见提案「方案」节。实施时比提案多改了三处，见下。

## 实际执行

1. **跳板识别对任何地址都做**。提案写的是「镜像外先查镜像表、查不到再试 island」，探针发现镜像外也有读 GOT 槽的 stub，于是 `resolveCallee` 重排为：本镜像内先查索引 / 本地符号，镜像外先查 cache 镜像表；都认不出就对该地址试 stub 形状（槽 → bind 或 rebase）再试 island 形状，目标经 `hopping` 再认一次（最多 8 跳），accessor 记在跳板地址名下。
2. **第一版把宿主 cache 整体搞退化了**（SwiftUI 17 未读、oracle 测试全红）：arm64e 每个函数尾声都是 `autibsp; eor x16, x30, x30, lsl #1; tbz x16, #62, Lret; brk`，「不认识的条件跳转就放弃」一到尾声就放弃。加了一条通用规则：条件跳转的直行落点是 `brk` 陷阱时按跳走处理（`ThunkOperation.trap`）。
3. **宿主 cache 的合并 accessor 字段又退化了一次**：arm64e thunk 是 `ldr x16, [got]; mov x17, #5129; pacia x16, x17; mov x3, x16`，「不认识的指令作废它写的寄存器」把 `pacia` 写的 x16 作废了。PAC 一家（`pacia` / `pacda` / `autia` / `autda` / `xpaci` / `xpacd` 及 `…z` 变体）建模为 `signOrAuthenticatePointer(register:)`，保值。
4. 归档 cache 测试对 SwiftUICore 两个字段只钉类型自身拼写：iOS 构建印成 `…Definition.Storage`，macOS 构建印成 `…Definition.(Storage in _DD01…)`。
5. 解码器测试里 `pacia` / `autda` 的编码第一次手抄错了（`DAD1` 应为 `DAC1`），Capstone 对非法编码返回空列表，测试因此立刻暴露。

## 验证

- **定向**：`swift test --filter '^SwiftThunkAnalysisTests\.'` 73 条 / 16 个套件全绿（退出码 0），含宿主 cache 门控与归档 iOS cache 门控的套件。新增：`CapstoneThunkDecoderTests`（条件跳转带目标、`brk`、PAC 保值、不认识的指令报写入寄存器、`b.ne` 跨过 `ret` 不截断函数）、`ThunkTypeEvaluatorTests` 三条（放弃、陷阱例外、作废寄存器 / 栈）、`AccessorThunkAnalyzerTests.refusesAThunkWhoseArmHasAnUnmodelledConditionalBranch`、`ArchivedIOSCacheThunkTests` 两条（SwiftUI 两个 `Mutex` 字段 + SwiftUICore 两个合并 accessor 字段；全部 witness 无未读且有分支注释）。
- **全量**：`swift test --skip '^IntegrationTests\.'` 1931 条 / 355 个套件，唯二红的是 `SharedCacheTests` 里按墙钟断言并行度的两条老 flaky（`differentKeysParallelViaTaskGroup` / `AsyncLet`，当时 CLI 验证批次正在并行占 CPU；单独复跑 9 条全绿）。本批的套件与快照套件全绿。
- **CLI 输出**（release 构建）：

| 二进制 | 落地前未读 | 现在 |
|---|---|---|
| iOS 26.3.1 设备 cache SwiftUI | 7（0 条注释） | 0（5 条注释，与 iOS 27 模拟器 cache 一致） |
| iOS 26.3.1 设备 cache SwiftUICore | 2 | 0（`StatefulMaterialProviderBox<A>.cache` → `Mutex<Optional<…Cache>>`、`MaterialBackdropProxy.Storage.data` → `Mutex<…Data>`） |
| macOS 27.0（`dyld_shared_cache_arm64e_x1`）SwiftUI / SwiftUICore | 未测过 | **打不开**：`Error: invalidCpuType`。这份 cache 的 magic 是 `dyld_v1arm64ex1`（新的 `arm64ex1` 架构串，16 字节里没有空格填充），header 的 mapping 偏移也从 0x228 涨到 0x238；MachOKit 的 `DyldCacheHeader._cpuType` 只认到 `dyld_v1  arm64e`。要在 MachOKit 里加这个 magic 才谈得上验证，本批不动它 |
| macOS 14.7–26.6 普查（11 份） | 全 0 | 全 0，与上一次普查的输出逐字节一致 |
| 七份标准输出（iOS 26.5 SwiftUI dump / interface、SwiftUICore、iOS 18.5、macOS 26.6.2 cache 两份、probe） | 与合并 accessor 那批一致 | 七份逐字节一致（第一次跑时脚本没给带空格的模拟器路径加引号，四份模拟器输出以退出码 64 报用法错误，加引号重跑后一致） |

## 偏差

- 提案的「先查镜像表再试 island」扩成「任何地址都认 stub 与 island」；提案没预见 `brk` 例外和 PAC 保值，两者都是宿主 cache 回归抓出来的。
- 提案写 `registerNamesAccessed.written`，实现用的是同一 API 的类型化版本 `registersAccessed.written`（加隐式写入表）。
