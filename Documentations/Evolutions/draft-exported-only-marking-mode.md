# Draft - 导出过滤进入标记模式，C 导入类型不再判成未导出

- **状态**: Draft
- **创建日期**: 2026-10-30
- **最后更新**: 2026-10-30
- **关联提案**: [0016](0016-exported-only-interface.md)（导出过滤）、[0024](0024-exported-declaration-flag.md)（类型 / 协议的 `exportStatus`）、[0056](0056-visibility-regions.md)（标记模式）；RuntimeViewer 的 `draft-exported-declarations-filter`（使用方）

## 摘要

RuntimeViewer 要加「只看导出的声明」：侧栏按 `exportStatus` 筛掉未导出的类型与协议，内容区、批量导出与 Find 删掉导出类型里未导出的成员。内容区打开 `printExportedDeclarationsOnly` 就行，Find 却不行：它的语料用标记模式打印——全量打一遍，受选项控制的内容标上可见条件，搜索时按当前选项投影——而 0056 把导出过滤明确留在了标记模式之外，开着这个选项 Find 照样搜得到未导出的成员。本提案让标记模式覆盖导出过滤。

排查中还发现一处裁决错误。C 导入类型（`__C.CGSize` 一类）的描述符是每个用到它的模块各自生成的一份副本：编译器对 Clang 声明一律给 `PublicNonUnique` 链接（`swift/lib/SIL/IR/SIL.cpp` 的 `getDeclLinkage`），副本从不进导出表，所以它的 `exportStatus` 读成 `.notExported`。可本镜像给它写的扩展可以是公开 API（SwiftUI 的 `extension CGSize: VectorArithmetic`）。RuntimeViewer 开着 `showCImportedTypes`，并把这类扩展并进 C 类型的条目，按类型筛会把它们一起藏掉；打印器的 `ExportFilterScope` 也会把这些类型收进「未导出」集合，开了 `--show-c-imported-types` 的 `--exported-only` 因此很可能删掉这些扩展（读代码推断，由第 1 步的测试确认）。

## 方案

1. **C 导入类型不裁决。** `ExportStatus` 加一个不给结论的 case（暂名 `cImportedDeclaration`）：`ExportStatus.resolve` 遇到 `isCImportedContextDescriptor` 为真（模块是 `__C` 或 `__C_Synthesized`）的描述符直接返回它，`isExported` 为 `nil`，`isDefinitelyNotExported` 为 `false`。于是 `ExportFilterScope` 不再收这些类型，它们的扩展照常按成员裁决，`--exported-only --show-c-imported-types` 也不再删 C 类型本身，ExportedOnlyInterfaceFiltering.md「已知降级」里的那一条随之撤掉。
   - 先写复现测试：在现场编译的 fixture（`ExportedOnlyLibraryEvolutionFixtureTests` 那一套）里加一个 C 结构体的公开扩展与 conformance，以 `showCImportedTypes: true` 打印 `--exported-only`，断言二者保留，并确认修复前失败。若修复前就通过，说明扩展那一腿的推断不成立，测试改为钉住新 case 与 C 类型本身被保留，并在决策日志记下。
2. **标记模式覆盖导出过滤。** `SwiftVisibilityOption` 加 `printExportedDeclarationsOnly`（原始值 `swift.printExportedDeclarationsOnly`），`isVisibilityOptionEnabled` 认它。标记模式下，过滤器原本不输出的每一处——类型、协议、扩展三个打印入口，被清空的普通扩展，成员循环，存储属性的预筛——改为照常输出，包进 `VisibilityRegion(.disabled("swift.printExportedDeclarationsOnly"))`。判定沿用同一组 `isExcludedByExportFilter`，标记模式下不看开关本身的取值；`ExportFilterScope` 照旧要由宿主装上。conformance 扩展被清空后印成 `{}`、相邻声明之间不多出空行，交给 swift-semantic-string 的容器把成员的条件带到分隔符上，与其他选项一样。普通模式的输出逐字节不变。
   - `VisibilityRegionProjectionTests` 加这个选项开、关两组（两边装同一个 scope），断言「标记打印按该配置投影」与「按该配置直接打印」完全相等。fixture 用 SymbolTestsCore（它导出全部 internal，未导出的是 private 声明）与第 1 步的现场编译模块。
3. **宿主须知**写进 `marksOptionalContent` 与 `installExportFilterScope` 的文档注释：标记打印同样要先装 scope，否则扩展这一腿全部保留。

不做：

- 成员不加模型上的导出标志。类型或协议没导出，它的成员与嵌套类型必然也没导出（成员的有效访问级别受所在类型限制，见 `ValueDecl::getEffectiveAccess`），宿主按类型筛就够；导出类型里未导出的成员由打印器删，RuntimeViewer 的成员搜索读的是投影。
- `printExportStatus`（`// not exported` 标注）、dump 路径、ObjC 一侧都不动。

兼容性：给 `ExportStatus` 加 case 会让宿主里穷举的 `switch` 编译不过；RuntimeViewer、MachOKitUI、MachOViewer、swift-decompiler 目前都没有用它，0024 选枚举时也为新增结局留了位置。`--exported-only` 的说明本来就写着「没有导出证据的一律保留」，C 类型落进这一条，flag 文案与 agent 插件 skill 不用改。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-10-30 | Created as Draft | RuntimeViewer 要过滤未导出的类型与成员，Find 依赖的标记模式不覆盖导出过滤；排查中发现 C 导入类型被判成未导出，会连带藏掉本镜像给它写的公开扩展。用户批准分两份提案推进：本库一份，RuntimeViewer 一份。 |
| 2026-10-30 | 成员级的导出判断不下沉到模型 | 类型或协议没导出时，它的成员与嵌套类型必然没导出（编译器按所在类型限制成员的有效访问级别）。还需要成员级判断的只剩导出类型内部、别的模块类型的扩展与全局声明，这些都由打印器处理，RuntimeViewer 读投影即可。 |
| 2026-10-30 | C 导入类型在裁决源头改为不给结论，不在扩展那一腿特判 | 错在裁决本身：描述符副本的导出状态说明不了类型能否被外部使用。改在源头，宿主的侧栏、过滤范围与 `exportStatus` 的其他读者一起正确。 |
