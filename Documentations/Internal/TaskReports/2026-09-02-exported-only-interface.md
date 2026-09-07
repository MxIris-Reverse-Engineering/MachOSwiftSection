# 2026-09-02 Interface 只打印导出声明（`--exported-only`）

## 问题

用户要求「SwiftInterface 只打印 exported 的方法和类型」。现状：提案 0008 只在成员上打 `// not exported` 标注；类型、协议、扩展层面没有任何导出判断（`Sources/` 里对 `…Mn` / `…Mp` 描述符符号零查询），`printRoot` 与三个打印入口没有任何过滤钩子。提案 [0016](../../Evolutions/0016-exported-only-interface.md)。

## 调研

- `SymbolIndexStore` 的导出事实层（`isExported` 三态、`isExportedIncludingDerivedSymbols` 的 `Tj`/`Tq`/`Tu`/`TjTu` 派生形态）与 `SwiftDeclarationPrinter.exportVerdict(forSymbolNames:)` 可直接复用；`renderMember` 三 case + `renderModelFields` 字段腿 + `printRoot` 两个全局块是全部发射点。
- fixture（`SymbolTestsCore`，library-evolution Release + `ENABLE_TESTABILITY`）实测：`Mn` 378 导出 / 19 本地（全是 `private` 类型 + `__C` 外来描述符），`Mp` 54 / 2，`Mc` 147 / 44——44 个未导出 conformance 全涉及私有类型，扩展不必再查 `Mc`；导出 `Mn` 集合与 `Ma` 集合完全一致。
- Remangler 对 `.global` 节点发 `_$s` 前缀，与存储里的符号名形态一致；`BlockList` / `NestedDeclaration` 对空项整体跳过，被过滤的定义返回空串即可不留空行。
- `TypeDefinition.extensions` 在索引器里从未被填充，扩展与类型的关联只能经名字（`ExtensionName` ↔ `TypeName` 结构相等）建立。

## 澄清提问（一轮三题，均选推荐项）

1. 过滤层级：**打印期**（模型完整、diff / RuntimeViewer 不受影响）vs 索引期。
2. 存储属性：**按 accessor 判定过滤**（与标注一致）vs 一律保留。
3. 范围：**只做 interface** vs 连 dump 一起。

## 实际执行

1. `SwiftPrinting`：`printExportedDeclarationsOnly`；新文件 `SwiftDeclarationPrinter+ExportFilter.swift`（`ExportFilterScope`、`installExportFilterScope`、类型 / 协议两腿 verdict、全部 `isExcludedByExportFilter` 判定、`isEmptiedByExportFilter`）；三个打印入口拆成过滤壳 + `printIncluded…` builder 体；成员循环 `where` 过滤；`renderModelFields` 字段预筛保原始下标。
2. `SwiftInterface`：`printRoot()` 拆壳装 scope，全局块 `where` 过滤。
3. CLI：`interface --exported-only`。
4. 文档：提案（轻量档三段）、实现说明、README（公开 + 文档索引）、Evolutions 状态表、Glossary、演进账本、AGENTS.md、模块参考。

## 过程中的一次纠错（真实二进制暴露）

第一版类型级判据纯靠重整名（`TypeName.node` → `_$s…Mn`）查 trie。全量输出交叉比对发现 `GenericRequirementTest where A: RawRepresentable` 下的公开嵌套类型 `RawRepresentableNestedStruct` 被误删：编译器给带约束扩展里的类型 mangle 的上下文只含扩展自己的 requirement（`…VAASYRzrlE…`），模型节点却带类型完整签名（interface 头部印两条 `where`），重整结果与真实符号不等价。改为**先反查描述符 offset 处的符号**（编译器自己的拼法），只在描述符处无符号时才用重整名兜底、且含 `.extension` 上下文的名字拒绝兜底。回归钉在 `publicTypeNestedInConstrainedExtensionIsKept`。

另一处测试侧的返工：即时编译 fixture 里想用「两个带约束扩展」造两个容器，实际上带约束扩展成员都渲染进同一个 `extension Foo { … where … }` 容器（每个成员自带 where 子句），改用第二个泛型类型 `PublicPair` 承载「只有内部成员的容器」。

## 验证

- 新增三套 22 测试全绿：`ExportedOnlyInterfaceTests`（12）、`ExportedOnlyLibraryEvolutionFixtureTests`（7，`-enable-library-evolution` 无 `-enable-testing`，覆盖 `internal` 形态与存储属性）、`ExportedOnlyFlagTests`（3）。
- fixture 全量交叉验证：3824 → 2839 行；标注模式 378 处 `// not exported` 对应声明在过滤输出里零残留；新增行只有 conformance 扩展 `{` → `{}`；无 `\n\n\n` / `{\n}`。
- 回归：`SwiftInterfaceTests` / `SwiftSectionCommandTests` / `SwiftDiffingTests` / `SwiftPrintingTests` 过滤子集全绿（见下方备注）；默认输出由既有快照与 `defaultOutputIsUnchanged` 钉住。
- 默认路径零行为改动，不构成 large refactor，未跑渲染 A/B 脚本。

## 与计划的偏离

- 类型级判据加了 offset 反查腿（提案决策日志原本主张按名字查优于 offset 反查），原因见上文纠错；记入实现说明「与提案的差异」。
- 被清空的普通扩展会派发一对 start / completed 事件（索引必须在 start 之后才能判空），被过滤的定义则不发事件——提案未涉及事件契约，实现说明补记。
