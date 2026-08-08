# Documentation

Documentation is split by audience.

> **Project kind: library (source distribution).** SPM library product consumed from source —
> downstream repos (RuntimeViewer, MachOKitUI, SymbolViewer, …) recompile every time, so there is
> no ABI constraint, but **source compatibility must be assessed** on every public API change.
> The `swift-section` executable is a companion CLI, not the outward contract.
> Note that `Tests/Projects/SymbolTests` does enable library evolution — that is the test project,
> not the library itself.
> Evolution proposals live in [`Evolutions/`](Evolutions/README.md) (status table + numbering there).
> Proposals 0001–0003 (the memory-optimization line) live on the `feature/node-store-migration`
> branch and are not on main yet; [0004](Evolutions/0004-arm64e-signed-vwt-pointer-hardening.md)
> (arm64e signed VWT pointer hardening) is the first proposal landed on main.

## External — for library users / other developers

Public, reference-style documentation. Bilingual (English + 中文).

- **[Swift Enum Memory Layout — From First Principles to Mastery](SwiftEnumLayout.md)** —
  a three-part guide to how Swift lays out enums in memory. Part 1 is a practical guide
  (size prediction, cheat sheet, reading `swift-section --emit-enum-layout` output);
  Part 2 derives the three layout strategies (single-payload / spare-bits / tagged, extra
  inhabitants, exact case encodings) with probe-verified byte dumps; Part 3 dissects the
  implementation across the Swift sources (all citations pinned to `swift-6.3.3-RELEASE`
  with file:line links) and explains how this project's runtime and static engines
  implement the same ABI. General reference — useful beyond this project.
  - 中文版：**[Swift Enum 内存布局 —— 从入门到精通](SwiftEnumLayout_zh.md)**

This is the only documentation aimed at an outside audience. Everything under
[`Internal/`](Internal/) is maintainer-facing.

## Internal — maintainer-facing notes ([`Internal/`](Internal/))

Design notes, migration guides, refactor write-ups, and per-task reports for contributors to
this repository. Not part of the public documentation surface (mixed Chinese / English).

**Start here for history:** [ProjectEvolutionLog.md](Internal/ProjectEvolutionLog.md) is the
chronological ledger of the library's own evolution — one section per work arc (period,
motivation, key decisions, landed modules, doc links, version range), maintained on every
non-trivial batch. Related repo-root surfaces (not under `Documentations/`):
[`Roadmaps/`](../Roadmaps/) holds forward-looking specs and review-finding backlogs, and
[`Changelogs/`](../Changelogs/) holds the user-facing per-release notes (one file per tag,
required by `Version.swift`'s bump contract).

| Doc | What it covers |
|---|---|
| [ProjectEvolutionLog.md](Internal/ProjectEvolutionLog.md) | 编年演进账本：逐工作弧（Foundation 解析 → demangler → 模块化 → SwiftLayout → SwiftDiffing/ABI evolution …）的时间段/动机/关键决策/落地文档/版本对应，含每批次必须追加的维护约定。 |
| [ReviewAdjudications.md](Internal/ReviewAdjudications.md) | Review 已裁决清单：判定为「不修 / 误报」的发现及结论、理由、复审条件；每轮 code review 先对照此表，已裁决且理由仍成立的直接跳过。 |
| [SwiftModularizationMigration.md](Internal/SwiftModularizationMigration.md) | The `SwiftInterface` monolith → layered peer modules refactor; where everything moved. |
| [FieldMetadataRenderingMigration.md](Internal/FieldMetadataRenderingMigration.md) | Extracting metadata-derived field rendering into `SwiftDeclarationRendering` (single source for dumper + printer). |
| [FieldLayoutRendererReaderSpecialization.md](Internal/FieldLayoutRendererReaderSpecialization.md) | Splitting `FieldLayoutRenderer` into a generic facade dispatching to two reader-specialized implementations: the `MachOImage` runtime path (in-process metadata) and the `MachOFile` static path (offline field offsets / type layouts / expanded tree / enum layouts via `SwiftLayout`). Covers the `self as?` dispatch, the `StaticFieldLayoutProvider` injection seam (built once per session), the new SwiftLayout convenience APIs, graceful degradation, and the `typeLayoutTransformer`/tuple limitations. |
| [GenericArgumentSubstitution.md](Internal/GenericArgumentSubstitution.md) | The static generic-argument substitution in nested field-offset rendering: what it solves, why it exists (runtime PAC-fault avoidance), the ABI, value/pack support. |
| [NestedFieldOffsetCycleGuard.md](Internal/NestedFieldOffsetCycleGuard.md) | 嵌套字段偏移展开在**有环**类型图上的指数级路径枚举（`DVTIconKit` "死循环"）与两道守卫：`indirect` case 是堆 box 指针故报告但不下钻（值类型字段图唯一的成环途径，实际消除爆炸的那道），以及**路径作用域**的已打开类型集合（运行时按 metatype 指针、静态按打印类型名）作为解析误判造成假环的纵深防御。含"为什么深度上限约束不了路径数"、按路径而非全局的取舍、运行时/静态两条实现各自的回归套件，以及 2026-05-16 打印路径 DAG 爆炸修复的教训为何没能横移过来的查证。 |
| [StaticFieldOffsetComputation.md](Internal/StaticFieldOffsetComputation.md) | Research + implementation guide for computing stored-property field offsets statically (offline, no runtime): fixed-layout vs resilient, the `performBasicLayout` algorithm, `MetadataInitialization` triage, the dependency-closure type resolver, ObjC ancestors via MachOObjCSection, and a generics difficulty assessment. |
| [StaticLayoutEngine.md](Internal/StaticLayoutEngine.md) | The shipped `SwiftLayout` module: what was actually built for static field-offset computation (recompute via `performBasicLayout` rather than reading the vector), the file structure, the runtime-accessor-vs-static validation suite, empirical findings that diverged from the research, and the known per-field degradations. Existentials (opaque / class-bound / error / metatype), the default-actor storage builtin, cross-module field/superclass/protocol types (via the dependency closure), ObjC-ancestor classes (Phase 4 — a Swift class deriving from `NSObject` et al. starts its fields at the ObjC ancestor's `instanceSize`, read via `MachOObjCSection`), multi-payload enums + imported C value types (via `__swift5_builtin` whole-type layouts), imported-ObjC-protocol existentials (`any NSCopying`), C-function-pointer / ObjC-block fields, and concrete bound-generic instantiations as fields (Phase 5 — purely syntactic `dependentGenericParamType` substitution via `GenericArgumentEnvironment`, depth-0 type parameters) are resolved; only a top-level generic type's own unsubstituted parameters, value/pack arguments, and depth>0 nested-context parameters remain degraded. |
| [StaticLayoutDependencyClosure.md](Internal/StaticLayoutDependencyClosure.md) | Phase-3 (**shipped**): extends `SwiftLayout` from single-image to a dependency closure (`LC_LOAD_DYLIB` + dyld shared cache) so cross-module field/superclass/protocol types resolve, with zero resolver changes. Covers the homogeneous-per-root typing decision, the `ImageUniverse.dependencyClosure` factory, the resilient-class static-computability boundary (and why their runtime field-offset vector is empty), and the validation strategy — plus a "落地实测" section recording where the implementation diverged from the plan (lazy per-image indexing over a 551-image closure, bare-name matching, missing-section tolerance, one-shot cache indexing, literal pinning for resilient classes that emit no `…Wvd` global). ObjC ancestors were resolved by Phase 4 (`ObjCClassIndex` + a third `resolveObjCClassInstanceSize` seam; see StaticLayoutEngine.md). |
| [LeafMigrationPlan.md](Internal/LeafMigrationPlan.md) | Plan for making `SwiftDump` a leaf module. |
| [SpecializedInterfaceBoundRenderingRestoration.md](Internal/SpecializedInterfaceBoundRenderingRestoration.md) | 修复 leaf 迁移引入的回归：interface 路径重新对特化定义做绑定渲染——头部打印 `Box<Int>`（跳过泛型签名子句）、字段经特化 metadata 替换；机制经 `SpecializedMetadataNodeSubstitution` + 下移的 `BoundDumpedTypeNameRenderer` 落在 `SwiftDeclarationRendering`，dump 路径零变化。 |
| [LeafMigrationRegressionAudit.md](Internal/LeafMigrationRegressionAudit.md) | 对 `aa233bc` leaf 迁移线的全面回归审计：三路逐行比对方法、7 项问题清单（多 payload 枚举容错丢失、深度截断诊断静默 + 测试钉死常量、Void payload case 两路不一致等——已于 2026-07-31 全部修复，见 LeafMigrationRegressionFixes.md）、已修复的历史断裂记录（metadata 注释全丢 / SIGBUS / 绑定渲染回归）与已核对干净的面。 |
| [LeafMigrationRegressionFixes.md](Internal/LeafMigrationRegressionFixes.md) | 审计清单 7 项问题的整批修复：`MultiPayloadEnumDescriptorCache` 恢复（per-image 部分 map，dump/interface 共享）、注释/字段渲染全链错误传播恢复（`throws` 化，幽灵空行消失）、Void payload case 括号统一（`printThrowingEnumCase` 按 mangled name 判 payload）、extension conformance 子句 nil-塌缩语义恢复、深度截断 `#log` 恢复、死代码删除。含跨提交差分 harness 方法与收敛数据（edge 语料 0 diff）。 |
| [AccessorFunctionReferenceRendering.md](Internal/AccessorFunctionReferenceRendering.md) | kind-9（accessor-function）symbolic reference 的触发机理（`~Copyable` 泛型 + 向后部署 → 编译器嵌 metadata accessor thunk 指针而非类型名）与三层解析阶梯：层 0（已落地：`NodePrintable` 补兜底文案 + `FieldFlags.hasMangledTypeName` payload gating + 空 payload 双防护网，消除 `case type()` 非法输出）、层 1（进程内经 runtime 真解析，待做）、层 2（离线符号表还原 `get_type_metadata` thunk 符号，待验证）。 |
| [DiffableInterfacePlan.md](Internal/DiffableInterfacePlan.md) | Implementation plan for the diffable (ABI-diff) interface. |
| [ABIDiffDesignAndLimitations.md](Internal/ABIDiffDesignAndLimitations.md) | The `SwiftDiffing` ABI-diff engine: identity/payload keys, three-way match, extension-bucket merging, and the known limitations (notably: `@frozen` is unrecoverable from the binary, so the compatibility verdict treats every type as resilient). |
| [ABIEvolutionDesign.md](Internal/ABIEvolutionDesign.md) | N ≥ 2 版本的 ABI 演化追踪（`ABIEvolution` lineage 模型 + N 路矩阵算法 + timeline reporter）与作为其地基的 snapshot 持久化（`ABISnapshotDocument` 版本头、`ABIProvenance`、CLI `snapshot` / `evolution` 命令、diff 的快照输入与 `--json`）。 |
| [PerConformanceAttribution.md](Internal/PerConformanceAttribution.md) | extension 变更的 per-conformance / per-`where`-block 归属：容器按 (target, protocol, where 指纹, retroactive) 拆分、索引期冻结的归属字段与 witness 投影（`assocwitness:`）、key scheme v3、键碰撞源的结构性消解、diffable renderer 的 `: Protocol` 头。 |
| [ProtocolRequirementProjection.md](Internal/ProtocolRequirementProjection.md) | stripped protocol requirement（PWT slot）投影（`pwtslot:` 命名空间、flags 指纹 payload、中段插入的诚实级联、符号化状态不对称局限）+ remangle 回退键自识别（`unmangled:` 前缀）与 `remangleFallbacks()` 审计通道；key scheme v4。 |
| [DefaultImplementationAwareCompatibility.md](Internal/DefaultImplementationAwareCompatibility.md) | 默认实现感知的兼容性判定：`ProtocolDefinition.defaultedRequirementPWTOffsets`（描述符相对指针，不经符号表，stripped 侧同样精确）、`MemberRecord.hasDefaultImplementation`（仅 verdict 元数据，经 PWT offset 关联已解析成员）、`MemberChange` / `LineageEvent` 的 `compatibilityOverride`（defaultless requirement 追加判 breaking，stripped slot 获得默认实现判 additive）；formatVersion 5。 |
| [MetadataReaderRefactoring.md](Internal/MetadataReaderRefactoring.md) | `MetadataReader` refactoring plan. |
| [RuntimeEnumCaseProjection.md](Internal/RuntimeEnumCaseProjection.md) | 基于 value witness 的枚举 case 内存图样投影：为什么「只知道 XI 个数」推不出单 payload 空 case 的判别字节（`Text.Style.LineStyle` 反馈案例），`RuntimeEnumCaseProjector` 的双基线注入 + `getEnumTag` 回读校验机制，`EnumCaseProjection` 模型重构（`declaredName` / `isPayloadCase` / `patternResolution`）与可读化渲染，runtime 精确 / static 诚实降级的两路接线；arm64e 签名 VWT 槽的 `stripPointerTags` 修复与「`swift test` 的 arm64e 测试进程 PAC 不生效」验证陷阱（提案 0004）。 |
| [EnumLayoutAuditFixes.md](Internal/EnumLayoutAuditFixes.md) | 对照 Swift 官方源码（`EnumImpl.h` / `Enum.cpp` / `GenEnum.cpp` / `TypeLowering.cpp`）的枚举布局全面审计与五项修复：indirect 单 payload 的 heap-pointer XI（曾被误判为 overflow 布局）、枚举自身 VWT 的 size 交叉校验与 payloadXI 精确反推、spare-bits payload case 的位级 `fixedBitMasks`（不再整字节过度声明）、empty case 判别区完整记录（tagged 零扩展 + spare-bits 全位固定）、no-payload XI 封顶；runtime 对拍测试增量与 RuntimeViewerCore token 同步。 |
| [OutputTransformerMigration.md](Internal/OutputTransformerMigration.md) | `Transformer` 模板机制的 Swift 侧（注释 token 模板 + 预设）从 RuntimeViewerCore 迁入库侧的新 `OutputTransformer` 模块（ObjC 侧 CType/ivarOffset 暂留 RV）：架构（模块清单、宽容 Codable 持久化契约、SwiftInspection 桥接、闭包工厂 + `applyTransformers` 接线）、RV 兼容语义（auto-append、partial-mask 安全回退）、RV 侧收编为 `@_exported` shim + 一行接线。 |
| [CLITransformerTemplateInterface.md](Internal/CLITransformerTemplateInterface.md) | `swift-section` 的注释模板命令行入口：三层配置（`--transformer-config` JSON 文件 / `--enum-layout-style` 整模块预设 / 逐模块模板选项）与其优先级、"内置模板名 vs 字面模板" 的解析规则（未知名字报错而非退化）、"启用的模块自动打开对应注释开关" 规则、`transformer tokens/templates/config` 发现性子命令，以及 `interface` 补齐 `--emit-type-layout` / `--emit-enum-layout`。 |
| [ReadingContextAbstraction.md](Internal/ReadingContextAbstraction.md) | The `ReadingContext` reading-abstraction design. |
| [ClassMemberKeywordRecovery.md](Internal/ClassMemberKeywordRecovery.md) | `class` / `static` 成员关键字的还原：mangling 层面两者不可区分，判据是「类型级成员有 vtable method descriptor ⇒ 源码是 `class`」（`static` 隐式 final、不进 vtable）；模型侧 `isClassMember` 计算属性 + 三个 node printer 接线 + dump vtable 段落关键字，顺带消灭非法的 `override static` 输出；`final class func` 等四类 ABI 上与 `static` 完全一致，保守输出语义等价的 `static`。 |
| [NodeStoreMigrationPlan.md](Internal/NodeStoreMigrationPlan.md) | `SymbolIndexStore` 迁移到 `NodeStore` arena 存储的分期计划与实施记录（Stage 0–5）：12B/节点扁平缓冲、cache-free build sweep、Symbol 表压缩、声明层换持 `NodeReference`、散点 transient demangling；含 Stage 5a 的 override/vtable 回归修复（裸 `[NodeReference: …]` 的 store-identity 陷阱 → `StructuralNodeReferenceKey`）与三源快照验收。 |
| [SharedNodeStoreMigration.md](Internal/SharedNodeStoreMigration.md) | **Accepted（待上游 push 后动工）**：三条小 store 流水线（`InternedNodeReferenceCache` / `TypeDefinition` 字段树批量 store / `lateDemangledNode`）汇入上游 0010 `SharedNodeStore` 的迁移设计——改动位置、明确不动的部分、验收计划与落地前置条件。 |
| [DeclarationModelMemoryFootprint.md](Internal/DeclarationModelMemoryFootprint.md) | NodeStore 迁移后的声明模型内存足迹量测：`TypeDefinition` 1272 字节的逐属性构成（两份 `TypeContextWrapper` 占 74%）、`TypeContextWrapper` 按最大 case `Class` 定尺的原因、`parentContext` 是被当成永久字段的临时值、mini-store 增殖与 `MetadataReaderCache` 仍持 `Node` 树；含四项可回收估算（合计 ~8–10%）与「当前不建议实施、应先剖析其余 90%」的结论。 |
| [NodeStoreMigrationOpenIssues.md](Internal/NodeStoreMigrationOpenIssues.md) | `feature/node-store-migration` 的**已确认问题清单**（2026-07-28 两轮审查 + 复核）。第一节是前一轮修复自身的两处缺口（Catalyst 降级只覆盖 framework 形态导致 plain dylib 仍平局、`appendRowIfAbsent` 线性扫描），已于 2026-07-29 闭环并保留成因；第二节起为仍然打开或已裁决的条目：`structuralHash` 每文本节点分配 `String` 与 `ABIKey` 每 key materialize 两条**已按上游设计终审关闭**（0.5.1 保持现状且上游说明不改，见 ReviewAdjudications A1/A2）、`memberSymbols` 改为线性 + 全树比对（**已证实量级可忽略，不是回归**）；`lateDemangledNode` 持锁 demangle 与 `ProtocolConformanceDumper` 的 materialize 分支两条**已于 2026-08-03 闭环**（连同失败名裁决缓存、dump 路径引用化）、build sweep 串行且每符号跨线程往返（上游）、`ABIKey` 每 key materialize，以及四条代码卫生项；两个公开查询 API 的字典键一条**已于 2026-08-03 裁决为不修**（类型级 SPI），rebase 前置事项一条前提已过期但压着两条仍成立的注意事项。逐条注明成因、影响面与「该在哪里修」。与 `Reviews/` 下两份审查记录冲突时以后者为准。 |
| [SystemFrameworkRenderingVerification.md](Internal/SystemFrameworkRenderingVerification.md) | 系统框架渲染 A/B 验证流程（大重构必跑）：两个检出对同一批真实输入（归档 dyld cache → 无则当前系统 cache、模拟器 runtime → 无则现有 runtime、当前系统 MachOImage）逐字节比对 dump+interface；入口脚本 `Scripts/run-rendering-ab-verification.py`，含回退规则、踩坑清单（`-p` 消歧、fat 二进制 `-a`、同 boot 会话、scratch 隔离）与 2026-08-03 基线运行记录。 |
| [TaskReports/](Internal/TaskReports/) | Dated per-task fix / investigation reports. |
| [Reviews/](Internal/Reviews/) | Dated code-review records — one file per review event: findings, measurements taken at the time, and the resulting to-do list. Distinct from the topic-organised issue ledgers (e.g. `NodeStoreMigrationOpenIssues.md`), which they cross-reference. |
