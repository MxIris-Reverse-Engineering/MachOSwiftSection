# 0007 - Extension 容器索引期去重与协议默认实现归属标注

- **状态**: Implemented
- **作者**: JH
- **创建日期**: 2026-08-22
- **最后更新**: 2026-08-22
- **所属愿景**: 无
- **关联提案**: [0006](0006-final-keyword-and-lazy-accessor-type-recovery.md)、[0008](0008-interface-header-and-export-status-annotations.md)（同一 issue 的其余批次）
- **实现分支 / PR**: `feature/0007-extension-container-dedup`（叠于 `feature/0006-final-and-lazy-recovery` 之上）
- **配套文档**: [ExtensionContainerUnification.md](../Internal/ExtensionContainerUnification.md)（实现说明）

## 摘要

消除 interface 输出里同一 extension 块被重复发射多份的问题：在**索引期**按 SwiftDiffing 已有的容器键（target、protocol、where 指纹、retroactive）合并 `ExtensionDefinition`，让 `printRoot`、RuntimeViewer 的 per-type 打印、diffing 三个消费方统一受益。同时给经协议扩展默认实现兜底解析出来的成员打上 `// protocol-extension default` 标注，不再让它们伪装成类型自己的 API。顺带修复索引桶只增不清的重入累加隐患，以及 `SwiftInterfaceBuilder` 里嵌套协议默认实现恒不打印的死循环 bug。

来源：[issue #106](https://github.com/MxIris-Reverse-Engineering/MachOSwiftSection/issues/106) 第 5 点 —— 协议扩展块被打印三份（同成员、同地址），以及若干类成员共享同一个占位地址、实为协议扩展默认实现。

## 动机

issue 作者在重建 `SourceEditor.framework` 时，`grep -c '^extension SourceEditor.SourceEditorSelectionObserver'` 得到 3 —— 三份一模一样的 extension 块。同时 `SourceEditorView.elide` / `.selectionWillChange` / `.didScrollPositionToVisible` 三个「类成员」共享 `// Address: 0x6608`，实际是协议扩展的默认实现被归到了类名下，读者会把它们当成类自己的 API 去写 stub。

本仓库自己的基线就复现重复问题（非 resilient 情形）：`Tests/SwiftInterfaceTests/Snapshots/__Snapshots__/SymbolTestsCoreInterfaceSnapshotTests/interfaceSnapshot.1.txt` 对同一个 target 发射了三个 extension 块（嵌套类型产线一个、泛型签名桶一个、catch-all 桶一个；main 基线行号 3230/3239/3244 一带）。

## 前期调研

调研基于 main（`32bf83c1`）；next 已并入 0002 号提案（声明模型 descriptor 化）等模型层改动，**开工第一步必须在 next 上复核下列文件与行号**（机制预期不变，形态可能漂移）。

- **五条独立产线写入四个扩展桶，几乎没有去重。** `SwiftDeclarationIndexer.Storage` 有 `typeExtensionDefinitions` / `protocolExtensionDefinitions` / `typeAliasExtensionDefinitions` / `conformanceExtensionDefinitions` 四个桶（`Sources/SwiftIndexing/SwiftDeclarationIndexer.swift:78-87`），产线是：`indexTypes()`（嵌套在扩展里的类型，`:377-407`）、`indexProtocols()`（`:449-460`）、`indexConformances()`（每条 conformance record 一个块，`:537-566`）、`indexExtensions()`（符号表扫描，`:631-776`）、以及 `ProtocolDefinition.index()` 从协议 descriptor 读出的 resilient default witness 合成块（`Sources/SwiftDeclaration/Components/Definitions/ProtocolDefinition.swift:151-179`，存到 `defaultImplementationExtensions`）。既有的唯一去重仅覆盖 typealias-only 的 conformance 扩展（`SwiftDeclarationIndexer.swift:568-599`，当年就明确把带成员的情形排除在范围外）。
- **打印路径零去重。** `SwiftInterfaceBuilder.allExtensionDefinitions` 是四个桶的平铺拼接（`Sources/SwiftInterface/SwiftInterfaceBuilder.swift:42-44`），每个 `ExtensionDefinition` 对象打一个块（`:180-186`）。
- **容器键已存在且经过实战。** `ABIDiffer.extensionContainerKey(for:of:)`（`Sources/SwiftDiffing/ABIDiffer.swift:108-149`）按 (target, protocol, where 指纹, retroactive) 分组，diff 渲染器已在用（`Sources/SwiftInterface/SwiftDiffableInterfaceRenderer.swift:231-248`）；键的输入字段在索引期就冻结在 `ExtensionDefinition` 上（`conformingProtocolName` / `genericSignature` 等，见 [PerConformanceAttribution.md](../Internal/PerConformanceAttribution.md)）。
- **三份重复在 resilient 框架上的最佳解释是双产线**：`ProtocolDefinition.index()` 与 `indexExtensions()` 会对同一批 `…PAAE…` 默认实现符号各造一个 `extension P` 块。SymbolTestsCore 未开 library evolution，`layout.defaultImplementation.isValid` 恒 false，所以 fixture 测不出而 SourceEditor（resilient）能看到 —— **此判断在真实 resilient 二进制上尚未逐符号证实，标注为推测**，落地第一步先验证。
- **泛型签名分桶造成碎片化**：`indexExtensions()` 只对 `case .variable = kind` 按 `dependentGenericSignature` 分桶（`SwiftDeclarationIndexer.swift:710-721`），函数从不分桶；且 `printExtensionHeader` 仅当签名的 requirement 子节点非空才打 `where` 子句（`SwiftDeclarationPrinter.swift:268-284`），签名桶渲染出来可能与 catch-all 桶视觉上一模一样。
- **索引桶只增不清**：全部写入是 `[key, default: []].append(...)`（`SwiftDeclarationIndexer.swift:394,399,405,459,766,770`），`prepare()` 半途抛错后重试、或第二次 `index()` 都会成倍复制扩展块而 `rootTypeDefinitions` 不受影响 —— 「恰好三份、地址相同」也与重入一致，需要查证 RuntimeViewer 是否有 `prepare()` 重试。
- **相同地址不是占位符**：`memberAddressString` 是 `machO.addressString(forOffset:)` 直通（`SwiftPrinting/SwiftDeclarationPrinter.swift:483-486`），若干无实质代码的默认实现被链接器 identical code folding 折叠到同一地址是真实事实；`ExtensionDefinition.index()` 在 resilient witness 解析不到时回退 `defaultImplementationSymbols`（`Sources/SwiftDeclaration/Components/Definitions/ExtensionDefinition.swift:122-124`），把协议扩展默认实现归到 conforming 类型的扩展块下，且**成功回退不留任何痕迹**（`missingSymbolWitnesses` 只记失败的）。同址多符号时 `_symbol(for:...)`（`ExtensionDefinition.swift:97-104`）按迭代序取，具体归到哪个名字带有任意性。
- **死代码 bug**：`SwiftInterfaceBuilder.swift:170-178` 遍历 `rootProtocolDefinitions.values.filterNonNil(\.parent)`，而 root 协议的 `parent` 恒为 nil，此循环永远为空 —— 嵌套协议的默认实现扩展目前从不打印。

## 提议方案

1. **索引期容器合并**：把容器键计算下沉到 `SwiftDeclaration`（如 `ExtensionDefinition.containerIdentity`），`ABIDiffer.extensionContainerKey` 改为基于它实现（**diff key 的字符串必须逐字节不变**，用既有 diffing 测试钉死）；`SwiftDeclarationIndexer` 在索引收尾阶段按容器键把四个桶与 `ProtocolDefinition.defaultImplementationExtensions` 里键相同的 `ExtensionDefinition` 合并为一个（成员按符号恒等去重），双产线与碎片桶自然坍缩。
2. **泛型签名桶修正**：分桶范围从 `variable` 扩展到 function / subscript；requirement 子节点渲染为空的签名桶并入 catch-all（消除「看起来相同的裸 extension」）。
3. **重入防护**：`index()` 入口重置扩展桶（或 `prepare()` 幂等化），加回归测试（连续两次 index 输出一致）。
4. **默认实现标注**：`ExtensionDefinition.index()` 的 `defaultImplementationSymbols` 回退路径给产出的成员打标（如 `Accessor` / `FunctionDefinition` 上的 `isProtocolExtensionDefault`），渲染时在地址注释旁输出 `// protocol-extension default`，跟随 `printMemberAddress` 开关（它是对地址语义的限定，与地址同进退）。成员保留在 conforming 类型的扩展块里（该 conformance 确实使用这个默认实现），只标注不搬家。
5. **死循环修复**：修正 `SwiftInterfaceBuilder.swift:170-178` 的过滤方向，让嵌套协议的默认实现扩展真正打印（快照会新增内容，逐行审查）。

### 非目标

- 不改 diffing 的容器语义与 `formatVersion`（索引期合并的是**键完全相同**的重复容器，diff 侧本就按键聚合，快照键集不变 —— 落地时用既有 diffing 测试验证此断言）。
- 不动 `_symbol(for:...)` 的同址消歧策略（归属名字的任意性是 ICF 的固有信息损失，标注已让读者知情；更强的消歧另行提案）。
- 不把默认实现成员搬回协议的 extension 块（用户已决策：原地标注）。
- 不改 RuntimeViewer 侧代码（索引期合并对它自动生效）。

## 详细设计

```swift
// SwiftDeclaration — 容器身份（示意）
extension ExtensionDefinition {
    /// The (target, protocol, where-clause fingerprint, retroactive) identity that
    /// ABIDiffer.extensionContainerKey and the indexer's merge pass both derive from.
    public var containerIdentity: ExtensionContainerIdentity { ... }
}

// SwiftIndexing — 收尾合并（示意）
// for each bucket: group by containerIdentity, merge members (dedup by symbol identity),
// preferring the definition that carries protocolConformance / associated-type witnesses.
```

合并语义细则：成员去重键用成员符号的 mangled name（同名同符号即同一成员；双产线场景两份成员集合完全同源）；`protocolConformance`、`resolvedAssociatedTypeWitnesses`、`missingSymbolWitnesses` 等归属字段取并集/首个非空。合并发生在 `currentStorage` 定稿处（`SwiftDeclarationIndexer.swift:765-771` 一带），即所有产线之后、任何消费方之前。

标注渲染：`renderMember` 的地址注释位（`SwiftPrinting/SwiftDeclarationPrinter.swift:388/395/403`）与 dump 路径的 `memberAddressComment`（`Sources/SwiftDeclarationRendering/DeclarationRenderConfiguration.swift:100-111`）各加一个兄弟组件，文案 `protocol-extension default`。

## 替代方案考量

- **仅在 `printRoot` 打印时分组**（复用 diff 渲染器的做法）—— 否。RuntimeViewer 绕过 `printRoot` 逐类型打印，issue 作者实际看到的输出修不到；用户已决策索引期合并。
- **两层都做（索引合并 + 打印兜底分组）** —— 暂否。索引期合并后打印层分组是空操作；若落地后发现仍有漏网重复再补，不预付复杂度。
- **`SwiftIndexing` 直接 import `SwiftDiffing` 复用 `extensionContainerKey`** —— 否。会让索引层依赖 diff 层，层次倒挂；键输入本就冻结在 `SwiftDeclaration` 的字段上，下沉是正确方向。
- **把默认实现成员从类的扩展块移除、只在协议扩展块出现一次** —— 否（用户决策）。会丢失「这个 conformance 使用了默认实现」的信息，而这正是 witness table 层面的事实。

## 影响

### 源码兼容性（source compatibility）

`containerIdentity` 与成员打标字段为纯新增（打标字段带默认值 false）。`ABIDiffer.extensionContainerKey` 若为 public 且签名变化，保持签名、仅内部改为基于 `containerIdentity` 实现。索引器行为变化不涉及 API 破坏。

**输出行为变化**：默认输出的重复 extension 块消失、嵌套协议默认实现扩展开始出现 —— 全部 interface/dump 快照重生成并逐行审查；开启 `--emit-member-addresses` 时新增 `// protocol-extension default` 标注。

### ABI 兼容性（条件项）

不适用 —— 本库以 SPM 源码分发，使用方每次重新编译。

### 下游影响

本仓库内：`SwiftDeclaration`、`SwiftIndexing`、`SwiftDiffing`（键实现重构，行为钉死不变）、`SwiftPrinting`、`SwiftDeclarationRendering`、`SwiftInterface`、快照测试。**`SwiftDiffing` 是重点回归对象**：`ABISnapshot` 键集与 `formatVersion` 必须不变，用既有 diff/evolution 测试全量验证。

下游仓库：RuntimeViewer per-type 导出的重复块消失（正向）；若其对 `prepare()` 有重试逻辑，重入防护落地后行为更稳。

### 文档与示例

AGENTS.md 的 SwiftIndexing / SwiftDiffing 条目、[PerConformanceAttribution.md](../Internal/PerConformanceAttribution.md) 补充索引期合并一节、`Roadmaps/2026-04-13-swiftinterface-dump-improvements.md` 中 typealias 去重条目（P1-9）标注被本提案泛化。

## API 演进与废弃策略

- 无废弃；`Version.swift` minor bump + changelog。

## 落地步骤

0. **前置**：在 next 基线上复核「前期调研」全部文件与行号（0002 号提案的模型层改动可能造成形态漂移），结论回填。
1. **证实双产线推测**：对一个 resilient 真实框架（SourceEditor）跑索引，确认三份重复的产线构成（双产线 vs 重入 vs 碎片桶），结论回填本提案「前期调研」。
2. 容器键下沉 `SwiftDeclaration` + `ABIDiffer` 改基于它实现；diffing 全量测试钉死键字符串不变。
3. 索引收尾合并 + 成员去重；`SwiftInterfaceTests` 快照里的重复 extension 块消失，逐行审查。
4. 泛型签名桶修正、重入防护 + 各自回归测试。
5. 默认实现打标 + 两路标注渲染（`printMemberAddress` 门控）；需要 resilient fixture 或以真实框架人工抽查验证回退路径。
6. 死循环修复 + 快照审查新增的嵌套协议默认实现块。
7. 全量 `swift test --skip IntegrationTests`；文档同批；提案状态推进。

**收尾时必须判断两件事**（判断结果写进决策日志，不允许沉默跳过）：

- **要不要配套专题文章** —— 索引期合并与 diff key 冻结的关系属于「下次维护会踩」的决策，预计并入 PerConformanceAttribution.md 或新实现说明。
- **有没有引入新术语** —— container identity 若成为常用语则登记术语表。

## 决策日志

| 日期 | 变更 | 说明 |
|------|------|------|
| 2026-08-22 | Created as Draft | 源自 issue #106 第 5 点调研；用户决定：索引期合并（非仅打印分组）、默认实现原地标注（不搬家）。 |
| 2026-08-22 | Draft → Accepted | 用户批准三批全做（「全部做」+「开工」）。原编号 0006 因 next 上编号顺延改为 0007；排在 0006（final + lazy）之后实施。 |
| 2026-08-22 | In Progress → Implemented | 实现完成于 `feature/0007-extension-container-dedup`（叠于 0006 分支，待并入 next）。全量 1443 tests 全绿（SwiftDiffingTests 全绿 = 快照格式零扰动实证）；`ExtensionContainerUnificationTests` 四用例；SourceEditor 复测重复头全部归一且 0006 哨兵保持；interface 快照四块纯迁移。**收尾两判**：配套文档已写并登记（[ExtensionContainerUnification.md](../Internal/ExtensionContainerUnification.md)，含与提案的差异与已知残余）；无需登记新术语（attachment / print suppression 为描述性短语）。 |
| 2026-08-22 | 双产线推测证实 + 设计转向（SourceEditor 实测驱动） | （1）重复实测为**两份**非三份：`ProtocolDefinition.index()` 的 descriptor 派生尾随副本 + `indexExtensions()` 的符号扫描桶副本，且两份成员不一致——per-requirement 默认实现解析在 ICF 折叠地址上丢成员，尾随副本反而更少（`SourceEditorSelectionObserver` 尾随 1 个成员、桶副本 2 个）；第三份未在当前 next 复现。（2）**「容器键下沉 + 索引期从桶合并」被格式冻结否决**：四个扩展桶是 `ABIModule` 的直接输入，从桶移除定义会让容器从 ABI 快照消失。转向「附着 + 打印抑制」——协议的符号扫描块附着到 `defaultImplementationExtensions` 尾随渲染，同一对象留桶并打 `isAttachedToProtocolDefinition`，顶层打印跳过；桶内同身份合并对快照无影响（差分器本就按键分组）。（3）descriptor 合成降级为 fallback（符号扫描是超集）。（4）「签名分桶扩展到 functions」被否——函数/下标的成员级 `where` 合法且已渲染，扩展分桶只会制造更多块；改为仅折叠空 requirement 的变量签名桶。（5）伴生修复：`updateConfiguration` 的 re-prepare 因 `isPrepared` 从不复位而恒 no-op；修复后成为桶重置的确定性测试入口。（6）issue 点名的 `SourceEditorView.elide` 三兄弟经 `nm` 证实是真类成员被 ICF 折叠（0006 的 `Tq` 门处理），非误归属默认实现；`protocol-extension default` 标注仍按提案落地（interface+dump 两路），但在已验框架上不触发（首选 witness 符号分支总命中）。（7）已知残余：typealias-only 块与成员块的裸头并存（P1-9 残余，跨桶合并动快照格式，不做）。 |
