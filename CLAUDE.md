# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Documentation

All project documentation lives in the `Documentations/` directory, split by audience (see [`Documentations/README.md`](Documentations/README.md)):

- **`Documentations/` (top level) — external / public docs**, for library users and other developers. Reference-style, English or bilingual (an `*_zh.md` companion). Currently just `SwiftEnumLayout.md` (+ `SwiftEnumLayout_zh.md`).
- **`Documentations/Internal/` — maintainer-facing notes** (design notes, migration guides, refactor write-ups; `Internal/TaskReports/` holds dated per-task reports). This is the default home for working docs.

Name doc files in **PascalCase** with the `.md` extension (e.g. `Internal/SwiftModularizationMigration.md`, `Internal/ReadingContextAbstraction.md`). When asked to "write a doc", default to `Documentations/Internal/` with a PascalCase name — only put it at the top level if it is genuinely a public, externally-facing reference (and then keep it English/bilingual). Do not scatter docs next to source files. When adding or moving a doc, update `Documentations/README.md`.

## Build and Test Commands

```bash
# Build the project
swift build

# Run all tests (skip IntegrationTests — see note below)
swift test --skip IntegrationTests

# Run specific test suites
swift test --filter DemanglingTests
swift test --filter MachOSwiftSectionTests
swift test --filter SwiftDumpTests
swift test --filter SwiftInterfaceTests

# Run the CLI tool
swift run swift-section dump /path/to/binary
swift run swift-section interface /path/to/binary

# Build release executable
./build-executable-product.sh
```

Requires Swift 6.2+ / Xcode 26.0+.

**Test suite convention:** `Tests/IntegrationTests/` is for the maintainer's manual inspection only — it prints results with no assertions or preconditions. Agents must not run it (use `--skip IntegrationTests` when running the full suite). All other `*Tests` targets have proper assertions and required preconditions, and are safe to run.

## Architecture Overview

This is a Swift library for parsing Mach-O files to extract Swift metadata (types, protocols, conformances). It uses a custom Demangler to parse symbolic references and restore Swift Runtime logic.

### Module Dependency Hierarchy

```
swift-section (CLI)
    └── SwiftInterface (orchestrator)
            └── SwiftIndexing, SwiftPrinting, SwiftSpecialization, SwiftAttributeInference
                    └── SwiftDeclaration (shared declaration model)
                            └── SwiftDump
                                    └── SwiftInspection
                                            └── MachOSwiftSection
                                                    └── MachOFoundation
                                                            └── MachOSymbols, MachOPointers
                                                                    └── MachOReading, MachOResolving
                                                                            └── MachOExtensions, MachOCaches
                                                                                    └── MachOKit (external)
```

`SwiftLayout` (static field-offset engine) is an independent peer that depends on
`SwiftInspection` + `MachOSwiftSection` (+ `MachOObjCSection` for ObjC-ancestor
instance sizes); nothing depends on it yet — it backs the static ABI-analysis
path (consumed by `SwiftDiffing` in a later step).

### Core Modules

**Demangling** - Custom Swift symbol demangler supporting symbolic references
- `Demangler` - Main demangling logic, parses mangled symbols into `Node` AST
- `Remangler` - Re-mangles nodes back to symbol strings
- `NodePrinter` - Prints nodes as human-readable Swift types
- `Node` - AST representation with `Kind` enum for ~200 mangling node types

**MachOSwiftSection** - Low-level Swift section parsing
- Reads `__swift5_types`, `__swift5_proto`, `__swift5_protos`, `__swift5_assocty`, `__swift5_builtin`
- `MachOFile.Swift` / `MachOImage.Swift` - Entry point via `.swift` property
- Models for descriptors: `TypeContextDescriptor`, `ProtocolDescriptor`, `ProtocolConformanceDescriptor`
- Relative pointer resolution for Swift's position-independent metadata

**SwiftDump** - High-level type wrappers
- `Struct`, `Enum`, `Class`, `Protocol`, `ProtocolConformance`, `AssociatedType`
- `DemangleResolver` - Resolves mangled names using the Demangler

The interface generation is split into layered peer modules over a shared `SwiftDeclaration` base model (`SwiftInterface` orchestrates them):

**SwiftDeclaration** - Shared declaration model (base layer for the Swift* modules)
- `TypeDefinition`, `ProtocolDefinition`, `ExtensionDefinition`, `FunctionDefinition`, names, kinds, `DefinitionBuilder`
- `SwiftIndexEvents` - event namespace (Payload/Dispatcher/Handler) emitted by both indexer and printer

**SwiftIndexing** - Builds the `SwiftDeclaration` model from a Mach-O image
- `SwiftDeclarationIndexer` - Indexes types, extensions, conformances
- `SwiftIndexEventReporter`, `OSLogEventHandler`, `ConsoleEventHandler` - event handlers
- `SwiftDeclarationIndexConfiguration`

**SwiftAttributeInference** - Infers source-level attributes (`@propertyWrapper`, `@resultBuilder`, `@dynamicMemberLookup`, `@objc`, …)
- `TypeAttributeInferrer`, `MemberAttributeInferrer`

**SwiftPrinting** - Renders the `SwiftDeclaration` model as Swift source (depends on `SwiftAttributeInference`)
- `SwiftDeclarationPrinter`, `TypeNodePrinter`, `FunctionNodePrinter`
- `SwiftDeclarationPrintConfiguration`, `SwiftDeclarationMemberSortOrder`

**SwiftSpecialization** - Runtime generic specialization (see implementation plan below)
- `GenericSpecializer`, `ConformanceProvider`
- `TypeDefinition` specialization behavior (`specialize(...)`, `specializedChildren`)

**SwiftInterface** - Thin orchestrator tying indexing + printing into a full interface dump
- `SwiftInterfaceBuilder` - Main builder, call `prepare()` then `printRoot()`
- `.swiftinterface` file types (`SwiftInterfaceFile`, `SwiftInterfaceParser`, …)

Printing and indexing are peers — neither depends on the other.

**SwiftInspection** - Runtime metadata analysis
- `EnumLayoutCalculator` - Calculates enum memory layouts (multi-payload enum support)
- `ClassHierarchyDumper` - Dumps class inheritance hierarchies
- `MetadataReader` - Reads runtime metadata from MachOImage

**SwiftLayout** - Static aggregate-layout engine (offline field offsets, no runtime)
- `StaticLayoutCalculator` - Entry point: computes struct/class stored-property field offsets from a Mach-O file without loading the process or calling the metadata accessor
- `StaticTypeLayoutResolver` - Recursive `mangled name → TypeLayoutInfo` solver (`Node.Kind` dispatch, memoized, cycle-guarded); class references stop at one pointer
- `BasicLayout` - Offline port of the runtime `performBasicLayout` (struct/class/tuple field accumulation)
- `KnownLayoutTable` / `BuiltinTypeLayoutIndex` - Frozen stdlib layouts + per-image `__swift5_builtin` whole-type layouts. The builtin section carries the compiler-embedded layout (size/stride/align/XI) of types reflection cannot derive structurally — **imported C value types** (`__C.CGRect`, `__C.Decimal`) and **multi-payload enums** — keyed by the demangled qualified name (the descriptor's `typeName` is a symbolic reference whose raw string is empty). The resolver consults it (per origin image) before its structural struct/enum paths, so those types resolve as opaque whole-type values
- `EnumLayoutBridge` - No-payload + single-payload (incl. `Optional`) enum layout (runtime `getEnumTagCounts` formulas). Multi-payload enums resolve via the builtin whole-type descriptor first; when absent, `multiPayloadEnumLayout` computes them structurally by reusing `SwiftInspection.EnumLayoutCalculator` (`GenEnum.cpp`/`TypeLowering.cpp` port) over the largest payload + the `MultiPayloadEnumDescriptor` (`__swift5_mpenum`) common spare bits, deriving size/stride itself (`LayoutResult` carries none)
- `ExistentialLayoutBridge` - Existential containers (`any P`, compositions, `AnyObject`, `any Error`) + existential metatypes, ported from the runtime reflection lowering (`ExistentialTypeInfoBuilder`): opaque `32 + 8N`, class-bound `8·(1+N)`, error `8`; class-boundness derived from each protocol's class constraint. Imported ObjC protocols (`any NSCopying`, `__C.<Name>` `.protocol` nodes) are always class-bound and contribute no Swift witness table
- `ObjCClassIndex` - Phase-4 Objective-C ancestor support: reads a class's instance `class_ro_t.instanceSize` from `__objc_classlist` (bare name → start layout), resolving the realized `class_rw_t` form for classes dyld has realized in-process. Uses `instanceSize` (where a Swift subclass's first field begins), **not** `instanceStart`; value matches `ObjCClass.info(in:).instanceSize` without parsing methods/ivars. `objc.classes64`/ro accessors are concrete `MachOFile`/`MachOImage` overloads, so the builder is split per reader
- `ImageUniverse` / `ImageReference` - Type/protocol/ObjC-class lookup seam (three resolvers: `resolveType`, `resolveProtocolClassConstraint`, `resolveObjCClassInstanceSize`). `ImageReference` indexes one image's type descriptors (`__swift5_types`), protocol class constraints (`__swift5_protos`), and ObjC class instance sizes (`__objc_classlist`); `ImageUniverse` is either single-image (`singleImage`) or a **dependency closure** (`dependencyClosure`) that merges a root plus its transitive dependencies, **indexing each dependency lazily** (root eager, dependencies folded in resolution order only when a lookup misses, all three indexes merged together) so a several-hundred-image OS closure is not eagerly demangled
- `ImageUniverse+DependencyClosure` - Closure factories: in-process (`dependencyClosure(root: MachOImage)`, resolves dependencies through the active dyld) and offline (`dependencyClosure(root: MachOFile, searchPaths:)`, resolves through explicit on-disk paths + the dyld shared cache, the latter indexed once by bare name). `LayoutDependencySearchPath` is SwiftLayout-local (no `SwiftInterface` dependency). Dependency load names are matched by **bare name** (`MachOImage(name:)` semantics); `MachOFile.imagePath` is the install name, not a filesystem path
- Per-field degradation: unresolved fields (unsubstituted generic parameters, not-yet-substituted concrete bound-generic instantiations) report `FieldResolution.unknown` instead of failing the whole type. Existentials (incl. imported ObjC protocols), the default-actor storage builtin, C-function-pointer / ObjC-block fields, **cross-module field/superclass/protocol types (via the dependency closure)**, **ObjC-ancestor classes** (a Swift class deriving from `NSObject` et al. starts its own fields at the ObjC ancestor's `instanceSize`, located via the closure's libobjc), and **multi-payload enums + imported C value types** (via `BuiltinTypeLayoutIndex` whole-type layouts) are resolved; cross-module resilient classes' offsets are computed against the dependency's actual binary ("this specific deployment" semantics)
- See [Documentations/Internal/StaticLayoutEngine.md](Documentations/Internal/StaticLayoutEngine.md) and [Documentations/Internal/StaticLayoutDependencyClosure.md](Documentations/Internal/StaticLayoutDependencyClosure.md)

**Semantic** - Semantic string building for colored/annotated output
- `SemanticString` - String with semantic type annotations (keyword, type, variable)
- `SemanticType` - Categories: `.keyword`, `.typeName`, `.functionName`, `.variable`, etc.

### MachO Infrastructure Modules

- **MachOFoundation** - Combines reading, symbols, pointers
- **MachOReading** - File reading abstractions
- **MachOResolving** - Address/offset resolution
- **MachOSymbols** - Symbol table parsing and demangling
- **MachOPointers** - Pointer types (relative, indirect, etc.)
- **MachOCaches** - dyld shared cache support
- **MachOExtensions** - Extensions to MachOKit types

### Key Patterns

**Descriptor → Type Wrappers**: Raw descriptors from sections get wrapped:
```swift
let descriptors = try machO.swift.protocolDescriptors
for descriptor in descriptors {
    let proto = try Protocol(descriptor: descriptor, in: machO)
}
```

**Relative Pointers**: Swift uses position-independent relative offsets. The `RelativeDirectPointer<T>` and related types handle resolution.

**Node-based Demangling**: Mangled symbols parse to `Node` trees, then print via `NodePrinter`:
```swift
let node = try demangleAsNode("$sSiD")  // Returns Node tree
let string = node.print(using: .default) // "Swift.Int"
```

## Test Environment

Tests use `MACHO_SWIFT_SECTION_SILENT_TEST=1` to suppress verbose output.

Tests read Mach-O files from Xcode frameworks and dyld shared cache for real-world validation.

## Fixture-Based Test Coverage (MachOSwiftSection)

`MachOSwiftSection/Models/` is exhaustively covered by `Tests/MachOSwiftSectionTests/Fixtures/`. Suites mirror the source directory and assert one of:

- **Cross-reader equality** across MachOFile/MachOImage/InProcess + their ReadingContext counterparts (via `acrossAllReaders` / `acrossAllContexts` helpers), plus per-method ABI literal values from `__Baseline__/*Baseline.swift` — this is the standard depth.
- **InProcess single-reader equality** plus per-method ABI literal values (via `usingInProcessOnly` helper). Used for runtime-allocated metadata types (MetatypeMetadata, TupleTypeMetadata, etc.) that have no Mach-O section presence.
- **Sentinel allowlist** with typed `SentinelReason` (in `CoverageAllowlistEntries.swift`). Used for:
  - `pureDataUtility`: pure raw-value enums / flag bitfields with no behavior to test (tests would just be tautologies)
  - `runtimeOnly`: types impossible to construct stably from tests (e.g., `swift_allocBox`-allocated `GenericBoxHeapMetadata`)
  - `needsFixtureExtension`: residual entries deferred by toolchain limits (e.g., `MethodDefaultOverrideTable` requires the not-yet-shipped CoroutineAccessors ABI; canonical-specialized-metadata records need the `-prespecialize-generic-metadata` frontend flag)

`MachOSwiftSectionCoverageInvariantTests` enforces four invariants:
1. Every public method in `Sources/MachOSwiftSection/Models/` has a registered test (or allowlist entry)
2. Every registered test name maps to an actual public method
3. Sentinel-tagged keys' Suites must actually have sentinel behavior (no `acrossAllReaders` / `inProcessContext` references)
4. Sentinel-behavior Suites must be tagged in the allowlist (no silent sentinels)

`SuiteBehaviorScanner` (in `MachOFixtureSupport`) classifies each `@Test func` body by substring presence of `acrossAllReaders` / `acrossAllContexts` / `machOFile` / `machOImage` / `fileContext` / `imageContext` (cross-reader real test) or `usingInProcessOnly` / `inProcessContext` (InProcess-only real test). Helper-call indirection within the same Suite class is recognized via class-scope inheritance.

To add a new public method:

1. Add the method.
2. Run `swift test --filter MachOSwiftSectionCoverageInvariantTests` to see which Suite needs updating.
3. Add a `@Test` to that Suite, using `acrossAllReaders` for fixture-bound types or `usingInProcessOnly` for runtime-only metadata.
4. Append the member name to `registeredTestMethodNames`.
5. Run `swift package --allow-writing-to-package-directory regen-baselines --suite <Name>` to regenerate the baseline.
6. Re-run the affected Suite.

To regenerate all baselines after fixture rebuild or toolchain upgrade:

```bash
xcodebuild -project Tests/Projects/SymbolTests/SymbolTests.xcodeproj -scheme SymbolTestsCore -configuration Release build
swift package --allow-writing-to-package-directory regen-baselines
git diff Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/  # review drift
```

The `regen-baselines` command is provided by the `RegenerateBaselinesPlugin`
SwiftPM command plugin (`Plugins/RegenerateBaselinesPlugin/`). It builds and
invokes the `baseline-generator` executable target. From Xcode you can also
right-click the package → "Regenerate MachOSwiftSection fixture-test ABI
baselines.".

## Work In Progress

### GenericSpecializer (SwiftSpecialization module)

Interactive API for specializing generic Swift types at runtime, living in the `SwiftSpecialization` module.

**Status:** Core implementation complete with tests.

**Key Design Points:**
- Only protocol requirements require Protocol Witness Tables (PWT)
- `baseClass`, `layout`, and `sameType` requirements need validation only, no PWT
- PWT passed in requirement order (critical for correct specialization)
- Generic parameter names derived from depth/index (A, B, A1, B1...) since names not preserved in binary
- Two-step API: `makeRequest()` returns parameters/candidates, `specialize()` executes with user selections
- Uses `ConformanceProvider` protocol to query type conformances from the `SwiftDeclarationIndexer`
- `specialize(...)` / `specializedChildren` are grafted onto the base `TypeDefinition` (in `SwiftDeclaration`) via a cross-module extension; `specializedChildren` is held as an `@AssociatedObject` since an extension cannot add stored properties

**File Structure:**
```
Sources/SwiftSpecialization/
├── GenericSpecializer.swift            # Main class
├── ConformanceProvider.swift           # Protocol and implementations
├── TypeDefinition+Specialization.swift # specialize(...) / specializedChildren on the model
├── SpecializationRequest.swift         # Request with parameters, requirements, candidates
├── SpecializationSelection.swift       # User selection with builder pattern
├── SpecializationResult.swift          # Result with metadata, fieldOffsets, valueWitnessTable
└── SpecializationValidation.swift      # Validation errors/warnings
```
