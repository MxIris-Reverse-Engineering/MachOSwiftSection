# SwiftInterface 模块

> 模块参考文档（module reference），随代码维护。读者：维护者。
> 细节文档见文末[「相关文档」](#相关文档)；本文负责全貌与分工，不复述细节。

## 模块定位

SwiftInterface 是接口生成的**编排层**（thin orchestrator）：它自己不索引、不打印、不算 diff，而是把下层的 `SwiftIndexing`（建声明模型）、`SwiftPrinting`（渲染声明）、`SwiftDiffing`（ABI 键与 lineage 事实）组合成三种**面向人读的输出产品**：

1. **单版本完整 interface** —— `SwiftInterfaceBuilder.printRoot()`，`swift-section interface` 与 RuntimeViewer 的主路径；
2. **两版本 diff interface** —— `SwiftDiffableInterfaceRenderer`，整份接口逐行标 `+`/`-`/` `，`swift-section diff --interface`；
3. **N 版本 evolution interface** —— `AnySwiftEvolutionInterfaceBuilder`，并集接口 + 生命周期注解（`// [●●○] removed in 26.0`），`swift-section evolution --interface`。

产品 2 与 3 共享同一套结构遍历核心 `InterfaceUnionWalker`（演进提案 0014 的统一），只在「呈现策略」上分叉。另有一个不渲染的旁支：`SwiftDiffableInterfaceBuilder` 把索引结果**冻结**成 `ABIModule` / `ABISnapshot`，是 `SwiftDiffing` 数据管线（change list / JSON / lineage 报告）的输入生产者——渲染路径和纯数据路径吃的是同一份冻结事实，这是两边永不打架的根基。

下游消费者：`swift-section` CLI（`InterfaceCommand` / `DiffCommand` / `EvolutionCommand`）、`TypeIndexing`（它的 provider 实现本模块的注入协议）、RuntimeViewer 等宿主（走 `@_spi(Support)` 的结构化流）。

## 文件 → 子系统对照

| 子系统 | 文件 |
|---|---|
| 1. 单版本接口生成 | `SwiftInterfaceBuilder`、`SwiftInterfaceBuilderConfiguration`、`SwiftInterfaceBuilderDependencies`、`DependencyPath`、`SwiftInterfaceBuilderExtraDataProvider` |
| 2. Opaque 返回类型解析 | `SwiftInterfaceBuilderOpaqueTypeProvider`、`ProtocolFactsResolver`、`BuiltinStandardLibraryProtocolFacts`、`OpaqueSameTypeConstraint` |
| 3. 共享 union 走查 | `InterfaceUnionWalker`、`InterfaceVersionRendering` |
| 4. 两侧 diff 渲染 | `SwiftDiffableInterfaceBuilder`、`SwiftDiffableInterfaceRenderer`（含 `DiffUnionStrategy`）、`DiffMarking`（含 `DiffMarker`/`DiffLine`）、`DiffContainerAssembler`、`DiffFormat`、`UnifiedDiffFormatter`、`SwiftDeclarationPrinter+DiffRendering` |
| 5. N 路 evolution 渲染 | `AnySwiftEvolutionInterfaceBuilder`、`SwiftEvolutionInterfaceBuilder`（pack façade）、`SwiftEvolutionInterfaceRenderer`、`EvolutionAnnotationIndex`、`EvolutionLine`（含 `EvolutionAnnotation`）、`EvolutionMarking`（含 `EvolutionContainerAssembler`） |

## 子系统 1：单版本接口生成

`SwiftInterfaceBuilder<MachO: FieldLayoutRenderable>` 持有一对 `SwiftDeclarationIndexer` + `SwiftDeclarationPrinter`（`@_spi(Support)` 暴露，宿主可直接触达），生命周期是两步：`prepare()` 然后 `printRoot()`。

**`prepare()` 的顺序与失败语义**：先逐个 `extraDataProvider.setup()`（失败**降级**为 `renderingDegraded` 事件，不阻断——外挂数据源坏了不该毁掉整份接口），再 `indexer.prepare()`（失败**抛出**），最后 `collectModules()`（失败**抛出**）。全程用 `phaseTransition` 事件汇报阶段。

**`collectModules()`**：import 列表不来自 load command，而是扫全部符号的 demangle 树收 `.module` 节点——binary 里真正被引用的模块才进 import。过滤 `__C` / `__ObjC` / stdlib 三个伪模块；`internalModules`（`Swift`、`_Concurrency`、`_StringProcessing`、`_SwiftConcurrencyShims`）恒定并入。

**`printRoot()` 的段落与 catch 契约**：组成顺序是 header（提案 0008，flag-gated 默认缺席）→ imports → 全局变量 → 全局函数 → 根类型 → 特化变体（`specializedChildren` 挂在各 `TypeDefinition` 上，indexer 对用户驱动的特化保持无知，所以这里全量走查 `allTypeDefinitions`）→ 根协议 → **嵌套**协议的 default-implementation 扩展块（extension 不能嵌进父体，顶层补印；这个循环在提案 0007 之前是死代码）→ 四桶 extension（`isAttachedToProtocolDefinition` 的已附着定义被过滤，避免 issue #106 §5 的重复块）。贯穿全部段落的契约是**逐定义 catch**：一个定义打印抛错只丢它自己，绝不空掉整块（历史上块级 catch 让一个旧 binary 的全部类型被抹白；由 `LegacyDyldInfoBindTests` 与 `corruptNestedChildDropsOnlyItself` 钉住）。两个全局块例外地不带定义上下文——`printVariable`/`printFunction` 本身不抛、各自派发过失败事件，块级包裹只是保险带。

**`SwiftInterfaceBuilderExtraDataProvider`**：外部数据源的注入缝，纯生命周期钩子——`Sendable` + 一个默认为空的 `setup()`（提案 0015 之前它还继承 printer 的 resolver 协议，强迫所有 provider 都是类型名解析器）。「会不会回答 printer 查询」是正交能力：provider 按需另行声明 `SwiftPrinting` 的角色协议（`ModuleNameResolving` / `CImportedNameResolving` / `OpaqueTypeResolving`，均 refine 空标记协议 `TypeNameResolving`），`addExtraDataProvider(_:)` 用 `as? any TypeNameResolving` 命中才把它转发给 printer——所以一个 resolver 型 provider 一头挂在 builder 的 prepare 生命周期上，一头挂在打印热路径上，而纯 setup 型 provider（只预热缓存之类）也是合法形态。两个已知实现：`TypeIndexing.SwiftInterfaceBuilderTypeNameProvider`（`__C` 模块归属，跨模块，声明两个名字角色）和本模块的 `SwiftInterfaceBuilderOpaqueTypeProvider`（声明 `OpaqueTypeResolving`，见子系统 2）。

**`SwiftInterfaceBuilderDependencies` + `DependencyPath`**：把「主 binary + 它的依赖镜像」凑成一组，按 reader 分特化——`MachOFile` 版从 `DependencyPath`（单个 Mach-O 路径 / dyld cache 路径 / 宿主系统 cache）按 install name 匹配装载，装载失败走 `renderingDegraded` 事件（默认无 handler 也有 os_log 地板）；`MachOImage` 版直接按名字向 dyld 要。消费者是 CLI 的 `InterfaceCommand` 与 `TypeIndexing`（依赖过滤 + 惰性 ObjC 元数据索引都需要依赖镜像清单）。

## 子系统 2：Opaque 返回类型解析

把 `some P` 的占位还原成带 primary associated type 实参的完整拼写（`some Collection<Int> & Sendable`）。领域细节已有两篇专文——[OpaqueReturnTypeResolution.md](../OpaqueReturnTypeResolution.md)（descriptor 编码、anchor/塌缩机制、字节级调试）与 [OpaquePrimaryAssociatedTypeAttribution.md](../OpaquePrimaryAssociatedTypeAttribution.md)（提案 0011 的实现说明）——本节只给文件分工：

- **`SwiftInterfaceBuilderOpaqueTypeProvider`**：入口，也是一个 `ExtraDataProvider`（挂到 builder 上，printer 打印 `some` 返回类型时经 `opaqueType(forNode:index:)` 回查）。从符号表定位 opaque type descriptor，把 generic requirements 拆成协议项与 same-type 项，逐协议调用归属判定（anchor 直接命中 → refine 闭包 → 名字兜底，兜底四条件缺一不可——宁可少一个实参也不捏造一个）。
- **`OpaqueSameTypeConstraint`** / **`OpaqueDependentMemberProjection`**：从 requirement 节点里挖出来的单条 same-type 约束（区分正向 pin `τ.Name == X` 与反向 pin `outer == τ.Name`，后者渲染期经 `SubstitutionMap` 回溯）及其解析器。
- **`ProtocolFactsResolver`**：按「可达 descriptor 优先、内置表兜底」的链条解析协议事实（自声明的 associated type 名、refine 闭包），`refineClosureContainsAnchor` 对不完整闭包返回三态（命中 / 完整排除 / `nil` 不可证）。
- **`BuiltinStandardLibraryProtocolFacts`**：冻结的 stdlib 协议表——**primary associated type 名单与顺序的唯一来源**（SE-0346 不留运行时痕迹），也是离线 bind-only 外部协议的兜底。无 associated type 的协议也登记空条目，让归属能说「确定不附着」而非降级。

## 子系统 3：共享 union 走查（提案 0014）

diff 与 evolution 两条比较渲染路径的公共结构核心。分工是这个子系统的全部要点：

- **`InterfaceUnionWalker` 拥有结构**：N 版本按 `ABIKey` 匹配（与 `ABIDiffer` 冻结进 snapshot 的同一套键构造，所以渲染视图与数据视图的匹配永远一致）；并集排序 = 最新版本的声明顺序做脊柱，缺席声明按「最后携带它的版本」的顺序追加；每版本键 first-wins（**含发射**——同键后来者不会被发射第二次）。extension 桶按 `ABIDiffer.extensionContainerKey` 拆成 per-(target, protocol, where, retroactive) 容器；成员经 `UnionRenderableMember`（identity/payload 键取自 differ 冻结的同一 `MemberRecord` 投影）构造；类别调度走 `MemberCategory.allCases`；body 组装顺序镜像 `printTypeDefinition`。
- **`InterfaceUnionEmitting` 策略拥有呈现**：五个定制点——type/protocol header 解析（返回 `nil` 则整个声明连体丢弃：没有 header 行的成员不是合法 Swift）、extension header 包装、成员发射（一个 match 出零到多个 unit）、容器组装。真正双侧语义（`HeaderOutcome` 配对）留在 diff 策略、注解锚定留在 evolution 策略，绝不上提进 walker。
- **`InterfaceVersionRendering` / `InterfaceVersionUnit`**：版本抽象缝。每个版本 = 一个 `SwiftDiffableInterfaceBuilder` + 一个共享其事件 dispatcher 的 printer（dispatcher 共享是修过的坑：裸 `.init(in:)` 的 printer 没有 sink，diff 路径曾整条静默吞失败）。reader 泛型在此擦除且无损——walker 对 printer 的全部消费就是「把这个成员渲染成 `SemanticString`」，没有任何 `MachO` 类型的值跨缝。
- **成员一律在 printer level 0 渲染**：变量/下标 printer 会按 `level` 绝对烘焙 accessor 块内部缩进，而两个格式层又按行自缩进——真实 level 渲染会让 `get`/`}` 双重缩进（diff 路径在统一前正是带着这个缺陷；`DiffMemberIndentationTests` 钉住）。

## 子系统 4：两侧 diff 渲染

数据流：`SwiftDiffableInterfaceBuilder` ×2（prepare）→ `SwiftDiffableInterfaceRenderer`（包成 `[old, new]` 双元素轴）→ walker + `DiffUnionStrategy` → 分类流 `[[DiffLine]]` → `DiffFormat` → 最终文本。

- **`SwiftDiffableInterfaceBuilder`**：`SwiftInterfaceBuilder` 的 ABI-diff 对应物——索引后不打印而是冻结。`prepare()` 必须自己驱动逐定义的 `index(in:)`：成员索引平时由 printer 惰性触发，differ 不打印，没人替它触发。`abiModule()` 是 indexer 属性的纯投影；`snapshot()` 直通 `Codable` 快照（存基线、离线 diff）。
- **`DiffUnionStrategy`**：三路成员发射（unchanged 发新侧 ` `、added/removed 发单侧、modified 发 `-` 旧行 + `+` 新行），带**同文塌缩**——payload 键（remangle）变了但两侧渲染逐字节相同（symbolic reference、私有判别符被 `.default` 打印抹掉的场合）就塌成一条上下文行，change list 里仍记录键变。header 走 `HeaderOutcome` 三态（absent / rendered / failed，**不是** `SemanticString?`——「本侧没有这个声明」和「有但渲染失败」曾被同一个值表示，混同的后果是空 header 顶着成员出场）；两侧**总是都尝试**，单侧失败由另一侧顶替站位，失败在失败侧自己的 dispatcher 上派发。
- **分类流 / 格式层分离**：renderer 永不把 `+`/`-` 符号烤进文本，只产 `[[DiffLine]]`（marker + 裸单行内容 + indentLevel；`@_spi(Support) annotatedDiffBlocks()` 直接暴露给宿主）。`DiffFormat` 是唯一的符号化缝：`inline`（git-diff 风格，marker 占 0 列 + 一格 gutter）、`markdownFenced`（```` ```diff ````围栏，围栏长度自适应内容里的反引号串）、`unified(contextLines:)`（真 unified diff，`git apply` 可消费，gutter 为空）、`perLine` 最小扩展点。`UnifiedDiffFormatter` 独立成文件做行号 / hunk 分组。
- **`DiffMarking` / `DiffContainerAssembler`**：纯函数格式工具。`markLines`（急切成串）与 `markedLines`（结构化）共享同一条 per-line 规则，防两路漂移；`splitIntoLines` 故意开 internal 给 `EvolutionMarking` 复用。assembler 管容器组装：added/removed 容器整体带 marker、common 容器 header 变了才 `-`/`+` 成对、空 body 内联 ` {}`。
- **`SwiftDeclarationPrinter+DiffRendering`**：diff 专用的 `package` 打印入口（无 body 的 type/protocol header、独立 `deinit` / `associatedtype` 行）。放本模块而非 `SwiftPrinting` 是刻意的——只服务 diff 路径的帮手不该混在共享渲染原语旁边；但 header 渲染义务上要与 `printTypeDefinition` / `printProtocolDefinition` 的 header 部分**保持同步**（源码注释里有 keep-in-sync 标记）。

## 子系统 5：N 路 evolution 渲染（提案 0013）

N ≥ 2 版本渲染成**一份**并集接口，声明尾注生命周期注解。承重决策是**事实与文本的分工**：

- **注解事实只来自 `ABIEvolution`**：`prepare()` 逐版本索引 → 冻结 snapshot → `ABIEvolutionBuilder` 建 lineage 矩阵；渲染期经 `EvolutionAnnotationIndex` 按键查询，**查不到即是「全程在场、从未变化」的裁决**（`ABIEvolution` 只物化有变化的 lineage），渲染为无注解。策略自己绝不重推事件，所以注解接口、lineage 报告、JSON 三个视图永不打架。
- **渲染文本来自活模型**：每个声明由最后携带它的版本的 printer 渲染（modified 成员只显示最新一代，旧形态进注解短语 `modified in 26.0: old → new`；箭头两侧相同则塌回裸短语）。header 解析是「最新可渲染」：从新到旧找第一个渲染成功的版本，每次失败都在其版本自己的 dispatcher 上派发，全部失败才整体丢弃（diff 的 drop-whole 规则推广到 N 侧）。
- **公开面是两个类型**：`AnySwiftEvolutionInterfaceBuilder` 是类型擦除的 runtime-N 主力（同构数组 init + 异构 pack init 都全平台可用——pack 在*函数*位不需要可用性门槛），CLI 与宿主的用户选版场景都走它；`SwiftEvolutionInterfaceBuilder<each MachO>` 是 pack 泛型 façade（类型位的 pack 需要 Swift 5.9 运行时，故 `@available(macOS 14…)`；构造即擦除，行为逐字节一致，由 `packGenericFacadeMatchesTheErasedBuilder` 钉住）。工具链尚不支持 `repeat each MachO == M` 的同元素约束，所以数组 init 上不了 pack 类型——这是两个类型并存的直接原因。
- **格式层 `EvolutionMarking`**（+ `EvolutionContainerAssembler`）：legend 头两行（轴 + bitmap 位置对照）、注解列按块对齐、上限 72 列（超限换行缩一级）、锚点规则（成员注解锚**首行**——attribute 内联，computed property 的注解不能沉到 accessor 块闭括号；容器 header 锚**末行**——带 `{` 的那行）、镜像 `ABIEvolutionReporter` 措辞的 warnings 尾巴。与 `DiffMarking` 故意不合并：marker 按行、注解按 unit 锚定，是真不同语义。
- **结构化流**：`@_spi(Support) annotatedBlocks()` → `[[EvolutionLine]]`（`EvolutionAnnotation` 是纯数据——presence bitmap + `LineageEvent`s），宿主可自行着色/折叠。

限制：输入必须全是 binary（snapshot 没有可渲染接口）；协议的 `pwtslot:` 记录不渲染（没有对应声明，与 `diff --interface` 一致，变化仍见于 lineage 报告与 JSON）。

## 消费入口速查

| 入口 | 路径 |
|---|---|
| `swift-section interface` | `SwiftInterfaceBuilder`（+ `--resolve-c-module-names` 挂 TypeIndexing provider，opaque provider 默认挂） |
| `swift-section diff --interface` | `SwiftDiffableInterfaceBuilder` ×2 + `SwiftDiffableInterfaceRenderer` |
| `swift-section evolution --interface` | `AnySwiftEvolutionInterfaceBuilder`（与 `--json`/`--summary-only` 互斥） |
| `swift-section diff` / `snapshot` / `evolution`（数据路径） | `SwiftDiffableInterfaceBuilder.abiModule()/snapshot()` → SwiftDiffing |
| RuntimeViewer 等宿主 | `@_spi(Support)`：indexer/printer 直达、`annotatedDiffBlocks()`、`annotatedBlocks()`；`InterfaceHeaderBlock` 是独立组件（per-type 导出不走 `printRoot`） |

## 相关文档

- [Evolutions/0013](../../Evolutions/0013-swift-evolution-interface-builder.md) —— evolution 渲染的提案（决策记录，含 API 全貌与决策日志）
- [Evolutions/0014](../../Evolutions/0014-unify-interface-renderers.md) —— union walker 统一的提案
- [Evolutions/0011](../../Evolutions/0011-opaque-primary-associated-type-attribution.md) / [OpaquePrimaryAssociatedTypeAttribution.md](../OpaquePrimaryAssociatedTypeAttribution.md) / [OpaqueReturnTypeResolution.md](../OpaqueReturnTypeResolution.md) —— opaque 子系统
- [InterfaceHeaderAndExportStatusAnnotations.md](../InterfaceHeaderAndExportStatusAnnotations.md) —— 接口头部与导出状态标注（提案 0008；header 组件在本模块消费）
- [DiffableInterfacePlan.md](../DiffableInterfacePlan.md) —— diff 接口的原始实现计划（历史文档，统一前的形态）
- [ABIDiffDesignAndLimitations.md](../ABIDiffDesignAndLimitations.md) / [ABIEvolutionDesign.md](../ABIEvolutionDesign.md) —— 下层 SwiftDiffing 的键方案与 lineage 模型
- [LeafMigrationRegressionFixes.md](../LeafMigrationRegressionFixes.md) —— `printRoot` 逐定义 catch 契约的来历
- [SwiftModularizationMigration.md](../SwiftModularizationMigration.md) —— SwiftInterface 单体拆成分层对等模块的迁移记录
