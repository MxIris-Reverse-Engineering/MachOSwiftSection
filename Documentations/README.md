# Documentation

Documentation is split by audience.

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
| [ProjectEvolutionLog.md](Internal/ProjectEvolutionLog.md) | 编年演进账本：15 个工作弧（Foundation 解析 → demangler → 模块化 → SwiftLayout → SwiftDiffing/ABI evolution …）的时间段/动机/关键决策/落地文档/版本对应，含每批次必须追加的维护约定。 |
| [SwiftModularizationMigration.md](Internal/SwiftModularizationMigration.md) | The `SwiftInterface` monolith → layered peer modules refactor; where everything moved. |
| [FieldMetadataRenderingMigration.md](Internal/FieldMetadataRenderingMigration.md) | Extracting metadata-derived field rendering into `SwiftDeclarationRendering` (single source for dumper + printer). |
| [FieldLayoutRendererReaderSpecialization.md](Internal/FieldLayoutRendererReaderSpecialization.md) | Splitting `FieldLayoutRenderer` into a generic facade dispatching to two reader-specialized implementations: the `MachOImage` runtime path (in-process metadata) and the `MachOFile` static path (offline field offsets / type layouts / expanded tree / enum layouts via `SwiftLayout`). Covers the `self as?` dispatch, the `StaticFieldLayoutProvider` injection seam (built once per session), the new SwiftLayout convenience APIs, graceful degradation, and the `typeLayoutTransformer`/tuple limitations. |
| [GenericArgumentSubstitution.md](Internal/GenericArgumentSubstitution.md) | The static generic-argument substitution in nested field-offset rendering: what it solves, why it exists (runtime PAC-fault avoidance), the ABI, value/pack support. |
| [StaticFieldOffsetComputation.md](Internal/StaticFieldOffsetComputation.md) | Research + implementation guide for computing stored-property field offsets statically (offline, no runtime): fixed-layout vs resilient, the `performBasicLayout` algorithm, `MetadataInitialization` triage, the dependency-closure type resolver, ObjC ancestors via MachOObjCSection, and a generics difficulty assessment. |
| [StaticLayoutEngine.md](Internal/StaticLayoutEngine.md) | The shipped `SwiftLayout` module: what was actually built for static field-offset computation (recompute via `performBasicLayout` rather than reading the vector), the file structure, the runtime-accessor-vs-static validation suite, empirical findings that diverged from the research, and the known per-field degradations. Existentials (opaque / class-bound / error / metatype), the default-actor storage builtin, cross-module field/superclass/protocol types (via the dependency closure), ObjC-ancestor classes (Phase 4 — a Swift class deriving from `NSObject` et al. starts its fields at the ObjC ancestor's `instanceSize`, read via `MachOObjCSection`), multi-payload enums + imported C value types (via `__swift5_builtin` whole-type layouts), imported-ObjC-protocol existentials (`any NSCopying`), C-function-pointer / ObjC-block fields, and concrete bound-generic instantiations as fields (Phase 5 — purely syntactic `dependentGenericParamType` substitution via `GenericArgumentEnvironment`, depth-0 type parameters) are resolved; only a top-level generic type's own unsubstituted parameters, value/pack arguments, and depth>0 nested-context parameters remain degraded. |
| [StaticLayoutDependencyClosure.md](Internal/StaticLayoutDependencyClosure.md) | Phase-3 (**shipped**): extends `SwiftLayout` from single-image to a dependency closure (`LC_LOAD_DYLIB` + dyld shared cache) so cross-module field/superclass/protocol types resolve, with zero resolver changes. Covers the homogeneous-per-root typing decision, the `ImageUniverse.dependencyClosure` factory, the resilient-class static-computability boundary (and why their runtime field-offset vector is empty), and the validation strategy — plus a "落地实测" section recording where the implementation diverged from the plan (lazy per-image indexing over a 551-image closure, bare-name matching, missing-section tolerance, one-shot cache indexing, literal pinning for resilient classes that emit no `…Wvd` global). ObjC ancestors were resolved by Phase 4 (`ObjCClassIndex` + a third `resolveObjCClassInstanceSize` seam; see StaticLayoutEngine.md). |
| [LeafMigrationPlan.md](Internal/LeafMigrationPlan.md) | Plan for making `SwiftDump` a leaf module. |
| [DiffableInterfacePlan.md](Internal/DiffableInterfacePlan.md) | Implementation plan for the diffable (ABI-diff) interface. |
| [ABIDiffDesignAndLimitations.md](Internal/ABIDiffDesignAndLimitations.md) | The `SwiftDiffing` ABI-diff engine: identity/payload keys, three-way match, extension-bucket merging, and the known limitations (notably: `@frozen` is unrecoverable from the binary, so the compatibility verdict treats every type as resilient). |
| [ABIEvolutionDesign.md](Internal/ABIEvolutionDesign.md) | N ≥ 2 版本的 ABI 演化追踪（`ABIEvolution` lineage 模型 + N 路矩阵算法 + timeline reporter）与作为其地基的 snapshot 持久化（`ABISnapshotDocument` 版本头、`ABIProvenance`、CLI `snapshot` / `evolution` 命令、diff 的快照输入与 `--json`）。 |
| [MetadataReaderRefactoring.md](Internal/MetadataReaderRefactoring.md) | `MetadataReader` refactoring plan. |
| [RuntimeEnumCaseProjection.md](Internal/RuntimeEnumCaseProjection.md) | 基于 value witness 的枚举 case 内存图样投影：为什么「只知道 XI 个数」推不出单 payload 空 case 的判别字节（`Text.Style.LineStyle` 反馈案例），`RuntimeEnumCaseProjector` 的双基线注入 + `getEnumTag` 回读校验机制，`EnumCaseProjection` 模型重构（`declaredName` / `isPayloadCase` / `patternResolution`）与可读化渲染，runtime 精确 / static 诚实降级的两路接线。 |
| [EnumLayoutAuditFixes.md](Internal/EnumLayoutAuditFixes.md) | 对照 Swift 官方源码（`EnumImpl.h` / `Enum.cpp` / `GenEnum.cpp` / `TypeLowering.cpp`）的枚举布局全面审计与五项修复：indirect 单 payload 的 heap-pointer XI（曾被误判为 overflow 布局）、枚举自身 VWT 的 size 交叉校验与 payloadXI 精确反推、spare-bits payload case 的位级 `fixedBitMasks`（不再整字节过度声明）、empty case 判别区完整记录（tagged 零扩展 + spare-bits 全位固定）、no-payload XI 封顶；runtime 对拍测试增量与 RuntimeViewerCore token 同步。 |
| [OutputTransformerMigration.md](Internal/OutputTransformerMigration.md) | `Transformer` 模板机制的 Swift 侧（注释 token 模板 + 预设）从 RuntimeViewerCore 迁入库侧的新 `OutputTransformer` 模块（ObjC 侧 CType/ivarOffset 暂留 RV）：架构（模块清单、宽容 Codable 持久化契约、SwiftInspection 桥接、闭包工厂 + `applyTransformers` 接线）、RV 兼容语义（auto-append、partial-mask 安全回退）、RV 侧收编为 `@_exported` shim + 一行接线。 |
| [ReadingContextAbstraction.md](Internal/ReadingContextAbstraction.md) | The `ReadingContext` reading-abstraction design. |
| [TaskReports/](Internal/TaskReports/) | Dated per-task fix / investigation reports. |
