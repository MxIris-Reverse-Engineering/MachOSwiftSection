# 0002 - 声明模型 descriptor 化：TypeDefinition / ExtensionDefinition / ProtocolDefinition 不再驻留急切解析的胖 wrapper

- **状态**: In Review
- **作者**: JH
- **创建日期**: 2026-08-09
- **最后更新**: 2026-08-09
- **所属愿景**: 无
- **关联提案**: [0001](0001-symbol-name-offsetization.md)（方法论同构：「驻留只留定位信息，重内容按需物化」；其落地记录里 RV 复测的落地后堆格局是本案的立项输入）
- **实现分支 / PR**: `feature/node-store-migration`（拟，待批准后实施）
- **配套文档**: 先行账本 [DeclarationModelMemoryFootprint.md](../Internal/DeclarationModelMemoryFootprint.md)（2026-07-25 逐属性量测——本案的精确数字来源；其「当前不建议实施」结论的前提已被 0001 消解，见「前期调研」）；落地时按收尾判断决定是否另写实现说明

## 摘要

0001 落地后 RuntimeViewer 五镜像 322 MB 稳态的堆格局里，新头部是两个同根的簇：`SwiftDeclaration` 声明模型 41.3 MiB（`ExtensionDefinition` 28,225 × 640 B ≈ 17.2、`TypeDefinition` 11,985 × 1272 B ≈ 14.6）与 MachOSwiftSection 解析结构 33.4 MiB（`ProtocolConformance` 的 `[ResilientWitness]` 等 trailing 数组 20.6 打头）。根源是同一个模式：声明模型在**模型构建期**就把 MachOSwiftSection 的高层 wrapper（`TypeContextWrapper`、`ProtocolConformance`、`Protocol`）连 trailing objects 一起急切解析并**终身驻留**，而其中的重载部分只有惰性 `index(in:)`（和少量打印路径）才消费——RV 稳态里绝大多数定义从未被索引，这些解析产物为「将来可能被点开」白白常驻。

本案把三处驻留换成小的 descriptor 引用（几十字节级），trailing 解析改为在 `index()` / 打印期**临时物化、用完即弃**。预估稳态再省 30–45 MiB。

## 动机

- **实测数字**（RV 2026-08-08/09 复测，详见 0001 落地记录；每实例构成见先行账本 [DeclarationModelMemoryFootprint.md](../Internal/DeclarationModelMemoryFootprint.md)，`class_getInstanceSize` 精确量测）：`TypeDefinition` 每实例 **1272 B**，其中 `type: TypeContextWrapper` 472 + `parentContext: ParentContext?` 472 = **944 B，占 74%**；`ExtensionDefinition` 640 B（账本时期 520，此后随 conformance attribution 字段增长）。两类合计 31.8 MiB 内联块，另拖着 MachOSwiftSection 簇 33.4 MiB 的 trailing 堆数组。
- **驻留点一：`TypeDefinition.type: TypeContextWrapper`**（`Sources/SwiftDeclaration/Components/Definitions/TypeDefinition.swift:22`）。这是内联 enum，按最大 case `Class` 定尺 472 B——**struct / enum 的定义也照 472 付费**；`Class` 档 17 个存储属性（其中 `TypeGenericContext?` 一项 160 B，绝大多数类型存的是 nil）+ 5 条堆数组（`methodDescriptors`、`methodOverrideDescriptors` 等，`Sources/MachOSwiftSection/Models/Type/Class/Class.swift:30-47`），构造函数把 trailing objects 全部读进堆。更糟的是 `parentContext` 的 `case type(TypeContextWrapper)` **再内联一份** 472 B——且账本的全库读写点追踪证实它**在索引函数返回后再无任何消费者**（写与读都在 `SwiftDeclarationIndexer` 同一个函数里，读只为取一次父类型名）。
- **驻留点二：`ExtensionDefinition.protocolConformance: ProtocolConformance?`**（`ExtensionDefinition.swift:16`）。`ProtocolConformance` 构造即读 protocol 解析、type reference、witness table pattern、conditional requirements、**`resilientWitnesses: [ResilientWitness]`**（`Models/ProtocolConformance/ProtocolConformance.swift:45-132`）——最后这项就是 MachOSwiftSection 簇 20.6 MiB 的打头项。
- **驻留点三：`ProtocolDefinition.protocol: MachOSwiftSection.Protocol`**（`ProtocolDefinition.swift:74`）。`Protocol` 驻留 `requirementInSignatures: [GenericRequirement]` + `requirements: [ProtocolRequirement]` 两条堆数组。协议人口比类型小，但同一模式。
- **关键事实：`index(in:)` 是惰性的。** 触发点在打印器（`SwiftPrinting/SwiftDeclarationPrinter.swift:110/159/200/294`，另有 SwiftInterface 的 diff 渲染路径）——用户查看到哪个声明，哪个才被索引。RV 稳态下绝大多数定义 `isIndexed == false`，胖 wrapper 里的 vtable 描述符、resilient witnesses、protocol requirements 从未被读过第二次。
- 与 0001 的关系：0001 把「49 万个符号名 String」换成字符串表引用按需物化；本案把「4 万个声明的解析产物」换成 descriptor 引用按需物化。同一方法论在堆格局新头部上的第二次应用。
- **与先行账本结论的关系**：账本（2026-07-25）当年的裁决是「当前不建议实施」，前提有二——彼时这条线只占 434 MB 的 8–10%，且其余 90% 未剖析。两个前提如今都已消解：其余大头已经 0001（符号名 68.7 MiB）与两次专项清退（`SharedNodeStore` 合并、`MetadataReaderCache` 换持）逐一处理，RV 全景剖析（malloc 归属）也已做过两轮，声明模型如今**就是**堆内头部。账本四项里的 3a（mini-store 增殖）/ 3b（`MetadataReaderCache`）已分别落地，1（`parentContext`）/ 2（wrapper 装箱）由本案以更优形态收编（见「替代方案考量」）。

## 前期调研

### 现状代码怎么走的

- **模型构建**：`SwiftDeclarationIndexer` 的 sweep 为每个 type descriptor 构造完整 wrapper 并传入 `TypeDefinition(type:in:)`；conformance 一侧先 `machO.swift.protocolConformances` 全量物化成数组、按类型名分组（`SwiftDeclarationIndexer.swift:243/515-539`），再逐个塞进 `ExtensionDefinition(… protocolConformance: …)` 驻留。
- **索引消费（惰性，每定义至多一次）**：`TypeDefinition.index()` 以 `case .class(let cls)` 读 `methodDescriptors` / `vTableDescriptorHeader` / `methodOverrideDescriptors` / `methodDefaultOverrideDescriptors` 构建 vtable/override 查找表（`TypeDefinition.swift:205-270`）；`ExtensionDefinition.index()` 消费 `protocolConformance.resilientWitnesses`（`ExtensionDefinition.swift:95-141`）；`ProtocolDefinition.index()` 消费 `requirements`。
- **打印消费（每次打印该定义）**：
  - 表头与成员打印读 `.type` 的 descriptor 级事实（kind、`contextDescriptorWrapper`）；
  - `FieldLayoutRenderer(type: typeDefinition.type, …)` 与字段记录再读（`SwiftDeclarationPrinter+Headers.swift:327-328`）；
  - 扩展头打印读 `protocolConformance.protocolNode(in:)` 与 `.globalActorReference`（`SwiftDeclarationPrinter.swift:246-262`）。
- **消费点普查（库内）**：`.type` 约 30 处——SwiftSpecialization 11（`GenericSpecializer` / `ConformanceProvider` / `TypeDefinition+Specialization`）、SwiftPrinting 8、SwiftInterface 4、SwiftIndexing 3、SwiftDeclarationRendering 4；`.protocolConformance` 打印 1 处 + `index()` 自用；`.protocol` 集中在协议打印与 SwiftDiffing 的 requirement 投影（后者在 `index()` 期冻结成 Mach-O-free 值，不受本案影响）。

### 验证过什么

- **惰性确认**：`index(in:)` 的全部调用点都在打印/渲染路径（grep 全库），索引器 sweep 不调用——「稳态未索引即胖结构未消费」成立。
- **descriptor 可再物化**：全部三个 wrapper 都能由 descriptor 重建，且入口现成——`TypeContextWrapper.forTypeContextDescriptorWrapper(_:in:)`（`TypeContextWrapper.swift:50`）、`ProtocolConformance(descriptor:in:)`、`Protocol(descriptor:in:)` 正是今天模型构建期走的构造路径。物化成本 = 一次 trailing objects 顺序解析（`MachOImage` 是映射内存指针步进，`MachOFile` 是页缓存友好的文件读）——与今天模型构建期完全相同的工作量，只是从「每声明一次、永久驻留」变为「用时一次、即弃」。
- **descriptor 体积**：`ClassDescriptor` 等 = raw layout（十几个 32 位字段）+ offset，内联 ~64 B 级；`TypeContextDescriptorWrapper` 是三档 descriptor 的 enum，同量级。对比被替换的 wrapper 内联 ~300–500 B + 堆数组，一个量级的差距。
- **尚未验证（落地步骤补）**：下游仓库（RuntimeViewer / MachOKitUI / SymbolViewer）是否直接消费 `.type` / `.protocolConformance` / `.protocol`——落地第一步做下游普查（RV 侧可请对面会话代查）。

## 提议方案

1. **`TypeDefinition`**：存 `typeContextDescriptorWrapper: TypeContextDescriptorWrapper`（替代 `type: TypeContextWrapper`）。`parentContext` 首选**降级为索引期局部载体**（账本证实索引函数返回后零消费者——写读都在 `SwiftDeclarationIndexer` 一个函数里，用局部结构承载、函数返回即释放，存储属性整个移除）；若落地第一步的下游普查发现真实消费者，则退而把 `case type` 载荷换成 descriptor 形态保留属性。新增 `materializedTypeContext(in:) throws -> TypeContextWrapper` 按需物化入口；`index()` 在函数体开头物化一次、以局部变量贯穿全程。
2. **`ExtensionDefinition`**：存 `protocolConformanceDescriptor: ProtocolConformanceDescriptor?`（替代 `protocolConformance: ProtocolConformance?`）；`index()` 与扩展头打印各自临时物化。
3. **`ProtocolDefinition`**：存 `protocolDescriptor: ProtocolDescriptor`（替代 `protocol: MachOSwiftSection.Protocol`；名字早已冻结在 `protocolName`，不受影响）；`index()` 临时物化取 requirements。
4. **物化纪律**：每「处理一个定义」（索引它 / 打印它 / specialize 它）至多物化一次，物化结果以局部变量或函数参数贯穿，**不做 per-access 计算属性**——防止打印循环里反复触发全套 trailing 解析。

### 非目标

- **`[UInt32]` 行号桶扁平化**：另案 [0003](0003-symbol-row-bucket-flattening.md)，两案不重叠（不同簇、不同模块）。
- **StringStorage 残余 31.3 MiB 的成分治理**（member 分类索引的 String 键、字段名、打印名等混合人口）：成分未明，等 RV 侧 malloc_history 切片再议，不盲做。
- **SwiftDump 路径（`TypedDumper` 等）**：本就 per-dump 临时构造 wrapper、无驻留，不动。
- **MachOSwiftSection wrapper 类型本身**：`Class` / `Struct` / `Enum` / `ProtocolConformance` / `Protocol` 保持「构造即完整解析」的值语义——它们是解析结果的正确表达，问题只在**声明模型驻留它们**，不在它们自身。
- **成员数组与 `orderedMembers` 的表示**：索引后才产生的人口，规模由用户实际浏览量决定，与本案无关。
- **`metadata: MetadataWrapper?` 与 specialized 定义**：specialize 路径持 runtime metadata 指针，本就轻量，不动。

## 详细设计

### 存储形态对照

| 位置 | 现状（驻留） | 提案后（驻留） | 重内容去向 |
|---|---|---|---|
| `TypeDefinition.type` | `TypeContextWrapper`（内联 472 B + trailing 堆数组） | `TypeContextDescriptorWrapper`（~60 B 级：`ClassDescriptor` raw layout 52 B + enum tag） | `index()` / 打印期临时物化 |
| `TypeDefinition.parentContext` | `case type(TypeContextWrapper)` 再内联 472 B | **移除**（降级为索引期局部载体；下游普查有消费者则退为 descriptor 载荷保留） | 索引函数返回即释放 |
| `ExtensionDefinition.protocolConformance` | `ProtocolConformance?`（内联 ~250–300 B + `[ResilientWitness]` 等堆数组） | `ProtocolConformanceDescriptor?` | `index()` / 扩展头打印临时物化 |
| `ProtocolDefinition.protocol` | `Protocol`（含 2 条 requirements 堆数组） | `ProtocolDescriptor` | `index()` 临时物化 |

预期实例尺寸（按账本逐属性账目推算，落地时以同款探针复量为准）：`TypeDefinition` 1272 → **~400 B**（−944 的两份 wrapper，+~60 的 descriptor wrapper），11,985 实例 ≈ 14.6 → ~4.6 MiB；`ExtensionDefinition` 640 → ~400 B，28,225 实例 ≈ 17.2 → ~10.8 MiB；另加 MachOSwiftSection 簇 33.4 MiB 中 trailing 数组（`[ResilientWitness]` 20.6 打头）的大部释放。

### 物化接口

```swift
extension TypeDefinition {
    public func materializedTypeContext<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> TypeContextWrapper
}
extension ExtensionDefinition {
    public func materializedProtocolConformance<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> ProtocolConformance?
}
extension ProtocolDefinition {
    public func materializedProtocol<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> MachOSwiftSection.Protocol
}
```

三者都是薄封装（转调现成的 `forTypeContextDescriptorWrapper` / `ProtocolConformance(descriptor:in:)` / `Protocol(descriptor:in:)`），throws 语义与今天模型构建期相同。

### 构造路径

- 索引器 sweep 今天就持有完整 wrapper（要用它派生 `typeName`）：`TypeDefinition` 的 init 继续收 wrapper，**内部只存其 `typeContextDescriptorWrapper`**——sweep 的解析工作量不变，变化只是解析产物在 init 返回后即可释放。
- conformance 一侧：indexer 的全量 `protocolConformances` 数组在分组、构造 `ExtensionDefinition` 之后本就出栈；本案后 `ExtensionDefinition` 只留 descriptor，整批 `[ResilientWitness]` 随之释放。
- specialized 定义（`specialize(with:in:)` 派生）同样只存 descriptor；`isSpecialized` / `metadata` 语义不变。

### 消费点迁移（库内 ~30 处）

两类机械迁移：

- **读 descriptor 级事实**（kind 判断、`contextDescriptorWrapper`、offset）：直接改读新属性，零物化。约占一半。
- **读 trailing 内容**（vtable 表、requirements、witnesses、genericContext、`FieldLayoutRenderer(type:)` 传参）：在所属函数入口物化一次、局部贯穿。集中在 `TypeDefinition.index()`、`ExtensionDefinition.index()`、`ProtocolDefinition.index()`、打印器的 header/字段渲染入口、`GenericSpecializer` 的 specialize 入口。

`FieldLayoutRenderer` 等接收 `TypeContextWrapper` 的既有签名**不改**——调用方物化后传入。

### 风险与接受的约束

- **物化 CPU**：索引/打印一个定义多付一次 trailing 解析（顺序读 + 几次小数组分配）。打印本身要做成体量大得多的 demangle + node print，解析占比预期为噪声级；渲染 A/B 的 wall-clock 持平是验收线。CLI 的 `interface` 全量打印会为每个类型物化一次——与今天模型构建期的一次性全量解析**总量相同**，只是时点后移。
- **物化生命周期**：descriptor 再物化要求 `machO` 存活——与 0001 mapped 名字同一条生命周期约束（RV 的索引对象从不卸载），且声明模型本就处处以 `in machO:` 参数工作，无新增约束面。
- **API 破坏**：三个 public 属性换形态（见「影响」）。下游若直接消费需机械迁移；先普查再动手。

## 替代方案考量

- **`indirect` enum 装箱 `TypeContextWrapper`**（账本第 2 项，当年估实例 → 344 B / 省 ~12.6 MB）：只省内联不省堆——trailing 数组照旧驻留，MachOSwiftSection 簇 33.4 MiB 分文不动，且装箱让全库按值传递的 wrapper 背上引用计数流量（账本自己标注的吞吐风险）。descriptor 化拿到同量级内联收益（~400 B vs 344 B）**外加**整个 trailing 簇，无 ARC 代价。被否。
- **`parentContext` 换 descriptor 载荷保留属性**（账本第 1 项的另一半改法）：账本已证实索引后零消费者——为一个没有读者的属性保留任何形态都是浪费；首选整个移除、降级为索引期局部载体，descriptor 载荷仅作下游普查发现真实消费者时的退路。
- **计算属性 per-access 物化、保住 `.type` API 原样**：每次属性访问都触发全套 trailing 解析，打印循环里不可控地反复付费；显式 `materialized…(in:)` 让成本出现在调用方眼前、强制局部贯穿。被否。
- **`index()` 完成后把胖字段置 nil、API 不变**：`isIndexed` 之后 `.type` 语义变成「阶段依赖可空」，比直接换 descriptor 更伤下游（且稳态里未索引定义占大头，收益反而小）。被否。
- **只做 `ExtensionDefinition`（最大簇）**：同一模式修一半，`TypeDefinition` 的 1.25 KB × 12k 与 `parentContext` 双份内联原样留下，下次还得再来一轮 API 破坏。被否——一次修完这一类。
- **把 wrapper 改成惰性解析（存 descriptor、trailing 属性按需读）**：改动落在 MachOSwiftSection 的 15+ 个 wrapper 类型上，波及 fixture 基线套件全量，且「解析结果值类型」的语义被打破（`private(set) var` 全变计算）；声明模型侧收敛改动面等价拿到同一收益。被否。

## 影响

### 源码兼容性（source compatibility）

**破坏性变更**，三个 public 存储属性换形态：

- `TypeDefinition.type: TypeContextWrapper` → `typeContextDescriptorWrapper: TypeContextDescriptorWrapper` + `materializedTypeContext(in:)`
- `TypeDefinition.parentContext`（含 `ParentContext` 类型本身）：首选整体移除（降级为索引期局部载体）；下游普查有消费者则退为 descriptor 载荷保留
- `ExtensionDefinition.protocolConformance: ProtocolConformance?` → `protocolConformanceDescriptor: ProtocolConformanceDescriptor?` + `materializedProtocolConformance(in:)`
- `ProtocolDefinition.protocol: MachOSwiftSection.Protocol` → `protocolDescriptor: ProtocolDescriptor` + `materializedProtocol(in:)`

迁移是机械的：读 descriptor 事实改属性名；读 trailing 内容加一次 materialize 调用。库内约 30 处同批迁移。

### ABI 兼容性（条件项）

不适用——本库以 SPM 源码分发，使用方每次重新编译（项目类型声明见 `Documentations/README.md`）。

### 下游影响

- 仓库内：`SwiftDeclaration` 为改动主体；`SwiftIndexing` / `SwiftPrinting` / `SwiftInterface` / `SwiftSpecialization` / `SwiftDeclarationRendering` 消费点迁移。`SwiftDiffing` 无改动（attribution 早已在 index 期冻结为 Mach-O-free 值）。
- 下游仓库（RuntimeViewer、MachOKitUI、SymbolViewer）：落地第一步普查三个属性的直接消费点；有则同批送机械迁移补丁，无则重编即得收益。RV 是验收方（footprint + heap 复测）。

### 文档与示例

- AGENTS.md「SwiftDeclaration」段同步 descriptor 化模型与物化纪律（谁物化、活多久、不做 per-access）。
- `Documentations/README.md` 索引与本提案状态同步。
- [DeclarationModelMemoryFootprint.md](../Internal/DeclarationModelMemoryFootprint.md) 按其既有惯例补后记（第 1 / 2 项由本案收编落地，量测账目保持原貌），并以同款探针复量落地后的实例尺寸。
- 落地时按「落地步骤」收尾判断决定是否另写实现说明。

## API 演进与废弃策略

- **直接替换，不留 deprecated 旧属性**：deprecated 的 `.type` 要能继续返回 `TypeContextWrapper` 就得继续驻留数据，与本案目的直接冲突；源码分发、下游数量少且受控，一次性迁移优于长尾兼容。
- 随下一次常规版本发布；changelog（英文）明确列出三处破坏点与迁移句式。

## 落地步骤

1. 下游普查：RV / MachOKitUI / SymbolViewer 对 `.type` / `.protocolConformance` / `.protocol` 的直接消费点清单（RV 侧请对面会话代查）。
2. `TypeDefinition` descriptor 化：存储换形态 + `parentContext` 移除（或退路形态）+ `materializedTypeContext(in:)` + `index()` 与打印路径的物化点。
3. `ExtensionDefinition` / `ProtocolDefinition` 同模式。
4. 库内消费点全量迁移（~30 处，两类句式）。
5. 测试：全量 `swift test --skip IntegrationTests` 同数全绿；**渲染 A/B 三 reader 路径逐字节一致**（硬线——本案不许改变任何输出字节）。
6. 性能：iOS 18.5 模拟器 SwiftUI `interface` wall-clock 持平（物化 CPU 的验收）。
7. RV 复测（对面协调）：预期堆存活 283 → **~240–255 MiB**；`SwiftDeclaration` 簇 41.3 → ~15–20 MiB；MachOSwiftSection 簇 33.4 → ~10–15 MiB。
8. 以账本同款探针（`class_getInstanceSize` + `MemoryLayout`）复量三类定义的落地后实例尺寸，给 [DeclarationModelMemoryFootprint.md](../Internal/DeclarationModelMemoryFootprint.md) 补后记。
9. 收尾判断（写进决策日志）：是否写实现说明（「物化纪律」是代码看不出来的契约，倾向写短篇或并入 AGENTS.md）；新术语是否登记。

## 决策日志

| 日期 | 变更 | 说明 |
|------|------|------|
| 2026-08-09 | Created as In Review | 0001 落地后 RV 复测把声明模型 41.3 MiB + MachOSwiftSection 解析结构 33.4 MiB 定位为堆内新头部；优化面普查（`index()` 惰性 × wrapper 急切驻留的错配）成文本案；用户批准立项（「可以，写提案」）。 |
