# Extension 容器统一：实现说明

> 配套提案见 [0007](../Evolutions/0007-extension-container-dedup-and-default-impl-attribution.md)（issue #106 第 5 点）。
> 本文记录实际落地的实现、与提案的差异，以及当前覆盖范围与已知降级。面向维护者。相关：[PerConformanceAttribution.md](PerConformanceAttribution.md)（diff 侧的容器键，本文多处受它的格式冻结约束）。

## 背景与目标

同一个 extension 块在 interface 输出里被重复发射：SourceEditor 实测两打协议各出现两份 `extension P` 块（issue 报告为三份）。根因是双产线——`ProtocolDefinition.index()` 从协议 descriptor 的 per-requirement 默认实现合成一份「尾随协议」副本，`indexExtensions()` 的符号表扫描再产出一份桶副本；两份成员还**不一致**（descriptor 路径在 ICF 折叠地址上丢成员，尾随副本反而更少）。目标：每个源容器打印一次、成员取超集，同时不动 ABI-diff 的冻结快照格式。

## 关键设计决策

**附着 + 打印抑制，而非从桶移除或下沉容器键。** 提案原案是把 `ABIDiffer.extensionContainerKey` 下沉 `SwiftDeclaration` 并在索引期按键合并。落地时发现四个扩展桶是 `ABIModule` 的直接输入（`SwiftDiffableInterfaceBuilder` / diff 渲染器），**从桶里移除任何定义都会让容器从 ABI 快照里消失**（对旧基线产生虚假 removed）。最终形态：协议的符号扫描块**附着**到 `ProtocolDefinition.defaultImplementationExtensions`（尾随协议渲染），同一对象**留在桶里**并打 `isAttachedToProtocolDefinition` 标志，顶层打印器跳过已附着项。diff 侧零改动、零扰动（SwiftDiffingTests 全绿实证）；桶内的同身份合并同样对快照无影响——差分器的 `extensionContainerSnapshots` 本就按容器键分组合并。

**descriptor 派生的默认实现合成降级为 fallback。** 符号扫描块是它的严格超集：per-requirement 的 `defaultImplementationSymbols` 解析在 ICF 折叠地址上会丢成员（`_symbol` 的 visitedNodes 消歧在千余符号共址时配不齐），SourceEditor 上尾随副本只有 1 个成员而桶副本有 2 个正是这个成因。`ProtocolDefinition.index()` 仅在 `defaultImplementationExtensions` 为空（无模块级 indexer 的 SPI 场景、`(extension in)` 符号被 strip）时才走合成。

**桶内同身份合并只吃急切定义。** 身份 = (conformingProtocolName 结构键, genericSignature 结构键, isRetroactive)，`StructuralNodeReferenceKey` 键（跨 store 结构相等）。conformance-backed 定义（`protocolConformanceDescriptor != nil`）的成员在打印期才惰性解析，prepare 期把它合并掉会**静默丢成员**——一律保留原样（同身份 conformance 重复意味着重复 conformance record，实际不存在）。

**签名分桶只对 variables 是正确设计，不是缺陷。** 变量不能携带成员级 `where` 子句，约束扩展的变量必须自成 `extension … where …` 块；函数与下标的成员级 `where`（`func isEqualTo(_:) -> Bool where Self.Element: Equatable`）是合法 Swift 且已如实渲染。提案「把分桶扩展到 functions」会制造更多块，被否。真正修的是：requirement 子节点为空的签名桶渲染成与 catch-all 视觉相同的裸头——这类折叠进 catch-all。

**`updateConfiguration` 的 re-prepare 原为静默 no-op。** `prepare()` 的 `isPrepared` 门从无人复位，配置变更后的重建从未发生过。顺带修复（复位后重跑），它同时成为桶重置（`index()` 入口清空四桶）的确定性验证入口——修复前 re-run 会把所有 append 产线的块成倍复制。

**嵌套协议的扩展块经由原死循环的修复版打印。** `printRoot` 里那个循环原来在 root 协议上过滤 `parent != nil`（恒空）；修复为遍历 `allProtocolDefinitions` 的嵌套协议。fixture 的协议全部嵌套在 enum 命名空间里，所以快照中四个协议扩展块整体从 extensions 区迁到 protocols 区之后——纯迁移，零内容变化。顶层协议走 `printThrowingProtocol` 的尾随路径（`parent == nil` 门）。

**`protocol-extension default` 标注落在 conformance 兜底分支。** `ExtensionDefinition.index()` 经 `element.defaultImplementationSymbols` 解析成功的 witness，其成员打 `isProtocolExtensionDefault`，interface（`renderMember`）与 dump（`ProtocolConformanceDumper`）在 `printMemberAddress` 开启时渲染标注。**SourceEditor 上未触发**：折叠地址上 `resilientWitness.implementationSymbols` 的首选分支总能命中（protocol witness 符号在场），兜底分支需要「witness 实现符号缺失而默认实现符号可解析」的组合——已落地待真实触发场景（fixture 非 resilient，`resilientWitnesses` 为空，同样够不到）。issue 点名的 `SourceEditorView.elide` 三兄弟经 `nm` 证实是**真类成员**被 ICF 折叠（提案 0006 的 `Tq` 门处理），并非误归属的协议默认实现。

## 模块结构

```
Sources/SwiftDeclaration/Components/Definitions/
├── ExtensionDefinition.swift   # + isAttachedToProtocolDefinition / absorbMembers / 默认实现打标
├── ProtocolDefinition.swift    # index()：descriptor 合成降级为 fallback
└── {Function,Variable,Subscript}Definition.swift  # + isProtocolExtensionDefault
Sources/SwiftIndexing/SwiftDeclarationIndexer.swift
    # index() 入口四桶重置；unifyExtensionContainers()（桶内同身份合并 + 协议附着）；
    # 变量签名分桶的空 requirement 折叠；updateConfiguration 复位 isPrepared
Sources/SwiftInterface/SwiftInterfaceBuilder.swift
    # allExtensionDefinitions 过滤已附着项；嵌套协议扩展块循环修复
Sources/SwiftPrinting/SwiftDeclarationPrinter.swift   # renderMember 的默认实现标注
Sources/SwiftDump/Dumper/ProtocolConformanceDumper.swift  # dump 侧标注
```

## 与提案的差异

- 「容器键下沉 + ABIDiffer 改基于它实现」→ 附着 + 打印抑制（见上，格式冻结驱动）。
- 「签名分桶扩展到 function / subscript」→ 否（成员级 `where` 合法且信息完整）；仅做空 requirement 桶折叠。
- 实测重复为**两份**非三份（第三份未在当前 next 复现，疑为 RuntimeViewer 侧列表或旧版行为）。
- `updateConfiguration` no-op 修复为提案未预见的伴生项。

## 验证

- `Tests/SwiftInterfaceTests/ExtensionContainerUnificationTests.swift` 四用例：全桶成员级容器身份唯一性、协议扩展块尾随且唯一、桶内身份唯一、配置往返幂等（bucket 计数不变）。
- SourceEditor 实测：重复 `extension` 头从两打协议 ×2 → **全部 ×1**；0006 哨兵（`elide` 非 final、`languageService` final lazy 非 Optional）保持。
- interface 快照 diff 为四块纯迁移（22+/21−，一个空行）；SwiftDumpTests / SwiftIndexingTests / **SwiftDiffingTests** 全绿（快照格式零扰动的实证）。

## 修复：附着映射必须结构化键控（2026-08-27，PR #118 review 发现 2）

首版 `unifyExtensionContainers` 用一个临时的 `[String: ProtocolDefinition]` 建协议查找表，key 取 `ProtocolName.name` —— 即用 `interfaceTypeBuilderOnly` 打印出的名字，而该选项**明确移除 private discriminator**。两个同名的 `private protocol` 于是塌进同一个 key，last-wins。

后果比"挂错"更重，因为附着是**赋值**不是 append：

1. 先处理的桶被逐个打上 `isAttachedToProtocolDefinition = true` —— 顶层 `allExtensionDefinitions` 从此过滤掉它们；
2. 紧接着后一个桶的 `protocolDefinition.defaultImplementationExtensions = definitions` 把前者从附着位覆盖出去。

于是**那一整桶成员从输出里彻底消失**（既不在顶层 extensions 块，也不在任何协议的尾随块），而"哪个桶倒霉"取决于 `OrderedDictionary` 的迭代顺序。

修法是把 key 换成结构化的 `ExtensionName` —— 它的 `Hashable` 本就是对名字节点做结构比较，且 `ProtocolName` 自带一个现成的 `extensionName` 属性，正好是桶的键类型：

```swift
var protocolDefinitionsByName: [ExtensionName: ProtocolDefinition] = [:]
for (protocolName, protocolDefinition) in currentStorage.allProtocolDefinitions {
    protocolDefinitionsByName[protocolName.extensionName] = protocolDefinition
}
for (extensionName, definitions) in currentStorage.protocolExtensionDefinitions {
    guard let protocolDefinition = protocolDefinitionsByName[extensionName] else { continue }
```

结构键控之后附着是 1:1 的（查找键与桶键同型同值），赋值不再有覆盖风险。

**为什么这个修法是安全的**：协议定义那侧的名字节点来自类型描述符，扩展桶那侧来自符号扫描，两者出自不同的 node store。若结构对不上，附着会整体失效 —— 退回 main 的行为（扩展渲染在顶层，不丢数据），而 `protocolExtensionBlockTrailsItsProtocol` 断言 `!attachedDefinitions.isEmpty`，会立刻变红。也就是说这个修法的失败模式是"安全降级 + 测试立刻告警"，不是静默错误。

**同批修正的测试**：`memberCarryingContainerIdentitiesAreUnique` 自己也用去 discriminator 的字符串拼身份键，于是把两个**合法不同**的同名私有协议容器报成重复容器。它的身份键同样换成了以 `ExtensionName` 值为分量的结构化 key —— 与生产代码同一个教训。

红→绿实证（fixture `PrivateDoppelgangerProtocol` 对，一边 `alpha*` 一边 `beta*`）：

```
修前：protocol …{} / protocol …{} / extension …{ betaDefaultProperty, betaDefaultMethod }   ← alpha 整块消失
修后：protocol …{} / extension …{ alpha* } / protocol …{} / extension …{ beta* }
```

同族的其余漏网（`final` 恢复的 5 处 name-only 查找）见 [`PrivateTypeMemberAttribution.md`](PrivateTypeMemberAttribution.md) 的两条追记与 [`ReviewAdjudications.md`](ReviewAdjudications.md) 的 A22。

## 已知降级

- **裸头并存残余**：`extension X { typealias … }`（P1-9 合并代表、居 conformance 桶承载 assocwitness 归属）与同名成员块共享头文本。跨桶合并动快照格式，不做；属外观残余非重复容器。
- `protocol-extension default` 标注在已验框架上不触发（见上）；触发组合出现前实质为休眠代码。
- 附着仅覆盖「符号扫描桶里存在该协议条目」的协议；`(extension in)` 符号全部被 strip 时回落 descriptor 合成（成员可能少于真实集合，per-requirement 解析的固有损失）。

## 延伸阅读

- 提案 [0007](../Evolutions/0007-extension-container-dedup-and-default-impl-attribution.md)
- [PerConformanceAttribution.md](PerConformanceAttribution.md) —— diff 容器键与格式冻结
- [FinalKeywordAndLazyAccessorTypeRecovery.md](FinalKeywordAndLazyAccessorTypeRecovery.md) —— 0006（`elide` 案的另一半真相）
