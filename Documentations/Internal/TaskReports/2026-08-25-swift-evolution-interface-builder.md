# 2026-08-25 · SwiftEvolutionInterfaceBuilder：演进并集注解接口

## 问题

用户诉求：「写一个 SwiftEvolutionInterfaceBuilder，目前的 ABIEvolutionBuilder 输出太难看了」。
`swift-section evolution` 唯一的人读输出是 `ABIEvolutionReporter` 的 lineage 清单
（`[●●○] 名字` + 缩进事件行）：不是代码的形状、成员脱离容器语法上下文、只有变化没有
幸存者。两版本场景已有 `diff --interface`（完整接口 + git-diff 标记），N 版本没有对应物。

## 调研结论

- 两侧注解接口链路（`SwiftDiffableInterfaceBuilder` + `SwiftDiffableInterfaceRenderer`）
  的全部构件可复用：per-member 渲染单元、`HeaderOutcome` 三态失败处理、extension
  容器拆分（`ABIDiffer.extensionContainerKey` 同源）、`DiffMarking` 行拆分。
- `ABIEvolution` 只物化**有事件**的 lineage（changes-only 契约）——这直接决定了
  「注解 = lineage 查表命中，没注解 = 全程未变」的设计成立。
- 快照（`ContainerSnapshot`/`MemberRecord`）只有单行签名字符串，无嵌套、无 printer
  保真度 ⇒ interface 模式必须全二进制输入。
- 快照的 key 构造（容器 `ABIKey.makeUnwrappingType` / `extensionContainerKey`、成员
  `MemberRecord.make*`）与两侧 renderer 的匹配 key 完全一致 ⇒ 活模型渲染 + lineage
  注解可以按 key 无缝 join。
- parameter pack 需要 Swift 5.9 运行时（SE-0393）⇒ 公开 API 中只能作
  `@available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)` 门控的便利层。
- 模型值不携带 reader 泛型、printer 只以「async 渲染出 `SemanticString`」被消费 ⇒
  非泛型公开类 + 内部擦除无损。

## 定案（三轮澄清提问，前沿收空后确认）

1. 输出形态：并集接口 + 生命周期注解（否：逐 transition 串联、最新版 + since）。
2. 数据来源：全二进制（否：混用降级、纯快照渲染）。
3. CLI：`evolution --interface`（否：新子命令、替换默认输出）。
4. API：公开库 API 落 `SwiftInterface`，`@_spi(Support)` 暴露结构化行流。
5. 注解格式：行尾位图 + 事件短语 + 头部图例（否：纯短语、伪 `@available`）。
6. 无变化声明：渲染但不注解（否：每行位图；`--changes-only` 记为将来方向）。
7. modified：只渲染最新代际 + 变更注解（否：逐代际多行）。
8. 泛型形态：pack 异构 init（门控）+ 同质数组 init 双轨，实现收敛为非泛型类 + 擦除。

提案：`Documentations/Evolutions/0013-swift-evolution-interface-builder.md`。

## 实际执行

- `Sources/SwiftInterface/` 新增五个文件：
  - `EvolutionVersionRendering.swift`：擦除协议 + `EvolutionVersionUnit<MachO>`
    （包 `SwiftDiffableInterfaceBuilder` + 共享其 dispatcher 的 printer）。
  - `EvolutionLine.swift`：公开 `EvolutionAnnotation` / `EvolutionLine`。
  - `EvolutionAnnotationIndex.swift`：lineage → 注解查表（六桶容器 key 合一张表；
    容器空事件返回 nil——member-only lineage 的 header 保持裸）。
  - `EvolutionMarking.swift`：格式层（位图/短语/图例/逐块对齐列 cap 72/超限换行/
    警告尾注）+ `EvolutionContainerAssembler`。注解附着在渲染单元**末行**。
  - `SwiftEvolutionInterfaceRenderer.swift`：N 路归并核心（`matchAcrossVersions`：
    最新版序为脊柱、旧独有按最后存在版本序追加）、header 逐版本回退渲染
    （失败逐个 dispatch `definitionPrintFailed`，全败整体丢弃）。
  - `SwiftEvolutionInterfaceBuilder.swift`：公开类（`@Mutex` 存 prepare 产物）。
- `DiffMarking.splitIntoLines` 从 `private` 放宽为 internal（共享行拆分规则）。
- `EvolutionCommand`：`--interface` flag、与 `--json`/`--summary-only` 互斥、快照
  输入 `ValidationError`、按事件类别着色（removed 红 / modified 黄 / added 绿 /
  注释青）、`--fail-on-breaking` 复用 `builder.evolution`。
- 测试：`EvolutionMarkingTests` + `EvolutionAnnotationIndexTests`（格式层与 join
  规则单测）、`SwiftEvolutionInterfaceBuilderTests`（三版本即时编译 fixture 端到端：
  图例、四类注解、未变声明裸行、并集排序、结构化流轴对齐、notPrepared/入参校验、
  N==2 与两侧 diff 故事一致）、`EvolutionCommandValidationTests`（CLI 校验钉子）。

## 验证

- 新增 4 个 suite 共 30 tests 全绿（`swift test` 原始退出码 0，按规矩不认 xcsift 摘要）。
- 受影响三个 target（SwiftInterfaceTests / SwiftSectionCommandTests / SwiftDiffingTests）
  全量回归（见本批次 push 前的运行记录；worktree 无 `.package.env`，走远程 pin，
  fixture DerivedData symlink 自主检出）。
- CLI 手动端到端：三个 fixture dylib 跑 `evolution --interface`，输出与设计逐项吻合
  （对齐列、位图、removed 容器整体渲染、memberwise `init` 以 removed+added 呈现
  字段改型的涟漪——不同 mangled 签名即不同 ABI 入口，符合 differ 语义）。

## 与方案的差异

- `evolution` 属性定为 `ABIEvolution?`（prepare 前 nil），提案写的是非可选——可选
  更诚实，避免未 prepare 时 crash 或空值捏造。
- 渲染入口 `printAnnotatedInterface()` / `annotatedBlocks()` 增加 `throws`
  （`SwiftEvolutionInterfaceBuilderError.notPrepared`），同因。
- 注解附着点从提案的「首行」细化为「末行」：printer 在成员声明行上方发注释行、
  容器 header 末行是 `{` 行，末行才是声明本体。
- 提案预告的「实现说明单独成篇」改为在 `ABIEvolutionDesign.md` 追加「第五批」一节
  ——耦合点全部在与 evolution 模型的契约上，与既有增量批次同处一文更利检索。
- 输出中发现 extension 里多行 accessor 块（`hashValue { get }`）缩进偏深，与既有
  `diff --interface` 路径行为一致（printer 交互，非本改动引入），不在本批修。

## 后续（2026-08-26）：API 形态修订 + 集成测试

用户指正第二轮第 4 题的本意是 **pack 泛型类**
（`SwiftEvolutionInterfaceBuilder<each MachO: FieldLayoutRenderable>`），非
「非泛型类 + pack init」。探针实测钉住三个事实后重塑 API：

1. pack 在**类型泛型参数表**必须 `@available(macOS 14+)`（编译器强制：
   `parameter packs in generic types are only available in macOS 14.0.0 or newer`）；
2. pack 在**函数**位置不需要门——这解释了擦除类的 pack init 去门后仍可编译；
3. `repeat each MachO == Element` same-element 约束当前工具链不支持
   （`same-element requirements are not yet supported`），加上 pack arity 编译期
   固定，运行时 N（CLI / RuntimeViewer 用户任选版本）原理上无法用 pack 类型承接。

裁定（AskUserQuestion 一轮）：pack 类拿主名（macOS 14+ 薄 façade，构造即擦除、
暴露 `erased`，行为与擦除类逐字节一致，`packGenericFacadeMatchesTheErasedBuilder`
钉住）；运行时 N 擦除类循 Swift 擦除惯例定名 `AnySwiftEvolutionInterfaceBuilder`
（否：不公开——与第一轮「公开供 RuntimeViewer 复用」相抵触），CLI 改用之。

同批新增**集成测试** `Tests/IntegrationTests/SwiftInterface/
SwiftEvolutionInterfaceBuilderTests.swift`：沿用维护者手检 dump 形态（无断言；
agent 只编译不运行）。首版含一条双模拟器 N=2 轴，随后按用户裁定重写：
**evolution 不足 3 个 image 没意义**（N=2 已由 `diff --interface` 覆盖；本视图
的价值——中途出现/消失、两度修改、●○● 位图——三版本起才成立），且模拟器
runtime fixture 只有 18.5/26.5 两个版本凑不齐三。终版全部基于
`ABIEvolutionTestSuite.MultiVersionDyldCacheImageTests`（15.5 → 26.5.1 →
27.0-beta.1 三 macOS 缓存轴）：AppKit（与 `ABIEvolutionTests` 的 lineage 报告
dump 同输入，便于并排目检两个视图讲同一个故事）+ SwiftUICore（Swift 密集轴，
重泛型/opaque/extension），pack façade 实机 dump 亦为三镜像
（`SwiftEvolutionInterfaceBuilder<MachOFile, MachOFile, MachOFile>`）。
验证：`swift build --build-tests` 全量编译通过 + 受影响单测/E2E suite 重跑全绿。

## 后续（2026-08-26 二）：属性打印修正（用户实机反馈）

用户跑 SwiftUI 三缓存轴 dump 后指出属性打印有问题，定位为两处成员多行渲染缺陷：

1. **accessor 块双重缩进**：`VariableNodePrinter`/`SubscriptNodePrinter` 按 `level`
   给块内行烘焙**绝对**缩进（`(level+1)*4` 的 `get`、`level*4` 的 `}`），而 evolution
   格式层又给单元的每一行加了层级缩进——两者叠加。修法：成员一律以 **printer
   level 0** 渲染（function/field 本就不消费 level），块变相对缩进，格式层的统一
   逐行缩进即精确。normal interface 路径不受影响（它只给首行加缩进，续行吃烘焙的
   绝对缩进——两种消费契约对不上正是缺陷根源）。
2. **注解沉底**：多行成员（计算属性）的生命周期注解落在了 accessor 块收尾 `}` 上。
   「附着末行」规则改为**锚点分靶**：成员锚首行（属性内联打印，首行即声明行）；
   容器 header 锚末行（attribute 行在前，末行才是带 `{` 的声明行）。

钉子：`memberAnnotationAnchorsOnTheFirstLine` / `headerAnnotationAnchorsOnTheLastLine`
（格式层）+ e2e fixture 新增被移除的计算属性 `Alpha.summary`（注解在声明行、
`get`/`}` 相对缩进、全文无双重缩进痕迹）。

**同源遗留（本批不动、待另行处理）**：两侧 `diff --interface` 路径的成员渲染仍是
「真实 level + 逐行缩进」，带同样的双重缩进伪影；opaque `some` 裸打印（截图中的
`var body: some {`）是 diff 路径既有缺口——printer 的 opaque 展开靠宿主对
`SwiftInterfaceBuilder.addExtraDataProvider` 接线，diff/evolution 两路都没接。
