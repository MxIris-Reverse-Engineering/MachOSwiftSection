# 2026-09-10 删除 `PrimitiveTypeMapping`

对应提案：无（删死代码，豁免档）。前置：[0023-type-import-info-identity](../../Evolutions/0023-type-import-info-identity.md)。

## 问题

用户看到提案 0023 落地后 `__C.Style` 变成 `__C.NSTableViewStyle`，指出以前 dump 只打出用户可见名那一截、后面那截其实一直读不出来，并问 `PrimitiveTypeMapping` 是否可以去掉。

## 调研

`PrimitiveTypeMapping`（`Sources/SwiftInspection/`，2 个文件 59 + 25 行）是 TypeImportInfo 的手工残缺版：遍历 `__swift5_builtin` 记录里落在 `__C` 的类型，顺着描述符名字读下一个字符串，首字符是 `N` 就记「用户可见名 → ABI 名」。它只读了 import info 三个分量里的 ABI 名，只覆盖有 builtin 记录的 C 值类型，只处理直接引用。当年没认出那串字符串是 `TypeImportInfo`，按现象拼了张映射表。

调用点只有两处，同一个模式：`ProtocolConformanceDumper.demangledSymbol(for:typeName:...)` 与 `ExtensionDefinition._symbol(for:typeName:...)` 把描述符推出的类型名和 witness 符号里的类型名做字符串比较，不等时查这张表兜底。提案 0023 之后描述符推出的名字就是 ABI 拼法，等式直接成立，兜底分支走不到。RuntimeViewer 与 Sources 里没有其它引用。

## 方案

删两个源文件、`Tests/IntegrationTests` 里它的测试、两处 `||` 兜底分支，以及 `PrintFailureEventTests.knownBaselineDebt` 里为它的 `dump()` 用 `print` 登记的那条历史欠账。比较语义不动，仍是字符串相等。

## 实际执行

按方案。`Documentations/Internal/ReviewAdjudications.md` 与 `StaticFieldOffsetComputation.md` 里各有一处提到它，都是带日期的记录或引文，保留。

## 验证

全量 `swift test --skip IntegrationTests`（退出码取自 `swift test` 本身）：1676 条 / 313 个 suite，只剩 `SharedCacheTests` 那对用墙钟断言并行度的已知假失败，单独重跑 2/2 通过。

## 与提案的偏离

无提案。
