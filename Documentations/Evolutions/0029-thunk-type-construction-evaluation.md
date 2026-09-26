# 0029 - accessor thunk 的类型构造求值：离线解掉最后的 kind-9 引用

- **状态**: Implemented
- **创建日期**: 2026-09-12
- **最后更新**: 2026-09-12
- **所属愿景**: 无
- **关联提案**: [0028](0028-offline-opaque-accessor-thunk-resolution.md)（本提案是它的直接延续：0028 读的是「查表」形态的 thunk，本提案读「构造」形态）
- **实现分支 / PR**: `feature/accessor-thunk-resolution-follow-up`
- **配套文档**: [任务报告](../Internal/TaskReports/2026-09-12-thunk-type-construction-evaluation.md)、[AccessorFunctionReferenceRendering.md](../Internal/AccessorFunctionReferenceRendering.md)（层 3′）

## 摘要

0028 落地后 SwiftUI（macOS 26 共享缓存）全量 dump 里还剩 6 处未解析的 kind-9 accessor 引用：5 处关联类型 witness 指向同一个 thunk（`DefinesSearchCompletionModifier.Body`），1 处 field record（`Drag.LazyItem<A>.state`）。把这两个 thunk 的每一次调用都查出名字后发现，它们不是「读不懂的构造代码」，而是只用几种运行时入口写成的**类型构造程序**：调某个泛型类型的 metadata accessor（`$s…Ma`，实参来自参数缓冲区或上一次调用的结果）、调 `swift_getWitnessTable` 拿见证表、最后把结果返回。这些调用全部经过 dyld 缓存的 stub，stub 指向的槽位能解析出目标，而 accessor 的实参顺序就是被调类型的泛型签名顺序。所以不用执行，按指令顺序做**符号求值**——寄存器和栈槽里放「类型表达式」而不是数值——就能把每一支的结果写成 `ModifiedContent<参数0, _TagTraitWritingModifier<参数1>>` 这样的节点，再交给 0028 已有的实参替换管线。目标：SwiftUI 离线 6 → 0，并让 field record 里的 kind-9 走同一条路。

## 方案

**求值器**（`SwiftThunkAnalysis`；trait 已于 2026-09-12 撤销，见 0028 决策日志）：

- 指令词汇表补 `ldp` / `stp` / `str` / `ldur` / `stur`、`add x, sp, #k`、`retab` / `retaa`（视为返回，修掉现有解码器读过函数末尾的问题）、`br` / `braa`（视为尾调用）。`sp` 成为可跟踪的寄存器。
- 值域：`argument(k)`（参数缓冲区第 k 个词）、`constantMetadata(address)`（`adrp` / `add` 得到的 `…VN` 常量）、`bound(descriptor, [值])`（某 accessor 以若干实参调用的结果）、`witnessTable`、`stackAddress(k)`、`unknown`。调用 accessor 时实参按 x1–x3 取，超过三个从 x1 指向的栈缓冲区取；实参里的见证表按被调类型的泛型签名跳过，只留类型实参。
- 认识的被调方：同镜像的 metadata accessor（既有 `MetadataAccessorIndex`）；跨镜像的 accessor（stub → 槽位 → rebase 目标 → 用缓存的 image 表定位所属镜像 → 该镜像的 `MetadataAccessorIndex`）；非缓存文件的 bind 名（`_$s…Ma` 直接 demangle）；`swift_getWitnessTable`（产出见证表）；`__swift_instantiateConcreteTypeFromMangledNameV2`（直接读它指向的 mangled name）。其它调用一律不猜，只让那一支降级——0028 的三条「宁可不猜」原则不变，只是「多于一个 `bl`」不再是拒绝理由。
- 分支：有版本检查的沿用 0028 的分支切分，每支各自求值；没有版本检查的（field record 的 thunk 是「查缓存 → 未命中就构造」）先顺序求值到第一个返回，结果未知再从条件跳转的目标处求值。
- 结果转节点：`argument(k)` 按 thunk 主人的泛型上下文（参数在前、见证表在后，与 IRGen `enumerateGenericSignatureRequirements` 和 runtime 的实参布局一致）映射为第 `(depth, index)` 个泛型参数节点，由既有的 `OpaqueTypeGenericParameterRewriter` 替换；`bound` 按被调 descriptor 的父链逐层包 `boundGeneric*` 节点。为此 seam 多一个参数：thunk 主人的每层泛型参数个数。

**接线**：opaque witness 走既有 rewriter，不变；field record 在 `FieldRecord.demangledTypeNode(in:)` 和 `TypedDumper.fieldDemangledTypeNode(for:)` 两处接入同一个 rewriter（离线、resolver 已注册时），`argument(k)` 映射到所在类型的泛型参数，未特化 dump 直接打印 `A` / `B`。

**验证**：合成指令序列钉求值规则（两种分支形态、栈传参、未知调用、缓存查询形态、mangled name 形态）；SwiftUI 端到端要求三个 thunk 全部两支解出，`DefinesSearchCompletionModifier.Body` 的满足支与进程内 runtime 的答案逐字相等；fixture 的 `AccessorFunctionReferences` 命名空间钉 field record 离线解析（不随 OS 漂移）；渲染集成断言 SwiftUI 未读引用 5 → 0。

**未提问自定的假设**：跨镜像定位靠主缓存的 image 表按地址找镜像，只在 thunk 真的跨镜像调用时才打开那个镜像并建 accessor 索引；`swift_getWitnessTable` 等运行时入口按符号名认（bind 名或目标镜像的导出表），名单先只放 SwiftUI 实测用到的几个；class conformer / x86_64 仍不做。

## 落地

- `SwiftThunkAnalysis/Analysis/ThunkTypeExpression.swift`：类型表达式、被调方分类（`ThunkCallee`）、求值环境协议。
- `SwiftThunkAnalysis/Analysis/ThunkTypeEvaluator.swift`：求值器。跟踪寄存器与栈槽，照走控制流，能判定的条件直接判定，
  判定不了的按 `BranchPolicy` 决定并记下是哪条指令。
- `SwiftThunkAnalysis/Analysis/AccessorThunkAnalyzer.swift`：改为两次策略求值。有版本检查时两次结果就是两支，被决定的
  那条指令的种类（`cbz` / `cbnz` / `csel eq` / `csel ne`）说明哪次是满足支；没有版本检查时取第一次有结果的。求值为空的
  那一支退回 0028 的「唯一一次调用」读法，再不行记 `branchIsNotASingleLookup`。
- `SwiftThunkAnalysis/Resolution/MachOThunkEnvironment.swift`：被调方命名（同镜像 accessor 索引 → stub 解码 → bind 名 /
  rebase 目标 → 原始符号表 → 跨镜像）、槽位读取、`CacheImageResolver`。
- `SwiftThunkAnalysis/Resolution/ThunkTypeNodeBuilder.swift`：表达式转节点；`bound` 按被调 descriptor 的父链逐层包
  `boundGeneric*`，非 key 参数的链拒绝。
- 解码器：`ldp` / `stp` / `str` / `stur` / `ldur` / `sub` / `retab` / `retaa` / `br` / `braa`，`sp` 可跟踪，`isKnownFunction`
  谓词让到已知函数的前向 `b` 结束当前函数。
- seam：`AccessorThunkResolving.underlyingTypes(forAccessorThunkAt:in:ownerLayout:)`，`AccessorThunkOwnerLayout` 由
  opaque descriptor 或所在类型的泛型上下文构造。
- field record：`TypeDefinition.index` 与 `TypedDumper.fieldDemangledTypeNode(for:)` 经
  `Node.resolvingAccessorFunctionReferences(in:ownerLayout:)` 接入。

## 验证

- 合成指令序列（`ThunkTypeEvaluatorTests`，7 个）：accessor 链与尾调用、四实参栈缓冲、见证表跳过、未知被调方降级、
  命不了名的实参降级、缓存探测冷路径、常量 metadata 返回、mangled name 实例化。`AccessorThunkAnalyzerTests` 的
  `csel` 形态改成真实形态（`csel` 之后尾调用 accessor），并新增「尾调用不认识时不报选中值」。
- 真实框架（trait 开）：`AccessorThunkReaderTests` 三个 thunk 两支全解；`ConstructedThunkOracleTests` 对 SwiftUI 5 条
  非泛型 conformer 的 witness，离线满足支与进程内 runtime 的答案逐字相等（私有类型上下文的两种拼法归一后比较）；
  `OpaqueTypeRenderingIntegrationTests` 新增「每条引用都解出」（17 → 0）。
- fixture：`FieldRecordThunkResolutionTests`——`NoncopyableFieldHolderTest.resource` / `boxedInteger` 解到源码声明的
  类型，不注册 resolver 时保持占位。
- CLI：SwiftUI 全量 dump 未解析的 kind-9 引用 6 → 0；fixture dump 里 `case holding(NoncopyableResourceTest)`、
  `case boxed(NoncopyableGenericBoxTest<Swift.Int>)` 也随之出现。
- 回归：见决策日志末行。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-09-12 | Created as Draft | 用户要求「消除全部未解析的不透明类型」，0028 收尾后 SwiftUI 仍剩 6 处，全部来自「构造」形态的 thunk |
| 2026-09-12 | 范围：关联类型 + field record 一起做 | 用户选定。求值器一份，两侧只是接线不同；SwiftUI 那 1 处 field record 正好是同一形态 |
| 2026-09-12 | 用符号求值而不是模拟执行 | 探针把每次调用都查出名后确认：thunk 只用 metadata accessor、`swift_getWitnessTable`、mangled name 实例化三种入口，每一种的语义都是「类型层面」的，不需要真的算地址 |
| 2026-09-12 | 走轻量档 | 新 target 内的新能力，不改架构、不破坏 API（seam 多一个参数，实现方只有本仓库） |
| 2026-09-12 | 用户批准（范围：关联类型 + field record），进入 In Progress | 轻量档，一轮提问后点头 |
| 2026-09-12 | 求值器照走控制流、判定不了的条件按策略跑两遍，而不是切片求值 | 第一版按 0028 的分支切片求值，遇到 fixture 的缓存探测形态（`cbz` 命中缓存直接返回）和运行时能力标志的 `csel` 就没法表达；照走控制流后三种形态一套代码 |
| 2026-09-12 | 到未知被调方的尾调用结果为「未知」，不是当时 `x0` 里的值 | 第一版把 `x0` 里的地址当返回值，fixture 的 `b __swift_instantiateConcreteTypeFromMangledNameV2` 被读成返回缓存变量的地址——一个真实存在、但完全错误的 metadata。到已知函数的 `b` 才是尾调用，函数内的 `b` 是跳转 |
| 2026-09-12 | `csel` 形态改读尾调用，0028 的「两个操作数就是答案」作废 | 探针显示 `ResolvedMenuStyle.Body` 在 `csel` 之后 `b ModifiedContentVMa`，0028 报的 `…Static` 少了外层 `ModifiedContent<…>`；oracle 测试证实 |
| 2026-09-12 | 运行时能力标志（`_swift_runtimeSupportsNoncopyableTypes`）视为已置位 | 本分析面向的每个 runtime 都有该能力；另一支是给老 runtime 的替身类型，不是真实的备选 |
| 2026-09-12 | 镜像自身的运行时帮手按原始符号表认名 | `SymbolIndexStore` 故意只收 Swift 符号，`___swift_instantiateConcreteTypeFromMangledNameV2` 这类 C 符号查不到 |
| 2026-09-12 | oracle 比较归一私有类型上下文的拼法 | 描述符带私有判别符（`(Foo in _302179F1…).Static`），runtime 的 `_mangledTypeName` 只看到匿名上下文（`(unknown context at $…).Foo.Static`），同一个类型两种拼法 |
| 2026-09-12 | 测试里的 resolver 改为 task-local（`AccessorThunkResolution.taskResolver`），渲染层读 `effectiveResolver`，进程全局只留给 CLI | 它是进程全局状态，套件并行跑：先是一个套件的 `resolver = nil` 落在另一个套件解析中途（「装了 resolver」却读成未读），改用互斥键后又发现装上的 resolver 让并行跑的 fixture 快照套件把 kind-9 占位渲染成了真类型（`accessorFunctionReferencesSnapshot` / `interfaceSnapshot` 假红）。互斥只管自家套件，管不了别人的快照；task-local 把作用域收进设置它的那个测试 |
| 2026-09-12 | Implemented | 专项 43 个测试全绿；回归 trait 开 1350 测试 / 260 套件、trait 关 1259 测试 / 244 套件全绿（首轮 trait 开有 `FunctionTypeMetadataTests` 三条 `resolved → nil`，是已知的全量并行抖动，重跑绿）；fixture 快照零改动（resolver 不再进程全局注册后，快照套件不受影响）；SwiftUI 全量 dump 未解析 kind-9 引用 6 → 0，与上一批输出的 18 行差异全部是解出的引用与补全的外层类型。配套文档：任务报告、`AccessorFunctionReferenceRendering.md` 层 3′、AGENTS.md 条目、演进账本一节、术语表新增「type-construction evaluation」 |

