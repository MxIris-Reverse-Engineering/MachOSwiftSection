# 0002 - 声明模型 descriptor 化：TypeDefinition / ExtensionDefinition / ProtocolDefinition 不再驻留急切解析的胖 wrapper

- **状态**: Implemented
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

**物化结果不缓存**——每次用时重新物化，这是有意的：缓存存回定义对象会把省掉的内存按浏览顺序逐个攒回来，与本案目的直接冲突；物化本身是映射内存的一遍顺序解析 + 几次小数组分配（微秒级），比消费它的 demangle + 打印便宜几个数量级；且触发频度天然有界——`index()` 有 `isIndexed` 挡板一生一次，打印每次查看一次，specialize 是低频交互，没有热循环反复物化同一定义的路径（首次查看一个类型 = index + 打印共 2 次，之后每次重看 1 次）。若落地后 profiling 显示物化是热点，退路是镜像作用域、内存压力可驱逐的小缓存——结构兼容、不动 API，后补而非前置。

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

1. ✅ 下游普查：本地磁盘全量 grep 完成，结论「零物化需求」，详见决策日志。RV 的 8 处 `.type` 机械改名清单已备（6 处 `typeContextDescriptorWrapper` 改名 + 2 处 pattern-match 改到 descriptor 案）。
2. ✅ `TypeDefinition` descriptor 化：`typeContextDescriptorWrapper` 驻留 + `parentContext` 整体移除（`ParentContext` 枚举一并删除，降级为 `SwiftDeclarationIndexer.indexTypes` 的局部 `UnlinkedParentContext` 字典）+ `materializedTypeContext(in:)`；`index()` 仅 class 分支物化（struct/enum 的字段索引走 descriptor 级 `fieldDescriptor(in:)`，零物化）。
3. ✅ `ExtensionDefinition` / `ProtocolDefinition` 同模式（`index()` 各自单点物化；typealias-only 扩展先查 descriptor 为 nil，零物化即返回）。**追加**：indexer `Storage` 侧人口清退 + 名字级轻映射（实施期修正，见决策日志）。
4. ✅ 库内消费点全量迁移：打印器（`printTypeDefinition` / `printProtocolDefinition` 各一次物化贯穿 header + 字段/关联类型渲染；`printExtensionHeader` 一次）、`GenericSpecializer` / `TypeDefinition+Specialization` / `ConformanceProvider`（后者的子类图构建按类物化一次、随图缓存）、`SwiftAttributeInference` / `SwiftInterface` diff 渲染 / `SwiftDiffing` 的 kind 判断（descriptor 级改名）、测试侧 13 处。
5. ✅ 全量 `swift test --skip IntegrationTests` 1343 全绿；渲染 A/B 七对（iOS 18.5 模拟器 SwiftUI / SwiftData / SwiftUICore 的 dump + interface，宿主机 dyld shared cache 的 SwiftUI dump + interface）全部逐字节一致（interface 剥离日志行首时间戳后比对）。
6. 性能：iOS 18.5 模拟器 SwiftUI `interface` wall-clock 持平（物化 CPU 的验收）——见决策日志的 release 复测记录。
7. ✅ RV 复测（2026-08-09，五镜像同款负载，RV 侧 8 处适配后干净跑）：footprint 稳态 **322 → 262 MB**；堆存活 **283 → 209.6 MiB**（超出预期带 240–255，分配数 −50.7 万）；`SwiftDeclaration` 簇 41.3 → **19.5 MiB**（预期带内）；MachOSwiftSection 解析簇 33.4 → **3.3 MiB**（超出预期 10–15——`ProtocolConformance` 数组 20.6 MiB 整体消失）；另有意外之喜：索引瞬态峰值 **808 → 613 MB**（解析期 wrapper churn 被砍）。不动的簇（Demangling 33.2、ObjCDump 17.2、UI/Rx 21.4、NIO 5.8）均未动。RV 侧实例复量与本仓库探针一致（TypeDefinition 1280 vs 1272 为 malloc 桶圆整）。
8. ✅ 以账本同款探针复量：`TypeDefinition` 1272 → **384 B**、`ExtensionDefinition` 640 → **224 B**、`ProtocolDefinition` 440 → **384 B**；[DeclarationModelMemoryFootprint.md](../Internal/DeclarationModelMemoryFootprint.md) 已补后记，且探针固化为常驻回归守卫 `DeclarationModelInstanceSizeTests`（上限 448 / 320 / 416 B）。
9. ✅ 收尾判断：不另写实现说明——「物化纪律」已写进 AGENTS.md 的 SwiftDeclaration 段与三个 `materialized…(in:)` 的 doc comment，实例尺寸契约由回归测试钉住，一篇独立文章只会复述这两处；术语表无新词（materialize / wrapper vs descriptor 两条已覆盖本案语汇，bucket 条随 0003 更新）。

## 决策日志

| 日期 | 变更 | 说明 |
|------|------|------|
| 2026-08-09 | Created as In Review | 0001 落地后 RV 复测把声明模型 41.3 MiB + MachOSwiftSection 解析结构 33.4 MiB 定位为堆内新头部；优化面普查（`index()` 惰性 × wrapper 急切驻留的错配）成文本案；用户批准立项（「可以，写提案」）。 |
| 2026-08-09 | 审阅补充：物化结果不缓存 | 审阅期用户问「物化后会缓存吗」；裁决为不缓存、每次用时重新物化（缓存会按浏览顺序把内存攒回来；物化微秒级、频度有界），可驱逐小缓存仅作 profiling 证明热点后的退路。已写入「详细设计 · 物化接口」。 |
| 2026-08-09 | 审阅补充：与 RV 全局搜索不冲突 | 审阅期用户问「后面 RV 想做全局搜索咋办」；裁决为不冲突且同向——搜索匹配的是名字（类型名 / 成员名 / 符号名，均为冻结轻数据），本案清退的 vtable / witnesses 解析产物不是搜索目标，命中后看详情恰是「用时物化」场景；descriptor 化让「全量建骨架不索引成员」的搜索支撑形态更可行（~400 B vs 1272 B + 堆数组/类型）。真正的功课在「按需 per-image 索引 vs 全量覆盖」这层（本案之前就存在），届时另立搜索索引提案（候选形态：惰性全量 sweep + 限流 / 名字层前置倒排 + 库侧行收集模式 / 持久化索引），不构成本案的阻塞或修改项。 |
| 2026-08-09 | In Review → Accepted | 用户审核通过（「审核通过，开始实现」），按落地步骤开工，第一步为下游消费点普查。 |
| 2026-08-09 | 下游普查结论：零物化需求 | 本地磁盘全量 grep（RuntimeViewer / MachOKitUI / MachOViewer 等；SymbolViewer 无独立仓库）：`parentContext` 与 `.protocolConformance` / `.protocol` 零下游消费者——`parentContext` 移除首选路线成立；`.type` 仅 RV 8 处且全部为 descriptor 级事实（6 处读 `typeContextDescriptorWrapper` / flags，2 处 pattern-match 后只取 `.descriptor`），机械改名即可、无一处需要物化。 |
| 2026-08-09 | 实施期修正：indexer Storage 侧同批清退 | 动手时发现提案调研的一处失实：「indexer 的全量 protocolConformances 数组在分组后本就出栈」不成立——`SwiftDeclarationIndexer.Storage` 以 `types` / `protocols` / `protocolConformances` / `associatedTypes` 四个人口数组加 `protocolConformancesByTypeName` / `associatedTypesByTypeName` 两个按名 keyed 映射**终身驻留全部 wrapper**（CoW 共享底层堆数组），不清退则 definition 侧换 descriptor 后 trailing 簇分文不释放。消费面普查：六者的公开投影在库内外（含 RV）**零调用方**，唯二例外是 `ConformanceProvider` 读 `allProtocolConformancesByTypeName` 的存在性 + keys（纯名字级事实）与两个测试读 keys。修正：四个人口数组在 `prepare()` 索引完成后置空；两个重映射降级为索引期局部变量，新增名字级轻映射 `conformingProtocolNamesByTypeName`（+ 合并投影 `allConformingProtocolNamesByTypeName`）承接 ConformanceProvider 与测试；重投影与 `allTypes` / `allProtocols` / `allProtocolConformances` / `allAssociatedTypes` 聚合一并移除（额外 API 破坏，均为零调用方）。 |
| 2026-08-09 | wall-clock 验收：release 持平（一对反而更快） | debug 构建初测候选慢 5–10%（SwiftUICore interface 反转执行序复测仍 ~9%），但最大任务 dyld cache SwiftUI interface 仅 +0.2%，疑为 debug 常数因子；改以 release 构建 ABBA 序 ×2 轮定论：SwiftUI interface 基线均值 76.3s vs 候选 72.2s（候选**快 5.3%**），SwiftUICore 37.3s vs 37.4s（+0.5%，噪声带内）。验收线达成，以 release 为准；release 输出与 debug 同样逐字节一致。 |
| 2026-08-09 | Accepted → Implemented | 落地步骤 1–5、8、9 完成（步骤 6 见上一行）：三定义 descriptor 化 + `parentContext` / `ParentContext` 移除 + 三个物化入口 + indexer Storage 清退 + 库内与测试侧全量迁移；全量 1343 绿；A/B 七对（debug 与 release 双构建）逐字节一致；实例尺寸 1272 → 384 / 640 → 224 / 440 → 384 B（前两者优于预估 ~400），回归守卫 `DeclarationModelInstanceSizeTests` 落位。步骤 7（RV 堆复测）待下游拿到本分支后进行；RV 侧 8 处机械迁移句式已在步骤 1 备好。 |
| 2026-08-09 | 下游验收回报：全部达标、三项超预期 | RV 会话完成 8 处适配（与步骤 1 清单一致，零物化调用）并复测：稳态 322 → 262 MB、堆存活 283 → 209.6 MiB（超预期）、MSS 解析簇 33.4 → 3.3 MiB（超预期）、索引瞬态峰值 808 → 613 MB（超预期收获——提案未承诺瞬态收益）。数字已回填落地步骤 7。五镜像稳态全程曲线：842（起点）→ 470–480 → ~450 → 322（0001）→ **262 MB**（0002+0003）。 |
