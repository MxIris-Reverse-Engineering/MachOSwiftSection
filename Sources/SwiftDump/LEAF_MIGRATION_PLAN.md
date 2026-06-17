# SwiftDump → Leaf Module — Migration Plan

> Status: ✅ IMPLEMENTED. SwiftDump is now a **terminal/leaf module** — the only
> remaining `import SwiftDump` in `Sources/` are `swift-section` (`DumpCommand`,
> `DemangleOptionGroup`) and `MachOFixtureSupport` (test support). The whole
> package builds and `swift test --skip IntegrationTests` is green (0 failures).
> No baseline regeneration was needed: the migration is orchestration-only
> (who-calls-whom), so dump output is byte-identical (`SwiftDumpTests` passes as-is).
>
> Build/test require `USING_LOCAL_DEPENDENCIES=1`.
>
> ## What actually shipped (vs. the plan below)
>
> - **New module `SwiftDeclarationRendering`** (low-level, deps = SwiftDump's old
>   deps) absorbs: the pure extensions (`Keyword+Swift`, `Node+`, `SemanticString+`,
>   `String+`) + `DemangleResolver`; the render config (`DeclarationRenderConfiguration`
>   + `typealias DumperConfiguration`) and its comment builders; the header helpers
>   (`GenericContext+Dump` incl. invertible-protocol dumping, `ResilientSuperclass+Dump`,
>   `ContextDescriptorWrapper+Dump`, `MetadataWrapper+Dump`, `OpaqueType+`,
>   `ResolvedTypeReference+`, `ProtocolConformance+`); `ParentClassVTableCache`;
>   `Node.resolveOpaqueType`; `GenericRequirement.isProtocolInherited` + `extract(where:)`.
> - **`ClassDumper.demangledSymbol(for:typeNode:)`** became `demangledOverrideSymbol`,
>   placed in **SwiftDeclaration** (its only caller, `TypeDefinition.index`) — it is an
>   index-time symbol matcher, so the model layer is its natural home (not the renderer).
> - **Phase 4 (field-metadata engine extraction) was SKIPPED**: the engine's only
>   external consumer was `SwiftDeclarationPrinter`'s `dumper.fields`. Phase 6 renders
>   fields from the model instead, so the engine (offset / expanded-offset / type-layout
>   / enum-layout / spare-bit walkers) **stays in SwiftDump** with the dumpers that use it.
> - **Phase 6 used a localized rewrite, not shared free functions**: `SwiftPrinting`
>   renders type/protocol **headers** and stored-field/case bodies itself
>   (`SwiftDeclarationPrinter+Headers.swift`) from the descriptor + the shared helpers,
>   in the clean **unbound** interface form. The `SwiftDump` dumpers were left untouched
>   (zero risk to the dump path), so a little header/associated-type logic is duplicated
>   between the two paths — intentional, since the dump and interface paths legitimately
>   diverge (per the motivation below). Consequence: a user-driven *specialized* type
>   printed via the interface path renders with an **unbound** header (`Box<A>`, not
>   `Box<Int>`); fields still substitute. Not exercised by tests; bound-name rendering
>   stays available on the dump path.
> - **Bound-name machinery** (`boundDumped*`, `BoundDumpedTypeNameRenderer`,
>   `DumperMetadataContext`) and the `Dumper`/`TypedDumper`/`NamedDumper` protocols +
>   concrete dumpers all **stay in SwiftDump** (kept per the "keep Dumpers" decision).
>
> Validated suites (all green): SwiftPrintingTests(18), SwiftInterfaceTests(24),
> SwiftIndexingTests(30), SwiftAttributeInferenceTests(27), SwiftSpecializationTests(97),
> SwiftDiffingTests(33), SwiftDumpTests(65), MachOSwiftSectionTests(0 fail) + full
> `--skip IntegrationTests` run (0 fail).
>
> ---
> Original plan (kept for reference; some steps shifted as noted above):

## Confirmed decisions

1. New module name: **`SwiftDeclarationRendering`**.
2. **Keep the concrete `Dumper` structs** (`StructDumper`/`EnumDumper`/`ClassDumper`/
   `ProtocolDumper`/`ProtocolConformanceDumper`/`AssociatedTypeDumper`/`ExtensionDumper`)
   inside SwiftDump as the dump command's renderer (slimmed: their `declaration`/
   `fields` call the shared engine; their `body` stays dump-specific).
3. **Tests deferred**: do not chase snapshot parity per-step. Land the whole
   migration, get everything building, then fix/regenerate baselines at the end.
   (`SwiftDumpTests` already has pre-existing snapshot drift on a clean HEAD, so
   per-step "byte-identical" comparison is not meaningful until baselines are
   regenerated anyway.)

## Why (motivation)

SwiftDump is currently a LOW shared dependency. Adding new printing features (e.g.
the diffable annotated interface just built) means leaning on SwiftDump's dumper
structure from SwiftPrinting/SwiftInterface, which is awkward and couples the
clean-interface path to the raw-descriptor dump path. The two consumers actually
have different needs:

- **Dump path** (`swift-section dump`): raw, descriptor-driven, lists symbol-backed
  members straight from the symbol table with addresses. This is SwiftDump's reason
  to exist.
- **Interface path** (`swift-section interface` / diff): clean, **model-driven**
  (the deduped/classified `SwiftDeclaration` model), rendered by SwiftPrinting.

Sharing the dumpers between them was the wrong coupling. After this migration the
interface path is fully model-driven and the dump path keeps its dumpers, with a
shared low-level rendering engine underneath both.

## Current state (grounded)

`import SwiftDump` appears in: `SwiftAttributeInference` (2 files), `SwiftDeclaration`
(7 files), `SwiftIndexing`, `SwiftPrinting` (3 files), `SwiftInterface` (3 files),
plus `swift-section` (`DumpCommand`, `DemangleOptionGroup`) and `MachOFixtureSupport`
(test support). Only the last group is allowed to remain.

What each non-leaf dependent actually uses:

- **SwiftIndexing** — no real SwiftDump symbol (vestigial import; just delete it).
- **SwiftAttributeInference** — no real SwiftDump symbol (the lone `.fields` match is
  a model property, not a dumper; vestigial import).
- **SwiftDeclaration** — most files use only `Node` (a Demangling re-export →
  redirect to `import Demangling`); `TypeDefinition.index` uses
  `ClassDumper.demangledSymbol(...)` (a static symbol-matcher) at 3 call sites.
- **SwiftPrinting** — the real coupling: the `.dumper(...)` factory on
  `TypeContextWrapper`, `ProtocolDumper`, `AssociatedTypeDumper.mergedRecords`,
  `DumperConfiguration`, `Keyword.Swift`, and (transitively, via `dumper.fields`) the
  field-offset / type-layout / enum-layout machinery. Also an **unused**
  `import SwiftDump` in `SwiftDeclarationPrintConfiguration.swift` (delete).
- **SwiftInterface** — `SwiftInterfaceBuilderOpaqueTypeProvider` uses
  `GenericContext+Dump`'s `dumpParameterName` / `dumpContent`; `SwiftInterfaceBuilder`
  + `SwiftDiffableInterfaceRenderer` reach the dumper machinery via SwiftPrinting.

SwiftDump's own dependencies today: MachOKit, MachOObjCSection, Semantic, Demangling,
MachOSwiftSection, Utilities, SwiftInspection. The new module sits at the same level.

## Target architecture

New leaf `SwiftDeclarationRendering` (deps: MachOSwiftSection, SwiftInspection,
Semantic, Demangling, Utilities — i.e. SwiftDump's current deps) absorbs everything
reusable. SwiftDump moves to the top as a leaf.

```
SwiftInspection (+ below)
  └── SwiftDeclarationRendering   [NEW: extensions + render config + header helpers
        │                          + field-metadata engine + demangledSymbol + DemangleResolver]
        ├── SwiftDeclaration          ✂ no longer → SwiftDump
        │     └── SwiftIndexing / SwiftAttributeInference / SwiftSpecialization
        │           └── SwiftPrinting   ✂ no longer → SwiftDump (fully model-driven)
        │                 └── SwiftInterface   ✂ no longer → SwiftDump
        └── SwiftDump  [LEAF: slimmed dumpers' `body` + dump orchestration]
swift-section → SwiftInterface, SwiftDump (DumpCommand only)
```

Net severed edges: `SwiftPrinting→SwiftDump`, `SwiftDeclaration→SwiftDump`,
`SwiftInterface→SwiftDump`, `SwiftIndexing→SwiftDump`, `SwiftAttributeInference→SwiftDump`.

### What moves into `SwiftDeclarationRendering`

1. **Pure extensions**: `Keyword+Swift`, `Node+` (hasWeakNode/hasUnownedNode/…),
   `SemanticString+` (replacingTypeNameOrOtherToTypeDeclaration, printSemantic),
   `String+` (hasLazyPrefix/stripLazyPrefix), and `DemangleResolver`.
2. **Render config**: `DumperConfiguration` → rename `DeclarationRenderConfiguration`
   (+ transformer typealiases) and its comment builders (fieldOffsetComment /
   expandedFieldOffsetComment / typeLayoutComment / enumLayoutComment /
   enumLayoutCaseComment / spareBitAnalysisComment / memberAddressComment /
   vtableOffsetComment). Leave `typealias DumperConfiguration = DeclarationRenderConfiguration`
   in SwiftDump for source compatibility.
3. **Header-rendering helpers**: `GenericContext+Dump` (generic-signature dump,
   `dumpParameterName`, `dumpContent`), `ResilientSuperclass+Dump`, invertible-protocol
   dumping, `ContextDescriptorWrapper+Dump`, `MetadataWrapper+Dump`, `OpaqueType+`.
4. **Field-metadata engine** (the hard part): the `TypedDumper` offset / expanded-offset
   tree / per-field type-layout / enum-layout / spare-bit computation, plus
   `EnumLayoutCalculator` usage and `MultiPayloadEnumDescriptorCache`, refactored into
   **reusable functions keyed by field ordinal index** (inputs: descriptor + optional
   resolved metadata + machO + config → finished, indent+BreakLine-wrapped
   `SemanticString` comment fragments).
5. `ClassDumper.demangledSymbol(...)` → a free helper (used by SwiftDeclaration).

### What stays in SwiftDump (leaf)

- The concrete dumper structs, slimmed: `declaration` / `fields` call the shared
  engine; `body` keeps the dump-specific symbol-backed member listing (functions/vars
  with address comments) and the trailing `}`.
- Top-level dump orchestration used by `DumpCommand`: `dumpType` / `dumpProtocol` /
  `dumpProtocolConformance` / `dumpAssociatedType`, `dumpConfiguration`, `dumpError`,
  `dumpOrPrint`, the `Dumpable`/`ConformedDumpable` protocols.

## Metadata-bearing fields — the strategy

Two categories, two homes; no injection needed (everything lives in shared modules).

- **Comment fragments** (field offsets, expanded-offset tree, per-field type-layout,
  enum-layout, spare-bit, per-case projection): live in `SwiftDeclarationRendering`'s
  field-metadata engine as reusable functions **keyed by field ordinal index**. Both
  SwiftPrinting (model path) and SwiftDump's dumpers (raw-descriptor path) call the
  same functions. Index keying is sound: `TypeDefinition.index()` builds `fields` by
  iterating `typeContextDescriptor.fieldDescriptor().records()` in the exact order the
  dumper's `fields` surface enumerates, and both reach the same descriptor via
  `TypeDefinition.type`. When SwiftPrinting renders a clean interface it simply does
  not call them, so the comments vanish (the model-only path the diff renderer already
  uses). Add an invariant check that `model.fields.count == engine.recordCount`.
- **Substituted generic field type** (`Box<A>.value` → `Int` under `Box<Int>`): this
  is the type *node* changing, not a comment, so it is a model property. Add
  `public var substitutedTypeNode: Node? = nil` to `FieldDefinition`, populated at
  `SwiftDeclarationIndexer.specialize(with:in:)` time (which already holds the
  specialized in-process metadata) — mirroring how the bound `typeName` is already
  injected into the model. `printField`/`printEnumCase` print
  `field.substitutedTypeNode ?? field.typeNode`.

SwiftPrinting renders **headers** by calling the shared header helpers with the
`descriptor` it already reaches via `typeDefinition.type` + its `machO` — so the
generic signature does NOT need to be captured into the model.

## Reuse from the just-shipped diff work

`SwiftPrinting/SwiftDeclarationPrinter+Members.swift` already proves the model carries
enough to render stored fields (`printField` from `FieldDefinition`+`FieldFlags`),
enum cases (`printEnumCase`), `deinit`, and associated types with no dumper. Phase 6
generalizes that model-only loop from the diff renderer to the main
`printTypeDefinition` path; the only additions are (a) interleaving the shared
comment-engine fragments by field index and (b) reading `substitutedTypeNode ?? typeNode`.
The header-only `printTypeHeader`/`printProtocolHeader` in that same file are the
current last dumper users there and become the first consumers of the shared header
helpers in Phase 7.

## Phased plan (each step builds; tests deferred to the end)

0. **Drop vestigial imports** — remove `import SwiftDump` from `SwiftIndexing`,
   `SwiftAttributeInference`, and the unused one in
   `SwiftPrinting/SwiftDeclarationPrintConfiguration.swift`. Build whole package.
1. **Create `SwiftDeclarationRendering`** (deps: MachOSwiftSection, SwiftInspection,
   Semantic, Demangling, Utilities). Move the pure extensions + `DemangleResolver`
   into it at `package` visibility. SwiftDump `import SwiftDeclarationRendering`. Build.
2. **Move render config + comment builders** — `DeclarationRenderConfiguration`
   (+ `typealias DumperConfiguration`) and the comment-builder methods. Build.
3. **Move header helpers** — `GenericContext+Dump`, `ResilientSuperclass+Dump`,
   `ContextDescriptorWrapper+Dump`, `MetadataWrapper+Dump`, `OpaqueType+`, invertible
   protocol dumping. SwiftDump dumpers + SwiftInterface's OpaqueTypeProvider now call
   the moved versions. Build.
4. **Extract the field-metadata engine** — reusable, field-index-keyed functions;
   SwiftDump's `StructDumper`/`ClassDumper`/`EnumDumper` `fields` call them. Build.
5. **Extract `demangledSymbol`** → free helper in `SwiftDeclarationRendering`;
   `SwiftDeclaration.TypeDefinition` uses it; redirect SwiftDeclaration's `Node`-only
   imports to `Demangling`. **✂ remove SwiftDeclaration→SwiftDump** from Package.swift.
   Build.
6. **Make SwiftPrinting model-driven** — replace `dumper.declaration` (header) with the
   shared header helpers called on `typeDefinition.type`+`machO`; replace
   `dumper.fields` with the model field/case loop (`printField`/`printEnumCase`) plus
   the shared comment engine interleaved by index; replace `ProtocolDumper` /
   `AssociatedTypeDumper.mergedRecords` with the shared equivalents. Add
   `FieldDefinition.substitutedTypeNode` populated in `specialize(with:in:)`.
   **✂ remove SwiftPrinting→SwiftDump** from Package.swift. Build.
7. **Sever SwiftInterface→SwiftDump** — point OpaqueTypeProvider at the shared header
   helpers; confirm nothing else in SwiftInterface references a Dumper. Remove
   `.target(.SwiftDump)` from the SwiftInterface target. Build.
8. **Lift SwiftDump to leaf** — SwiftDump now depends on `SwiftDeclarationRendering`
   (and SwiftDeclaration only if its orchestration needs the model — likely not).
   Verify with `rg "import SwiftDump" Sources` → only `swift-section` (DumpCommand,
   DemangleOptionGroup) + `MachOFixtureSupport`. Verify SwiftPrinting builds in
   isolation: `swift build --target SwiftPrinting`.

## After everything builds (tests)

- Regenerate baselines: build the SymbolTests fixture, run
  `swift package --allow-writing-to-package-directory regen-baselines`, review
  `git diff Tests/.../__Baseline__/` and the SnapshotTesting `__Snapshots__/` diffs for
  drift. The migration is orchestration-only (who-calls-whom); comment content,
  indentation, and BreakLine ordering should be unchanged, so genuine drift should be
  near-zero — investigate anything that is not.
- Run `swift test --skip IntegrationTests` green.

## Open questions / risks

- **Null-header fidelity**: not needed under the chosen design — SwiftPrinting always
  has `machO`, so it renders full headers via the shared helpers; there is no
  "provider-less degraded header" case.
- **`DumperConfiguration` rename blast radius**: the `typealias` should absorb it;
  confirm `SwiftDeclarationPrintConfiguration` maps cleanly (it builds the render
  config today).
- **Enum spare-bit / multi-payload** annotation uses `MultiPayloadEnumDescriptorCache`
  and is gated on `!isGeneric` inside `EnumDumper.fields`; preserve both the cache
  lifetime and the gating when the engine moves.
- **`package` visibility** assumes one SwiftPM package. If anything ever needs
  cross-package use, promote to `public`.
- **Diff interface offsets**: with the shared engine, the diffable annotated interface
  could optionally show offset/layout comments too — a later product decision, free to
  wire either way.
