# 0056 - 标记模式：一次打印全量 interface，并标出每段内容受哪个开关控制

- **状态**: Implemented
- **创建日期**: 2026-09-29
- **最后更新**: 2026-09-30
- **所属愿景**: 无
- **关联提案**: swift-semantic-string 的设计记录 `docs/VisibilityRegions.md`（`VisibilityRegion`、区域表与投影）；
  MachOObjCSection 的提案 0011 `visibility-regions`；RuntimeViewer 的 `draft-find-navigator`（使用方）
- **实现分支 / PR**: `feature/visibility-regions`
- **配套文档**: 无

## 摘要

RuntimeViewer 的 Find 在引擎里给每个类型存一份打印好的 interface 供全文搜索，要求「只打印一次，搜索时按用户当前的
显示选项只输出可见内容」，切换选项不重新打印（SwiftUI 打一遍约两分钟）。`SwiftDeclarationPrinter` 今天在输出点上
看 `configuration.printX` 决定打不打，打出来的文本里已经没有「换一组选项会多出什么」的信息；而且偏移、地址、布局
注释的文字可被 transformer 改写，一个成员有几行注释又取决于偏移、符号是否存在，调用方从文字和位置都认不出归属。
本提案给打印器加一个**标记模式**：受选项控制的内容全部打印，并用 `VisibilityRegion` 标上它在什么选项下可见。
调用方按任意选项组合投影这份输出，得到与该组合下普通打印逐字节相同的文本。

## 方案

- **开关**：`SwiftDeclarationPrintConfiguration.marksOptionalContent`（默认 `false`）。为 `true` 时下列选项不再决定
  打不打，而是决定区域的条件；其余配置（transformer、`memberSortOrder`、不属于下列的开关）照常生效。布局注释经
  `DeclarationRenderConfiguration.marksOptionalContent` 同样标记，打印器在构造它时传下去。
- **选项名**：`SwiftVisibilityOption`（`SwiftDeclarationRendering`，原始值 `swift.printFieldOffset` 这类）：
  `printStrippedSymbolicItem`、`printFieldOffset`、`printExpandedFieldOffsets`、`printMemberAddress`、
  `printVTableOffset`、`printPWTOffset`、`printTypeLayout`、`printEnumLayout`、`infersObjCOverridesFromSelectorNames`、
  `opaqueTypeResolution`。投影用的谓词是 `SwiftDeclarationPrintConfiguration.isVisibilityOptionEnabled(_:resolvesOpaqueTypes:)`；
  opaque 那一项不是配置属性，而是「是否注册了 opaque 类型解析器」，由调用方在取谓词时给出。
- **输出点**：打印器的 `optionalContent(_:content:)` 与 `DeclarationRenderConfiguration.optionalContent(_:content:)`
  在普通模式下按开关取舍、在标记模式下总是输出并包进区域；数据的计算（字段偏移、enum 布局、静态布局 provider）
  在标记模式下总是进行（`producesContent(for:)`）。覆盖：
  - `renderMember` 的偏移 / vtable / 地址注释与 `protocol-extension default`，deinit 的两条地址注释；
  - protocol 的 stripped symbolic item 整块（内层 PWT 偏移再嵌一层）；
  - 存储属性访问器的 vtable 注释；运行时与静态两个布局后端的字段偏移（展开偏移嵌在其内）、类型布局、enum 布局
    与 enum 前导注释，两种布局注释之间「两者都开才有」的换行用嵌套区域表达；
  - `@objc @implementation` 类的字段偏移注释；
  - opaque 类型：`TypeNodePrintable.printOpaqueReturnType` 照常写入 ` <约束>`，写完用
    `SemanticString.markAtoms(from:visibleUnder:)` 给这几个原子补上条件（`NodePrintableDelegate.marksOptionalContent`）；
  - `infersObjCOverridesFromSelectorNames`：两种判定的 `ResolvedObjCMemberFacts` 不同时（`printUnderObjCVerdicts`），
    整条声明按两种判定各打一遍，分别包进「开」与「关」的区域——开时加 `@objc` / `override` / `class`、去掉 `final`，
    不是单纯的增删。
- **容器**：不需要打印器处理。swift-semantic-string 的容器会把成员的条件带到自己打的换行、缩进与分隔符上（见其
  设计记录 `docs/VisibilityRegions.md`）。
- **不覆盖**：`printExportStatus`、`printExportedDeclarationsOnly`、`printSpareBitAnalysis`、
  `printConformancePWTAddress` 不是 RuntimeViewer 的选项，按配置原样处理；`memberSortOrder` 是重排，区域表达不了。
- **正确性**：`VisibilityRegionProjectionTests`（`SwiftInterfaceTests`）对 SymbolTestsCore 的每个顶层类型、协议与
  扩展断言「标记打印按某配置投影」与「按该配置直接打印」完全相等（文本、span、identifier）：进程内打印（运行时布局，
  RuntimeViewer 走的路径）覆盖全关、全开、每个选项单开与单关共 22 组，约 10 秒；从文件打印（静态布局）只变动四个
  布局选项共 10 组，因为其余输出与进程内相同。漏标的新输出点会在这里现形。
- **依赖**：需要 swift-semantic-string 带 `VisibilityRegion` 与 `markAtoms` 的版本；发布后抬远程依赖下限，此前本地
  构建走 `USING_LOCAL_DEPENDENCIES` 或 SwiftPM 的 edit 模式。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-09-29 | Created as Accepted | RuntimeViewer 的用户要求 Find「语料要为所有可能出现的内容进行索引，但是只输出匹配当前options的内容」，且「可以动上游MachOSwiftSection，目前打印2次的方法可能会有性能问题」。两个会话分别设计后比较，都认为归属只能由打印器在输出时给出。用户：「可以改，上游都是我自己的库，写提案直接开工吧」。 |
| 2026-09-29 | 不用「每个选项各打一遍再 diff」 | 每个类型多打三到六遍，SwiftUI 这种镜像不可接受；注释文字又会被 transformer 改写，diff 出来也认不出归属。 |
| 2026-09-29 | `synthesizeOpaqueType` 与 `infersObjCOverridesFromSelectorNames` 纳入标记 | 用户指出前者「输出的结果是固定的，只是要改的地方是返回值」；核实后它关掉时只剩 `some`，是纯删减。后者核实为替换（加 `@objc` / `override` / `class`，去 `final`），用同一选项的开、关两种区域表达。 |
| 2026-09-29 | 容器不需要打印器另外处理；opaque 约束用 `markAtoms` 事后补标 | 容器由 swift-semantic-string 按成员条件自动带上装饰。opaque 约束是 NodePrinter 经泛型输出目标逐段写入的，写完后给这几个原子补标，文本与原子个数都不变，也保住了类型引用作用域盖上的 identifier。 |
| 2026-09-29 | Accepted → In Progress | 实现与测试完成于 `feature/visibility-regions`（基于 `next` 7ba306ed），未提交。与同一提交的临时基线比较 `SwiftInterfaceTests` / `SwiftPrintingTests` / `SwiftDumpTests` / `SwiftDeclarationRenderingTests`：基线 41 + 256 + 95 + 39 全过，本分支多出两条对照测试，唯一的失败是源码扫描测试把名为 `print` 的闭包参数当成了标准输出，改名为 `render` 后复跑。快照测试两边都过，普通打印的输出没有变化。 |
| 2026-09-30 | In Progress → Implemented，编号 0056，合入 `next` | rebase 到 `next`（4d93f328，抛错版 `init(bitPattern:)` 收回本仓库）无冲突。本地依赖模式（MachOKit `next` 0.53.101、MachOKitExtensions、已合入 `VisibilityRegion` 的 swift-semantic-string `next`、MachOObjCSection `next`）下`USING_LOCAL_DEPENDENCIES=1 swift test --skip IntegrationTests` 原始退出码 0：19 批、2146 个测试、406 个套件全部通过，唯一的 known issue 是既有的 `SymbolicManglingIndexTests`。远程依赖下限未抬：`from: "0.3.0"` 的 swift-semantic-string 没有 `VisibilityRegion`，带它的版本发布后同批抬下限；在此之前 `next` 只能以 `USING_LOCAL_DEPENDENCIES=1` 构建。 |
| 2026-09-30 | 不另写使用指南与实现说明；术语表登记「marking mode（标记模式）」，账本记第 71 节 | 用法与契约写在 `marksOptionalContent` 与 `SwiftDeclarationPrinter+VisibilityRegions.swift` 的文档注释和本提案「方案」里，包括两条不在签名里的约定：transformer、排序与导出选项照常生效（在打印时定死，投影改不了），以及 opaque 类型约束要先注册解析器才有内容可标。「可见性区域」「投影」由 swift-semantic-string 的设计记录定义。 |
| 2026-09-30 | swift-semantic-string 的远程下限抬到 `from: "0.4.0"` | swift-semantic-string 0.4.0 发布（带 `VisibilityRegion`）。不开本地依赖构建（MachOKit 0.52.103、MachOKitExtensions 1.0.0、MachOObjCSection 0.8.107、swift-semantic-string 0.4.0）通过，打印相关的五组测试通过；`next` 从此不必再靠 `USING_LOCAL_DEPENDENCIES=1` 构建。 |
