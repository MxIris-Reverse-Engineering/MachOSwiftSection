# 2026-09-11 离线解析 accessor thunk 的收尾批次

对应提案：[0028](../../Evolutions/0028-offline-opaque-accessor-thunk-resolution.md)（同日第二批，提案原地续写）。
首批的过程见 [2026-09-11-offline-accessor-thunk-resolution.md](2026-09-11-offline-accessor-thunk-resolution.md)。

## 问题

首批把「当前系统那一支」接进了渲染，SwiftUI 的裸地址 17 → 5，但提案第 5 步只完成一半，「未做」一节
挂着三件事：模型里没有「另一支」的落位；不开 trait、或 thunk 读不出来时，那一行仍是
`opaque type symbolic reference 0x…`，周围的 `ModifiedContent<…>` 链和全部实参一起被丢掉；进程内
（`MachOImage`）路径完全没做。用户指着这一节说「还有下一步，没有完全做完」。

## 调研

- **裸地址是谁打出来的**：不是 kind-9 节点——`OpaqueTypeRewriter.visit` 在 underlying type 解出来不是
  `.type` 节点时整支放弃，返回原 `opaqueType` 节点，由上游 `NodePrinter.printOpaqueType` 打出描述符地址加
  ordinal，它的第三个子节点（实参列表）那两行是注释掉的。所以只要不放弃、让含 kind-9 的树照常走实参替换和
  嵌套展开，引用位置就会由层 0 那句 `accessor function at N` 兜底，实参也就回来了。
- **索引期投影的既有问题**：`SwiftDeclarationIndexer.resolvedWitnessProjections` 打印 witness 文本时从来没调
  `resolveOpaqueType`，任何 `some View` 的 witness 在 ABI 快照里都是 `opaque type symbolic reference 0x<描述符偏移>.0`；
  而 `MemberRecord.makeAssociatedTypeWitness` 把这段文本直接拼进 `assocwitness:` 的 payload key，偏移随构建变，
  两个 OS 版本之间每个 `Body` 都会被报成 `.modified`。提案说的「单值字段始终等于最新分支」要在模型里成立，
  投影就必须解析 opaque。用户裁定：解析。
- **进程内怎么调**：先写了个一次性探针（跑完即删）在 dlopen 进测试进程的 SwiftUI 上试。runtime 处理 kind-9
  的方式是 `swift_getTypeByMangledNode` 遇到根节点是 `AccessorFunctionReference` 就 `accessorFn(origArgumentVector)`，
  把调用方传进来的泛型实参指针原样交给 thunk——而 SwiftUI 的 thunk 第一条就是 `ldr x19, [x0]`，所以实参指针
  必须是真实的区，传 null 会当场崩。照 `swift_getAssociatedTypeWitnessSlow` 的做法：context 用 conforming type
  的 descriptor，实参用它 metadata 的泛型实参区（struct / enum 是 metadata + 16，仓库里
  `RuntimeFunctions.getTypeByMangledNameInContext(_:specializedFrom:in:)` 已经这么算）。探针结果：17 条里 5 条
  答出（全部是非泛型 conformer），12 条 runtime 对 conformer 本身就返回 nil（`Slider` / `Toggle` / `TextField` /
  `Picker` 等泛型 conformer，没有实参就没有 metadata），无一崩溃。答出的 5 条里有
  `DefinesSearchCompletionModifier.Body`——正是离线反汇编刻意不猜的那个 thunk。
- **上游 `Node.Rewriter` 的约束**：`visit` 对每个唯一节点实例只调一次，必须是纯变换。「按分支重渲染」因此
  不能在一次遍历里变着答，只能把选择固定下来整棵重跑。

## 最终方案

三个决策点问了用户一轮：范围（三件都做）、投影口径（解析 opaque）、回落文案（沿用 `accessor function at N`，
只恢复实参）。其余自定，记在提案决策日志。

- **模型**：`AssociatedTypeWitnessProjection.conditionalCandidates: [ConditionalWitnessCandidate]`，每支带
  `availability`（`PlatformAvailabilityCondition`，补了 `Codable`）、`candidateTypeText`（thunk 那一支的类型）、
  `substitutedTypeText`（整条 witness 按该分支替换后的全文）。两个文本都给，是因为宿主做「按版本切换」要的是
  全文、不该要求它知道 thunk 嵌在树的哪一层，而「到底哪一段在变」又只有候选类型能说清。解码用
  `decodeIfPresent` 容忍缺 key。
- **渲染层**：`AccessorFunctionReferenceRewriter` 多两个输入——`AccessorThunkBranchSelection`（thunk 偏移 →
  分支下标，缺省取 0 即当前系统那一支）与 `AccessorThunkCandidateLedger`（class，嵌套 rewriter 共写一本）。
  新入口 `Node.resolveOpaqueTypeCollectingConditionalCandidates(in:)` 先按默认跑一遍记账，再对每个非默认分支
  用 `[thunkOffset: index]` 的选择重跑一遍拿全文。同一个 thunk 在一棵树里出现两次（`StaticIf` 的两臂）按
  偏移当一个 thunk 处理，两处一起换——这是对的，同一个 thunk 只有一个答案。
- **回落**：`underlyingTypeContent(of:)` 三分：resolver 改写过的直接用；`.type` 信封剥掉；含 kind-9 的非
  `.type` 树原样保留。其它非 `.type` 形状（如 extended existential shape 引用）维持原来的放弃，不扩大改动面。
- **进程内**：`InProcessAccessorFunctionResolution.witnessNode(witnessMangledName:conformingTypeName:in:)`，
  按上面的调用形状走，`_mangledTypeName` → `demangleAsNodeTransient` 回读；`_mangledTypeName` 是 macOS 11 API，
  与 `RuntimeFieldLayoutBackend` 同样用 `#available` 门控。三个 witness 调用点（dump / interface / 索引）统一改走
  `Node.resolveOpaqueType(witnessMangledName:conformingTypeName:in:)`，离线时它就是原来的 `resolveOpaqueType(in:)`。
  class conformer 不接：泛型实参偏移不是常数，且没有实测样本。
- **`Package.swift`**：`SwiftIndexing` 显式声明对 `SwiftDeclarationRendering` 的依赖（此前靠传递可见，
  PR #121 审查的 F 条已经栽过一次）。

## 验证

- 单测：`AccessorFunctionReferenceRewriterTests`（5 个，桌面 resolver 钉默认分支 / 按选择 / 记账 / 读不出保留 /
  越界选择保留）、`AssociatedTypeWitnessProjectionTests`（3 个，Codable 往返与缺 key 解码）。
- 真实框架：`OpaqueTypeRenderingIntegrationTests`（trait 开）改写——未读引用 17 → 5、不注册 resolver 时引用
  留在类型里而非抹掉整行、候选入口对 `FeedbackGenerator.Body` 给出 `≥ 26.4` / `< 26.4` 两份不同全文且首份等于
  单值渲染；`InProcessAccessorFunctionResolutionTests`（不依赖 trait，dlopen SwiftUI）——runtime 答出 ≥ 1 条且
  无残留引用、泛型 conformer 原样保留、候选入口与单值入口在进程内一致且候选为空。
- 回归：见文末「测试结果」。
- CLI A/B：见文末。

## 与计划的偏差

- 进程内路径原计划放在 rewriter 的 `MachOImage` 分支里、只对无泛型参数的 opaque 上下文走 runtime。探针
  证明 thunk 要读实参缓冲，而 rewriter 手里只有 opaque descriptor、没有 conforming type，凑不出 runtime 要的
  那块区；于是改到三个 witness 调用点（它们手里有 `conformingTypeName`），门控也从「opaque 上下文无泛型参数」
  改成「conforming type 能不带实参实例化」——判据更直接，且与 runtime 自己的做法一致。
- 提案初稿的「回落文案换成说人话」按用户裁定不做，只恢复实参。

## 测试结果

- 专项：`AccessorFunctionReferenceRewriterTests` 5 / `AssociatedTypeWitnessProjectionTests` 3 /
  `OpaqueTypeRenderingIntegrationTests` 3 / `InProcessAccessorFunctionResolutionTests` 3，共 14 个全绿。
- 回归（trait 开，`SwiftInterfaceTests` + `SwiftDumpTests` + `SwiftDiffingTests` + `SwiftIndexingTests` +
  `SwiftPrintingTests` + `SwiftDeclarationRenderingTests` + `SwiftThunkAnalysisTests` + `SwiftSectionCommandTests`）：
  506 个测试 / 81 个套件全绿；快照基线零改动——fixture 里没有 availability-conditional 的 opaque 类型，
  投影解析 opaque 也没有改变任何 fixture witness 的文本。
- 回归（trait 关，另开 scratch 全量重编，`SwiftInterfaceTests` + `SwiftDumpTests` + `SwiftDiffingTests` +
  `SwiftIndexingTests` + `SwiftDeclarationRenderingTests` + `SwiftThunkAnalysisTests`）：428 个测试 / 68 个套件全绿。

## CLI A/B（SwiftUI，macOS 26 系统共享缓存，`dump -s associatedTypes`，两侧都开 trait）

基线是 `next`（`217f6d94`）在独立 scratch 里编的 `swift-section`，候选是本分支。两份输出各 12699 行，
`diff` 恰好 5 行；把基线里的 `opaque type symbolic reference 0x36EBA0F8.0` 原位替换成
`accessor function at 898926264` 后与候选**逐字节一致**——也就是说除了这 5 处引用不再抹掉整棵树以外，
输出没有任何别的变化。候选侧 `opaque type symbolic reference` 计数 5 → 0，`accessor function at` 0 → 5。

代表性的一行（`OutlinePrimitive` 系的 `Body`）：

```
- typealias Body = SwiftUI._ConditionalContent<SwiftUI._ConditionalContent<opaque type symbolic reference 0x36EBA0F8.0, opaque type symbolic reference 0x36EBA0F8.0>, SwiftUI._ConditionalContent<SwiftUI.ForEach<A, B, …
+ typealias Body = SwiftUI._ConditionalContent<SwiftUI._ConditionalContent<accessor function at 898926264, accessor function at 898926264>, SwiftUI._ConditionalContent<SwiftUI.ForEach<A, B, …
```
