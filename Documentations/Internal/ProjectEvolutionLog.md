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

- **时间**：2026-07-21 → 2026-07-22（发布于 `0.14.0`）
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

## 16. 文档第一公民 + per-conformance 归属

- **时间**：2026-07-22（发布于 `0.14.0`）
- **动机**：两条线合一。① 文档升级为第一交付物：建立本演进账本并回填 15 个 epoch、
  补齐近期 task report 缺口与 `0.13.0` changelog、把「每批次必附文档」写进
  AGENTS.md 纪律。② 关闭 SwiftDiffing 局限 5：extension 变更只能归到
  `ExtensionName` 总账（归因不了、条件变更不可见、witness 不参与 diff、
  键碰撞唯一现实来源）。
- **落地**：
  - 文档：本文（ProjectEvolutionLog）、TaskReports ×2 回填、`Changelogs/0.13.0.md`、
    AGENTS.md 文档纪律 + `Documentations/README.md` 索引扩展。
  - 归属：索引期把 protocol 名与 witness 投影冻结成纯值钉在
    `ExtensionDefinition` 上（`conformingProtocolName` /
    `resolvedAssociatedTypeWitnesses`）；快照按 (target, protocol, where 指纹,
    retroactive) 拆容器（key scheme v3）；conformance 增删 = 容器级事件、
    where/`@retroactive` 变更 = 身份翻转、witness 换绑 = `.modified`
    （`assocwitness:` 命名空间）；键碰撞源结构性消解（诊断通道保留兜底）；
    diffable renderer 的 header 携带 `: Protocol` 与 where 子句；evolution
    零改动获得 per-conformance lineage。
- **关键决策**：拆容器而非挂归因标签（新 conformance 成为干净的容器级事件、
  碰撞随作用域拆分自然消失）；演进记录选编年 ledger 而非 evolution-proposal
  体系（与产品功能 `swift-section evolution` 撞名、且提案是前瞻性的）。
- **文档**：[PerConformanceAttribution.md](PerConformanceAttribution.md)、
  [ABIDiffDesignAndLimitations.md](ABIDiffDesignAndLimitations.md)（局限 3/5 收口）、
  TaskReports [2026-07-22-per-conformance-attribution-and-docs-program.md](TaskReports/2026-07-22-per-conformance-attribution-and-docs-program.md)。

## 17. Protocol requirement（PWT slot）投影 + remangle 回退审计

- **时间**：2026-07-22（发布于 `0.14.0`）
- **动机**：消化 SwiftDiffing 挂账的两个 TODO(P2)。① 协议容器只比较可解析成员，
  符号被 strip 的 requirement（OS 框架常态）完全不可见——协议增删 witness-table
  slot 这一真 ABI 事件被静默吞掉；② `ABIKey` 的 remangle 回退键与刻意命名空间键
  无法区分，跨 toolchain 身份翻转风险不可观测。
- **落地**：
  - `StrippedSymbolicRequirement` 在 SwiftDeclaration 上暴露 Mach-O-free 事实门面
    （`kindToken` 显式 switch / `isInstance` / `isAsync` / `hasDefaultImplementation`），
    SwiftDiffing 维持「只依赖 SwiftDeclaration + Demangling」的模块契约；
  - `MemberKind.protocolRequirement` + `MemberRecord.makeProtocolRequirement`
    （身份 `pwtslot:<offset>`、payload 折入 flags 指纹）；中段插入如实级联
    removed+added；
  - remangle 回退键改为自识别前缀 `unmangled:`，`ABISnapshot.remangleFallbacks()`
    扫描全部键位面，经 `ABIDiff.diagnostics` / `ABIEvolution.remangleFallbacksByVersion`
    + 双 reporter Warnings 上浮；
  - 两项键格局变更共用一次 formatVersion bump（3 → 4）；计时测试
    `differentKeysParallelViaAsyncLet` 预算再放宽（0.5× → 0.75× serial ceiling）。
- **关键决策**：stripped slot 身份取 PWT offset（printer 既有词汇、自描述；级联
  有界且方向诚实）；**不**把已解析 requirement 的 offset 折入 payload（resilient
  协议运行时按 requirement descriptor 匹配，重排非破坏，折入即假阳性源）；新收录
  「符号化状态不对称」为文档化局限（stripped 与否是符号表状态而非 ABI 事实）。
- **文档**：[ProtocolRequirementProjection.md](ProtocolRequirementProjection.md)、
  [ABIDiffDesignAndLimitations.md](ABIDiffDesignAndLimitations.md)（局限 2 可观测化、
  局限 6 新增并收口）、TaskReports
  [2026-07-22-protocol-requirement-projection.md](TaskReports/2026-07-22-protocol-requirement-projection.md)。

---

## 18. 默认实现感知的 ABI 兼容性判定

- **时间**：2026-07-22（发布于 `0.14.0`）
- **动机**：`Compatibility` 的均匀启发式「新增即 additive」在协议 requirement 上与
  Swift library evolution 的官方规则相悖——**给协议追加一个没有默认实现的 requirement
  是破坏性变更**（既有 conformance 缺 witness，resilient 实例化后调用即 trap）。此前
  diff 对协议新增 requirement 一律报 backward-compatible，`--fail-on-breaking` 的 CI
  门在这类真破坏上静默放行，是核心结论最后一处「自信地出错」。上一批已把 stripped slot
  的 `hasDefaultImplementation` 备进 payload，本批将其升为结构化事实并折进 verdict，
  对**已解析** requirement 同样生效。
- **落地**：
  - `ProtocolDefinition.defaultedRequirementPWTOffsets`：`index(in:)` 的 requirement
    循环里对**每个** requirement（无论符号可否解析）读 `layout.defaultImplementation.isValid`
    ——纯相对指针运算、不需要符号表，故 stripped 侧与符号侧同样精确；
  - `MemberRecord.hasDefaultImplementation: Bool?`（**不**参与 identity/payload key，
    仅 verdict 元数据）：stripped slot 直取描述符位，已解析成员经纯函数
    `requirementDefaultImplementationFlag(slotOffsets:defaultedOffsets:)` 关联 PWT
    offset——所有 slot 均默认才为 `true`（`var { get set }` 只有 getter 默认 ⇒ `false`），
    任一 offset 缺失 ⇒ `nil`（诚实降级回 status 规则）；
  - `MemberChange` / `LineageEvent` 新增 `compatibilityOverride: Compatibility?`，
    `compatibility` 改为 `compatibilityOverride ?? status.compatibility`；override 由
    `MemberRecord.compatibilityOverride(old:new:)` 一条纯规则计算、双侧 differ 与 evolution
    builder 共享（N = 2 时两路结论自动一致），`ABIEvolution.transitionCompatibilities`
    随之改走精化后的 verdict；
  - formatVersion 4 → 5：键格局与 v4 相同，仅增 verdict 元数据；仍按「一版本一 schema」
    契约 bump——否则旧 baseline 会把 requirement 追加静默降级回 status 规则。
- **关键决策**：flag 的语义定为「**resilient default witness 存在**」而非「源码写了默认
  实现」（落地实测确认，比 spec 初稿更精确）——编译器只为 resilient 协议（public +
  library-evolution 模块）生成 default witness table，非 resilient 协议恒读 `false`；
  而这恰是**正确的** verdict 输入，因其既有 conformance 的 witness table 编译期定长，
  追加 requirement 无论有无源码默认都必然破坏。已解析 requirement 的 default flip 不入
  payload key（不产生事件）——不丢信息，默认实现函数本身就是 protocol-extension 容器里的
  成员增删，已在该轴如实呈现；stripped slot 的 `default:1→0` 维持 status 规则的 breaking
  （依赖默认实现的既有 conformance 将 trap）。
- **文档**：[DefaultImplementationAwareCompatibility.md](DefaultImplementationAwareCompatibility.md)。

---

## 19. NodeStore 迁移：符号索引与声明模型换用 arena 存储

- **时间**：2026-07-24 — 2026-07-26（未随版本发布，将入 `0.14.0`）
- **动机**：`SymbolIndexStore` 为每个符号保留 demangle 出来的 `Node` **类**树，且这些树
  经全局 `NodeCache` 做 hash-consing。两件事叠加的后果是：单镜像常驻内存以数十 MB 计，
  而 `NodeCache` 是**进程级永驻**的——浏览过的镜像即使 `Storage` 被淘汰，其节点仍留在全局
  缓存里累积，无上界。RuntimeViewer 长时间浏览必然膨胀。基线量测（SwiftUI，debug）：构建期
  `phys_footprint` +266–272 MB，释放 `Storage` 后仍残留 ~92 MB，`NodeCache` 净增 55.9 万子树。
- **落地**（详见 [NodeStoreMigrationPlan.md](NodeStoreMigrationPlan.md) 的分期实施记录）：
  - **Stage 1–2**：`Storage` 改持 `NodeStore` arena（每节点 12 B 扁平缓冲，`freeze()` 后
    不可变故天然 `Sendable` 免锁）。构建扫描改为「`demangleAsNodeTransient` 造瞬态树 →
    分类逻辑原样跑在瞬态树上 → `builder.intern` 入 arena」，全程不碰 `NodeCache`；
    消费端 matcher 与 `DefinitionBuilder` 换持 `NodeReference`。
  - **Stage 3–4**：符号表压缩。`Symbol` 去掉 `nlist` existential（64 B → 32 B），
    平铺 `symbolTable` 每唯一名一行、所有索引改存 4 B 行号、`DemangledSymbol` 压到 32 B，
    pending→populate 的双索引瞬态窗口整个删除。构建期增量 272 MB → **68 MB**，
    构建耗时反而快于旧管线 14%。
  - **Stage 5a/5c**：声明模型的 `node` 字段换持 `NodeReference`；`MetadataReader` 等散点
    改用 transient demangling，全局 `NodeCache` 不再随浏览增长。
  - **审查修复批次**（2026-07-26）：`demangledNodeReference` 的 offset 判等去除（见下）、
    dyld cache 选图排序跨 cache 生效、`StructuralNodeReferenceKey` 下沉到 `MachOSymbols`
    并覆盖全部跨 store 集合、opaque 描述符查找恢复 O(1)、同一行重复入桶修复、
    `printSemantic` 栈保护统一。
- **关键决策与取舍**：
  - **分类跑在瞬态树上而非 `NodeReference` 上**：`NodeStoreBuilder` 无读访问、`freeze()`
    后不可再 intern，硬要在 arena 上分类需要重写全部分类代码；瞬态树方案让
    `processMemberSymbol` 族几乎零改动。
  - **查询 API 保留 `Node` 入参**：实参来自 `MetadataReader` 的树，键在 store 内，
    靠新增的 `NodeReference.structurallyEquals(_:)` 做零物化跨表示比较。
  - **`NodeReference` 的固有 `Hashable` 是 store identity**，这是本迁移最大的隐蔽陷阱。
    结构相等但来自不同 store 的两个键既不相等也不同哈希，于是任何跨 store 的字典/集合
    都会**静默失效**——不报错、不崩溃，只是少一个 `override` 关键字、少半个 subscript、
    多一份重复成员。`StructuralNodeReferenceKey` 是统一解药，规则已写进 AGENTS.md。
  - **`demangledNodeReference` 不比 offset**：demangle 结果只是名字的函数，而行存的是
    canonical（cache 校正后）offset、查询方带的是查询时的 offset，比较只会否决合法命中。
    dyld cache 路径下曾因此**整镜像**退化到 per-symbol mini store，既是性能问题也是上面
    那类跨 store 失效的主要来源。同一 offset 对应多个符号是正常情形（它们名字不同），
    按名字查各自命中各自的行，不受影响。
  - **`DemangledSymbol` 的单元素数组保留**：审查建议改成内联 `Symbol` 的双 case 枚举以省掉
    这次分配，实测会把每个值从 32 B 撑到 48 B——而经共享表下发的值有数十万份，得不偿失。
    结论连同 `compactValueLayouts` 的约束写进了该初始化器的文档注释。
- **验收**：`SymbolTestsCore` 快照 60/60 逐字节一致；全量单元测试 1273 tests / 244 suites
  全绿；对冻结基线 `main-27726bc` 跑三源（File / DyldCache / Image）整文件快照对比。
  RuntimeViewer 实测同负载下 `Node` 实例 110 万 → 18.4 万、进程内存 842 MB → 434 MB。
- **文档**：[NodeStoreMigrationPlan.md](NodeStoreMigrationPlan.md)、
  [DeclarationModelMemoryFootprint.md](DeclarationModelMemoryFootprint.md)、TaskReports
  [2026-07-25-node-store-override-regression-and-baselines.md](TaskReports/2026-07-25-node-store-override-regression-and-baselines.md)、
  [2026-07-25-cache-image-selection-and-rv-index-lifecycle.md](TaskReports/2026-07-25-cache-image-selection-and-rv-index-lifecycle.md)、
  [2026-07-26-node-store-review-fixes.md](TaskReports/2026-07-26-node-store-review-fixes.md)。

---

## 20. 引用存储（weak/unowned）对 existential 的宽度修复

- **时间**：2026-07-26（发布于 `0.14.0`）
- **动机**：用户实报 `SwiftUI.StyledTextResponder` 的字段偏移与反汇编不符。追查确认真值
  是反汇编的 `0x128` 而引擎算 `0x120`——**`weak`/`unowned`/`unowned(unsafe)` 的宽度被
  无条件建模为单字**，而修饰符只作用在对象引用字上：referent 若是 class-bound existential，
  见证表字照样在字段里（`weak var x: (any P)?` = 16 字节、`any P & Q` = 24，而 `AnyObject`
  与 `@objc` 协议 existential 不带 Swift 见证表 = 8）。因 `ViewResponder` 这类基类持有
  `weak var host: (any ViewGraphDelegate)?`，误差沿继承链放大到**全部子类的全部字段**。
- **落地**：
  - `StaticTypeLayoutResolver` 新增 `ReferenceStorageKind` + `referenceStorageLayout`：剥掉
    `Optional` 包装后按 referent 分派，existential 复用既有 `existentialLayout` 取容器宽度，
    普通类引用 / 类约束泛型参数维持单字；协议解析不到时抛 `unknown` 降级而非猜宽度；
  - XI 与 bitwise-takable **按「字」拆开**：引用字贡献修饰符自身的 XI（weak 0 / unowned 1 /
    unowned(unsafe) 饱和），见证表字贡献饱和值，容器取 max；takable 改由 referent 决定——
    existential 引用计数未知，`unowned`(safe) 走 unknown-refcounting 表示 ⇒ **非 takable**
    （初版按修饰符建模为 takable，被 VWT 对照测试当场抓出后改正）；
  - fixture 新增 6 个引用存储 × existential 的 struct + 一对基类/子类，`WholeTypeLayoutVsRuntimeTests`
    加 7 组参数化宽度 pin（各自与 runtime VWT 五元组交叉验证）与类级偏移 pin。
- **关键决策**：宽度不可猜——解析不到协议就降级。宽度错会**静默**推移其后所有字段（且沿
  继承链放大），比一个 `unknown` 注释危险得多。另记一条方法论：本 bug 曾被 struct XI 传播
  缺陷**反向抵消**（`data: A?` 多吃一个 tag 字节、对齐后多 8，正好补上基类少的 8），使
  `childSubgraph` 起的偏移碰巧正确——**只看某一个字段对不对不足以判断引擎正确**，必须逐
  字段对齐真值。
- **顺带发现（未修）**：嵌套声明的 `@objc` 协议其旧式 ObjC 名带父上下文
  （`_TtPO<module><parent><name>_`），`ObjCProtocolIndex` 只解析两段式故解析不到。
- **文档**：[StaticLayoutEngine.md](StaticLayoutEngine.md)「引用存储不坍缩 existential」、
  [TaskReports/2026-07-26-reference-storage-existential-width.md](TaskReports/2026-07-26-reference-storage-existential-width.md)。

---

## 20. 注释模板的命令行入口

- **时间**：2026-07-26
- **动机**：`OutputTransformer` 把 RuntimeViewer 的注释模板机制搬进库里之后，模板、token、
  预设、`applyTransformers` 接线全部齐备，但命令行只开了 `dump --enum-layout-style`
  一个五选一的口子，且 `interface` 完全没接 transformer。库支持的自定义能力，CLI 用户
  一点也用不上——既不能传自己的模板，也不能复用 RuntimeViewer 里已调好的配置。这一批
  纯补 CLI 表面，库侧不动。
- **落地**：
  - `TransformerOptionGroup`（`dump` / `interface` / `transformer config` 共享）提供三层，
    后层覆盖前层：`--transformer-config <json>`（直接解码 `Transformer.SwiftConfiguration`，
    与 RuntimeViewer 持久化格式同构，可原样复用）→ `--enum-layout-style <preset>`（整模块
    预设）→ 逐模块模板/进制选项（五个模块共 8 个模板槽位）；
  - 模板值二义消解：含 `${` 当字面模板，否则按内置模板名查（大小写/空格/连字符/下划线
    不敏感），**查不到报错而不是退化成字面模板**——不含 token 的字面模板本身没有意义，
    不值得为它牺牲 `--field-offset-template rnge` 这类拼写错误的可发现性；
  - `transformer` 子命令补发现性：`tokens`（每个模块可用的 `${token}`，enum layout 按
    策略行/case/固定字节三段分列）、`templates`（内置命名模板及展开）、`config`（把一组
    选项冻结成 JSON，复用同一个参数组）；
  - `interface` 补齐 `--emit-type-layout` / `--emit-enum-layout`（打印配置本就有这两个字段、
    静态 provider 也按需自建，只是 CLI 从没暴露）并接上 `applyTransformers`；
  - 新增 `SwiftSectionCommandTests`（`@testable import swift_section`，本仓首个 CLI 测试
    target）14 项：模板名解析、三层优先级、隐式启用、配置文件往返与错误路径。
- **关键决策**：**`isEnabled` 驱动 emit 开关**——最终配置里启用的模块自动打开它渲染的
  那类注释。此前 `--enum-layout-style compact` 不配 `--emit-enum-layout` 完全没有输出，
  用户看不出哪里错了；改后传模板即可见效果。反向不成立：`--emit-field-offsets` 不启用
  模板模块，仍走库内置渲染（内置渲染是 `detailed` 预设的字节级等价物且有单元测试保证，
  无谓换成模板路径只会引入行为漂移风险）。不传任何模板选项时配置构建返回 `nil`，调用方
  完全不碰渲染配置，默认输出逐字节不变。
- **未做**：其余四个模块没有做预设枚举（它们的命名模板清单是设置界面用的展示清单，塞进
  `--help` 会淹没其他选项，按名字取用足够）；模板里的未知 `${token}` 不校验（与库侧
  `replacingOccurrences` 行为一致，CLI 单独校验会与库分叉）；ObjC 侧模块仍在
  RuntimeViewerCore，喂完整 RV 配置时其键被忽略而非报错。
- **文档**：[CLITransformerTemplateInterface.md](CLITransformerTemplateInterface.md)、
  [TaskReports/2026-07-26-cli-transformer-template-interface.md](TaskReports/2026-07-26-cli-transformer-template-interface.md)、
  README 的 `transformer` 一节。
- **对应版本**：0.14.1。

---

## 21. 特化定义的 interface 绑定渲染恢复（leaf 迁移回归修复）

- **时间段**：2026-07-30。
- **动机**：RuntimeViewer 用户报告——特化节点（如 `RawCodable<NSVerticalDirection>`）的
  interface 正文仍是 unbound 形式（`struct RawCodable<A> where …` + `var wrappedValue: A`），
  只有 layout 注释是特化的。回溯定位到 `aa233bc`（leaf 迁移，0.12.0-beta.6 首发）：
  interface 路径不再实例化 SwiftDump dumper 后，`TypedDumper` 上的整套 metadata 驱动
  替换机制（`boundDumpedTypeNode` / `fieldDemangledTypeNode`）被绕开；plan 承认了头部
  退化但误记 "fields still substitute"（`substitutedTypeNode` 方案从未落地），且无测试
  覆盖。
- **落地**：`BoundDumpedTypeNameRenderer` 逐字下移到 `SwiftDeclarationRendering`
  （dump 路径经转发零变化）；新增 `SpecializedMetadataNodeSubstitution`（旧 `TypedDumper`
  替换成员的 `MetadataWrapper` 版镜像）；`SwiftPrinting` 在 `isSpecialized` 时头部走
  绑定名渲染 + 跳过泛型签名子句（保留 invertible 标记与 superclass 段），
  `renderModelFields` 逐字段经 runtime 替换、失败逐字段回退 unbound——与旧 dumper
  的 best-effort 契约一致。新增端到端测试钉住绑定头部 + 字段替换。
- **关键决策**：恢复 runtime 驱动方案而非改用静态节点替换——前者是重构前原始行为，且
  `A.RawValue` 这类 dependent member 由 runtime 按 witness 解析到最终具体类型，静态
  替换做不到。
- **文档**：[SpecializedInterfaceBoundRenderingRestoration.md](SpecializedInterfaceBoundRenderingRestoration.md)、
  [LeafMigrationRegressionAudit.md](LeafMigrationRegressionAudit.md)（对该重构线的
  三路全面审计：7 项存活问题清单 + 历史断裂记录 + 干净面）、
  [LeafMigrationPlan.md](LeafMigrationPlan.md)（deviations 补 Superseded/Amended 标注）、
  [TaskReports/2026-07-30-specialized-interface-bound-rendering.md](TaskReports/2026-07-30-specialized-interface-bound-rendering.md)。
- **对应版本**：0.14.1（回归区间 0.12.0-beta.6 ~ 0.14.0）。

## 22. Leaf 迁移回归的整批修复（错误契约 + 缓存 + 括号统一）

- **时间段**：2026-07-31。
- **动机**：[LeafMigrationRegressionAudit.md](LeafMigrationRegressionAudit.md) 列出的
  7 个存活问题一次修完，硬性目标是「重构后的逻辑与重构前（`aa233bc^`）一致」。根因
  归类：leaf 迁移在 SwiftPrinting 里**重写**（而非搬运）interface 渲染时，①错误处理
  契约从 `try await` 传播悄悄变成 `try?` 吞错；②配套基础设施（MPE 描述符缓存、深度
  截断 `#log`）没跟过来；③主路径被改道到 diff 渲染器的宽松原语上（文本判 payload、
  逐成员吞错），把 diff 契约带进了主路径。
- **落地**：恢复 `MultiPayloadEnumDescriptorCache`（per-image 部分 map，进
  `SwiftDeclarationRendering`，dump/interface 共享，坏 descriptor 只降级自己）；
  `storedFieldComments` / `enumCaseComments` / `renderModelFields` 全链 `throws` 化
  （幽灵空行与错误路径多余空行随之消失）；新增 `printThrowingEnumCase` 按 mangled
  name 判 payload（`case a(Void)` 恢复 `case a()`，两路拼写一致）；extension
  conformance 子句恢复 nil-塌缩/抛错-丢弃的二分语义；深度截断 `#log` 恢复（沿用旧
  subsystem/category）；SwiftDump 死代码（`mergedRecords` 一族、深度常量死副本）删除，
  钉值测试改指活值。
- **验证**：跨提交差分 harness（独立 SPM 包按 `.package(path:)` 分别指向 `aa233bc^`
  与修复后 worktree，同一二进制 dump+interface 两遍 diff）：edge 语料收敛到 0 diff，
  fixture plain 仅剩 SE-0452 有意修复的 20 行，注释块存在性 371/371 类型一致。新增
  `MultiPayloadEnumDescriptorCacheTests` 与 `EnumCaseRenderingParityTests`。
- **关键决策**：一致性优先于「更好」——审计中两处新行为 arguably 更干净（裸
  `case a`、静默吞掉悬空 conformance 子句），仍按用户要求恢复旧语义；diff 渲染器
  自己的原语契约（重构前即如此）保持不动。
- **文档**：[LeafMigrationRegressionFixes.md](LeafMigrationRegressionFixes.md)、
  [LeafMigrationRegressionAudit.md](LeafMigrationRegressionAudit.md)（状态标注）、
  [TaskReports/2026-07-31-leaf-migration-regression-fixes.md](TaskReports/2026-07-31-leaf-migration-regression-fixes.md)。
- **补记（2026-08-02，同分支）**：mangled-name gating 重新暴露了一个早于 leaf 迁移的 bug——`SwiftPrinting` 节点渲染器不认识 kind-9（accessor-function）symbolic reference（`~Copyable` 泛型 + 向后部署时编译器嵌 accessor thunk 指针而非类型名），payload 渲染为空串后输出非法的 `case type()`。修复：`NodePrintable` 补兜底文案（与 Demangling `NodePrinter` 逐字一致）、payload gating 改读索引期捕获的 `FieldFlags.hasMangledTypeName`、两路各加「渲染为空则裸 case」防护网；Testing.framework A/B 仅三行变化（两个枚举 case + 一个同源的存储字段悬空冒号 `var _storage: `）且与 dump 拼写逐字一致。随后与重构前基线（`a583aa8`，对齐本地依赖与同一 fixture）做全量 A/B：dump 两语料 0 diff，interface 差异恰为 kind-9 修复（3 处）+ SE-0452 integer 节点修复（6 处），无未解释差异。fixture 补上 `AccessorFunctionReferences` 命名空间（走 always-noncopyable 字段的 capability-check 路径，部署目标无关），快照经偏移归一化保持重建稳定。机理与后续两层（进程内真解析、离线符号表还原）记录在 [AccessorFunctionReferenceRendering.md](AccessorFunctionReferenceRendering.md)。
- **对应版本**：0.14.1（回归区间 0.12.0-beta.6 ~ 0.14.0）。

---

## 23. 审查清单逐条复现，修掉线程跳转与符号表钉住

- **时间段**：2026-08-02。
- **动机**：[2026-07-31 审查报告](Reviews/2026-07-31-node-store-migration-review.md)留下 17 条待处理项，全部由多智能体审查归并得出，**没有一条做过实测**，且报告自己已经承认对唯一量化过的那条判断错了量级。这一轮的目标不是修完 17 条，而是把每条的真伪与量级钉死，让后续投入落在真问题上；只有性能第一条直接修。
- **落地**：两处修复 + 一轮全清单实测。
  - `SymbolIndexStore.buildStorageImpl` 的符号 sweep 包进 `StackSafeExecutor.withLargeStack`（函数体移入 `buildStorageSweep`，外层留薄壳）。`withLargeStack` 的收益是 `(批内调用次数 − 1) × 单次跳转成本`，所以必须包住循环——包住单次调用净收益为零，这也是为什么 `printSemantic` 里**不能**加。
  - 新增 `DemangledSymbol.detachedFromSharedTable()`，在存入声明模型的六处调用（`DefinitionBuilder` 的四个构造点 + `TypeDefinition` 的 `deallocatorSymbol` / `destructorSymbol`）。查询路径不动：共享 `[Symbol]` 表对「吐几十万个值随即丢弃」仍是正确取舍，问题只在存下来长期存活的那几千个。公开 API 只增不改。
- **关键决策**：
  - **打印路径的跳转重新定性为上游刻意交易，不修**。查 `swift-demangling` 历史发现 `0.4.3` 的 `NodePrinter.printRoot` 完全没有栈保护（深树在 512 KB worker 上会崩），`7b86137` 把两个公开打印入口强制过 executor 正是为此，且同批给了 `withLargeStack` 作为摊销手段。报告建议的「恢复内联调用」不可行且不应做。
  - **detach 选构造点而非改 `init`**。后者要把 `@MemberwiseInit(.public)` 换成手写 init，而那是公开 API，签名写错会让仓库外调用方编译失败；构造点只有六处且有回归测试守护。
  - **三条判断被实测推翻**：失败名重试的危害在重复计算而非锁争用（8 线程争用 1.97x，无锁路径本身 1.67x）；dyld 全遍历不是退化而是本分支 `7e5dfcc` / `cfe40f8` 正确性修复的代价；`materialize` 占导出总时长仅 0.8%，不构成性能问题。
- **验证**：`swift test --skip IntegrationTests` 1304 项全绿。关键实测（SwiftUI iOS 18.5，185,988 符号行）：build sweep 10 万符号 1317 ms → 701 ms（1.88x）；符号表钉住从约 21 MB 降到约 2 MB（9,872 个存活值只引用 9,506 行，占表 5.1%）；`memberSymbols` 桶 99.60% 只有 1 个元素，坐实台账第 5 条「机制成立但量级可忽略」。新增回归测试 `SymbolTableRetentionTests`，修复前失败（530 个存储符号全部持有 9,348 行共享表）、修复后通过。
- **文档**：[TaskReports/2026-08-02-review-reproduction-and-retention-fix.md](TaskReports/2026-08-02-review-reproduction-and-retention-fix.md)、[Reviews/2026-07-31-node-store-migration-review.md](Reviews/2026-07-31-node-store-migration-review.md)（新增第三节实测复现，各条定性按实测更新），`AGENTS.md` 符号索引段落补入「存进声明模型的 `DemangledSymbol` 必须先 detach」硬规则。
- **对应版本**：0.14.0 之后未发布区间。注意 `Symbol` 删除公开成员（`nlist` 属性、`init(offset:name:nlist:)`）尚未升版本、未写 changelog，发布前必须补。

---

## 24. 性能批次：失败名裁决、名字去重缓存、dump 路径引用化

- **时间段**：2026-08-03。
- **动机**：[2026-08-02 审查记录](Reviews/2026-08-02-node-store-migration-pr97-review.md)与既有台账合并后剩 19 条待处理，其中「立即可修」与「中等重构」两组获批同批落地；本批延续第 23 节的纪律——先测后修，测出不值得的就裁决留档而不是硬改。
- **落地**：
  - **失败名裁决**（`SymbolIndexStore`）：`demangledNodeReference` 对表内 demangle 失败的名字直接以 sweep 裁决回答 `nil`（`NodeStoreBuilder.demangle` 与 sweep 用同一个 demangler，拒绝集一致）；`lateDemangledNode` 改锁外 demangle + 锁内 insert-if-absent，拒绝结果作为 `nil` 裁决缓存。三条新回归测试钉住（其中缓存断言在修复前红）。
  - **`InternedNodeReferenceCache`**（`MachOSymbols` 新类型）：`NodeReference(interning:)` 的结构去重层，镜像键 + 进程键双作用域，25 处名字构造点全部改走缓存；`SwiftDeclarationIndexer` 清理与内存压力驱逐接通。fixture 实测驻留 mini store 730 → 471（= 结构唯一数），字节 −32%，重复名恢复 `store ===` 快路径。原「每镜像共用 builder」修法被实测推翻（freeze 前无法发引用，调用流即用即取），故改缓存形态。
  - **dump 路径引用化**：`ClassDumper` / `ProtocolDumper` / `ProtocolConformanceDumper` 五处 `demangleSymbol` 调用点迁 `demangleSymbolReference`，visited 集合与 `distributedFunctionNodes` 换 `StructuralNodeReferenceKey`（每 thunk 省一次 materialize）；`MetadataReader.demangleSymbol` 保留契约但包内热调用方清零。
  - **`indexExtensions` 恢复 `await` + 依赖升 0.5.1**：当日早间的「不修」裁决被上游动作推翻——0.5.1（`f913742`）把 print 便利方法整体迁到 `DemanglingNode` 并补 async 变体（挂起 + 大栈），对 `NodeReference` 直接可用，一行恢复 main 的任务挂起语义；具体同步 `print` 同时被上游删除，async 上下文由编译器强制 `await`（dump 路径三处一并加上）。依赖要求升至 `from: "0.5.1"`。remangle 桥接与 `structuralHash` 分配两条随升级按上游设计终审关闭（[ReviewAdjudications.md](ReviewAdjudications.md) A1/A2）。
- **关键决策**：
  - **打印器每成员 materialize 裁决为暂不修**：临时计量显示其只占打印墙钟 1.18%（fixture 全量导出 1313 次共 32.6 ms），根治需 1700 行打印栈泛型化 + 3 处节点合成重设计，投入产出不成比例；数据与重开条件留档在审查记录。
  - 快照套件（SwiftInterfaceTests 53 项含逐字节 interface 快照、SwiftDumpTests）全绿，输出零变化是本批的硬约束。
- **关联文档**：[TaskReports/2026-08-03-performance-batch-fixes.md](TaskReports/2026-08-03-performance-batch-fixes.md)、台账第 9/10 条闭环与第 4/7 条上游状态核对、AGENTS.md「Symbol indexing」段同步。
- **对应版本**：0.14.0 之后未发布区间（`feature/node-store-migration` 分支）。

---

## 25. 系统框架渲染 A/B 验证：78 对零差异 + 流程固化

- **时间段**：2026-08-03（紧接第 24 节的性能批次）。
- **动机**：性能批次落地后，用真实 OS 框架对 `feature/node-store-migration` 做全面的输出对等验证——fixture 快照覆盖构造形态，但覆盖不了 10 万行级输出规模、iOS 15 时代的历史 metadata 与三种 reader 路径的全量组合；维护者随后要求把这套测试固化为「大重构必跑」的流程。
- **落地**：
  - **验证结果**：main ↔ feature 双侧 release CLI + `RenderingVerificationTests` harness，SwiftUI / SwiftUICore / SwiftData / Combine / ActivityKit / WidgetKit 六框架，三部分共 **78 对输出全部逐字节一致**——DyldCache（macOS 26.5.2 + 15.5 归档 cache，24 对）、MachOFile（iOS 15.5 / 18.5 / 26.5 模拟器 runtime，30 对）、MachOImage（当前系统 in-process + 当前 cache 文件，全选项，24 对）。附带 fixture（SymbolTestsCore）smoke 亦一致。
  - **流程固化**：新增 [`Scripts/run-rendering-ab-verification.py`](../../Scripts/run-rendering-ab-verification.py)（自动构建双侧、三部分渲染、逐对 diff、差异非零退出；归档 cache 缺失回退当前系统 cache，指定模拟器缺失回退现有 runtime）与流程文档 [SystemFrameworkRenderingVerification.md](SystemFrameworkRenderingVerification.md)；AGENTS.md 增设「大重构后必跑」规则，并把 `RenderingVerificationTests` 登记为 IntegrationTests 禁跑规则的唯一例外。
- **关键决策**：cache 镜像一律 `-p` 全路径（iOSSupport 副本消歧）；模拟器一律 `-a arm64`（15.5/18.5 为 fat 二进制）；MachOImage 双侧必须同一次开机会话（memberAddress 依赖 per-boot cache slide）；interface 输出走 `-o` 使时间戳日志与被比对内容分离。
- **关联文档**：[SystemFrameworkRenderingVerification.md](SystemFrameworkRenderingVerification.md)、[TaskReports/2026-08-03-system-framework-rendering-ab.md](TaskReports/2026-08-03-system-framework-rendering-ab.md)。
- **对应版本**：`0.16.0`（`feature/node-store-migration` → `next` 合并批次）。

---

## 26. 旧格式 bind 支持：LC_DYLD_INFO opcode 回退 + interface 逐项降级

- **时间段**：2026-08-03（第 25 节 A/B 验证的直接产出）。
- **动机**：A/B 验证发现 iOS 15.5 模拟器框架的 interface 输出只剩全局函数（三框架、数百条 `offsetOutOfBounds`），dump 却正常。根因两层：`resolveBind(fileOffset:)` 只认 chained fixups，旧格式（部署目标 < macOS 12 / iOS 16 的 `LC_DYLD_INFO_ONLY`）二进制的外部引用全部按裸指针误读；`printRoot` 的块级 catch 把单类型打印失败放大成全部类型消失。
- **落地**：
  - `MachOExtensions/MachOFile+.swift`：chained fixups 缺席时按 dyld 状态机解释 `bindOperations` / `weakBindOperations` opcode 流，惰性构建「文件偏移 → 符号名」索引（arm64e threaded 旧格式不索引、lazy 流不索引）。
  - `SwiftInterface/SwiftInterfaceBuilder.swift` + `SwiftPrinting/SwiftDeclarationPrinter.swift`：printRoot 四个块与 printThrowingProtocol 的 default-implementation extensions 块全部改为逐项 `printCatchedThrowing`——单个定义抛错只丢它自己。
  - 新增 `LegacyDyldInfoBindTests`（fixture 用 `swiftc -target arm64-apple-macosx11.0` 在测试内即时编译强制旧格式；红 7 → 仅 fix 2 剩 4 → 双修复全绿的阶梯实测留档）。
- **效果**：iOS 15.5 模拟器 interface：Combine 10 → 6907 行、WidgetKit 17 → 2795 行、SwiftUI 139 → 81157 行，解析错误全部归零（SwiftUI 7616 个 conformance 全数解析）；全量 1315 测试 / 250 套件绿，现代二进制快照逐字节不变。旧格式输入的 interface 输出自此与 main 合理不一致（feature 更完整），main 合并后恢复对等。
- **关联文档**：[TaskReports/2026-08-03-legacy-dyld-info-bind-support.md](TaskReports/2026-08-03-legacy-dyld-info-bind-support.md)（含完整的无调试器调试方法学 walkthrough）、[SystemFrameworkRenderingVerification.md](SystemFrameworkRenderingVerification.md)。
- **对应版本**：`0.16.0`（`feature/node-store-migration` → `next` 合并批次）。

---

## 27. SwiftLayout 系统框架保真度普查 + foreign struct / ObjC 滑动两批修复

- **时间段**：2026-08-04。
- **动机**：SwiftLayout 此前的 5 框架普查只度量**解析率**（不降级），从未对真实系统框架做
  **正确率**对拍（fixture 之外一个错而自信的偏移不会被发现）。本批对当前 dyld shared cache
  的 SwiftUICore + SwiftUI + SwiftData 共 **6246 个非泛型 struct/class** 做静态引擎
  （离线 MachOFile + 依赖闭包）vs 运行时真值（唯一权威）的全量对拍。
- **普查方法要点**：struct 真值 = metadata accessor 的 field-offset vector + VWT；class
  真值 = **realize 之后**的 ObjC runtime `ivar_getOffset`（首版直接读 metadata 向量得到
  101 个假不一致——未 realize 的 ObjC 祖先类躺着编译期未滑动的向量、resilient 父类向量
  读不出来，是取真值的方法错，不是引擎错）。零尺寸字段的 offset 约定差异（引擎按
  IRGen 报 0，运行时布局报累加器位置）单独归类，无存储意义。
- **普查结果**：完全解析率 99.95%；真实不一致归结为 4 个根因——① foreign（C-imported）
  struct 顶层布局无 builtin 防护（本批修复）；② ObjC 祖先链的类字段起点未按 objc
  `moveIvars` 滑动语义计算（3 个类，各错 4–8 字节，本批第二批修复）；③ 预特化泛型
  multi-payload enum 实为编译期 spare-bits 布局，引擎按运行时 tagged 公式多算 1 字节
  （`Dictionary` 迭代器一族 2 型——**已登记为已知偏差与后续硬骨头**，见
  [StaticLayoutEngine.md](StaticLayoutEngine.md) 的「后续工作」）；④ 零尺寸字段约定
  差异（10 型，无害）。
- **落地修复（②，同日第二批）**：类字段起点改为「本类 `class_ro_t.instanceStart` + objc `moveIvars` 滑动」精确模型——`ObjCClassIndex` 新增 Swift 类自身 `instanceStart` 索引（`_TtC…` 名 demangle 建 key；classlist 成员资格即「静态发射」判据，泛型/singleton 类缺席、维持原 Swift-runtime 规则），`classFieldStartOffset` 在 resolver/calculator 两个入口接入（滑动量按本类字段最大对齐取整）。dyld cache 镜像的盘上 `instanceStart` 是预滑终值，直接命中；fixture 无漂移场景 diff=0 逐字节不变。语义对照 `Metadata.cpp` `initClassFieldOffsetVector` 与 objc4 `moveIvars` 双向核实。普查复跑偏移不一致 3→0。测试：`ObjCAncestorSlideLayoutTests`（fixture 索引守卫 + dyld cache SwiftUI 真实漂移端到端 vs realize 后 `ivar_getOffset`）。
- **落地修复（①）**：`StaticLayoutCalculator` 顶层 struct 路径（`fieldLayout(of:)` /
  `typeLayout(ofStruct:)`）对 `hasForeignMetadataInitialization` 描述符用 `__swift5_builtin`
  记录交叉校验：结构化累加与 builtin 一致则保留逐字段结果（字段记录完整的 C struct 本就
  正确），不一致（C bitfield / 无字段记录）则逐字段降级为新 reason
  `.foreignTypeFieldOffsetsUnavailable`、整型取 builtin。此前 builtin 查表只在字段类型
  解析路径上，顶层枚举 `__C` 描述符（全量 dump / 普查）会算出 `__C.Decimal._mantissa@0`
  （真值 4）、`__C.PathData` size 0（真值 96）这类自信错值。修复后普查复跑：`__C` 类
  不一致全部清零（偏移不一致 5→3，整型不一致 20→6，余项均属 ②③）。
- **关键决策**：「交叉校验、一致才信」而非「foreign 一律降级」——`__C.RBColor` 等字段
  记录完整的 C struct 结构化累加本就正确，保留其逐字段偏移；无 builtin 记录时无从校验，
  维持现状（文档记为已知限制）。
- **文档**：[StaticLayoutEngine.md](StaticLayoutEngine.md)（新增 pitfall 条目 + 测试清单）、
  [TaskReports/2026-08-04-foreign-struct-top-level-layout.md](TaskReports/2026-08-04-foreign-struct-top-level-layout.md)
  （含 ②③④ 的完整裁决记录与普查 harness 说明）。
- **对应版本**：`0.15.0`（main，0.14.1 之后）。

---

## 28. 泛型 fixed MPE 的 spare-bits 布局：错误模型修正 + 普查整型偏差清零

- **时间段**：2026-08-05。
- **动机**：第 27 节留档的硬骨头 ③——`Dictionary` 迭代器一族（`AttributedString.Keys.SetIterator` /
  `SpatialEventCollection.Iterator`）真值 40/40/XI 126，引擎按「泛型 MPE 恒 tagged」算
  41/48/254。当时定性为「编译器预特化 metadata 按编译期 spare-bits 布局」。
- **定性修正（实验推翻旧结论）**：用探针二进制里全新定义的参数类型实例化
  `Dictionary<FreshKey, FreshValue>.Iterator`，读运行时 VWT 仍是 40/40/126，且 metadata
  位于 runtime 的 `InitialAllocationPool`——**与预特化无关**。真实机制：**布局与实参无关**的
  泛型 MPE 由编译器静态布局（spare-bits 策略），完整 VWT 烘焙进 generic metadata pattern，
  运行时完成函数从不重算；`swift_initEnumMetadataMultiPayload`（纯 tagged）只对**布局依赖
  实参**的 MPE 运行。且编译器把裁决写进了二进制：`GenReflection.cpp` 只为
  `!needsPayloadSizeInMetadata()`（静态 fixed）的 MPE 发射 `__swift5_builtin` +
  `__swift5_mpenum` 记录，`!AllowFixedLayoutOptimizations` 时编译器自己也清空 spare bits
  退回与 runtime 一致的 tagged 布局（GenEnum.cpp:7192）——**「记录存在 ⇔ spare-bits/fixed」
  在构造上精确**。5 个 OS 镜像实测：记录 typeref 全部 demangle 为无参数 nominal 名（与
  `BuiltinTypeLayoutIndex` 现有 key 一致），零 bound-concrete 实例化记录。
- **落地修复（SwiftLayout，约 20 行）**：放开 `EnumLayoutBridge` 两道基于错误模型的门——
  builtin 查表的 `environment.isEmpty`（实例化/未特化泛型 enum 节点照常查剥参数 key）与
  `multiPayloadEnumLayout` / `enumCaseLayoutResult` 的 `!descriptor.isGeneric`（只按
  `usesPayloadSpareBits` 分流）；`compute()` 补查**定义镜像**的 builtin 索引（enum 记录按
  声明模块发射，跨镜像 + mask>16k 边角随之闭合）；`BuiltinTypeLayoutIndex` 防御性跳过
  bound-concrete 实例化记录。
- **验证**：新 `GenericSpareBitsEnumLayoutTests` 修复前红（fixture `SpareBitsVariantEnum`
  24/24/XI 125 vs 引擎 25/32/253；OS 端到端 40/40/126 vs 41/48/254）修复后绿；fixture 新增
  `Dictionary.Iterator._Variant` 形态类型族；SwiftUI 全量 dump before/after 对拍：117 行
  diff 全部是 enum-layout 注释、恰好 4 个受益枚举（`NSHostingView.AllowAutomationElementsState`、
  `AnimatedValueState<A>` 一族），声明本体零变化；普查复跑整型偏差清零。顺带修
  `MultiPayloadEnumStructuralTests` 既有缺陷：遍历未过滤泛型描述符，第一个空环境可解析的
  泛型 MPE（新 fixture 类型）会让它对泛型 enum 无参调 accessor 而 SIGSEGV。
- **关键决策**：判据用「编译器记录的存在性」而非结构化推导 fixedness——后者需要重放
  resilience 语义（`layoutScope`），二进制里读不到 `@frozen`，必然出启发式误差；记录存在性
  是编译器原话、零启发式，且索引早已收录，修复只是放行。
- **文档**：[StaticLayoutEngine.md](StaticLayoutEngine.md)（核心算法 / pitfall / 已知偏差表 /
  后续工作四处改写，硬骨头条目标记已解决）、AGENTS.md（`EnumLayoutBridge` 条目重写）、
  [TaskReports/2026-08-05-generic-fixed-mpe-spare-bits.md](TaskReports/2026-08-05-generic-fixed-mpe-spare-bits.md)。
- **对应版本**：`0.15.0`（main，0.14.1 之后，紧接第 27 节）。

## 29. 嵌套字段偏移展开的环守卫（indirect case 不下钻 + 路径环检测）

- **时间段**：2026-08-06。
- **动机**：RuntimeViewer 对 Xcode 的 `DVTIconKit` 生成 Swift interface 时"死循环"，
  日志刷 `walkNestedExpandedFieldOffsets reached … depth limit 16` 千余条仍在增长，
  约 20 条线程堵在 demangle 上。诊断结论：不是死循环，是**有环类型图上的指数级路径
  枚举**——深度上限约束"走多深"，而环让"有多少条路径"爆炸，两者管的不是一回事。
- **落地**：两条独立实现各加两道守卫。①`indirect` case 的 payload 是堆 box 指针，
  声明类型不布置在该偏移上，因此报告该 case 但不下钻（与 class 引用同等对待）——这也
  是值类型字段图唯一可能成环的地方，是实际消除爆炸的那道；②**路径作用域**的已打开
  类型集合（运行时按 `ObjectIdentifier(metatype)`，静态按打印类型名，以区分
  `Box<Int>`/`Box<String>`），作为解析误判造成假环的纵深防御。深度上限保留，继续兜
  "无环但很深"。落在 `SwiftDeclarationRendering.RuntimeFieldLayoutBackend` 与
  `SwiftLayout.NestedFieldOffsetTree`。
- **关键决策**：环检测按路径而非全局——同一类型经**不同字段**到达时两处都必须完整
  展开（`String` 挂在两个属性下是两棵真实子树），全局 visited 会让输出残缺。
- **验证**：新增 fixture `RecursiveIndirectFieldLayout`（复刻 `DVTIconKit` 形状：struct
  ↔ 逐 case `indirect` 的泛型 enum，外加无环三层深的对照）与两个回归套件（运行时/静态
  各 4 个测试）。修复前实测 8 个测试 6 个失败、925 个 issue、运行时路径展开 892 行，
  失败信息直接打印出那条环；修复后 8/8 通过，全量套件（`--skip IntegrationTests`）绿。
  fixture 变更按既定流程重生成 ABI baseline（59 文件，纯 `descriptorOffset` 漂移）。
- **合入**：开发基线为 `3396cfd`，完成后 rebase 到 `main`（`4eeb3b4`）——源码与文档干净
  合并，冲突仅在 59 个 baseline（重新生成而非手工调和）。此步暴露一个必要前置：`main`
  依赖 node-store 迁移引入的 `NodeReference`，本地 swift-demangling 停在 `04c959b` 时
  `main` 编译不过、`regen-baselines` 失败，故把本地 swift-demangling fast-forward 到
  `main`（`985c9b7`）。副作用：RuntimeViewer 的 Debug workspace 共用该 checkout，其依赖
  随之前移（这本就是与本仓库 `main` 自洽的组合）。
- **历史查证**：同一类问题 2026-05-16 在 **SwiftInterface 打印路径**上修过（DAG 被当树
  展开，394,062 次节点访问），当时报告已明确写下"Apple-style MaxDepth 单一兜底对本类
  爆炸无效"；三周后的 PR #88（2026-06-10）动了本次这段代码，却只把硬编码 `16` 抽成常量、
  加 `os_log`、加钉值测试——**把深度上限诊断化了，没有把五月的结论横移过来**。所以本次
  不是回归，是教训没有跨路径传播。
- **横向排查**：全库读 enum payload record 处逐一核对，`EnumLayoutBridge`(185/250)、
  `enumPayloadSize`、`enumPayloadExtraInhabitantCount` 均已正确处理 `isIndirectCase`，
  遗漏仅本次两处；`SwiftSpecialization.deriveNestedSpecializedTypeChildren` 虽同为
  `depth < 16`，遍历的是嵌套类型**声明**树（天然无环），不属同类，不改。
- **文档**：[NestedFieldOffsetCycleGuard.md](NestedFieldOffsetCycleGuard.md)、
  [TaskReports/2026-08-06-nested-field-offset-cycle-guard.md](TaskReports/2026-08-06-nested-field-offset-cycle-guard.md)。
- **对应版本**：`0.15.0`（main，0.14.1 之后，紧接第 28 节）。

---

## 30. main 退回 0.14.1 基线：node-store 合并撤出，四个 SwiftLayout 修复重新接线

- **时间段**：2026-08-06。
- **动机**：维护者判断 PR #97（`feature/node-store-migration`，2026-08-04 合入）进 main
  过早，要求 main 回到 `0.14.1` 发布点，同时**保留**合并之后落在 main 上的四个
  SwiftLayout / rendering 修复（即本文第 27–29 节），node-store 的工作整体退回 feature
  分支等待合适时机。
- **落地**：main 由 `621f6fa` 重写为 `3396cfd`（tag `0.14.1`）+ 四次 cherry-pick。
  `Package.swift` 随之退回 `swift-demangling` 的 `0.4.5 ..< 0.5.0` pin（0.5.x 重塑了
  `NodePrinterTarget`、删除了 `Node: Codable`，是本次回退唯一的硬耦合点），
  `MachOSymbolsTests` 与三处 target 依赖一并回退。
- **关键决策**：
  - **选 cherry-pick 重写而非 `git revert -m 1`**。revert 会在历史里留下「这些改动已被
    处理过」的记录，将来把 feature 分支合回 main 时 Git 不再带回那些代码，必须先
    revert the revert；而 node-store 明确是要回来的。重写后两个分支之间重新有完整
    diff，重开 PR 即可。
  - **动手前用 `git merge-tree --write-tree` 只读预演两条路径**，在不碰工作区的前提下
    确认「代码文件全自动合并、唯一冲突是 `ProjectEvolutionLog.md`」，把最大的不确定性
    前置消解。
  - **四个修复与 node-store 无源码耦合**这一判断先由 diff 扫描得出（无一处引用
    `NodeReference` / `demangleAsNodeTransient` / `NodeStore` 等新 API），再由 0.4.5
    依赖下的全量构建 0 错误 0 警告证实。
  - **数据安全靠三重保险**：`backup/main-before-0.14.1-rewind` 分支 + 同名带日期 tag
    （本地与 origin 双份）+ `feature/node-store-migration` 保持在 `621f6fa` 不动。
    重写前先备份、先推远程，再动分支。
  - **历史叙述不改写**：各 TaskReport 正文里对旧 SHA 的引用（如「rebase 到 main
    （`4eeb3b4`）」）保留原貌——那是对当时事实的记录；旧 SHA 一律可通过备份分支解析。
    只有「对应版本」这类元数据字段改为不依赖 SHA 的表述。
- **影响面**：回退期间 node-store 分支带来的能力（符号索引 NodeStore 化、性能批次、
  旧格式 `LC_DYLD_INFO` bind 支持、系统框架渲染 A/B 验证流程与其「大重构必跑」规则）
  不在 main 上。本文的节号在回退期间也顺延过一轮（node-store 的第 23–26 节移出 main 后，
  原第 27–29 节临时占用了 23–25）。
- **后续（同日）**：`feature/node-store-migration` 随即以
  `git rebase --onto main 439ecca f31711c` 落到重写后的 main 上——36 个提交线性重放，
  天然排除四个已 cherry-pick 的修复（它们在 `f31711c` 之上），全程唯一冲突是
  `Package.swift` 里 swift-demangling 的 pin 之争（取 node-store 侧，终态回到
  `from: "0.5.1"`）。本文按编年顺序恢复原样：node-store 四节回到 23–26（工作时间
  08-02~08-03），SwiftLayout 三节回到它们原本的 27–29（08-04~08-06），本节顺延为
  第 30 节。此后重新合入 main 时，本文这 30 节不再需要重新编号。
- **后续（2026-08-07）**：main 上又落了一个批次（class / static 成员关键字还原），
  分支再次 rebase 到 main。这次的冲突面比上次小得多：代码只有 `SwiftDeclarationPrinter`
  的三个成员打印入口（main 加 `isClassMember:` 参数、本分支把 `node` 换成
  `node.materialize()`，两侧叠加即可），文档是 `Documentations/README.md` 的索引表
  与本文——main 的新批次作为**第 31 节**接在本节之后，既有 30 节的编号一个没动，
  上一条「不再需要重新编号」的承诺因此只对**本分支自己的节**成立：main 每落一个
  批次，本文末尾就要接一节新的，这是编年账本的常态，不是重新编号。
- **文档**：[TaskReports/2026-08-06-main-rewind-onto-0.14.1.md](TaskReports/2026-08-06-main-rewind-onto-0.14.1.md)。
- **对应版本**：`0.15.0`（0.14.1 与该 tag 之间只有第 27–29、31 节的四个修复批次）。

---

## 31. class / static 成员关键字的还原（vtable method descriptor 判据）

- **时间段**：2026-08-07。
- **动机**：interface 输出把所有类型级成员渲染成 `static`，源码里的 `class func` /
  `class var` 无法还原；更严重的是存在非法 Swift 语法 `override static`（`static`
  不可 override）——iOS 18.5 SwiftUI 里 19 处，项目自己的 interface 快照基线里 2 处。
- **关键决策**：
  - **判据用正向的 method descriptor 存在性**，不推断 final：class 里的 `static`
    成员被编译器隐式推成 final、不进 vtable；`class` 成员非 final、有 method
    descriptor。ABI 里没有任何 final 位（`ClassFlags` / descriptor flags /
    `class_ro_t` 三处查证），但这个判据不需要它。
  - **用 `methodDescriptor` 而非 `vtableOffset`**：后者对部分 override 成员解析
    失败（父类 vtable 查不到槽位）而前者始终在。
  - **无法识别的四类保守输出 `static`**（`final class func`、final class 里的
    `class func`、extension 里的 `class func`、`@objc dynamic class func`）——它们
    在 ABI 上与 `static` 完全一致，且 `static` 与 `final class` 语义等价，不产生
    错误代码。
  - **dump 的 override table 行保留 demangler 的 `static` 前缀**：那是对符号的
    忠实还原（与 `swift-demangle` 一致），不是 interface 语法，不篡改。
- **落地模块**：`SwiftDeclaration`（`isClassMember` / `hasVTableAccessor` 计算
  属性）、`SwiftPrinting`（三个 node printer 的 `isClassMember` 参数 +
  `SwiftDeclarationPrinter` 接线）、`SwiftDump`（`ClassDumper` vtable 段落
  关键字）；interface / diff / dump 三路全覆盖，无新解析。
- **文档**：[ClassMemberKeywordRecovery.md](ClassMemberKeywordRecovery.md)、
  [TaskReports/2026-08-07-class-member-keyword-recovery.md](TaskReports/2026-08-07-class-member-keyword-recovery.md)。
- **对应版本**：`0.16.0`。

---

## 32. 内存图驱动的 NodeStore 驻留收口：容量预留 + 残余 cached demangle 清零

- **时间段**：2026-08-08。
- **动机**：RuntimeViewer 索引五个系统镜像（Foundation + libswiftCore + AppKit + SwiftUI + SwiftUICore）后的 memory graph 显示存活 `Node` 208,809 个、`NodeStore` 14,451 个；swift-demangling 侧会话定位来源后转来三项计划，本批落地其中两项，第三项显式等待上游。
- **落地**：
  - `SymbolIndexStore` 主 sweep 的 `NodeStoreBuilder` 构造后一行 `reserveCapacity(expectedSymbolCount: totalSymbolCount)`（上游提案 0009 API），消掉构建期缓冲增长拷贝与冷启动 footprint 尖峰（上游实测减半）；预留 growing-only 且不改变 interning 结果。
  - 最后两处带全局缓存的 `demangleAsNode` 转 `demangleAsNodeTransient`：`SwiftLayout.ObjCClassIndex`（取限定名字符串即弃树）与 `SwiftDeclarationRendering.SpecializedMetadataNodeSubstitution`（渲染即弃）。至此 Sources 下 cached `demangleAsNode(` 清零，Stage 5c 收口补全。
- **关键决策**：三条「每树/每类型/每晚到名字铸小 store」的流水线（`InternedNodeReferenceCache`、`TypeDefinition` 字段树批量 store、`lateDemangledNode`）**不动**——它们是对上游「builder 一次性 freeze」缺口的正确规避，等 swift-demangling 提案 0010（`SharedNodeStore`，Draft）落地后统一汇入每镜像共享 store。
- **文档**：[NodeStoreMigrationPlan.md](NodeStoreMigrationPlan.md)「内存图驱动的驻留收口（2026-08-08）」一节；AGENTS.md Stage 5c 站点清单同步。
- **补记（2026-08-08 同日，第三项落地）**：上游 0010（`SharedNodeStore`）当日 Implemented，本仓库迁移设计（[SharedNodeStoreMigration.md](SharedNodeStoreMigration.md)）经批准后同日实施：`InternedNodeReferenceCache` 退役哈希桶层、外壳换持每 scope 一个 `SharedNodeStore`（31 个调用点零波及）；`TypeDefinition.index` 字段树两阶段收敛为直接 intern 进镜像 store（去重范围从单类型扩到全镜像）；`lateDemangledNode` 换 `Storage` 自持的 side store、「loser 弃店」删除。全量 1337 tests 全绿且与迁移前同数，缓存与 late-path 的八条行为测试未改一行原样通过。用户裁决豁免「上游先 push」前置条件（无 sibling 环境在上游 push 前不可构建，知情接受）。RV 五镜像 memory graph 实景复测闭环：`NodeStore` 实例 **14,451 → 15（−99.9%）**，存活 `Node` 208,809 → 207,489（预期内小降），数字已回填上游 0010 决策日志。
- **对应版本**：`0.16.0`（`feature/node-store-migration` 分支）。

---

## 33. MetadataReaderCache 清退：残留 class Node 树的持有主体换持 NodeReference

- **时间段**：2026-08-08（第 32 节同日的后续）。
- **动机**：`SharedNodeStore` 迁移后 RV 五镜像复测显示存活 class `Node` 几乎未动（207,489），归因约 89%（~18.4 万棵树）被 `MetadataReaderCache.Storage` 的三张字典永久持有——NodeStore 体系之前的旧式缓存，private 单例、只进不出、零跨树共享。用户经 swift-demangling 会话下达清退指示。
- **落地**：三张字典载荷换 `NodeReference`（树体 intern 进 `InternedNodeReferenceCache` 的镜像/进程作用域 store，与声明模型的同批树直接去重共享），hit 路径 `materialize()` 重建独立树，公开 API 与 Sources 内 103 处调用点零改动；新增 `MetadataReader.removeCache(for:)` 接进 `SwiftDeclarationIndexer.deinit`，关掉「只进不出」。
- **关键决策**：换后端而非彻底删除（字典 memo 的 demangle 工作有 103 处调用点反复命中，删除必致 CPU 回归且内存不多赚）；对面「`MultiPayloadEnumDescriptorCache` 必须同批改键」的判断经核实不成立（class `Node` 的 `==`/`hash` 是结构语义，实例身份只是快路径），该缓存保留原样。
- **验证**：全量 1337 tests 同数全绿；渲染 A/B 96 对逐字节一致（三 reader 路径 × dump/interface）；性能持平（72 对场景总耗时 ±0.2%，受控交错测量中位 71.3s vs 70.9s）；RV 五镜像 memory graph 实景复测存活 class `Node` **207,489 → 44（−99.98%）**、`NodeStore` 持平 15——远低于方案预期 ≲23k 的原因（跨测量上下文相减的假象人口、两个预期残留源在索引负载下不运行）记录于设计文档。
- **附带发现**：本地 sibling 依赖生效需「兄弟目录存在 + `USING_LOCAL_DEPENDENCIES=1`」双条件，旧 scratch 的 manifest 求值缓存会掩盖后者——已补进 AGENTS.md 环境漂移检查第 2 条。
- **文档**：[MetadataReaderCacheRetirement.md](MetadataReaderCacheRetirement.md)、[TaskReports/2026-08-08-metadata-reader-cache-retirement.md](TaskReports/2026-08-08-metadata-reader-cache-retirement.md)；[DeclarationModelMemoryFootprint.md](DeclarationModelMemoryFootprint.md) 后记标注该项结论失效。
- **对应版本**：`0.16.0`（`feature/node-store-migration` 分支）。

---

## 34. SymbolIndexStore 符号名 offset 化：驻留字符串换字符串表引用（evolution 提案 0001）

- **时间段**：2026-08-08（第 33 节同日的后续；本仓库 Evolution 提案制的首个提案）。
- **动机**：RV 五镜像 445 MB 稳态剖析定位 `SymbolIndexStore` ≈ 215 MiB 为堆内头号大户，最大单项是 49.4 万个驻留符号名 `String`（68.7 MiB）——原文本就在镜像 mmap 的 LINKEDIT 字符串表（clean 页），eager 拷贝把免费页复制成付费脏页。方案以提案 0001 落盘、经用户批准后实施。
- **落地**：`SymbolTable`（16 字节 `SymbolRow` = canonical offset + packed name reference；名字来源双腿——镜像行零拷贝直指 mapped 字符串表、文件行与 export-trie 名进私有连续字节缓冲）；收集循环 reader 分腿（镜像腿字节级 `isSwiftSymbol`，非 Swift 符号零分配；文件腿沿用 `readString`）；`tableRowByName` 退役换名字序 permutation 字节级二分（build 期临时去重字典 freeze 丢弃 + 精确容量拷贝）；vend 面按需物化（`DemangledSymbol` 加 `offset`/`isExternal`/`name` 快路径）。公开 API 与全部调用点零改动。
- **关键决策 / 实施偏差**：`Span`/`UTF8Span` 运行时可用性 macOS 26+、本包部署下限 10.15 → 字节访问层改 `UnsafeBufferPointer`（closure-scoped 形态不变）；`RigidArray` 的 class 属性 borrow 人体工学要 SE-0507 → 精确容量 `Array` 拷贝、免掉 `BasicContainers` 依赖；`Optional<NodeIndex>` 哨兵搭车项放弃（`NodeIndex` 构造器上游 internal）。均记入提案决策日志。
- **验证**：等价性测试 4 项全绿（字节级判定 vs `String.isSwiftSymbol` 全符号表逐条一致、mapped 收集 vs String 收集全等、二分逐行自洽、detach 物化正确）；全量 1341 tests / 256 suites 全绿（前 1337 + 新增 4）；渲染 A/B 96 对逐字节一致、性能持平（详见提案落地记录）；RV 五镜像实景复测同日闭环——footprint 稳态 **445 → 322 MB（−28%）**、堆存活 355 → 283.3 MiB、`SymbolIndexStore` 簇 214.6 → 120.9 MiB、驻留符号名 StringStorage 如预期消失（−42.8 万个），无回归旁证。
- **文档**：[Evolutions/0001-symbol-name-offsetization.md](../Evolutions/0001-symbol-name-offsetization.md)（提案全生命周期）、[TaskReports/2026-08-08-symbol-name-offsetization.md](TaskReports/2026-08-08-symbol-name-offsetization.md)。
- **对应版本**：`0.16.0`（`feature/node-store-migration` 分支）。

---

## 35. SymbolIndexStore `[UInt32]` 行号桶扁平化（evolution 提案 0003）

- **时间段**：2026-08-09（0001 落地次日；0001「非目标」一节点名的候选正式立项）。
- **动机**：RV 五镜像复测显示 offset / member 索引里的 `[UInt32]` 碎数组簇 38.8 MiB / 约 45 万个——绝大多数桶只有一个元素，却各自付一次堆分配与数组头。
- **落地**：`SymbolRowBucket`（`RandomAccessCollection`）替换四处 `[UInt32]` 桶：单元素 case 内联在字典槽里，收到第二个元素才落堆数组；迭代序保持插入序，查询输出与旧桶逐字节一致。fixture 上单元素桶占比 87.6%。
- **验证**：全量 1343 tests 全绿；渲染 A/B 七对（含 dyld cache 两对）逐字节一致。下游 RV 复测超预期：`[UInt32]` 簇 38.8 → **7.2 MiB**（预期 15–20），碎数组人口坍缩为 5 个桶字典。
- **文档**：[Evolutions/0003-symbol-row-bucket-flattening.md](../Evolutions/0003-symbol-row-bucket-flattening.md)（提案全生命周期）。
- **对应版本**：`0.16.0`（`feature/node-store-migration` 分支）。

---

## 36. 声明模型 descriptor 化：不再驻留急切解析的胖 wrapper（evolution 提案 0002）

- **时间段**：2026-08-09（与 0003 同批立项、独立实施）。
- **动机**：0001 落地后 RV 复测把堆内新头部定位为声明模型 41.3 MiB + MachOSwiftSection 解析簇 33.4 MiB——`index()` 惰性与 wrapper 急切驻留错配：每个 `TypeDefinition` / `ExtensionDefinition` / `ProtocolDefinition` 终身抱着全量解析的 `TypeContextWrapper` / `ProtocolConformance` / `Protocol`（trailing objects 含 `[ResilientWitness]` 全在内），但索引完成后几乎无人再读。
- **落地**：三定义改为驻留 **descriptor 引用**，全量 wrapper 用时经 `materializedTypeContext(in:)` / `materializedProtocolConformance(in:)` / `materializedProtocol(in:)` 按需重建（每操作至多一次、线程化为局部变量、绝不缓存回定义）；`parentContext` 及其 `ParentContext` 类型整体移除；实施期修正扩展到 indexer `Storage` 侧——四个人口数组在 `prepare()` 后清退、按名 keyed 重映射降级为索引期局部变量，新增名字级轻映射 `conformingProtocolNamesByTypeName` 等承接全部索引后消费者。
- **关键决策**：物化结果不缓存（缓存会按浏览顺序把清退的内存攒回来）；wall-clock 以 release ABBA 定论——SwiftUI interface 候选反而快 5.3%，SwiftUICore 噪声带内。
- **验证**：全量 1343 全绿；渲染 A/B 七对逐字节一致（debug 与 release 双构建）；实例尺寸 `TypeDefinition` 1272 → **384 B**、`ExtensionDefinition` 640 → **224 B**、`ProtocolDefinition` 440 → **384 B**，回归守卫 `DeclarationModelInstanceSizeTests` 钉住上限。下游 RV 五镜像复测全部达标、三项超预期：稳态 322 → **262 MB**、堆存活 283 → 209.6 MiB、解析簇 33.4 → 3.3 MiB、索引瞬态峰值 808 → 613 MB。五镜像稳态全程曲线：842 → 470–480 → ~450 → 322（0001）→ **262 MB**（0002+0003）。
- **后记**：机械迁移漏审了读人口数组的六个公开统计属性（清退后静默归零）——由 PR #103 review 发现（H1）并在第 37 节的批次里修复；教训已记入 0002 决策日志（编译器驱动的迁移看不见「语义在、数值错」的调用面）。
- **文档**：[Evolutions/0002-declaration-model-descriptor-slimming.md](../Evolutions/0002-declaration-model-descriptor-slimming.md)（提案全生命周期）、[DeclarationModelMemoryFootprint.md](DeclarationModelMemoryFootprint.md)（后记复量）。
- **对应版本**：`0.16.0`（`feature/node-store-migration` 分支）。

---

## 37. PR #103 review 修复批次：14 条发现的实现与裁决

- **时间段**：2026-08-09（PR #103 的 max 级 review 移交清单；B1（swift-demangling 远端 pin 缺上游 tag）由用户自行处理，不在本批次内）。
- **动机**：`feature/node-store-migration` → `main` 的 PR review 产出 15 条经四问验证的发现；除 B1 外全部批准实施。四条共因串起十一条发现：0002 机械迁移的语义盲区（H1/H2/M1/L1）、0001 引入的裸指针与位预算（M2/M3/M5）、新二进制解码信任输入（H3/M4）、验收工具无自检（H4/L2/L4）。
- **落地（代码修复 9 条 + 测试/工具 3 条）**：H2 扩展索引早退补 `isIndexed`；H1 统计快照在清退前冻结（`PreparationStatistics`）；M4 `isBind` 补 LC_DYLD_INFO 回退与 `resolveBind` 对齐；H3 bind 解码器按段界 bound（repeat count 挂死与 wrap 错归因关死）；M3 `PackedNameReference` 改 failable（build sweep 跳过超预算名、standalone 公开路径 clamp，release 下不再由二进制决定进程生死）；H4 A/B 验收脚本零对比即失败 + 硬失败传播；L2 fixture 编译先排空管道再等退出 + 临时目录进程退出清理；L4 offset 重建测试去 500 采样上限、排序全量；M6 per-image 缓存驱逐移交「镜像最后一个存活 indexer」（进程级登记表，修掉 A 死抽走 B 的三缓存）；M1 公开 `printExtensionHeader` 的物化失败改传播（与 `index(in:)` 契约对齐）；L1 嵌套子定义下压 per-child catch（坏子类型只丢自己）。
- **裁决（3 条，记入 [ReviewAdjudications.md](ReviewAdjudications.md) A4–A6）**：M2 卸载后悬垂指针——实验证明 Darwin 把含 Swift 内容的镜像全部 pin 死（连无类 dylib 都不 unmap）、唯一能卸载的纯 C 镜像不产生 mapped 行，触发面结构性不存在；M5 建议的 detach 时拷贝 node store——定义自身 `node` 字段同店引用，拷贝零回收，改为文档写准 + 共享契约测试钉住；L3 建议的 achievable-rank 早退——机制不可靠（会复发跨 subcache 误解析）且全扫描实测仅 43 ms，强制配套的 plain-`.dylib` 端到端用例落地。
- **实施期修订（留痕于清单文档）**：H3 的 `Int(segment)` trap 被推翻（segment 是 4-bit opcode immediate）；M1 的渲染路径失败被 review 会话自行推翻（库内不可达）并降级为 Low；L3 的开销估计被测量推翻。每条修复先写修复前失败的回归测试（M3 的 precondition trap、M6 的三缓存被抽、L1 的整型丢弃等均有失败实录），验证全程走本地兄弟依赖环境（B1 未决期间 CI 不可用）。
- **文档**：[Roadmaps/2026-08-09-pr103-review-findings.md](../../Roadmaps/2026-08-09-pr103-review-findings.md)（原始清单 + 修订注记）、[ReviewAdjudications.md](ReviewAdjudications.md)（A4–A6）、[TaskReports/2026-08-09-pr103-review-fix-implementation.md](TaskReports/2026-08-09-pr103-review-fix-implementation.md)。
- **对应版本**：`0.16.0`（`feature/node-store-migration` 分支）。

---

## 38. rebase 到 0.15.0：跟随 `MachOExtensions` 抽包，把分支成果移植上游

- **时间段**：2026-08-10。
- **动机**：`main` 走到 `0.15.0`，其中 `6550d22d` 把整个 `Sources/MachOExtensions/` 模块抽到上游独立包 `MachOKitExtensions`（抽出去是为了让 `MachOObjCSection` 也能依赖它——本包依赖 `MachOObjCSection`，ObjC 侧无法反向依赖包内 target，否则构成包级循环），同时 `OutputTransformer` 改名 `SwiftOutputTransformer`。`feature/node-store-migration` 的 70 个 commit 需要 rebase 到新 `main`，但两边的文件重叠里有两个是**被 main 删掉、被分支修改**的：`MachOExtensions/MachOFile+.swift` 与 `DyldCache+.swift`。逐字节比对上游包后确认它停在抽取时的状态，也就是说直接按「接受 main 的删除」解冲突，会静默丢掉分支上五个 commit 的成果。
- **落地**：**先移植上游、再 rebase**。移植四块改动到 `MachOKitExtensions`——dyld cache 跨 subcache 的 `matchRank` 排序与 Catalyst 支持根降级（`17ad4358` + `6647359e`）、legacy `LC_DYLD_INFO(_ONLY)` bind 索引（`5c74ad67`）、bind 解码器按段界 bound（`c36a3a2e`，PR #103 的 H3）、`isBind` 补同源回退（`b3bffa0d`，M4）。移植按**分支 tip 的文件状态**做，不逐 commit 搬，因此 rebase 时中间 commit 的 hunk 可以安全丢弃。适配上游的两处差异：访问级 `package` → `public`；上游不依赖 `FoundationToolbox`，路径取叶名改用 Foundation 的 `URL` 惯用法。随后 rebase 71 个 commit，7 处 modify/delete 冲突一律按删除解，另有三处 `import MachOExtensions` 改名、两个测试 target 依赖从 `.target(.MachOExtensions)` 换成 `.product(.MachOKitExtensions)`。
- **关键决策**：`DyldCacheImageSearchTests` 的 `@testable import` 降级为普通 `import`——`matchRank` / `bestMatchRank` 在上游是 `public`，而外部包依赖本就不以 testability 构建，`@testable` 在这个位置既不必要也不可行。
- **验证**：上游包单独 `swift build` 通过；本仓库全量 **1408 tests / 264 suites、退出码 0**（`--skip IntegrationTests`）。验证过程中踩到两个已知环境陷阱并记录：`.claude/worktrees/` 下缺 `MachOKitExtensions` 软链（静默回落远端 `0.1.0`）、`swift-semantic-string` 软链指向的兄弟 worktree 还没有 `OutputTransformer` product；另外 SwiftPM 的 manifest 求值缓存会让改过软链后的解析结果不刷新，需要 `--manifest-cache none` 才能真正切到本地包。
- **上游发版**：移植已由用户于同日推送并打出 `MachOKitExtensions 0.1.1`。核验过 tag 内容与本地通过测试的副本逐字节一致，并摘掉本地软链、强制远端解析后重跑：相关 17 个测试与全量 1408 测试均退出码 0。本仓库 pin 随之从 `from: "0.1.0"` 收紧到 `from: "0.1.1"`（真实下限——两个测试套在 `0.1.0` 上无法编译），本地解析与 CI 就此一致。
- **遗留**：`swift-demangling` 的 `0.5.1` tag 不含 `SharedNodeStore` 与 `NodeStoreBuilder.reserveCapacity(expectedSymbolCount:)`，PR #103 的 B1 仍未解——这是 CI 唯一剩下的阻塞项，本地验证仍需 `USING_LOCAL_DEPENDENCIES=1` + 兄弟目录取 `swift-demangling`。
- **文档**：[TaskReports/2026-08-10-rebase-onto-0.15.0-and-upstream-port.md](TaskReports/2026-08-10-rebase-onto-0.15.0-and-upstream-port.md)。
- **对应版本**：`0.16.0`（`feature/node-store-migration` 分支）。

---

## 39. PR #103 第二轮 review：15 条发现的四问、复核与实现

- **时间段**：2026-08-13（`feature/node-store-migration` 的第二轮 max 级 review；第一轮见第 37 节）。
- **动机**：第一轮修复落地后再审一遍，产出 15 条发现。四问（复现 / 基线对比 / 值不值得修 / 既往修复）不是走过场——它推翻了初版结论中的三条，全部靠查证而非推理：F1「本 PR 引入」实为基线既有（main 的 `printTypeHeader` 本身就含两处会抛的 `try`，初版只盯着换掉的那个参数）、F7 的破坏面被默认参数缩小（`Symbol(offset:name:)` 两边都编译）、F15 的 `cls` 是 main 上沿用而非新发明。另有 F2 因结构上触发不到而降为防御性、F13 因无法复现且 main 相同而记入已裁决清单。
- **交叉复核**：15 条结论交同项目另一会话独立复核，四点实质修正全部采纳。其中两条是原查证不足：F10 曾因「未核实上游」撤掉的论点，经复核在上游 `DemangleInterface.swift:56-67` 找到文档契约而**恢复**（无参数 kind 即使走 transient 也解析到进程级 `NodeFactory` 单例，故修法不能简单加强 `!==` 否则假失败）；F5 的「修法现成」被指出说过头（`StructuralNodeReferenceKey` 只包 `NodeReference`，查询侧是裸 `Node`，无零成本包装），且该处并不违反 AGENTS.md 那条硬规则。
- **落地（代码 6 条 + 横向 4 处 + 文档/测试）**：A1 A/B 验收脚本双边失败但退出码不同时计入差异（第一轮 H4 同根因的第二个实例）；A2 `printCatchedThrowing` 停止 `print(error)` 改派发 `.definitionPrintFailed`，13 个调用点补 context——这正是 Issue #102 明确提出而本 PR 原先只做了三分之一的另外两条；A3 diff 头行渲染失败丢弃整条声明（空 header 下渲染成员是非法 Swift）；B1 opaque 查询从「按 identifier 分桶后线性 `structurallyEquals`」改为结构化哈希一次探测（`StructuralNodeReferenceKey` 增加 `init(querying:)` 的裸 `Node` 形态，两侧哈希由上游保证一致）；B2 缓存回收资格拆成三位分别 claim（只有 symbol store 必然是 indexer 建的，另两份 SwiftLayout / 渲染器 / SwiftSpecialization 也在填），注册改 identity-keyed 顺带吸收 B3 的 check-then-set 竞态；F15 `cls` → `classWrapper`。横向排查另找到 4 处 `print(error)` 全部改写 stderr，`Sources/` 下现已归零。
- **裁决（2 条，记入 [ReviewAdjudications.md](ReviewAdjudications.md) A7–A8）**：索引器与 dump 路径 witness 匹配的 print options 分歧（无法构造触发场景，main 相同，无 fixture）；`updateConfiguration` 的 re-prepare 因 `isPrepared` 早退而是 no-op（零调用点，RuntimeViewer 硬编码使其不可达）。
- **踩坑留痕**：B1 改了 `SymbolIndexStore.Storage` 字段结构却未按 AGENTS.md 立即 `swift package clean`，导致增量构建链接 stale object——`swift build` 连续报成功、全量测试跑到 484 例后 SIGSEGV 且零断言失败；clean 后才暴露真实编译错误（把一个 `NodeReference` 属性改成了 optional，破坏三个既有调用点）。另：sibling `swift-demangling` 是共享可变状态，构建中途撞上另一会话的半改状态，改为 pin 到 detached 只读 worktree 解决。
- **上游合流**：`swift-demangling` 同期修掉畸形符号的 SIGTRAP / 整数溢出 / 死循环（模糊语料 trap 与 hang 归零）。这与 A2 是同一条线的两端——在此之前 `printCatchedThrowing` 就算 catch 了也拦不住进程级信号，两边合上后 per-definition catch 才真正成立。
- **验证**：全量 1413 测试 / 266 suite / `swift test` 退出码 0；A/B 脚本新增 5 条标准库自测；依赖 pin 分两轮（先 `6eb3fc7` 确认自身改动，再 `5d2b476` 复跑）以分离变量。
- **文档**：[TaskReports/2026-08-13-pr103-review-round-two-fixes.md](TaskReports/2026-08-13-pr103-review-round-two-fixes.md)、[ReviewAdjudications.md](ReviewAdjudications.md)（A7–A8）、提案 0001 兼容性一节更正、AGENTS.md 的 opaque 索引与缓存回收两段同步。
- **对应版本**：`0.16.0`（`feature/node-store-migration` 分支）。

---

## 40. PR #103 第三轮 review：四问推翻三条结论，分批修静默错误

- **时间段**：2026-08-14 起（`feature/node-store-migration`；第二轮见第 39 节，审的就是第二轮修复落地后的状态）。
- **动机**：第三轮 max 级 review 产出 15 条发现。四问这次的产出主要是**减法**——推翻了初版的三条实质结论：`OrderedMember.minSymbolOffset` 的「每次比较分配一个 String」是误报（`.offset` 命中的是 `DemangledSymbol` 自己的具体属性，SE-0195 下具体成员优先于 `@dynamicMemberLookup`，且初版据以区分对错的两处是完全相同的表达式形状）；diff 头行丢声明不影响 change list / `--json` / `--fail-on-breaking`（那三条都走 `ABIDiffer`）；主 interface 路径的枚举 case 会抛错而非静默降级（`printThrowingEnumCase`，静默的那个只服务 diff 渲染器）。
- **交叉复核**：15 条结论交同项目另一会话独立复核。它补了一条我漏掉的发现（`ConformanceProvider` 子类映射的新静默丢失面）、推翻了 diff 渲染器「补事件诊断」的修法前提（该渲染器的 printer 由 `.init(in:)` 建、公开 init 不接 handler，事件没有 sink，只能走 stderr），并给误报判定补了排他性普查（全 `Sources/` 的 `.symbol.` 共 13 处，慢的只有 4 处，是穷尽结论）。
- **落地（批次 1，静默产生错误结果的 4 处）**：**opaque 类型改写**返回 `type.firstChild` 而非 `node.firstChild`——原代码把泛型参数替换成了它自己的 depth 字面量，真实框架里印出 `SwiftUI.StaticIf<A1, 1, C1>` 这种非法 Swift（SwiftUI 21 处、WidgetKit 1 处），缺陷代码自 `5e7373f`（2025-12-16）引入即如此、与 main 相同；**mpenum 缓存**的 catch 移进循环，循环级 catch 会在第一条坏记录处退出，其后每个多 payload 枚举都静默落到 `calculateTaggedMultiPayload`（错的布局，不是缺的布局）并被 `SharedCache` 记住一整轮；**子类映射**把 wrapper materialize 与 `superclassNode` 的 catch 分开并补 stderr——proposal 0002 把 wrapper 从存储属性改成按需 materialize，新的抛错落进了只为一个原因而写的 catch 里；**A/B 验收脚本**的 cache 成员判断改为按行锚定，规范路径是 iOSSupport 路径的字面子串，包含式判断永远到不了那个回退分支。
- **关键决策**：先做零行为变化的可测试性重构（rewriter 由 `private` 改 `internal`、索引循环抽成 `indexDescriptors(_:in:)`），再写会失败的复现测试，最后上修复——顺序刻意，用来证明测试真的抓住了问题。三条测试修复前全部失败（opaque 打印出 `"0"`/`"1"` 的 depth 字面量、mpenum 坏记录后的 12 条全丢）。
- **验证**：新增 5 个测试 / 2 个套件，`swift test` 退出码 0；A/B 脚本自测 9/9。真实二进制端到端：WidgetKit 离线 dump 在两份 cache 上裸整数实参归零，8011 行 dump **只差修好的那一行**。全量 1418 tests / 268 suites，唯二失败是已知的墙钟 flaky（`SharedCacheTests` 的两条并行度断言），单独跑必过。
- **落地（批次 2，可观测性与测试）**：**协议打印**的事件上下文与 `definitionPrintStarted` 挪到 materialize 之前，名字由 `Protocol.name`（descriptor 的裸名）改为 `protocolName.name`（限定名）——一步同时消掉「失败事件没有配对的开始事件」和「两个事件用两个名字」；**`printCatchedThrowing`** 在没有 dispatcher/context 时落 stderr，一处覆盖全部三个无 context 调用点，其中 `printType` 正是 diff 路径上让 `case foo(Payload)` 静默退化成 `case foo` 的那条；**diff 渲染器**丢声明时写 stderr（不能用事件——它的 printer 由 `.init(in:)` 构造、公开 init 不接 handler，派发出去没有 sink，这是交叉复核推翻的修法前提）；**NodeStore 不变量**从一个断不住的行为测试改为源码扫描测试（外加扫描器自检），旧测试的文档注释改成诚实的范围说明。附带：`printCatchedThrowing` 与新的 `MachOTestingSupport.StandardStreamCapture` 加 SE-0420 的 `isolated` 参数继承调用方隔离，否则测试闭包跨隔离域是编译期 `sending` 违规。
- **批次 2 的意外收获**：原计划用「真实 layout 重新包在越界 offset」构造一个 materialize 必失败的协议定义，来钉住事件顺序。`StructDescriptor` 用同样手法一直干净抛错，**`ProtocolDescriptor` 却直接 SIGSEGV**——损坏或恶意二进制能让进程崩掉而不是浮出错误。该测试已撤（会崩的测试比没有测试更糟），缺口记入 [Roadmaps/2026-08-14-pr103-review-round-three-findings.md](../../Roadmaps/2026-08-14-pr103-review-round-three-findings.md)。首次崩溃时曾误判为 AGENTS.md 记录的 stale-object 构建陷阱，`swift package clean` 重建后照样崩才推翻——两者表征（零断言失败的 SIGSEGV）完全一致，clean 后再看一次是唯一的分辨动作。
- **验证（批次 2）**：全量 **1423 tests / 269 suites，退出码 0，零 issue**（批次 1 那次唯二失败的墙钟 flaky 本轮也通过）。
- **落地（批次 3，清理与台账）**：**推翻 2026-08-03 对公开字典键类型的「不修」裁决**——`allOpaqueTypeDescriptorSymbols(in:)` 与 `memberSymbols(of:excluding:in:)`（后者本轮 review 没点到，是复核方指出的同形态第二处）的键由身份相等的 `NodeReference` 改为结构相等的 `StructuralNodeReferenceKey`，该类型连带从 `package` 提升为 `@_spi(Internals) public`（只暴露字典不暴露键类型，等于把陷阱换个形状）。推翻的理由不是旧裁决的事实变了（复核后仍然零调用方），而是同一 bug 类已经真实咬过一次：Stage 5a 的回归里身份键让 `override` 关键字与 vtable offset 注释成批消失，单条版正是为此改成结构化键，这两个批量版是那次修复漏下的。另修四处 `DemangledSymbol.symbol.offset` 的两跳读法（A10 穷尽普查里唯一真慢的四处），以及 `missingSymbolWitnesses` 三处不准确的注释（维护者决定保留数组、只改注释）。
- **裁决（4 条，记入 [ReviewAdjudications.md](ReviewAdjudications.md) A9–A12）**：A9 键类型（推翻旧裁决、已修）；A10 `OrderedMember.minSymbolOffset` 的 String 分配**是误报**（`.offset` 命中 `DemangledSymbol` 的具体属性，SE-0195 下具体成员优先于 `@dynamicMemberLookup`；附全 `Sources/` 13 处 `.symbol.` 的穷尽普查）；A11 `SwiftDiffableInterfaceBuilder` 无 per-definition catch（与 main 字面零 diff，非本 PR 回归，但记入「本 PR 让失败面变宽」的 caveat）；A12 每次操作重复 materialize（照 A3 先例先测量）。`NodeStoreMigrationOpenIssues.md` 第 3 条标记为被 A9 取代，两份平行台账合一。
- **验证（批次 3）**：全量 **1424 tests / 269 suites，退出码 0，零 issue**。
- **文档**：[TaskReports/2026-08-14-pr103-review-round-three-fixes.md](TaskReports/2026-08-14-pr103-review-round-three-fixes.md)、[ReviewAdjudications.md](ReviewAdjudications.md)（A9–A12）、[Roadmaps/2026-08-14-pr103-review-round-three-findings.md](../../Roadmaps/2026-08-14-pr103-review-round-three-findings.md)（唯一仍 OPEN 的发现 + 本轮四问对自己的三处更正）。
- **对应版本**：`0.16.0`（`feature/node-store-migration` 分支）。

---

## 41. PR #103 第四轮 review：降级上报统一走事件，库不再自选落点

- **时间段**：2026-08-16（`fix/event-based-diagnostics` → `feature/node-store-migration`）。
- **动机**：第四轮 max 级 review 的 15 条发现，经同项目另一会话独立复核后收敛为 9 真 / 1 误报 / 2 属实但不值得修。其中一条把第三轮的修法本身推翻了：批次 2 用 `FileHandle.standardError.write(_:)` 落 stderr，而那个重载是 ObjC 桥接、写失败时抛 `NSFileHandleOperationException`，Swift 接不住 → **进程 abort**。库 9 处 + CLI 5 处共 14 处中招。
- **复核的减法同样重要**：`Codable` 从三个 `Name` 类型移除被判**误报**——复核方查到 7/31 的 commit 完整记录了决策（mangled symbol 本身就是树的序列化）、同批更新了 AGENTS.md，并对本地 RuntimeViewer 全仓 grep 确认零 `Codable` 消费者；符号表按名查找（机制全真但 late path 与 main 逐位等价，且第一轮已作为 below-the-cut 记录过）与 mpenum 全有或全无（唯一真缺陷窗下 main 行为逐字等价）判为基线旧问题。
- **关键决策**：不是「把 stderr 换成安全写法」，而是**库代码一律不写进程流**。落点由宿主装的 `Handler` 决定（GUI → os_log，CLI → stderr），因为这个分歧在库里选不对：os_log 对 CLI 不可见（终端 / `2>` / CI 日志全空，直接违背 issue #102 的报告场景），stderr 对 GUI 宿主无意义。配套三件事缺一不可——`Dispatcher.dispatch` 零 handler 时落 os_log 地板（否则是把 crash 换成静默）、diff 渲染器的 printer 改为共享 indexer 的 dispatcher（此前 `.init(in:)` 构造、零 handler，事件发进空数组）、`ConsoleEventHandler` 从 **stdout** 改到 stderr（它是 CLI 的默认 sink 却在写产品输出流，issue #102 的第三条诉求原地破功）。
- **一次改动解掉 5 条发现**：raising 写（crash）、`printCatchedThrowing` 兜底死代码、孪生 helper 无兜底、diff 单侧 header 失败删两侧、测试挂死；并让「测试隔离前提为假」那条失去存在意义——验证不再需要 fd 重定向。
- **单侧 header 的语义修正**：`guard let old = ..., let new = ...` 从左到右短路，旧侧失败时新侧根本没渲染，返回 `[]` 又把声明连同成员和嵌套子节点从**两侧**一起删。改为两侧各自渲染后经 `resolveHeaders` 决议，且用**三态** `HeaderOutcome`（`absent` / `rendered` / `failed`）——`SemanticString?` 会把「这侧不存在」和「渲染失败」混同，实测正是这个混同让 `.added` 路径用空 header 顶替了失败侧。
- **测试改造**：`StandardStreamCapture` 退役，代之以 `MachOTestingSupport.SwiftIndexEventCollector`（附加断言更锐利：事件带失败者的名字，旧的 stderr 行不指名任何声明）。「不写 stdout」改为**源码扫描**，因为 fd 重定向路线安全不了——`swift test` 单进程 + `.serialized` 只管 suite 内，两个 suite 交错能让一方的 pipe 写端被另一方的备份持有、EOF 永不到来、**整轮挂死**。扫描器必须能识别裸调用（`node.print(using:)` 是本库渲染 API）且自带正反例自检。扫描暴露的基线既有违规记入显式的**只减不增**清单，不在本次范围内修。
- **踩到的硬约束**（详见实现说明）：`SwiftIndexEvents.Handler` 非 `Sendable`，存不进 `Sendable` 的 builder，改为注入 `Dispatcher`（结果更好：indexer 与 printer 共用一个，宿主装一次覆盖两边）；`SwiftDeclarationRendering` 因依赖方向够不到事件类型（`SwiftDeclaration` 依赖它），改为闭包注入 + 日志地板。
- **`@Loggable` 的一次错判与更正**：实现中给 `SwiftDeclaration` 加了 `OSToolbox` product 依赖（宏的声明文件在那个目录下），SPM 报 product 不存在，据此误判「这里用不了 `@Loggable`」并临时改用裸 `os_log`。**判定是错的** —— 项目所有 `@Loggable` 用法都经 **`FoundationToolbox`** 拿到宏。三处已全部改回 `@Loggable` / `#log`，宏自带的 `#available` 回退顺带覆盖了「`os.Logger` 要 macOS 11 而本包下限 10.15」。泛型类型（`OpaqueTypeRewriter<MachO>`）不能直接标注（展开成 static stored property），改用**协议式** `@Loggable` —— 与既有的 `NestedSpecializationLogging` 同形，访问级别按遵循者范围收紧（同文件用 `fileprivate`，跨文件才 `internal`），但**不能用 `private`** —— 它会把成员一并压到 `private`，而 `#log` 在遵循者内部展开、看不见。**该约定已写进 AGENTS.md 新增的 Logging 一节**：全项目日志一律 `@Loggable` + `#log`，禁用 `os.Logger` / 裸 `os_log` / `OSLog(subsystem:category:)`。
- **落地（续，跨 suite fixture 互斥）**：修掉发现 [10] —— `PerImageCacheEvictionTests` 头注释声称跑在「no other suite indexes」的镜像上，而 `SwiftLayoutTests.DependencyClosureLayoutTests` 手工拼路径用着同一个二进制，**按 fixture 枚举名搜索永远搜不到它**。新增 `MachOTestingSupport.ExclusiveImageAccess`（`TestScoping` trait，Swift 6.1+），两侧都声明。否掉的两条：`.serialized` 只管容器内（其文档原话 "does not affect the execution of a test relative to its peers or to unrelated tests"）；自定义全局 actor 也不行 —— 测试是 `async`，`await` 让出 actor，actor 保证「无并发」而非「无交错」。**两个关键行为靠临时探针实测确定**（文档没展开）：`provideScope` 只在函数层调用、从不在 suite 层（故非重入锁安全），且 `testCase` 恒为 `some`。Swift 6 严格并发不允许非 `Sendable` 的测试体跨进 actor，故把锁状态（actor 上的 `acquire`/`release`）与临界区（留在调用方隔离域）拆开，释放走显式 catch（`defer` 里不能 `await`）。配套三测试自带反证：同 key 并发抢最大持有者 == 1、不同 key > 1、抛出后仍释放。
- **落地（续，缓存驱逐两条 [2][3]）**：`Claims.normalized` 恢复「扔驻留仓库 ⇒ 必扔 demangle 备忘录」的单向绑定 —— 备忘录的值是指向仓库的 `NodeReference`，仓库文档原话 "Eviction reclaims nothing while external references survive"，所以「扔仓库留备忘录」不是部分成功而是**完全无效**；该绑定 8/9 存在、8/13 拆 claim 时被移除，解释它的注释却留在原地。TOCTOU 两处窗口一起关：`registerLiveIndexer` 改收采样闭包（锁内采样），`deregisterLiveIndexer` 改收驱逐闭包（锁内驱逐）—— 只关采样那半会把竞态从「注册前」搬到「注销后」而非消除。**一个被诊断否定的怀疑**：曾疑心采样位置太晚（注册在 `prepare()` 第 62 行之后，中间有子 indexer prepare 与四段 section 读取），实测显示那些读取不填这两个缓存，清空后 prepare 再释放三者都正确认领并清除。**一个差点漏过的测试陷阱**：第一版绑定测试红了但**红错断言** —— 我假设 `MetadataReader.demangleContext` 只填备忘录，实际两个都填，于是 indexer 正确地不认领仓库、而我的断言是错的；靠一轮状态诊断才发现，否则会用一个测着别的东西的测试"验证"修复。修正版用生产中真实可达的路径构造目标组合（内存压力驱逐清仓库、不清备忘录）。
- **验证**：14 处危险写法清零（`grep` 剩余命中全是注释）；三个受影响套件 11 tests 全绿；缓存两条红→绿闭环（去绑定红在备忘录断言，恢复后 5 tests 全绿）；全量套件退出码 0。
- **文档**：[Evolutions/0005](../Evolutions/0005-event-based-degradation-reporting.md)（含「实施中偏离提案的地方」四条）、[EventBasedDegradationReporting.md](EventBasedDegradationReporting.md)（分层契约 + 四条走不通的近路）、[TaskReports/2026-08-16-pr103-review-round-four-event-reporting.md](TaskReports/2026-08-16-pr103-review-round-four-event-reporting.md)。
- **对应版本**：`0.16.0`（`feature/node-store-migration` 分支）。

---

## 42. issue #106 首批：`final` 关键字还原与 lazy var 访问器类型修正

- **时间段**：2026-08-22（`feature/0006-final-and-lazy-recovery`，基于 next）。
- **动机**：issue #106（用 dump 手写可编译 `.swiftinterface` 重建 `SourceEditor.framework` 的实战反馈）里唯一**破坏链接**的两点——`final` 完全缺失（经 dispatch thunk 的成员必须平凡声明、只有直接符号的必须 `final`，写错直接 `Undefined symbols`），以及 lazy var 打印 `Optional` 存储类型而非调用方看到的 getter 类型。判据沿用 `isClassMember` 的同一条 ABI 事实的镜像：有 vtable method descriptor ⇒ 非 final。
- **核心发现：数据早就算出来了，只是被丢弃**。stored `var` 的 accessor 符号组在 `DefinitionBuilder.variables` 里已完成 descriptor/vtable-slot 解析，被 `fieldNames` 去重整组扔掉。改为 `variablesProduct` 交还、折回 `FieldDefinition.accessors`——`final` 判定、stored var 的 vtable 注释（`--emit-vtable-offsets` 下）、lazy 访问器类型三件事共用这份数据。
- **快照审查抓住三类误标并逐一处置**：（1）被子类 override 的 `asyncMethod` 被标 `final` → 根因是 **async 成员的 descriptor join 从未成功过**（descriptor 的 implementation 指向 `Tu` async-function-pointer 常量，树多一层 `.asyncFunctionPointer` 标记），`memberJoinKey` 剥标记修复，顺带找回 async 成员一直缺失的 `override` 关键字与 vtable 注释（修的是既有 bug）；（2）`@objc dynamic` 走 objc_msgSend、无 vtable 条目但可覆写 → 「`@objc` 且无 descriptor ⇒ dynamic」排除，标记块因此移到 `applyThunkAttributes` 之后；（3）final class 因 designated init 的 vtable 条目仍带 header、其成员获得成员级 `final` → **接受**——类级 `final` 无 ABI 位不可恢复，成员级标记对重建链接恰好正确。
- **三层证据门，宁缺勿错**：非 actor class 且 vtable header 可读；stored 属性要求 accessor 组确实 join 上（符号 strip ⇒ 静默不标）；`@objc` 排除。stored `let` 不标（本就不可覆写）；`final override` 不还原（override descriptor 在场，保守平凡输出）。
- **lazy 取型顺序**：特化替换节点 ＞ getter 的 `accessorTypeNode` ＞ 存储类型（getter 缺失即诚实回退，提案里的「剥一层 Optional」回退未实现）；dump 路径 lazy 保持存储真相（`[Getter]` 列表已展示访问器类型），`final` 关键字则 dump 两路对齐（名字级 join + 同套排除）。
- **验证**：fixture 新增 `VTableEntryVariants.FinalMembersTest` 全组合矩阵（final/plain × 存储/lazy/计算属性/方法/下标）；`FinalMemberRecoveryTests` 五用例（渲染配对、lazy 类型、vtable 注释邻接、模型事实×2）；interface 整模块 + dump 三份快照逐行审查重录；全量套件除 fixture 重建引发的 ABI 基线 offset 漂移（按既定流程 regen）外全绿。
- **文档**：[Evolutions/0006](../Evolutions/0006-final-keyword-and-lazy-accessor-type-recovery.md)（决策日志含六项实现发现与偏差）、[FinalKeywordAndLazyAccessorTypeRecovery.md](FinalKeywordAndLazyAccessorTypeRecovery.md)、Roadmaps 新增 L-12（类级 `final` 不可恢复）、AGENTS.md SwiftPrinting 段新条目。同 issue 的 0007（extension 容器去重）、0008（文件头部与导出标注）已 Accepted 待实施。
- **对应版本**：待发布（本批次未 bump `Version.swift`）。

---

## 43. issue #106 次批：extension 容器统一与协议默认实现归属

- **时间段**：2026-08-22（`feature/0007-extension-container-dedup`，叠于 0006 分支）。
- **动机**：issue #106 §5——同一 `extension P` 块被重复打印（SourceEditor 两打协议各两份），若干「类成员」共享同一折叠地址被读成协议默认实现。
- **双产线证实与成员不一致的意外发现**：副本一来自 `ProtocolDefinition.index()` 按协议 descriptor 的 per-requirement 默认实现合成（尾随协议渲染），副本二来自 `indexExtensions()` 的符号表扫描桶。两份成员**不一致**——per-requirement 解析在 ICF 折叠地址上配不齐符号，尾随副本反而更少。故合并方向不是「删一份」而是「符号扫描超集为准，descriptor 合成降级为 fallback」。
- **设计转向：附着 + 打印抑制**。原案「容器键下沉 + 索引期从桶合并」被格式冻结否决：四个扩展桶是 `ABIModule` 的直接输入，从桶移除定义 = 容器从 ABI 快照消失（旧基线对比出虚假 removed）。落地形态：协议的符号扫描块附着到 `defaultImplementationExtensions`（尾随协议渲染），同一对象留桶打 `isAttachedToProtocolDefinition`，顶层打印跳过；桶内同身份合并（急切定义限定——conformance-backed 惰性解析，prepare 期合并会丢成员）对快照无影响，差分器本就按键分组。SwiftDiffingTests 全绿实证零扰动。
- **顺带修复三处**：`printRoot` 嵌套协议扩展块循环恒空（root 上过滤 `parent != nil`）——fixture 协议全部命名空间嵌套，修复后四块纯迁移到 protocols 区之后；`updateConfiguration` 的 re-prepare 因 `isPrepared` 从不复位恒 no-op——修复后成为四桶入口重置的确定性测试入口；空 requirement 的变量签名桶渲染成与 catch-all 相同的裸头——折叠进 catch-all。
- **被否的方案**：签名分桶扩展到 functions/subscripts（成员级 `where` 合法且信息完整，扩展只会制造更多块）；跨桶合并 typealias-only 块与成员块（动快照格式）——裸头并存记为 P1-9 残余。
- **`protocol-extension default` 标注**：模型（`isProtocolExtensionDefault`）+ interface/dump 两路渲染（`--emit-member-addresses` 门控）落地；SourceEditor 上不触发（witness 实现符号分支总命中），属休眠防御。issue 点名的 `elide` 三兄弟经 `nm` 证实是真类成员被 ICF 折叠——第 42 节 `Tq` 门的辖区，非归属错误。
- **验证**：`ExtensionContainerUnificationTests` 四用例（成员级容器身份全桶唯一、协议扩展块尾随且唯一、桶内身份唯一、配置往返幂等）；SourceEditor 重复头全部归一且 0006 哨兵保持；interface 快照四块纯迁移；全量套件绿。
- **文档**：[Evolutions/0007](../Evolutions/0007-extension-container-dedup-and-default-impl-attribution.md)、[ExtensionContainerUnification.md](ExtensionContainerUnification.md)、AGENTS.md SwiftIndexing 段新条目。
- **对应版本**：待发布（与 0006 同线）。

## 44. issue #106 末批：interface 文件头部与导出状态标注

- **时间段**：2026-08-22（`feature/0008-interface-header-and-export-status`，叠于 0007 分支）。
- **动机**：issue #106 §2/§3/§8——输出没有任何一行告诉读者「这个二进制开没开 library evolution」（`final` 一类推断的有效性取决于它）；`SourceEditorGutter.updateLineNumberDisplay()` 带满注释看起来可调用、实际导出表零命中（作者写 stub 才发现）；空白读起来像「源码没有」而非「二进制恢复不出来」。
- **提前开工决策**：原前置「等 §6 import 重构落地」被用户指示覆盖（`origin/next` 未动、远端无其分支）；实际冲突面仅 `printRoot` 里 `ImportsBlock` 之前数行，接线做成零侵入（独立 if 块）压最小化合并冲突。
- **导出集必须显式收集**：next 基线复核揭示 symtab 两条收集腿都过滤 `!nlist.isExternal`（只收本地符号），导出符号仅经 trie 腿建行且该腿带两筛——「行来自 trie」事后不可恢复、offset-less re-export 连行都没有。落地：同一遍循环旁路收集（行号 bitmap ≈ 23 KB / 185k 行 + 无行名字 fallback set），表建行为零改动；`isExported` 三态（`nil` = 镜像无导出信息，不标注）。
- **裸查名字是错的（本批最大教训）**：第一版按实现符号裸查，fixture（evolution Release 构建）当场全量假阳性——public 成员实现符号照例 local，外部经导出的 `Tj` thunk 派发。改为 `isExportedIncludingDerivedSymbols`（`Tj`/`Tq`/`Tu`/`TjTu` 追加后缀形态任一命中即 exported），对应 issue 作者「任何符号零命中」的验证法。再叠两个发射豁免：`override`（经父类 thunk 可达）与 `@objc`（经 objc_msgSend 可达），两者「自有符号零导出」都是编译器常态；conformance witness 故意不豁免（零导出 = 确实不可静态直接调用）。
- **头部组件**：`InterfaceHeaderInfo`（纯值，generator 身份调用方传入——`BundledVersion` 是 CLI 私有且 RuntimeViewer 不该冒充 swift-section；日期可选默认缺席保快照字节稳定）+ `InterfaceHeaderBlock`（public——RuntimeViewer per-type 导出绕过 `printRoot`）+ Mach-O 事实工厂（install name / UUID / 架构人话映射 / fileType / `Tj` 计数，evolution 行措辞 detected / not detected 不断言）。CLI 两命令 `--emit-header` / `--emit-export-status`，默认全关。
- **验证**：新增四套 22 测试（导出事实全量 sweeping + 三类假阳性各一钉 + true positive + 渲染逐行 + flag 解析）；全量 1465 测试绿（默认输出字节不变由既有快照实证）；SourceEditor 复核 issue §3 场景精确解决（`updateLineNumberDisplay` 带 `VTable offset: 66` + `not exported`，全库 3487 处，public API 经 `fCTj` 不误标）。Roadmap Known limitations 补 L-13…L-16（参数内部名 / `@discardableResult` / 默认参数值 / `internal` vs `fileprivate`）。
- **文档**：[Evolutions/0008](../Evolutions/0008-interface-header-and-export-status-annotations.md)、[InterfaceHeaderAndExportStatusAnnotations.md](InterfaceHeaderAndExportStatusAnnotations.md)、Glossary 两新术语（derived symbol forms、export status）、README CLI 两段、AGENTS.md SwiftPrinting/MachOSymbols 段。
- **对应版本**：待发布（与 0006/0007 同线）。

---

## 45. TypeIndexing 重启：`__C` 模块归属解析（提案 0009）

- **时间段**：2026-08-21 ~ 2026-08-22（`feature/type-indexing-revival`，基于 `next`，独立 worktree）。
- **动机**：`Sources/TypeIndexing`（`__C.NSString` → `Foundation.NSString` 的模块归属索引）自 Swift 6 迁移期被整体注释出 `Package.swift`；打印侧 delegate 挂接点一直是活的，唯一 provider 实现却不参与编译。用户要求修复重启。
- **禁用主因与修法**：历史实现在 SDK 扫描时对**每个**发现的 `.swiftmodule` 当场跑 sourcekitd 生成全模块 interface，依赖过滤在其后才生效——首次索引小时级。重构为发现与生成分离：扫描只做文件发现（秒级），interface 生成下沉到依赖过滤之后，配 per-module、按 SDK 精确构建（`Version-ProductBuildVersion`）分层的 JSON 缓存。实测 fixture 依赖面只生成 9 个模块条目、首次 33 秒、缓存命中 10 秒。
- **两条用户裁定**：① 旧 ObjCDump 自建索引器删除，私有类归属改用 MachOObjCSection 的 `ObjCIndexing`（下限 0.8.105，泛型 `ObjCMetadataSource` indexer），做成查询 miss 才逐依赖 image 索引的懒路径；② SwiftSyntax 不进运行时依赖（体积数十 MB，而 `TypeDatabase` 只消费类型名清单）——类型名提取改走 `editor.open.interface` + `key.enablesubstructure` 的结构树（探针实测完整可用，兜底行级解析器按提案条款不再编写），extension 嵌套键错误在新提取器里结构性消失。
- **顺带修掉的正确性 bug**：APINotes 双向表 `moduleName` 字段被写成 swiftName（修复 + 复现测试）；缓存无 SDK 版本导致 Xcode 升级吃旧数据；sourcekitd 路径硬编码 `/Applications/Xcode.app`（改从 `xcode-select -p` 派生）；`SwiftModule.write` 写错路径（随重构消亡）。APINotes 归属注册放宽到每个列出的实体（`__C.X` 的 X 是 C 名，归属与 Swift 侧可见性无关）。
- **规范整改**：全模块 `@Loggable` + `#log`，`PrintFailureEventTests` 的 `SDKIndexer.swift` 豁免移除（其注释原话 "If that target is ever revived, convert it first"）。踩到并记档的坑：`@Loggable` 直接类型形态在 `@available(macOS 13.0, *)` 类型上被 emit-module 拒绝（宏展开的 static stored logger 自带更高 availability；单 target 编译只是 warning）——全模块改 protocol 形态。
- **提案编号避让**：立项用 0006，实施当天发现 `main` 上并行会话同日登记 0005–0007 三个 Draft（其 0006 为 Extension 容器去重），避让至 **0008**（两线合并时因与 `main` 线 interface-header 提案再次撞号，最终重排为 **0009**）；`main` 新 0005 与 `next` 既有 0005 的互撞是既有漂移，留待两线合并裁决。
- **验证**：整包构建零 error；`TypeIndexingTests` 23 个纯单测（提取器 / import 扫描 / APINotes / 合并优先级 / 缓存）全绿；全套 1456 tests / 275 suites 退出码 0；端到端（fixture `SymbolTestsCore`）baseline 21 处 `__C.` → 0 处，diff 全部行都是模块名替换（`Foundation.NSObject`、`CoreFoundation.CFStringRef`、APINotes 改名的 `Foundation.Decimal`），缓存命中输出逐字节一致。CLI 入口 `swift-section interface --resolve-c-module-names`（默认关，默认输出字节不变）。
- **追加批次（identifier 重写，用户指正驱动）**：首轮输出的 `CoreFoundation.CFStringRef` 被指正为 Swift 不存在的拼写（ClangImporter 对 `objc_bridge` / `CF_BRIDGED_TYPE` 类型剥 `Ref` 桥接为原生 class `CFString`）。打印侧在 `__C` module 解析成功时对 identifier 消费 `swiftName(forCName:category:)`（此前零消费者），数据侧补 CF `Ref` 剥除兜底。第一版合并改名表当场踩出 `NSObject` 回归——ObjC 的 class 与 protocol 同名而 APINotes 只改 protocol（`NSObjectProtocol`），类别盲查重写了所有 class 继承行；修正为 `CImportedTypeNameCategory`（按 mangling `Node.Kind`）贯穿协议签名、`APINotesIndex` 三张类别隔离改名表、`.other` 永不查 protocol 表、CF 规则对 protocol 关闭。回归用例双重钉死。
- **追加批次（补充映射，提案 0010）**：用户以 AttributeGraph（SDK 无模块的私有框架，`AG_SWIFT_NAME` 改名头文件独有、二进制零残留）追问覆盖边界后裁定「提供接口接受社区贡献、Database 预加载、碰到直接替换」。落地为**标准 `.apinotes` 格式**的补充映射包（零新格式，直接进 `APINotesIndex` 管线）：库内置 SPM resource（首发 AttributeGraph，宁缺毋滥只收有头文件一手证据的 Graph / Subgraph / GraphContext）+ 宿主/CLI 追加路径（`--supplementary-apinotes`），覆盖顺序 SDK → 内置 → 宿主（`register(files:)` 后写覆盖即实现）。实施中把提案的「两形态」模型修正为**三形态**（手造 clang module 复刻 `objc_bridge` + `swift_name` 的 AG probe 实测）：typedef 名（Typedefs 表）、storage tag 名（字段元数据 foreign **class** descriptor——`.objcClass` 查询为此增加值类型表回退，protocol 表照旧绝不回退）、**导入名直出**（`__C.Graph`，归属同步把 `cNamesBySwiftName` 的 SwiftName 拼写也登进归属表，SDK 的 `NSDecimal → Decimal` 同理受益）。验证：新增 6 单测全绿（全套 1466 / 276 退出码 0）、AG probe 5 处引用全解析、CGCVProbe 输出与重启批次基线字节一致。公开贡献指引 [SupplementaryTypeMappings.md](../SupplementaryTypeMappings.md)（英文，顶层）。
- **追加批次（PR #110 review 修复）**：并行 review 会话对 PR #110 提出 15 条发现并做四问核实（原始清单与处置状态见 [Roadmaps/2026-08-23-pr110-review-findings.md](../../Roadmaps/2026-08-23-pr110-review-findings.md)）；关键教训是当时全绿的 1466 个测试对该修的 7 条**一条都抓不到**——新代码测试只盖了纯函数，装配与分发路径空白。用户裁定「3/4/5/6/7 直接修，不要内置资源」：**内置 SPM resource 层整体移除**（`Bundle.module` accessor 在 bundle 缺失时 fatalError，而发布脚本只分发裸二进制——分发出去一用就崩；补充映射改纯用户自备，review 发现 2 结构性消解）；依赖解析为空与坏 `--supplementary-apinotes` 路径改为 stderr 警告（发现 3/6）；submodule 失败不再固化残缺缓存条目（发现 4，`ModuleInterfaceIndexer` 增 `InterfaceGenerator` 注入缝使缓存纪律可单测）；`moduleName(forImagePath:)` 前导点名字死循环加不动点守卫（发现 5，`.hidden` 实测复现）；task group 完成序注册改为按 SDK 发现序重排（发现 7，`entriesInDiscoveryOrder`）。「不修 / 误报」终审 5 条（Ref 剥除守卫、import 列表、actor 重入、补充覆盖面、双查询）进 [ReviewAdjudications.md](ReviewAdjudications.md) A15–A19（合并时因与 PR #111 review 的 A13/A14 撞号顺移）；发现 1（`USE_CUSTOM_OBJC_SECTION=0` 构建失败）与 15（协议签名源码破坏）待定。验证：TypeIndexingTests 37/7、全套 1470 tests / 277 suites 退出码 0。
- **文档**：[Evolutions/0009](../Evolutions/0009-type-indexing-revival.md)、[Evolutions/0010](../Evolutions/0010-community-type-mapping-bundles.md)、[TypeIndexingPipeline.md](TypeIndexingPipeline.md)（含与提案的差异：swift-dependencies 未引入、兜底解析器未编写；identifier 重写一节；补充映射一节）、[SupplementaryTypeMappings.md](../SupplementaryTypeMappings.md)、[TaskReports/2026-08-22-type-indexing-revival.md](TaskReports/2026-08-22-type-indexing-revival.md)、[TaskReports/2026-08-22-community-type-mapping-bundles.md](TaskReports/2026-08-22-community-type-mapping-bundles.md)、[TaskReports/2026-08-23-pr110-review-fixes.md](TaskReports/2026-08-23-pr110-review-fixes.md)、AGENTS.md 架构节新增 TypeIndexing 条目。
- **对应版本**：未随本批 bump（`feature/type-indexing-revival` 待并入 `next`）。
## 46. opaque 返回类型的 primary associated type 归属（提案 0011）

- **时间段**：2026-08-24。
- **动机**：`SwiftInterfaceBuilderOpaqueTypeProvider` 把 opaque 参数上的 same-type
  约束无差别分发给组合里每个协议，产出 `some Swift.Equatable<[A]>` 这类非法 Swift
  （`Equatable` 没有任何 associated type）。fixture `functionNested` 长期携带此错误
  输出，E2E 注释甚至把它当预期描述。
- **关键决策**：
  - **约束按 anchor 协议逐条归属**：subject mangling 本就带声明协议（`ST` 标准替换 /
    symbolic reference），demangler 保留在 `dependentAssociatedTypeRef` 第二个
    child——「信息不够」的旧印象失实，丢信息的是打印端。
  - **归属四步**：anchor 直接命中（纯身份比对，离线 bind 可判）→ refine 闭包命中 →
    名字兜底（恢复编译器塌缩的等价类，要求候选唯一**且 anchor 在组合外**——塌缩与
    未 pin 在 descriptor 里逐字节同形，anchor 在组合内时兜底会捏造 sugar）→ 信息
    缺失不挂（宁缺毋滥）。
  - **协议事实经「descriptor 可达性」两问解析**：`resolvedContent` 把提案的三层
    （本模块 descriptor / 内置表 / 进程内跨镜像）自然塌并——可达 descriptor 读
    requirement signature + associated type 名单，不可达走内置 stdlib 表；primary
    名单与顺序只有内置表能给（SE-0346 无运行时痕迹）。
  - **接受两种 reader 输出深度差异**：离线拿不到外部协议内容时诚实降级不挂，进程内
    跨镜像严格增量；离线依赖闭包另立后续提案。
- **落地模块**：`SwiftInterface`（`OpaqueSameTypeConstraint` / `ProtocolFactsResolver` /
  `BuiltinStandardLibraryProtocolFacts` + provider 重写）；fixture 新增四场景
  （名字兜底防捏造、模块内 refine 闭包、跨镜像 refine 闭包、多 primary 顺序）与
  `SymbolTestsHelper` 跨镜像协议对；E2E 断言收紧 + MachOImage 侧新 suite。
- **文档**：[0011-opaque-primary-associated-type-attribution.md](../Evolutions/0011-opaque-primary-associated-type-attribution.md)、
  [OpaquePrimaryAssociatedTypeAttribution.md](OpaquePrimaryAssociatedTypeAttribution.md)、
  [TaskReports/2026-08-24-opaque-primary-associated-type-attribution.md](TaskReports/2026-08-24-opaque-primary-associated-type-attribution.md)。
- **对应版本**：`0.15.2` 之后、下一次 bump 之前。

---

## 43. 演进并集注解接口 SwiftEvolutionInterfaceBuilder（提案 draft-swift-evolution-interface-builder）

- **时间段**：2026-08-25。
- **动机**：`swift-section evolution` 唯一的人读输出是 `ABIEvolutionReporter` 的
  「位图 + 事件行」lineage 清单——不是代码的形状，成员脱离容器语法上下文，且只有
  变化没有幸存者，判断一次删减的严重性无从对照。两版本场景 `diff --interface`
  早已解决同类问题，N 版本没有对应物。
- **关键决策**：
  - **并集接口 + 生命周期注解**：所有版本声明的并集只渲染一次（每条由最后存在
    版本的模型与 printer 渲染），行尾 `// [●●○] removed in 26.0` 注解，没注解 =
    全程存在未变；否掉逐 transition 串联与「最新版 + since」两形态。
  - **注解事实唯一来源是 `ABIEvolution`**：渲染器按 `ABIKey`（与 `ABIDiffer`
    冻结快照完全同构的构造）查 lineage，不自行推导事件——接口视图、清单报告与
    JSON 永不各说各话；lineage 查不到就是「未变」裁决（依赖 changes-only 契约）。
  - **全二进制输入**：快照只有单行签名，interface 模式直接拒收（与
    `diff --interface` 同款约束）；混用降级留作后续提案。
  - **公开类非泛型 + 双 init**：逐版本擦除（`EvolutionVersionRendering` /
    `EvolutionVersionUnit`），同质 `[MachO]` init 全平台可用（CLI 走它），
    parameter-pack 异构 init 按 SE-0393 运行时下限 `@available(macOS 14…)` 门控。
  - **modified 只渲染最新代际**：旧形态进注解短语（`modified in X: 旧 → 新`；
    两侧文本相同省箭头），同一成员不裂多行，接口主体保持合法 Swift 的形状。
- **落地模块**：`SwiftInterface`（`SwiftEvolutionInterfaceBuilder` / `Renderer` /
  `EvolutionMarking` / `EvolutionAnnotationIndex` / `EvolutionVersionRendering` /
  `EvolutionLine`）、`swift-section`（`evolution --interface` + 事件类别着色）；
  测试为格式层/注解索引单测 + 三版本即时编译 fixture 的端到端 suite +
  CLI 校验规则钉子。
- **文档**：[draft-swift-evolution-interface-builder.md](../Evolutions/draft-swift-evolution-interface-builder.md)、
  [ABIEvolutionDesign.md](ABIEvolutionDesign.md)（第五批增量一节）、
  [TaskReports/2026-08-25-swift-evolution-interface-builder.md](TaskReports/2026-08-25-swift-evolution-interface-builder.md)、
  README `evolution` 一节、术语表新增「union interface」「lifecycle annotation」。
- **对应版本**：`0.16.0` 之后、下一次 bump 之前。

---

## 维护约定

1. **每个非平凡批次结束时必须在本文追加/更新一节**（新工作弧新增一节；延续既有弧则在该节
   补记）。一节至少包含：时间段、动机、关键决策与取舍、落地模块、关联文档链接、对应版本。
2. 设计细节写在 `Documentations/Internal/` 的独立设计文档里，本文只放指针；单任务的
   过程复盘写 [`TaskReports/`](TaskReports/)；面向用户的 per-release 说明写
   [`Changelogs/`](../../Changelogs/)。
3. 版本发布时（bump `Version.swift` + tag），同步核对本文各节的「对应版本」标注。
4. **节号在落地时取**（与提案编号同规则，2026-08-24 起）：在分支上写作期间节标题不预占编号
   （用日期+标题占位即可），合入长寿命共享分支的落地 commit 里按目标分支本文的最大节号 +1
   定号——多线并行下预占编号必撞（第 46 节曾经历 28→42→46 两次让位）。
