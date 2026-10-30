# Draft - 导出过滤进入标记模式，C 导入类型不再判成未导出

- **状态**: In Progress
- **创建日期**: 2026-10-30
- **最后更新**: 2026-10-30
- **关联提案**: [0016](0016-exported-only-interface.md)（导出过滤）、[0024](0024-exported-declaration-flag.md)（类型 / 协议的 `exportStatus`）、[0056](0056-visibility-regions.md)（标记模式）；RuntimeViewer 的 `draft-exported-declarations-filter`（使用方）
- **实现分支 / PR**: `feature/exported-only-marking-mode`（worktree `.worktrees/MachOSwiftSection-ExportedOnlyMarkingMode`，基于 `next`）

## 摘要

RuntimeViewer 要加「只看导出的声明」：侧栏按 `exportStatus` 筛掉未导出的类型与协议，内容区、批量导出与 Find 删掉导出类型里未导出的成员。内容区打开 `printExportedDeclarationsOnly` 就行，Find 却不行：它的语料用标记模式打印——全量打一遍，受选项控制的内容标上可见条件，搜索时按当前选项投影——而 0056 把导出过滤明确留在了标记模式之外，开着这个选项 Find 照样搜得到未导出的成员。本提案让标记模式覆盖导出过滤。

排查中还发现一处裁决错误。C 导入类型（`__C.CGSize` 一类）的描述符是每个用到它的模块各自生成的一份副本：编译器对 Clang 声明一律给 `PublicNonUnique` 链接（`swift/lib/SIL/IR/SIL.cpp` 的 `getDeclLinkage`），副本从不进导出表，所以它的 `exportStatus` 读成 `.notExported`。可本镜像给它写的扩展可以是公开 API（SwiftUI 的 `extension CGSize: VectorArithmetic`）。RuntimeViewer 开着 `showCImportedTypes`，并把这类扩展并进 C 类型的条目，按类型筛会把它们一起藏掉；打印器的 `ExportFilterScope` 也会把这些类型收进「未导出」集合，开了 `--show-c-imported-types` 的 `--exported-only` 因此很可能删掉这些扩展（读代码推断，由第 1 步的测试确认）。

## 方案

1. **C 导入类型不裁决**（已完成）。`ExportStatus` 加一个不给结论的 case `declarationIsCImported`：`ExportStatus.resolve` 遇到 `isCImportedContextDescriptor` 为真（模块是 `__C` 或 `__C_Synthesized`）的描述符直接返回它，`isExported` 为 `nil`，`isDefinitelyNotExported` 为 `false`。两个 `resolve` 入口因此改为接收描述符本身（原先只收 offset），类型与协议走同一条规则。于是 `ExportFilterScope` 不再收这些类型，它们的扩展照常按成员裁决，`--exported-only --show-c-imported-types` 也不再删 C 类型本身，ExportedOnlyInterfaceFiltering.md「已知降级」里的那一条随之撤掉。
   - 复现测试：现场编译的 fixture（当时在 `ExportedOnlyLibraryEvolutionFixtureTests` 里，第 2 步挪成共享的 `ExportedOnlyFixture`）加了 `CGPoint` 的公开扩展与对 `PublicContract` 的 conformance，`cImportedTypeIsNotRuledOnAndItsPublicExtensionsAreKept` 以 `showCImportedTypes: true` 打印 `--exported-only`。修复前它的四条断言全红：`CGPoint` 判成未导出，类型本身、conformance 扩展与公开扩展一起被删，扩展那一腿的推断成立。`ExportStatusTests.cImportedTypeIsNotRuledOn` 在 SymbolTestsCore 唯一的 C 导入类型 `CMTimeFlags`（描述符是 private external）上钉住新 case。
2. **标记模式覆盖导出过滤**（已完成）。`SwiftVisibilityOption` 加 `printExportedDeclarationsOnly`（原始值 `swift.printExportedDeclarationsOnly`），`isVisibilityOptionEnabled` 认它。标记模式下，过滤器原本不输出的每一处——类型、协议、扩展三个打印入口，被清空的普通扩展，成员循环，存储属性的预筛，以及 `printRoot` 的两个全局块与 ObjC category conformance 块——改为照常输出，标上 `.disabled("swift.printExportedDeclarationsOnly")`。判定沿用同一组 `isExcludedByExportFilter`，标记模式下不看开关本身的取值（`evaluatesExportFilter`），每处都问 `exportFilterVisibility(excluded:)` 要「输出 / 略过 / 标记」；已经打好的 `SemanticString` 用 `visible(under:)`（即 `markAtoms(from:visibleUnder:)`）补标。`ExportFilterScope` 照旧要由宿主装上，`printRoot()` 在标记模式下也装。conformance 扩展被清空后印成 `{}`、相邻声明之间不多出空行，交给 swift-semantic-string 的容器把成员的条件带到分隔符上，与其他选项一样；容器管不到的只有 `DeclarationBlock` 闭合 `}` 前的换行（见决策日志），由打印器补：类型与扩展 body 里嵌套定义之后的声明全被过滤时，标记模式下去掉那部分最后的换行（`bodyAfterNestedDefinitions(of:content:)`）。普通模式的输出逐字节不变。
   - 测试：现场编译的模块挪进 `MachOTestingSupport` 成为共享的 `ExportedOnlyFixture`，另加五个定义：嵌套类型保留、之后的声明全被过滤的类型（`Holder`）、存储属性是 internal 的类型（`FieldHolder`）、无 case 的枚举（`Namespace`）、别的模块类型的扩展（`extension Int`），以及什么都不剩的 `Hidden`。`VisibilityRegionProjectionTests` 的每个打印器都装同一个 scope，选项组合里多了这个选项：SymbolTestsCore 进程内全关、全开与每个选项单开单关（24 组），从文件打印仍只变动布局选项；`ExportedOnlyFixture` 逐个定义按开关开、关投影（`exportedOnlyFixturePrintsProjectToTheFilterBothWays`），整份 `printRoot()` 也投影一次（`exportedOnlyFixtureRootPrintProjectsToTheFilterBothWays`）。两个探针确认测试会红：标记模式退回不管导出过滤时三条投影测试都红；不去掉 body 末尾的换行时，上述四种形态投影到开关打开都印成 `}}`。
3. **宿主须知**（已完成，随第 2 步提交）写进 `marksOptionalContent` 与 `installExportFilterScope` 的文档注释：标记打印同样要先装 scope，否则扩展这一腿全部保留。

不做：

- 成员不加模型上的导出标志。类型或协议没导出，它的成员与嵌套类型必然也没导出（成员的有效访问级别受所在类型限制，见 `ValueDecl::getEffectiveAccess`），宿主按类型筛就够；导出类型里未导出的成员由打印器删，RuntimeViewer 的成员搜索读的是投影。
- `printExportStatus`（`// not exported` 标注）、dump 路径、ObjC 一侧都不动。

兼容性：给 `ExportStatus` 加 case 会让宿主里穷举的 `switch` 编译不过；RuntimeViewer、MachOKitUI、MachOViewer、swift-decompiler 目前都没有用它，0024 选枚举时也为新增结局留了位置。`SwiftVisibilityOption` 加 case 同理，这四个仓库都没有穷举它：RuntimeViewer 只经 `isVisibilityOptionEnabled(_:resolvesOpaqueTypes:)` 投影，会自动认出新选项。`--exported-only` 的说明本来就写着「没有导出证据的一律保留」，C 类型落进这一条，flag 文案与 agent 插件 skill 不用改。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-10-30 | Created as Draft | RuntimeViewer 要过滤未导出的类型与成员，Find 依赖的标记模式不覆盖导出过滤；排查中发现 C 导入类型被判成未导出，会连带藏掉本镜像给它写的公开扩展。用户批准分两份提案推进：本库一份，RuntimeViewer 一份。 |
| 2026-10-30 | 成员级的导出判断不下沉到模型 | 类型或协议没导出时，它的成员与嵌套类型必然没导出（编译器按所在类型限制成员的有效访问级别）。还需要成员级判断的只剩导出类型内部、别的模块类型的扩展与全局声明，这些都由打印器处理，RuntimeViewer 读投影即可。 |
| 2026-10-30 | C 导入类型在裁决源头改为不给结论，不在扩展那一腿特判 | 错在裁决本身：描述符副本的导出状态说明不了类型能否被外部使用。改在源头，宿主的侧栏、过滤范围与 `exportStatus` 的其他读者一起正确。 |
| 2026-10-30 | Draft → Accepted | 用户批准，开始实现。 |
| 2026-10-30 | Accepted → In Progress；新 case 定名 `declarationIsCImported` | 实现在 `feature/exported-only-marking-mode`。暂名 `cImportedDeclaration` 改成与同枚举的 `declarationHasNoSymbol` 同一句式（主语 + 谓语），读作「这个声明是 C 导入的」，`exportStatus == .declarationIsCImported` 在调用处读得通。 |
| 2026-10-30 | 协议描述符也走 C 导入检查 | 规则针对的是描述符而不是种类：Clang 的协议在 Swift 里没有协议描述符，这条检查在协议上不会命中，但两个入口共用一条规则，以后出现例外也不会漏。代价是每个协议多读一次上下文链。 |
| 2026-10-30 | `DeclarationBlock` 闭合换行由打印器补，不改 swift-semantic-string | 方案原以为分隔符全交给容器即可。`DeclarationBlock` 是例外：它按全量打印的 body 最后一个字节决定补不补闭合换行，swift-semantic-string 的设计记录把这列为已知限制。别的选项只控制注释，从不改变 body 的最后一个字节；导出过滤会删掉整段声明，body 留着嵌套类型、之后的声明全被过滤时，投影到开关打开就印成 `}}`。在容器里修要给条件加取反、发新版再抬依赖，超出本提案范围；打印器知道哪些声明被过滤，在标记模式下去掉那部分最后的换行，交给块自己补一个条件为「body 任一部分可见」的换行，各种投影下都对。 |
| 2026-10-30 | `printRoot` 的全局块与 ObjC category conformance 块一并标记 | 方案列的是打印器的入口，但原则是「过滤器原本不输出的每一处」。这两处也会删内容，不标就会让 `printRoot()` 的标记打印投影出错。逐个定义打印的 RuntimeViewer 用不到，但 `printRoot` 的契约要和逐个定义的一致。 |
| 2026-10-30 | 现场编译的模块挪进 `MachOTestingSupport` | 投影测试与原来的过滤测试要用同一份模块，照 `ModuleSelectorFixture` 的样子做成共享的 `ExportedOnlyFixture`，每个进程只编一次。 |
| 2026-10-30 | 实现完成，待用户看过后收尾 | 三步都已提交。验证（JHs-Mac-Studio-Ultra）：全量 2,738 个测试、518 个套件只红 `ThunkOnlyObjCMemberTests` 4 条，`next` 快照在同一工具链下同样红、换 Xcode 26.6 则绿，是现场编译 fixture 随编译器漂移的既有问题；Xcode 26.6 下编译通过、相关 9 个套件全过；临时探针在本机 dyld cache 的 Combine、SwiftUICore、AppKit 上逐个定义比对标记打印的投影，848 / 14,086 / 2,879 个定义全部一致。普通打印的路径在构造上逐字节不变、SymbolTestsCore 的 interface 快照通过，不算大重构，未跑渲染 A/B。文档：不另写使用指南或实现说明，ExportedOnlyInterfaceFiltering.md 加了「C 导入类型不裁决」与「标记模式」两节，术语表的 marking mode 与 exported-only 过滤两条已更新、没有新术语，演进账本按日期占位，节号落地时取。 |
