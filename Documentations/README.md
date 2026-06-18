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
| [LeafMigrationPlan.md](Internal/LeafMigrationPlan.md) | Plan for making `SwiftDump` a leaf module. |
| [DiffableInterfacePlan.md](Internal/DiffableInterfacePlan.md) | Implementation plan for the diffable (ABI-diff) interface. |
| [MetadataReaderRefactoring.md](Internal/MetadataReaderRefactoring.md) | `MetadataReader` refactoring plan. |
| [ReadingContextAbstraction.md](Internal/ReadingContextAbstraction.md) | The `ReadingContext` reading-abstraction design. |
| [TaskReports/](Internal/TaskReports/) | Dated per-task fix / investigation reports. |
