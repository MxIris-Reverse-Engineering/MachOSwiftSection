# 2026-08-22 Extension 容器统一与协议默认实现归属（issue #106 次批）

## 问题

issue #106 §5：同一 `extension P` 块被重复打印（作者 `grep -c` 得 3；当前 next 实测 SourceEditor 两打协议各 2 份），以及若干共享同一地址的「类成员」疑似被误归属的协议扩展默认实现。提案 [0007](../../Evolutions/0007-extension-container-dedup-and-default-impl-attribution.md)。

## 调研结论（含对提案预案的两次推翻）

- **双产线证实**：副本一 = `ProtocolDefinition.index()` 按协议 descriptor 合成、尾随协议渲染；副本二 = `indexExtensions()` 符号扫描桶、经 `allExtensionDefinitions` 渲染。关键意外：两份成员**不一致**——per-requirement 的默认实现符号解析在 ICF 折叠地址上丢成员（`SourceEditorSelectionObserver` 尾随副本 1 个成员、桶副本 2 个），所以正确方向是符号扫描超集为准。
- **「容器键下沉 + 索引期从桶合并」被格式冻结否决**：四个扩展桶是 `ABIModule` 的直接输入（`SwiftDiffableInterfaceBuilder:52/74`），从桶移除定义会让容器从 ABI 快照消失。
- **「签名分桶扩展到 functions」被否**：函数/下标的成员级 `where` 子句是合法 Swift 且已完整渲染；变量不能带成员级 `where` 所以只有变量需要分桶——那不是碎片化缺陷而是必要设计。
- **`elide` 三兄弟的真相**：`nm` 证实它们是真类成员（有 `Tq`+`Tj`）被 ICF 折叠到 0x6608（1128 个符号共址），非误归属默认实现——这半个问题实际由 0006 的 `Tq` 门解决。

## 最终方案

附着 + 打印抑制：`unifyExtensionContainers()`（prepare 收尾）把协议的符号扫描块附着到 `ProtocolDefinition.defaultImplementationExtensions`（顶层协议经 `printThrowingProtocol` 尾随渲染；嵌套协议经 `printRoot` 修复后的专用循环，因为 extension 不能嵌套）；同一对象留桶并打 `isAttachedToProtocolDefinition`，`allExtensionDefinitions` 跳过。桶内同身份合并（`StructuralNodeReferenceKey` 键的 (protocol, where, retroactive)）仅限急切定义——conformance-backed 定义惰性解析成员，prepare 期合并会静默丢内容。descriptor 合成降级为 `defaultImplementationExtensions.isEmpty` 时的 fallback。

## 实际执行

1. `ExtensionDefinition`：`isAttachedToProtocolDefinition`、`absorbMembers(of:)`、默认实现 witness 打标（`isProtocolExtensionDefault` 三成员定义 + 名字回填）。
2. `SwiftDeclarationIndexer`：`index()` 入口四桶重置（append 产线的重入防护）；`unifyExtensionContainers()`；变量签名分桶折叠空 requirement 桶；`updateConfiguration` 复位 `isPrepared`（原为静默 no-op——配置变更后的 re-prepare 从未发生过）。
3. `SwiftInterfaceBuilder`：`allExtensionDefinitions` 过滤已附着项；嵌套协议扩展块循环修复（原在 root 协议上过滤 `parent != nil`，恒空）。
4. 渲染：`renderMember` 与 `ProtocolConformanceDumper` 在 `printMemberAddress` 下输出 `protocol-extension default` 标注。
5. 测试：`ExtensionContainerUnificationTests` 四用例。第一版「顶层 extension 头文本全局唯一」断言当场抓到跨桶残余（typealias-only 块与成员块裸头并存）——判定为 P1-9 残余、格式冻结下不合并，断言改为「带成员的急切容器身份全桶唯一」并把残余写进文档。

## 验证

- 全量 `swift test --skip IntegrationTests` 绿（SwiftDiffingTests 全绿 = 快照格式零扰动的实证）。
- interface 快照 diff 为四个协议扩展块纯迁移（extensions 区 → protocols 区之后，22+/21−）。
- SourceEditor 复测：重复 `extension` 头全部归一；0006 哨兵保持（`elide` 非 final ×2、`final lazy var languageService` 在位）。
- `protocol-extension default` 标注在 SourceEditor 上未触发（首选 witness 符号分支总命中）——落地为休眠防御，触发条件（witness 实现符号缺失且默认实现符号可解析）记录在实现说明。

## 与计划的偏离

- 附着 + 打印抑制取代容器键下沉（格式冻结驱动，diffing 零改动零风险）。
- 签名分桶不扩展到 functions（被否，理由见上）。
- 实测两份非三份；第三份未复现（疑 RuntimeViewer 侧或旧版行为）。
- `updateConfiguration` no-op 修复为计划外伴生项。
