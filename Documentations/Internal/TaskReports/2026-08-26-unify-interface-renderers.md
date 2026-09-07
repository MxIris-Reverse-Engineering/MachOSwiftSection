# 2026-08-26 统一 diff / evolution 接口渲染器的结构遍历核心

- **提案**: [0014-unify-interface-renderers](../../Evolutions/0014-unify-interface-renderers.md)
- **分支 / PR**: `feature/swift-evolution-interface-builder`（PR #114 同分支追加）

## 问题

用户诉求：「看一下怎么优化一下 3 个 Builder 的代码，现在太多重复代码了。」

## 调研

- **Builder 层重复其实很小**：`SwiftInterfaceBuilder`（243 行）、
  `SwiftDiffableInterfaceBuilder`（87 行）、`AnySwiftEvolutionInterfaceBuilder`（165 行）
  各自的逻辑基本独有；pack façade 的纯转发是既定双型设计的固有代价。
- **大头在两个渲染器**：`SwiftDiffableInterfaceRenderer`（602 行）与
  `SwiftEvolutionInterfaceRenderer`（525 行）约六成平行——`extensionContainers(of:)` 与
  extension header 构造逐字节相同；`matchByKey` 与 `matchAcrossVersions` 连输出顺序
  语义都一致（互为 N=2 特例）；八个成员构造器只差「具体 printer vs 擦除接缝、
  payloadKey、渲染 level」三点；顶层与 body 组合顺序全同。
- **同一条修复要打两遍的实证**：evolution 路刚修的 accessor 块双重缩进
  （`67d459e7`）在 diff 路原样存在，根因正是「diff 成员按真实 level 渲染」这条差异。
- **真不同、不能合的部分**：header 语义（diff 两侧配对 + failed 侧站位 vs evolution
  最新可渲染）、容器装配与格式层（marker 逐行 vs 注解锚点）。

## 最终方案

见提案。要点：共享 `InterfaceUnionWalker` + `InterfaceUnionEmitting` 策略协议；
成员发射统一 printer level 0（顺带修 diff 双重缩进）；公开 API 零破坏
（`SwiftDiffableInterfaceRenderer` 外壳化）；擦除接缝改中性名；格式层不合；
opaque 展开另立提案；验收不跑 rendering A/B（主路径零改动）。

## 实际执行

1. **修前必红回归测试先行**：`Tests/SwiftInterfaceTests/DiffMemberIndentationTests.swift`
   ——两版本即时编译 fixture（`summary` 两侧同在 / `legacySummary` 仅旧 /
   `freshSummary` 仅新），钉三种 marker 侧 accessor 块的相对缩进 + 全文无双重缩进。
   实测修前 4 断言全红（实际输出 `get` 在 14 列、`}` 在 10 列，与分析一致）。
2. **核心迁移**：新建 `InterfaceUnionWalker.swift`（`UnionMatch` /
   `UnionMemberScope` / `UnionRenderableMember` / `ExtensionUnionContainer` /
   `InterfaceUnionEmitting` / 遍历器）；`git mv EvolutionVersionRendering.swift →
   InterfaceVersionRendering.swift`（协议与 unit 改中性名，新增
   `init(builder:)` 构造口，原 init 收敛为 convenience）。
3. **两渲染器改写为策略**：`SwiftEvolutionInterfaceRenderer` 直接遵循
   `InterfaceUnionEmitting`（`latestRenderableHeader` + 注解查表 + 锚点）；
   `SwiftDiffableInterfaceRenderer` 变公开外壳（构造即擦除为 2 元素轴），
   `DiffUnionStrategy` 承接 `HeaderOutcome` / `resolveHeaders` / 同渲染折叠 /
   `DiffContainerAssembler` 装配。`AnySwiftEvolutionInterfaceBuilder` 两个渲染
   入口收敛为私有 `makeRenderer(for:)`。
4. **文档批次**：提案置 Implemented + 决策日志；AGENTS.md 新增
   `InterfaceUnionWalker` 条目并修正 evolution 条目三处过时表述 + Test
   Environment 记 fixture 地雷；演进账本第 44 节；术语表「emission strategy」；
   Evolutions 状态表。

## 验证

- 新回归测试修后转绿；`SwiftInterfaceTests` + `SwiftDiffingTests` +
  `SwiftSectionCommandTests` 全量 **209 tests / 34 suites 全绿**（原始退出码 0）。
- evolution 路 e2e 字节钉子原样通过 ⇒ 核心承接 N 路语义无损；diff 路除缩进修正外
  由 `DiffRendererHeaderFailureTests` 等既有钉子证明 N=2 等价。
- `swift test` 构建覆盖 IntegrationTests 编译（agent 不运行之）。
- 未跑 rendering A/B：`git diff` 确认 `SwiftPrinting` 与主 dump/interface 路径零改动。

## 与方案的差异

1. **first-wins 对齐带出一处测试注入手法修正**（提案决策日志已补记）：旧 diff 的
   发射循环对**新侧**同 key 重复项会重复发射（与其查表字典的 first-wins 及注释
   自相矛盾；`ABIDiffer.keyed` 为 first-wins），统一后连发射也 first-wins。
   `DiffRendererHeaderFailureTests.unrenderableHeaderIsReportedAsAnEvent` 原以
   「append 同名损坏定义」触发 header 失败，恰好依赖旧的重复发射；改用其姊妹
   测试已验证的「replace」注入，测试意图（header 失败必须报事件）不变。
2. **测试基建发现（方案外）**：纯 struct 的即时编译 fixture dylib **没有
   `__DATA` 段**，pinned MachOKit 解析该布局的 chained-fixup 页时读越 mmap 末尾，
   `SwiftDeclarationIndexer.prepare()` 内 SIGSEGV/SIGBUS（崩溃地址恰为映射
   按页取整的末尾；CLI dump 不触发——它不走 `resolveBind` 的 parent 链解析）。
   规避：fixture 加一个跨版本不变的 class（`Anchor`）强制生成 `__DATA` 段；
   规矩已记入 AGENTS.md Test Environment（新即时编译 fixture 模块至少带一个 class）。
   MachOKit 侧的根因修复属另一仓库，未在本批展开。
3. diff 协议 header 失败事件的 `kind` 从硬编码 `.type` 改为如实传 `.protocol`
   （evolution 路本就如此；无测试钉旧值，属顺手修正）。
