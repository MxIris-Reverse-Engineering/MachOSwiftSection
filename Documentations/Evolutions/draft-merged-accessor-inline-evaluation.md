# Draft - 合并 accessor 的内联求值：求值器跟进本镜像内没名字的被调函数

- **状态**: In Progress
- **创建日期**: 2026-09-13
- **最后更新**: 2026-09-13
- **所属愿景**: 无
- **关联提案**: [standalone-file-thunk-resolution](draft-standalone-file-thunk-resolution.md)（本提案做它明确留下的 G3）、[0029](0029-thunk-type-construction-evaluation.md)（求值器本体）
- **实现分支 / PR**: `feature/merged-accessor-inline-evaluation`，从 `feature/standalone-file-thunk-resolution` 切出（依赖它的 `DependencyImageResolver`）
- **配套文档**: [任务报告](../Internal/TaskReports/2026-09-13-merged-accessor-inline-evaluation.md)、[AccessorThunkResolutionExplained.md](../Internal/AccessorThunkResolutionExplained.md)「被调函数没名字怎么办」一节

## 摘要

SwiftUICore 里还有两个 `Mutex` 字段读不出来：`PlatformAccessibilitySettingsDefinition.cache`（真实类型 `Mutex<PlatformAccessibilitySettingsDefinition.Storage>`）和 `NamedImage.Cache.data`（`Mutex<NamedImage.Cache.Data>`）。iOS 26.5 模拟器的独立文件和 macOS 26.6.2 的系统 cache 上都一样，与是否独立文件无关。

它们的 thunk 长这样（iOS 26.5 模拟器 SwiftUICore，`0x4db018`；另一个在 `0x55b160`，只差常量）：

```asm
ldr  x8, [got _swift_runtimeSupportsNoncopyableTypes]
cbz  x8, unsupported                 ; unsupported: return _$sytN + 8, i.e. ()
adrp/add x1, <lazy cache variable for Mutex<Storage>>
adrp/add x2, <metadata of Storage>   ; a struct, kind 0x200, descriptor one word after the kind
ldr  x3, [got libswiftSynchronization/_$s15Synchronization5MutexVMa]
mov  x0, #0
bl   _$sypSgMaTm                     ; the merged body
ret
```

`_$sypSgMaTm` 是编译器把一批「带缓存的单参数 accessor」折叠成的一个函数体：SwiftUICore 里这一个地址上挂着 122 个 `…MaTm` 符号，整个镜像 858 个这种符号对应 260 个函数体。函数体只做三件事：查 `[x1]` 缓存，没命中就 `blr x3`（x0 = request，x1 = x2），结果存回缓存。类型信息全在调用方的寄存器里，函数体自己一个字都不带，符号名 `Optional<Any>` 只是折叠前某一份的名字（上一批已经钉住绝不拿它当答案）。

现在的求值器遇到这个 `bl`：既不是 descriptor accessor、不是运行时入口、符号又被 `isConcreteTypeAccessorSymbol` 拒绝、也不是 stub，于是判 `.unknown`，x0 作废，最后留占位。三件事它做不到：跟进一个本镜像内没名字的被调函数；解码 `blr`；把从 GOT bind 槽读出来的函数指针当成「函数引用」放在寄存器里。

目标：求值器带着当前寄存器状态跟进这种被调函数（内联求值），上面三件事补齐。iOS 26.5 模拟器 SwiftUICore 未读 2 → 0，macOS 26.6.2 系统 cache SwiftUICore 2 → 0，其余输出逐字节不变。顺带覆盖剥掉本地符号后的 G2（带符号的专用 accessor 剥符号后就是「本镜像内没名字的被调函数」，跟进它的函数体照样能读）。

## 方案

### 1. 指令层：`blr` 解码成间接调用

位置：`Sources/SwiftThunkAnalysis/Instructions/ThunkInstruction.swift`、`CapstoneThunkDecoder.swift`。

- `ThunkOperation` 新增 `case indirectCall(register: ThunkRegister)`；解码器把 `blr` / `blraa` / `blrab` 归到它（和 `br` / `braa` / `brab` → `indirectBranch` 对称）。
- `decodeFunction` 的函数边界规则不变：间接调用会返回，不结束函数。
- `ThunkRegisterTracker.apply` 对 `.indirectCall` 和 `.call` 一样作废 x0–x17。

### 2. 求值器：函数引用、间接调用、内联求值

位置：`Sources/SwiftThunkAnalysis/Analysis/ThunkTypeEvaluator.swift`、`ThunkTypeExpression.swift`。

**函数引用是一种寄存器值。** `ThunkTypeEvaluator.Value` 新增 `case functionReference(ThunkCallee)`。从 GOT 槽加载（`ldr xN, [<adrp 出来的地址>, #k]`）的顺序改为：能力标志 → `environment.pointer(at:)` 有值就是 `.address`（rebase，cache 与本镜像内指针）→ 否则问 `environment.callee(boundInSlotAt:)`，不是 `.unknown` 就是 `.functionReference`（bind，独立文件的跨镜像函数指针）。`typeExpression(of:)` 对它返回 `nil`（它不是类型），`isZero` 返回 `false`（非空指针）。

**间接调用和间接跳转按寄存器里的值解。** `.indirectCall(register)`：寄存器是 `.functionReference(callee)` 就 `apply(callee:)`；是 `.address(target)` 就 `apply(environment.callee(at: target))`（cache 里 rebase 出来的外镜像地址）；其它一律 `apply(.unknown)`。都记一条 `CallSite`，`target` 为 `nil`。`.indirectBranch(register)` 同样解，解出来就是尾调用（`.left(resultType, throughReturn: false)`）；解不出来 `.left(nil, throughReturn: false)`——现在它返回的是 `x0` 里的类型，那是被跳转函数的第一个实参而不是答案，一并改掉。

**`CallSite.target` 改成 `UInt64?`。** 分析器的单查找回退多一个条件：那唯一一次调用必须有静态目标。间接调用永远进不了回退。

**内联求值。** `.call(target)` 或离开函数的 `.branch(target)` 遇到 `environment.callee(at:) == .unknown`、且 `environment.instructions(ofFunctionAt: target)` 给得出指令时，跟进：

- 新建一个子求值器：同一个环境、被调函数的指令、寄存器表整份复制、栈模型整份复制、`inlineDepth + 1`、`inlineStack` 加上这个入口地址。
- 子求值器先按父策略跑；结果为 `nil` 且它自己决定过某个条件（`decidedInstructionIndex != nil`）就换相反策略再跑一遍，取有结果的那次。这是分析器对无版本检查的 thunk 早就在用的规则（「缓存命中那支返回的东西没名字，未命中那支胜出」），只是下沉到被调函数一层：版本检查只会出现在 thunk 自身，被调函数里的条件只有缓存探测和能力标志。父求值器的 `decidedInstructionIndex` 不受子求值器影响。
- 子求值器以 `ret` 离开：父求值器把 x0 换成子求值器的 x0（整个 `Value`，见证表也能传回来），x1–x17 作废，x19–x28、sp 和栈模型保持父求值器调用前的样子（AAPCS64 由被调方保存恢复），`lastComparison` 清空；子求值器的 `callSites` 以父求值器这条 `bl` 的指令序号追加进来（回退规则要看整条路径上的调用次数，被调函数里的调用也算），`limitations` 追加。
- 子求值器以尾调用或间接跳转离开：父求值器视同这次调用的结果就是子求值器的结果，其余同上。子求值器没有离开（步数耗尽、跳到不认识的地址）：视同 `apply(.unknown)`。
- 尾调用形式（`.branch` 跟进）：父求值器直接以子求值器的结果和离开方式返回。
- 深度上限 3，入口地址已在 `inlineStack` 里就不再跟进（递归），每次运行各有自己的 1024 步上限。
- 分析器认出的可用性检查调用（`PlatformAvailabilityCheck.checkFunctionAddress`）绝不内联：它的结果必须保持未知，后面的 `cbz` 才能由策略决定。`ThunkTypeEvaluator.init` 多一个 `callTargetsLeftOpaque: Set<UInt64>` 参数，分析器把那个地址传进去。
- 现有行为不变的部分：写回式的 `stp` / `ldp`（`[sp, #-32]!`）仍然让栈模型作废；这只影响子求值器自己那份拷贝，父求值器的栈模型在返回时原样保留。合并函数体不建栈上实参缓冲，够用；要建的那天再模型化写回。

### 3. 环境：三条新问法

位置：`Sources/SwiftThunkAnalysis/Analysis/ThunkTypeExpression.swift` 的 `ThunkEvaluationEnvironment`、`Resolution/MachOThunkEnvironment.swift`。

- 协议新增 `callee(boundInSlotAt slotAddress: UInt64) -> ThunkCallee` 与 `instructions(ofFunctionAt address: UInt64) -> [ThunkInstruction]?`，都给协议扩展默认实现（`.unknown` / `nil`），`EmptyThunkEvaluationEnvironment` 和测试里的 tabled 环境不用改。
- `MachOThunkEnvironment.callee(boundInSlotAt:)`：槽位是 bind 就走现成的 `runtimeEntryPoint(named:)`，否则 `dependencyCallee(at: slotAddress, bindName:)`；按槽地址缓存。origin 表（`accessorOriginsByAddress`）用槽地址做键——它在 `__DATA_CONST` / `__AUTH_CONST`，和代码地址不会撞。
- `resolveCallee(at:)`：地址不在本镜像任何段里（cache 里 rebase 出来的外镜像地址）时改走 `foreignCallee(at:targetAddress:)`，而不是直接 `.unknown`。macOS cache 上那两个字段就靠这条。
- `instructions(ofFunctionAt:)`：地址在本镜像 `__TEXT` 里才解码，用和 `AccessorThunkReader` 一样的 `decodeFunction`（1024 字节窗口、`constructionMaximumInstructionCount`、同一个 `isKnownFunction`）；按地址缓存。
- `MetadataNaming` 不动：两个样本的实参 metadata 都是 struct（kind `0x200`，descriptor 在 kind 后一个字，现成的 `typeNodeFromMetadataRecord` 读得出）。class 实参照旧不命名，是 0028 起就有的限制。

### 4. 测试

- `ThunkTypeEvaluatorTests`（tabled 环境补 `callee(boundInSlotAt:)` 与 `instructions(ofFunctionAt:)` 两张表）：合成上面的 thunk 加合并函数体，期望 `.bound(accessorAddress: <槽地址>, typeArguments: [.constantMetadata(address: <x2>)])`；`blr` 到未知寄存器 → `nil`；被调函数里的调用算进 `callSites`，间接调用的 `target` 为 `nil`；递归入口不再跟进；深度到 3 停；可用性检查地址不内联；`indirectBranch` 解出函数引用时是尾调用、解不出时结果为 `nil`。
- `AccessorThunkAnalyzerTests`：一支只有一次间接调用并 `ret` 的臂不进回退（`branchIsNotASingleLookup`）。
- `SimulatorStandaloneSwiftUIThunkTests.aMergedAccessorsSymbolIsNotTakenForTheType` 改名并翻转断言：两个字段读成 `Synchronization.Mutex<SwiftUI.PlatformAccessibilitySettingsDefinition.(Storage in _DD012B99EE4F6885B033D7D23FEF69C0)>` 与 `Synchronization.Mutex<SwiftUI.NamedImage.Cache.(Data in _8E7DCD4CEB1ACDE07B249BFF4CBC75C0)>`。`ConcreteTypeAccessorSymbolTests` 三条拒绝保留：合并符号仍然不能当名字，答案是内联求值算出来的。
- 试着用当前工具链现场编译出 `…MaTm`（两个类型各带一个 `Mutex<本地 struct>` 字段，让两份 accessor 体相同、可被 LLVM 合并）。能编出来就进 `StandaloneFileThunkResolutionTests`，编不出来（上一批实测具体类型走 `__swift_instantiateConcreteTypeFromMangledNameV2`）就只靠合成序列加模拟器门控，任务报告记录结果。
- 回归：`swift test --skip '^IntegrationTests\.'` 全绿；fixture 快照基线不变；release CLI 对 iOS 26.5 模拟器 SwiftUI / SwiftUICore、iOS 18.5 SwiftUI、macOS 26.6.2 cache SwiftUI / SwiftUICore、probe 重跑，与上一批的输出 diff 只应出现那两个字段各两处（dump 与 interface 各一）的变化，SwiftUICore 未读 2 → 0（两边），其余逐字节一致。

### 5. 文档

AGENTS.md 的 `SwiftThunkAnalysis` 条目加第五批一段（G3 已做、内联规则、三个绝不：可用性检查不内联、递归不跟进、间接调用不进回退）；[AccessorThunkResolutionExplained.md](../Internal/AccessorThunkResolutionExplained.md) 第三步加「被调函数没名字怎么办」一段并补术语对照（`blr`、merged function）、已知降级里去掉 G3、代码地图更新；[ProjectEvolutionLog.md](../Internal/ProjectEvolutionLog.md) 新一节；任务报告；上一批提案的 G3 行与 AGENTS.md 里「G3 deliberately NOT done」的措辞改成指向本提案。README 与术语表不动（没有新开关，没有新造的词）。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-09-13 | Created as Draft | 用户在两条路（内联求值 / 读 lazy cache variable 的符号名）里选了第一条：「走第一个吧」 |
| 2026-09-13 | 不走符号名那条便宜路 | `…ML` 符号是本地符号，剥符号的第三方 app 里没有；内联求值不依赖符号，还顺带覆盖剥符号后的 G2 |
| 2026-09-13 | 被调函数里的条件由「哪一支给得出类型」决定，父策略只管 thunk 自身的条件 | 版本检查只在 thunk 里；被调函数里只有缓存探测和能力标志，缓存命中那支返回的是读不出来的缓存内容，未命中那支才构造类型。和分析器对无版本检查 thunk 的既有规则一致 |
| 2026-09-13 | 可用性检查的调用绝不内联 | 它的结果必须保持未知，后面的 `cbz` 才能由策略跑两次；内联进去只会把 libSystem 的版本查询也拖进来，结果还是未知 |
| 2026-09-13 | 间接调用不进单查找回退（`CallSite.target` 可空） | 回退要拿调用目标去查 accessor 索引，间接调用没有静态目标；宁可占位 |
| 2026-09-13 | origin 表用 GOT 槽地址给 bind 出来的 accessor 做键 | `ThunkTypeExpression.bound(accessorAddress:)` 需要一个能反查 descriptor 的键，bind 没有代码地址；槽地址在数据段，与代码地址不撞 |
| 2026-09-13 | 写回式栈访问仍不模型化 | 合并函数体不建栈上实参缓冲；父求值器的栈模型在返回时原样保留，子求值器作废自己那份拷贝不影响父。留到有样本需要时再做 |
| 2026-09-13 | class 实参仍不命名 | 两个样本的实参都是 struct，`MetadataNaming` 现成能读；class metadata 的 descriptor 位置不同，是 0028 起记录在案的限制，没有样本就不动 |
| 2026-09-13 | Accepted → In Progress | 用户批准（「开工」），含四个默认：上一批先提交后从它切分支、索引与文档在新分支同批补、验证口径同上一批、`…MaTm` fixture 只试不承诺 |
| 2026-09-13 | fixture 用 `-Xfrontend -disable-concrete-type-metadata-mangled-name-accessors` 造出合并 accessor，进 `MergedAccessorFixtureTests` | 直接编译三个 `Mutex<本地 struct>` 字段（`-O` / `-Osize`）得不到 `…MaTm`：当前工具链把具体类型走 mangled name 实例化，根本不生成惰性 accessor。关掉这个前端优化后三个同形的惰性 accessor 被合并成一份 `…MaTm`，`blr x3` 形状与 SwiftUICore 完全一致；落地前的 CLI 对它三个字段全是占位，带不带本地符号都一样。fixture 同时保留一份 `strip -x` 过的副本，钉「跟进不依赖符号」 |
| 2026-09-13 | `br` / `braa` 改按寄存器里的值解 | 原实现对 `indirectBranch` 返回 x0 里的类型，那是被跳转函数的第一个实参而不是答案；`.argumentBuffer` / 立即数恰好没有类型表达式所以没出过错，但和 `blr` 用同一套「看寄存器」的解法后顺手改正，`anIndirectBranchIsATailCallWhenTheRegisterIsKnown` 钉住 |
| 2026-09-13 | 「地址在不在本镜像」按段范围判断（`ThunkAddressSpace.containsAddress(_:)`），不再用 `offset(forAddress:)` 是否为 `nil` | 第一版在 macOS cache 上仍然 2 条未读：cache 镜像的偏移换算是一次减法，对整个 cache 的任何地址都给得出偏移，rebase 出来的 libswiftSynchronization 地址被当成本镜像地址查本镜像索引。这是 0028 记录的「几套账」之外又一个 cache 特有的坑，`HostCacheSwiftUICoreMergedAccessorTests` 钉住 |

