# Documentation

Documentation is split by audience.

## External — for library users / other developers

Public, reference-style documentation. Bilingual (English + 中文).

- **[Swift Enum Memory Layout Internals](SwiftEnumLayout.md)** — a deep dive into how the
  Swift runtime lays out enums in memory: single-payload, multi-payload, spare-bit / tag
  strategies, extra inhabitants. General reference, not tied to this project's internals.
  - 中文版：**[Swift Enum 内存布局内部机制](SwiftEnumLayout_zh.md)**

This is the only documentation aimed at an outside audience. Everything under
[`Internal/`](Internal/) is maintainer-facing.

## Internal — maintainer-facing notes ([`Internal/`](Internal/))

Design notes, migration guides, refactor write-ups, and per-task reports for contributors to
this repository. Not part of the public documentation surface (mixed Chinese / English).

| Doc | What it covers |
|---|---|
| [SwiftModularizationMigration.md](Internal/SwiftModularizationMigration.md) | The `SwiftInterface` monolith → layered peer modules refactor; where everything moved. |
| [FieldMetadataRenderingMigration.md](Internal/FieldMetadataRenderingMigration.md) | Extracting metadata-derived field rendering into `SwiftDeclarationRendering` (single source for dumper + printer). |
| [GenericArgumentSubstitution.md](Internal/GenericArgumentSubstitution.md) | The static generic-argument substitution in nested field-offset rendering: what it solves, why it exists (runtime PAC-fault avoidance), the ABI, value/pack support. |
| [StaticFieldOffsetComputation.md](Internal/StaticFieldOffsetComputation.md) | Research + implementation guide for computing stored-property field offsets statically (offline, no runtime): fixed-layout vs resilient, the `performBasicLayout` algorithm, `MetadataInitialization` triage, the dependency-closure type resolver, ObjC ancestors via MachOObjCSection, and a generics difficulty assessment. |
| [StaticLayoutEngine.md](Internal/StaticLayoutEngine.md) | The shipped `SwiftLayout` module: what was actually built for static field-offset computation (recompute via `performBasicLayout` rather than reading the vector), the file structure, the runtime-accessor-vs-static validation suite, empirical findings that diverged from the research, and the known per-field degradations. Existentials (opaque / class-bound / error / metatype), the default-actor storage builtin, cross-module field/superclass/protocol types (via the dependency closure), ObjC-ancestor classes (Phase 4 — a Swift class deriving from `NSObject` et al. starts its fields at the ObjC ancestor's `instanceSize`, read via `MachOObjCSection`), and multi-payload enums + imported C value types (via `__swift5_builtin` whole-type layouts) are resolved; ObjC-protocol existentials and generics remain. |
| [StaticLayoutDependencyClosure.md](Internal/StaticLayoutDependencyClosure.md) | Phase-3 (**shipped**): extends `SwiftLayout` from single-image to a dependency closure (`LC_LOAD_DYLIB` + dyld shared cache) so cross-module field/superclass/protocol types resolve, with zero resolver changes. Covers the homogeneous-per-root typing decision, the `ImageUniverse.dependencyClosure` factory, the resilient-class static-computability boundary (and why their runtime field-offset vector is empty), and the validation strategy — plus a "落地实测" section recording where the implementation diverged from the plan (lazy per-image indexing over a 551-image closure, bare-name matching, missing-section tolerance, one-shot cache indexing, literal pinning for resilient classes that emit no `…Wvd` global). ObjC ancestors were resolved by Phase 4 (`ObjCClassIndex` + a third `resolveObjCClassInstanceSize` seam; see StaticLayoutEngine.md). |
| [LeafMigrationPlan.md](Internal/LeafMigrationPlan.md) | Plan for making `SwiftDump` a leaf module. |
| [DiffableInterfacePlan.md](Internal/DiffableInterfacePlan.md) | Implementation plan for the diffable (ABI-diff) interface. |
| [ABIDiffDesignAndLimitations.md](Internal/ABIDiffDesignAndLimitations.md) | The `SwiftDiffing` ABI-diff engine: identity/payload keys, three-way match, extension-bucket merging, and the known limitations (notably: `@frozen` is unrecoverable from the binary, so the compatibility verdict treats every type as resilient). |
| [MetadataReaderRefactoring.md](Internal/MetadataReaderRefactoring.md) | `MetadataReader` refactoring plan. |
| [ReadingContextAbstraction.md](Internal/ReadingContextAbstraction.md) | The `ReadingContext` reading-abstraction design. |
| [TaskReports/](Internal/TaskReports/) | Dated per-task fix / investigation reports. |
