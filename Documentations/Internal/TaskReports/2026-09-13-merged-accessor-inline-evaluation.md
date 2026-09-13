# 2026-09-13 合并 accessor 的内联求值

对应提案：[merged-accessor-inline-evaluation](../../Evolutions/draft-merged-accessor-inline-evaluation.md)（独立文件那批留下的 G3；前四批见 [2026-09-11 首批](2026-09-11-offline-accessor-thunk-resolution.md)、[2026-09-11 收尾](2026-09-11-accessor-thunk-resolution-follow-up.md)、[2026-09-12 求值器](2026-09-12-thunk-type-construction-evaluation.md)、[2026-09-13 独立文件](2026-09-13-standalone-file-thunk-resolution.md)）。

## 问题

独立文件那批做完后用户问「剩下的 2 个是什么情况」。SwiftUICore 里 `PlatformAccessibilitySettingsDefinition.cache` 与 `NamedImage.Cache.data` 两个 `Mutex` 字段在 iOS 26.5 模拟器的独立文件和 macOS 26.6.2 的系统 cache 上都还是 `accessor function at N`。

## 调研

- 反汇编两个 thunk（iOS 26.5 SwiftUICore `0x4db018` / `0x55b160`）：`cbz _swift_runtimeSupportsNoncopyableTypes` 之后，x1 = lazy cache variable、x2 = 实参 metadata（`Storage` / `Data` 都是 struct，kind `0x200`）、x3 = GOT 里 bind 到 `libswiftSynchronization/_$s15Synchronization5MutexVMa` 的函数指针，然后 `bl _$sypSgMaTm`。
- `_$sypSgMaTm`（`0x18dc4`）是编译器合并出来的「查缓存、未命中就 `blr x3`（x0 = request，x1 = x2）、存回缓存」函数体，一个地址上挂 122 个 `…MaTm` 符号；整个 SwiftUICore 858 个这种符号对应 260 个函数体。类型信息全在调用方寄存器里，函数体自身一个字都不带，符号名 `Optional<Any>` 只是合并前某一份的名字（上一批已经钉住绝不拿它当答案）。
- x1 指向的 lazy cache variable 的本地符号名直接拼出完整类型（`lazy cache variable for type metadata for Mutex<…Storage>`），是一条便宜路，但剥符号的第三方 app 里没有。给用户两条路，用户选了跟进函数体。

## 最终方案

见提案「方案」节。要点：`blr` 解码成 `indirectCall`；从 GOT bind 槽读出来的值是 `Value.functionReference(callee)`；求值器对「认不出、但在本镜像 `__TEXT` 里」的调用目标开子求值器跟进，寄存器与栈整份复制，返回时只带回 x0、作废 x1–x17、父栈模型原样保留；子求值器先按父策略跑，没类型且判定过条件就换相反策略再跑一遍；可用性检查绝不跟进、递归不跟进、深度上限 3；`CallSite.target` 可空，经寄存器的调用不进单查找回退；cache 里 rebase 出来的外镜像地址走 `foreignCallee`。

## 实际执行

按方案落地。两处方案没写的：

1. **fixture 造得出来**。直接编译三个 `Mutex<本地 struct>` 字段（`-O` / `-Osize`）得不到 `…MaTm`，当前工具链把具体类型走 `__swift_instantiateConcreteTypeFromMangledNameV2`。加 `-Xfrontend -disable-concrete-type-metadata-mangled-name-accessors` 后三个同形的惰性 accessor 被优化器合并成一份 `_$sSo16os_unfair_lock_sVMaTm`，函数体 `blr x3`，与 SwiftUICore 完全一致。落地前的 release CLI 对它三个字段全是占位，带不带本地符号都一样；新代码两份都读成声明的类型。进 `MergedAccessorFixtureTests`，含一份 `strip -x` 的副本。
2. **`br` / `braa` 顺手改正**。原来对 `indirectBranch` 返回 x0 里的类型，那是被跳转函数的第一个实参；现在和 `blr` 一样按寄存器里的值解，解得出是尾调用，解不出结果为 `nil`。
3. **cache 上第一版没解出来**：CLI 对比 macOS cache 的 SwiftUICore 还是 2 条未读。原因是「地址在不在本镜像」判错了：cache 镜像的 `ThunkAddressSpace.offset(forAddress:)` 是一次减法，对整个 cache 里任何地址都给得出偏移，所以 x3 里 rebase 出来的 libswiftSynchronization 地址被当成本镜像地址去查本镜像的索引，全部落空。加了按段范围判断的 `containsAddress(_:)`，不在本镜像任何段里的地址走 `foreignCallee`（主 cache 的 image 表）。新增宿主 cache 门控的 `HostCacheSwiftUICoreMergedAccessorTests` 钉住（macOS 26 及以上），修前红。

## 验证

- **定向**：`swift test --filter '^SwiftThunkAnalysisTests\.'`，含模拟器门控的两个套件，全绿（退出码 0）。新增：`ThunkTypeEvaluatorTests` 七条（合成的合并函数体端到端、跟进返回后的寄存器状态与调用记录、经未知寄存器的调用、经已知地址的调用、`br` 尾调用 / 未知、可用性检查不跟进、递归与深度）、`AccessorThunkAnalyzerTests.refusesAnArmWhoseOnlyCallIsThroughARegister`、`MergedAccessorFixtureTests` 三条（fixture 确有合并符号且符号路线拒绝它、带符号读出三个字段、剥符号读出三个字段）；`SimulatorStandaloneSwiftUIThunkTests.aMergedAccessorIsReadThroughItsBody`（原 `aMergedAccessorsSymbolIsNotTakenForTheType` 翻转断言）两个字段读成 `Synchronization.Mutex<SwiftUI.PlatformAccessibilitySettingsDefinition.(Storage in _DD012B99EE4F6885B033D7D23FEF69C0)>` / `Synchronization.Mutex<SwiftUI.NamedImage.Cache.(Data in _8E7DCD4CEB1ACDE07B249BFF4CBC75C0)>`；宿主 cache 门控的 `HostCacheSwiftUICoreMergedAccessorTests`（macOS 26 及以上）对系统 cache 里的同两个字段只钉类型自身的拼写（私有判别符随构建变）。
- **全量**：`swift test --skip '^IntegrationTests\.'` 跑了两遍。第一遍（cache 地址修正之前）1919 条 / 352 个套件，唯三红的是 `FunctionTypeMetadataTests` 里并行全量时抖动的三条老 flaky（`thrownErrorTypeOffset` / `thrownErrorType` / `extendedFlags`，单独复跑 15 条全绿）；第二遍（最终代码）1920 条 / 353 个套件，唯二红的是 `SharedCacheTests` 里按墙钟断言并行度的两条老 flaky（`differentKeysParallelViaTaskGroup` / `AsyncLet`，单独复跑 9 条全绿）。两遍里本批的套件与快照套件全绿。
- **CLI 输出对比**（release 构建，与独立文件那批的同一份输出 diff）：

| 二进制 | 落地前未读 | 现在未读 | 变化 |
|---|---|---|---|
| iOS 26.5 模拟器 SwiftUICore | 2 | 0 | 只有那两行变了 |
| macOS 26.6.2 系统 cache SwiftUICore | 2 | 0 | 只有那两行变了（第一版还是 2，见「实际执行」第 3 条） |
| iOS 26.5 模拟器 SwiftUI（dump / interface） | 0 | 0 | 逐字节一致 |
| iOS 18.5 模拟器 SwiftUI | 0 | 0 | 逐字节一致 |
| macOS 26.6.2 系统 cache SwiftUI | 0 | 0 | 逐字节一致 |
| 现场编译的 probe（独立文件那批的） | 0 | 0 | 逐字节一致 |

- fixture 快照基线不变。

## 偏差

- 提案写「深度上限 3」「递归不跟进」「可用性检查不跟进」，全部照做；提案没预见 fixture 造得出来，也没预见 `br` 的顺手改正。
- 写回式栈访问仍不建模（提案如此）；子求值器的栈拷贝在它自己的 prologue 处作废，父求值器不受影响。
