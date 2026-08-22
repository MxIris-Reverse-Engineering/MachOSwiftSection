# 2026-08-22 Interface 文件头部与导出状态标注（issue #106 末批）

## 问题

issue #106 §2/§3/§8：输出无一行说明二进制是否开了 library evolution（`final` 类推断的有效性取决于它）；私有成员带满注释看起来可调用、实际导出表零命中；不可恢复项的空白读起来像「源码没有」。提案 [0008](../../Evolutions/0008-interface-header-and-export-status-annotations.md)。

## 前置决策

原定「等 §6 import 重构落地再开工」。用户指示「继续推进下一个提案」覆盖该等待（`origin/next` 停在 a03d0f1b、远端无 §6 分支）；评估实际冲突面仅 `printRoot` 里 `ImportsBlock` 前数行，接线做成零侵入独立 if 块。步骤 0 的 next 基线复核完成，全部调研点无漂移，另揭示一个提案没写的关键事实：**symtab 两条收集腿都过滤 `!nlist.isExternal`，导出符号仅经 trie 腿建行**——导出集必须显式旁路收集，提案预警的「不能用现有循环残余」由此升级为结构性必然。

## 实际执行

1. `SymbolIndexStore`：trie 循环旁路收集 `ExportFacts`（行号 bitmap + offset-less re-export 名字 fallback + `hasExportInformation`），表建行为零改动；公开三态 `isExported(name:in:)` 与 `isExportedIncludingDerivedSymbols(name:in:)`。
2. `SwiftPrinting`：`InterfaceHeaderInfo` / `InterfaceHeaderBlock`（public）+ Mach-O 事实工厂；`ExportStatusComment` 组件；`SwiftDeclarationPrintConfiguration.printExportStatus`；`renderMember` 三 case 发射（override / `@objc` 豁免）。
3. `SwiftInterface`：`SwiftInterfaceBuilderConfiguration.interfaceHeaderInfo`，`printRoot` 于 imports 前渲染。
4. `SwiftDeclarationRendering` + 三个 Dumper：`printExportStatus` + `exportStatusComment()`，member-symbol 循环发射。
5. CLI：两命令 `--emit-header` / `--emit-export-status`，默认关。
6. Roadmap Known limitations 补 L-13…L-16；README CLI 两段；Glossary 两术语。

## 过程中的三次纠错（都由真实二进制暴露）

1. **裸查实现符号全量假阳性**：fixture（evolution Release）上 `public func mutateState()` 被标——实现符号 local、`Tj` 导出是 resilient 常态。改派生形态查询（`Tj`/`Tq`/`Tu`/`TjTu`）。
2. **`override` 与 `@objc dynamic` 假阳性**：`public override` 经父类 thunk 链接、`@objc public dynamic` 经 msgSend 派发，自有符号零导出但完全可达。加两个发射豁免；conformance witness 故意不豁免（零导出 = 确实不可静态直接调用，合成 `==`/`hash(into:)`/Codable witness 构成标注大头且正确）。
3. **true-positive 测试标本选错**：`Classes.ClassTest` 的隐式 internal `init()` 连实现符号都没发射（未被引用），interface 根本渲染不出；换 `GenericAsyncSequenceTest.AsyncIterator` 的隐式 init（实现符号以 local `t` 在 symtab）。

## 验证

- 新增四套 22 测试全绿：`ExportedSymbolFactsTests`（全量 trie sweeping、阴阳两性、派生转阳、internal init 全形态阴性）、`InterfaceHeaderTests`（逐行渲染、字段省略、日期缺席字节稳定、工厂、printRoot 接线与默认无头部）、`ExportStatusAnnotationTests`（三类假阳性钉死、true positive、默认零标注）、`HeaderAndExportStatusFlagTests`。
- 全量 `swift test --skip IntegrationTests`：1465 测试 / 277 套件绿；默认输出字节不变由既有快照与 SwiftDiffingTests 实证。
- SourceEditor（issue 原始二进制）复核：`updateLineNumberDisplay()` 现带 `// VTable offset: 66` + `// not exported`（§3 场景精确解决），全库 3487 处标注；反向抽查 `CachingManagedSourceEditorRange.init(_:greedy:)`（`fCTj` 导出）不被标。头部行 `Library evolution: detected (2376 dispatch thunks)`。
- 渲染 A/B 判断：本批对默认路径零行为改动（flag 全关、trie 循环建行为保持、仅旁路收集），不构成 AGENTS.md 意义上的 large refactor，未跑 `run-rendering-ab-verification.py`；等价性由 SymbolTableEquivalence + 全量快照钉住。

## 与计划的偏离

- `isExported` 单查询扩为双查询（派生形态）；发射豁免 override/@objc——均为计划外、实证驱动。
- 导出集形态从提案的「`Set<String>` 或字符串表引用」定为行号 bitmap + fallback set（对齐 0001）。
- `generatorVersion` 拆为 `generatorName` + `generatorVersion`（RuntimeViewer 不冒充 swift-section）。
- dump 侧 `ProtocolConformanceDumper` 不发射（witness 地址行无符号名在手），语义收窄记录在实现说明。
- 顺带发现 roadmap L-11 已过时（SwiftLayout 静态引擎早已支持 offline 布局注释），属既有文档准确性问题，未在本批修正。
