# 项目演进记录（Project Evolution Log）

> 本库自身的编年演进账本：按工作弧（epoch）记录每一段的时间范围、动机、关键决策与取舍、
> 落地模块、关联文档与对应版本。**这是面向维护者的单一编年入口**——设计细节住在各自的
> 设计文档里，本文只负责"什么时候、为什么、做了什么、记在哪"。
>
> 与其他文档载体的分工：[`Changelogs/`](../../Changelogs/)（面向用户的 per-release，英文）、
> [`Roadmaps/`](../../Roadmaps/)（前瞻规划）、[`TaskReports/`](TaskReports/)（单任务事后复盘）、
> `Internal/` 各设计文档（按主题的深度设计）。本文按时间轴把它们串起来。
>
> 维护约定见文末——**每个非平凡批次结束时必须追加/更新一节**。

---

## 1. Foundation：Mach-O Swift section 解析 + dumpers

- **时间**：2025-04 → 2025-05（`0.1.0`–`0.2.0`）
- **动机**：从 Mach-O 二进制直接读取 Swift 元数据（`__swift5_types` / `__swift5_proto` /
  `__swift5_protos` / `__swift5_assocty` 等），无需运行时配合，为逆向工程提供地基。
- **落地**：`MachOSwiftSection`（descriptor 模型 + relative pointer 解析）、`SwiftDump`
  （`Struct`/`Enum`/`Class`/`Protocol`/`ProtocolConformance` 高层包装）、`swift-section` CLI 雏形。
  基于 MachOKit。
- **关键决策**：descriptor → 类型包装的两层结构；relative pointer 统一走 `RelativeDirectPointer`
  一族抽象。
- **文档**：无当期设计文档（早于文档纪律建立；现状以 [AGENTS.md](../../AGENTS.md) 架构章节为准）。

## 2. 自研 Demangler / Remangler / NodePrinter

- **时间**：2025-06 起多轮（2025-06、2025-10、2026-02 各有一波；`0.3.0`–`0.7.x`）
- **动机**：系统 demangler 无法处理 Swift 元数据里的 **symbolic reference**（指向 descriptor 的
  内嵌指针），必须自研才能把 mangled name 还原成完整类型；同时需要 remangle 能力做身份键。
- **落地**：`Demangling`（后拆为外部包 `swift-demangling`）：`Demangler`（~200 种 Node kind）、
  `Remangler`、`NodePrinter`、leaf `NodeCache` interning。对齐上游 Swift 的 demangler 语义。
- **关键决策**：Node 树作为全库通用的类型表示（demangle → 加工 → print/remangle 的管线贯穿
  SwiftDump / SwiftInterface / SwiftLayout / SwiftDiffing）。
- **文档**：无当期设计文档（最大的历史缺口之一；行为以上游 `swift/lib/Demangling` 为对齐基准）。

## 3. 早期模块拆分：TypeIndexing + SwiftInterfaceBuilder

- **时间**：2025-11（`0.7.0`–`0.7.1`）
- **动机**：dump 输出向「完整 Swift interface 文件」演进，需要索引 + 构建器分层。
- **落地**：`TypeIndexing`、`SwiftInterfaceBuilder` 首版。
- **后续**：该结构被 epoch 10 的正式模块化（SwiftDeclaration/SwiftIndexing/SwiftPrinting 分层）
  取代；`TypeIndexing` 的 `.swiftinterface` 解析能力保留。
- **文档**：无当期设计文档（已被取代，现状见
  [SwiftModularizationMigration.md](SwiftModularizationMigration.md)）。

## 4. EnumLayoutCalculator + 枚举布局注释（第一版）

- **时间**：2025-12 → 2026-02（`0.7.1`–`0.8.0`）
- **动机**：从运行时公式预测枚举内存布局（single-payload XI/overflow、multi-payload
  spare-bits/tagged），为 RuntimeViewer 式的布局注释供数据。
- **落地**：`SwiftInspection.EnumLayoutCalculator`、`SpareBitAnalyzer`、首版布局注释渲染。
- **文档**：对外指南 [SwiftEnumLayout.md](../SwiftEnumLayout.md)（后在 epoch 13 重写）；
  内部审计记录见 [EnumLayoutAuditFixes.md](EnumLayoutAuditFixes.md)（epoch 13 补）。

## 5. GenericSpecializer（运行时泛型特化）

- **时间**：2026-01（`0.8.0` 前后；清理与 bug 修复延续到 2026-05/06）
- **动机**：交互式地在运行时特化泛型类型（拿到 metadata / field offsets / VWT），补足
  「无实参 dump 看不到的布局」。
- **落地**：`SwiftSpecialization`：`GenericSpecializer` 两步 API（`makeRequest` →
  `specialize`）、`ConformanceProvider`、PWT 按 requirement 顺序传递的关键不变量。
  后续加入 `Argument.boundGeneric` 嵌套绑定（Roadmap 2026-05-11 的 Approach 2）。
- **文档**：[../../docs/superpowers/specs/2026-05-02-generic-specializer-cleanup-design.md](../../docs/superpowers/specs/2026-05-02-generic-specializer-cleanup-design.md)、
  [../../docs/superpowers/reviews/2026-05-06-generic-specializer-bug-review.md](../../docs/superpowers/reviews/2026-05-06-generic-specializer-bug-review.md)、
  [../../Roadmaps/2026-05-11-bound-generic-candidates.md](../../Roadmaps/2026-05-11-bound-generic-candidates.md)、
  TaskReports [2026-06-10-pr88-nested-generic-specialization-followups.md](TaskReports/2026-06-10-pr88-nested-generic-specialization-followups.md)
  / [2026-06-10-pr88-nested-recursion-depth-limit.md](TaskReports/2026-06-10-pr88-nested-recursion-depth-limit.md)。
  原始设计（phase 1-3）无当期文档，现状见 [AGENTS.md](../../AGENTS.md) 的 Work In Progress 章节。

## 6. Snapshot 测试基础设施

- **时间**：2026-03-12 → 2026-04-18（`0.8.x`–`0.9.x`）
- **动机**：dump / interface 输出需要可回归的快照测试，且要能在 CI 上跑。
- **落地**：snapshot 测试管线 + CI 设计。
- **文档**：[../../docs/superpowers/specs/2026-03-15-ci-snapshot-testing-design.md](../../docs/superpowers/specs/2026-03-15-ci-snapshot-testing-design.md)、
  [../../docs/superpowers/specs/2026-04-18-ci-test-filter-design.md](../../docs/superpowers/specs/2026-04-18-ci-test-filter-design.md)。

## 7. SymbolTestsCore fixtures / 覆盖率体系

- **时间**：2026-04 → 2026-05（`0.9.0`–`0.11.0`）
- **动机**：用受控的 fixture framework（`Tests/Projects/SymbolTests`）替代对系统框架的依赖，
  并对 `MachOSwiftSection/Models` 建立「每个 public 方法必有测试或 allowlist」的覆盖不变量。
- **落地**：`MachOFixtureSupport`、`baseline-generator` + `RegenerateBaselinesPlugin`、
  `MachOSwiftSectionCoverageInvariantTests` 四不变量、`SuiteBehaviorScanner`。
- **文档**：[../../docs/superpowers/specs/2026-04-10-symboltestscore-integration-tests-design.md](../../docs/superpowers/specs/2026-04-10-symboltestscore-integration-tests-design.md)、
  [../../docs/superpowers/specs/2026-04-13-symboltestscore-fixture-expansion-design.md](../../docs/superpowers/specs/2026-04-13-symboltestscore-fixture-expansion-design.md)、
  [../../docs/superpowers/specs/2026-05-03-machoswift-section-fixture-tests-design.md](../../docs/superpowers/specs/2026-05-03-machoswift-section-fixture-tests-design.md)、
  [../../docs/superpowers/specs/2026-05-05-fixture-coverage-tightening-design.md](../../docs/superpowers/specs/2026-05-05-fixture-coverage-tightening-design.md)。
  测试约定见 [AGENTS.md](../../AGENTS.md)。

## 8. ReadingContext 读取抽象

- **时间**：2026-05 → 2026-06（发布于 `0.12.0`）
- **动机**：统一 `MachOFile` / `MachOImage` / InProcess 三种读取方式的 API 面，让上层代码
  对 reader 泛化。
- **落地**：`MachOReading.ReadingContext` 一族 + 全库适配。
- **文档**：[ReadingContextAbstraction.md](ReadingContextAbstraction.md)、
  [../../docs/superpowers/specs/2026-05-02-reading-context-api-design.md](../../docs/superpowers/specs/2026-05-02-reading-context-api-design.md)。

## 9. SwiftInterface ABI 解析 / 打印路径修复

- **时间**：2026-05（发布于 `0.12.0`）
- **动机**：conditional invertible protocols 区域的 ABI 解析错误；print 路径在共享子树上的
  DAG 爆炸。
- **文档**：TaskReports
  [2026-05-14-fix-conditional-invertible-protocols-region-abi-parsing.md](TaskReports/2026-05-14-fix-conditional-invertible-protocols-region-abi-parsing.md)、
  [2026-05-16-fix-swiftinterface-print-path-dag-explosion.md](TaskReports/2026-05-16-fix-swiftinterface-print-path-dag-explosion.md)。
  另有 dump 质量路线图 [../../Roadmaps/2026-04-13-swiftinterface-dump-improvements.md](../../Roadmaps/2026-04-13-swiftinterface-dump-improvements.md)
  （P0/P1/P2 分级，绝大部分已落地）与 PR 审查挂账
  [../../Roadmaps/2026-04-16-pr61-review-findings.md](../../Roadmaps/2026-04-16-pr61-review-findings.md)（未清）。

## 10. SwiftInterface 正式模块化（SwiftDeclaration 分层）

- **时间**：2026-06-15 → 2026-06-18（发布于 `0.12.0`）
- **动机**：单体 `SwiftInterface` 拆成共享声明模型上的对等分层，索引与打印互不依赖；
  `SwiftDump` 降为 leaf。
- **落地**：`SwiftDeclaration`（共享模型）、`SwiftIndexing`、`SwiftPrinting`、
  `SwiftAttributeInference`、`SwiftDeclarationRendering`（dumper + printer 共享的字段渲染）、
  `SwiftInterface` 缩为编排器。
- **文档**：[SwiftModularizationMigration.md](SwiftModularizationMigration.md)、
  [LeafMigrationPlan.md](LeafMigrationPlan.md)、
  [FieldMetadataRenderingMigration.md](FieldMetadataRenderingMigration.md)、
  [MetadataReaderRefactoring.md](MetadataReaderRefactoring.md)、
  [GenericArgumentSubstitution.md](GenericArgumentSubstitution.md)。

## 11. SwiftDiffing：ABI diff + 可比对接口

- **时间**：2026-06-15 → 2026-06-21（发布于 `0.12.0`；源自
  [../../Roadmaps/2026-04-10-feature-candidates.md](../../Roadmaps/2026-04-10-feature-candidates.md) 的候选 A）
- **动机**：在**二进制 ABI** 层面比对同一模块的两个版本——字段 retype、enum case tag 重编号、
  accessor 变化——`.swiftinterface` 文本 diff 看不到的信息。
- **落地**：`SwiftDiffing`（`ABIKey` remangle 身份 + `MemberRecord` 双键 + 三路集合差分 +
  `Compatibility` 判定）、`SwiftDiffableInterfaceBuilder/Renderer`、CLI `swift-section diff`
  （inline/unified/markdown 三格式）。
- **关键决策**：diff 本身 Mach-O-free（纯值计算）；function 签名变更 = add+remove（不同
  mangled symbol = 不同 ABI 入口点）；`@frozen` 不可恢复 ⇒ 兼容性判定一律按 resilient。
- **文档**：[ABIDiffDesignAndLimitations.md](ABIDiffDesignAndLimitations.md)、
  [DiffableInterfacePlan.md](DiffableInterfacePlan.md)。

## 12. SwiftLayout 静态布局引擎 phases 3-9

- **时间**：2026-06-18 → 2026-07-19（phase 3-7 发布于 `0.12.0`，phase 7-9 于 `0.13.0`）
- **动机**：离线（不加载进程、不调 metadata accessor）算出真实字段偏移，让
  `swift-section dump/interface` 的文件模式输出实打实的布局注释。
- **落地**：`SwiftLayout`：`StaticLayoutCalculator` / `StaticTypeLayoutResolver` /
  `BasicLayout`（`performBasicLayout` 离线移植）→ 依赖闭包（phase 3）→ ObjC 祖先（4）→
  具体 bound-generic 字段（5-6，值实参 + parameter packs）→ 关联类型 / 扩展 existential /
  嵌套类型（7）→ 父链实参 + `@objc` protocol 回退（8，非泛型字段降级 0%）→
  无实参泛型的 requirement-signature 挖掘（9：class-bound 参数、same-type/same-value pin、
  参数 metatype 恒 thick）。leaf XI 全部对齐运行时精确值。
- **关键决策**：per-field 降级而非整类型失败；五个 resolution seam 汇于
  `ImageUniverse`；官方 RemoteInspection 拒绝的 packs/spare-bits XI 这里直接对着运行时
  语义实现并以 VWT 对拍验证。
- **文档**：[StaticFieldOffsetComputation.md](StaticFieldOffsetComputation.md)（研究）、
  [StaticLayoutEngine.md](StaticLayoutEngine.md)（主文档）、
  [StaticLayoutDependencyClosure.md](StaticLayoutDependencyClosure.md)、
  [FieldLayoutRendererReaderSpecialization.md](FieldLayoutRendererReaderSpecialization.md)。

## 13. 枚举布局审计 + 运行时 case 投影

- **时间**：2026-07-18 → 2026-07-19（发布于 `0.13.0`）
- **动机**：`Text.Style.LineStyle` 反馈案例暴露「只知道 XI 个数推不出具体判别字节」；对
  `EnumImpl.h`/`Enum.cpp`/`GenEnum.cpp`/`TypeLowering.cpp` 逐行审计修正五处布局保真问题。
- **落地**：`RuntimeEnumCaseProjector`（双基线注入 + `getEnumTag` 回读校验）、
  `EnumCaseProjection` 模型（`patternResolution` 精确/诚实降级）、audit 五修复
  （indirect 单 payload 的 heap XI、VWT size 交叉校验、位级 `fixedBitMasks`、empty case
  全判别区、no-payload XI 封顶）。
- **文档**：[RuntimeEnumCaseProjection.md](RuntimeEnumCaseProjection.md)、
  [EnumLayoutAuditFixes.md](EnumLayoutAuditFixes.md)、对外指南重写
  [SwiftEnumLayout.md](../SwiftEnumLayout.md)（+[中文版](../SwiftEnumLayout_zh.md)）。

## 14. OutputTransformer 迁移（注释 token 模板库侧化）

- **时间**：2026-07-19 → 2026-07-21（发布于 `0.13.0`）
- **动机**：RuntimeViewer 的 `Transformer` 注释模板机制（字段偏移 / 类型布局 / 枚举布局等
  注释的 token 模板 + 预设）迁入库侧，RuntimeViewer 只留 UI。
- **落地**：`OutputTransformer` 模块（五个 Swift 注释模块 + 宽容 `Codable` 持久化契约）、
  `applyTransformers` 接线、CLI `--enum-layout-style` 五预设（detailed/explained/standard/
  inline/compact）。模块曾名 `SemanticTransformer`，发布前更名。ObjC 侧模块暂留
  RuntimeViewerCore（待库侧 ObjC 渲染管线，见挂账）。
- **文档**：[OutputTransformerMigration.md](OutputTransformerMigration.md)。

## 15. ABI Evolution：多版本演化追踪 + snapshot 持久化 + 诊断通道

- **时间**：2026-07-21 → 2026-07-22（未随版本发布，将入 `0.14.0`）
- **动机**：把双侧 diff 推广到 N ≥ 2 个有序版本——每个声明的生命线（introduced / modified /
  removed / re-added）；同时补齐 baseline 持久化（N 次索引是瓶颈，演化计算是毫秒级）。
- **落地**：
  - 第一批：`ABISnapshotDocument`（formatVersion 版本头 + `ABIProvenance`）、`ABIJSON`
    字节稳定编码、`ABIEvolution`/`ABIEvolutionBuilder`（key → 逐版本 presence/payload
    矩阵，非 N−1 次 pairwise join；N=2 与 `ABIDiffer.diff` 逐事件一致由测试锁定）、
    `ABIEvolutionReporter` timeline 报告、CLI `snapshot`/`evolution` 命令 + `diff` 的
    快照输入与 `--json`。
  - 第二批：`keyed` 碰撞诊断通道（`ABISnapshot.keyCollisions()` → `ABIDiff.diagnostics` /
    `ABIEvolution.keyCollisionsByVersion` + reporter Warnings，first-wins 不再静默）、
    enum case `indirect` 折入 payload key（key scheme 变更 ⇒ formatVersion 2，版本头
    首次实战拒绝旧 baseline）、`differentKeysParallelViaAsyncLet` 计时测试加固。
- **关键决策**：evolution 放进 `SwiftDiffing` 不另立模块（复用 `MemberRecord`/`ABIKey`
  内部细节）；成员事件只在容器于相邻两版本都存在时计算（与双侧 diff 的
  「added/removed 容器不枚举成员」一致）。
- **文档**：[ABIEvolutionDesign.md](ABIEvolutionDesign.md)、TaskReports
  [2026-07-21-abi-evolution-and-snapshot-persistence.md](TaskReports/2026-07-21-abi-evolution-and-snapshot-persistence.md)、
  [2026-07-22-key-collision-diagnostics-and-indirect-case.md](TaskReports/2026-07-22-key-collision-diagnostics-and-indirect-case.md)。

---

## 维护约定

1. **每个非平凡批次结束时必须在本文追加/更新一节**（新工作弧新增一节；延续既有弧则在该节
   补记）。一节至少包含：时间段、动机、关键决策与取舍、落地模块、关联文档链接、对应版本。
2. 设计细节写在 `Documentations/Internal/` 的独立设计文档里，本文只放指针；单任务的
   过程复盘写 [`TaskReports/`](TaskReports/)；面向用户的 per-release 说明写
   [`Changelogs/`](../../Changelogs/)。
3. 版本发布时（bump `Version.swift` + tag），同步核对本文各节的「对应版本」标注。
