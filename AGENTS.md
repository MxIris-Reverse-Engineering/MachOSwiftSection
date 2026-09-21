# AGENTS.md

This file provides guidance to coding agents when working with code in this repository.

A Swift library that parses Mach-O files to recover Swift metadata — types, protocols, conformances, field layouts — without loading the binary into a process. It carries its own demangler (symbolic references included) and reimplements the Swift runtime's own reading logic. `swift-section` is the companion CLI.

Requires Swift 6.2+ / Xcode 26.0+.

**Detail lives in `Documentations/`, not here.** This file carries what an agent gets wrong by default; everything else is one link away. Start at [`Documentations/README.md`](Documentations/README.md) — `Internal/Modules/` for per-module reference, `Internal/` for topic notes, `Evolutions/` for the proposal per change, `Internal/TaskReports/` for per-task retrospectives.

## Module dependency hierarchy

```
swift-section (CLI)
    └── SwiftInterface (orchestrator)
            └── SwiftIndexing, SwiftPrinting, SwiftSpecialization, SwiftAttributeInference
                    └── SwiftDeclaration (shared declaration model)
                            ├── SwiftDeclarationRendering
                            │       └── SwiftThunkAnalysis (Capstone; the kind-9 accessor-thunk reader)
                            └── SwiftDump
                                    └── SwiftInspection
                                            └── MachOSwiftSection (ABI model — depends on MachOBase ONLY)
                                                    └── MachOBase (umbrella: reading / resolving / pointers)
                                                            └── MachOPointers
                                                                    └── MachOReading, MachOResolving
                                                                            └── MachOKitExtensions (external), MachOKit (external)

SwiftInspection and everything above it also import
    MachOFoundation (umbrella = MachOBase + MachOSymbols + MachODependencies)
            └── MachOSymbols (symbol index + demangling), MachODependencies
                    └── MachOCaches, MachOBase
```

`SwiftLayout` is a peer of that spine: it depends on `SwiftInspection` + `MachOSwiftSection` (+ `MachOObjCSection` for ObjC-ancestor instance sizes) and is consumed by `SwiftDeclarationRendering`. `TypeIndexing`, `SwiftDiffing` and `OutputTransformer` hang off the same level as the modules that use them.

## What each module does

One or two lines each; the linked document is the authority.

### The Swift-facing stack

- **Demangling** (upstream package) — mangled symbol → `Node` AST → printed Swift, plus the remangler. `Node.Kind` covers ~200 mangling node kinds.
- **MachOSwiftSection** — the ABI model: the `__swift5_*` sections, every descriptor shape in them, and Swift's position-independent relative pointers. Self-contained — `MachOBase` only, no symbol index, no demangler; a descriptor exposes an implementation's *offset* and `SwiftInspection` attributes the name ([SelfContainedABILayer.md](Documentations/Internal/SelfContainedABILayer.md)).
- **SwiftInspection** — runtime metadata analysis, and where ABI-layer symbol attribution lives: `SymbolicDemangler` (names carrying symbolic references; also demanglings built straight from descriptors), `RuntimeMetadataTypeBuilder` (node → live metadata), `EnumLayoutCalculator` + `RuntimeEnumCaseProjector`, `ClassHierarchyDumper`, `ObjCImplementationClassIndex` (SE-0436 `@objc @implementation` classes, recognized from `__objc_classlist` joined with the symbol table — [ObjCImplementationClassRecognition.md](Documentations/Internal/ObjCImplementationClassRecognition.md)), `ObjCClassHierarchy` + `ObjCClassHierarchyProviding` / `ObjCClassHierarchyProviderStore` (the per-image seam through which a host hands over the ObjC class hierarchies it already indexed — RuntimeViewer's indexer, or `SwiftIndexing`'s adapter over `ObjCIndexing.ObjCInterfaceIndexer`) with `ObjCClassMethodIndex` as the library's own lazy reader behind it (class, metaclass and same-image category method lists, the ancestor chain, the adopted protocols' selectors) and `ObjCAncestorResolver` / `ObjCAncestorResolverStore` following a standalone file's bound superclass or category target by name into its dependency closure (export trie first, then the class list; the indexer and `dump` register one per image over the configured search paths, an unregistered file defaults to the system cache, an in-process image needs none — so a file's chain reaches libobjc's `NSObject` like a cache image's does), `ObjCMember` / `ObjCMemberTable` (the per-class ObjC member table: every method-table entry tied to its Swift member — the `@objc`, `override` and explicit-selector facts in one place) and `ObjCMemberShape` (a member's selector shape: the importer's naming rules applied as a forward CHECK, and the compiler's own selector derivation ported for the explicit-selector verdict) — [ObjCMemberRecovery.md](Documentations/Internal/ObjCMemberRecovery.md).
- **SwiftDump** — high-level wrappers (`Struct`, `Enum`, `Class`, `Protocol`, `ProtocolConformance`, `AssociatedType`, `ObjCImplementationClass`) and the `dump` output path.
- **SwiftDeclaration** — the shared declaration model every higher module reads and writes, plus the `SwiftIndexEvents` namespace. [Modules/SwiftDeclaration.md](Documentations/Internal/Modules/SwiftDeclaration.md).
- **SwiftDeclarationRendering** — the comment engine shared by dump and interface (`FieldLayoutRenderer`, opaque-type rewriting, specialized-metadata substitution), reader-specialized: live metadata in-process, SwiftLayout offline ([FieldLayoutRendererReaderSpecialization.md](Documentations/Internal/FieldLayoutRendererReaderSpecialization.md)).
- **SwiftIndexing** — builds the declaration model from an image (`SwiftDeclarationIndexer.prepare()`), unifies extension containers, owns the per-image cache eviction.
- **SwiftAttributeInference** — infers source-level attributes (`@propertyWrapper`, `@resultBuilder`, `@dynamicMemberLookup`, `@objc`, …).
- **SwiftPrinting** — renders the model as Swift source: keywords the mangling does not carry (`class` vs `static`, `final`), bound rendering of specialized definitions, export-status annotation and `--exported-only` filtering.
- **SwiftSpecialization** — runtime generic specialization (`GenericSpecializer`, `ConformanceProvider`); grafts `specialize(...)` onto `TypeDefinition`.
- **SwiftInterface** — the orchestrator: single-version, two-version diff, and N-version evolution interfaces, all three over one shared structure walk. [Modules/SwiftInterface.md](Documentations/Internal/Modules/SwiftInterface.md).
- **SwiftDiffing** — Mach-O-free ABI comparison over the indexed model: `ABIDiffer` (two-sided), `ABIEvolution` (N versions), `ABISnapshot` (the persisted baseline). [ABIDiffDesignAndLimitations.md](Documentations/Internal/ABIDiffDesignAndLimitations.md), [ABIEvolutionDesign.md](Documentations/Internal/ABIEvolutionDesign.md).
- **SwiftLayout** — the static field-offset / type-layout engine: computes offline what the runtime computes, and degrades honestly when the binary does not carry the fact. [Modules/SwiftLayout.md](Documentations/Internal/Modules/SwiftLayout.md).
- **SwiftThunkAnalysis** — reads an availability-conditional opaque type (a kind-9 accessor-function symbolic reference) by symbolically evaluating the thunk instead of running it. Capstone, ARM64 only. Also home of `ObjCMembers` (`ObjCMembers/`): a class's ObjC method table is its `@objc` member list, and it survives the strip that removes every `To` thunk symbol from an OS framework — the interface's only `@objc` evidence until then (the macOS 26.6 AppKit interface carried ZERO member-level `@objc`, and mis-marked `@objc dynamic` members `final`). Each entry is tied to its Swift member by the `To` thunk symbol at the IMP or — stripped — by decoding the anonymous thunk for the implementation it calls or materializes, guarded by the member's name being the importer's spelling of the selector; that gives `@objc`, the `override` of an ObjC-inherited member (invisible to Swift metadata: the compiler emits a NEW vtable entry for it, and an `@objc @implementation` class has no vtable) where an ancestor implements the selector, and `@objc(selector)` where the selector differs from the compiler's own derivation from the Swift name (never for an override or an `@objc` protocol witness, whose selectors are inherited — and therefore only when the whole ancestor chain and every adopted protocol were read, since a standalone file's bound superclass would otherwise turn every UIKit override into a false `@objc(hitTest:withEvent:)`; an `@implementation` body is NOT exempt — the compiler derives its selectors from the Swift names too and demands the header declare them). A name-only third tier for overrides exists behind `infersOverridesFromSelectorNames` (default off). `isOverride` / `isClassMember` on the member definitions OR the fact in, so `override class func` prints where `static` did. [Modules/SwiftThunkAnalysis.md](Documentations/Internal/Modules/SwiftThunkAnalysis.md).
- **TypeIndexing** — `__C` module attribution (`__C.NSString` → `Foundation.NSString`), macOS-only, via SourceKit module interfaces + APINotes + a lazy ObjC-metadata index. [TypeIndexingPipeline.md](Documentations/Internal/TypeIndexingPipeline.md).
- **OutputTransformer** — token-template rendering for the Swift comment kinds, dependency-free, shared with RuntimeViewer's settings UI. [OutputTransformerMigration.md](Documentations/Internal/OutputTransformerMigration.md), [CLITransformerTemplateInterface.md](Documentations/Internal/CLITransformerTemplateInterface.md).
- **Semantic** (upstream package) — `SemanticString`, for colored/annotated output.

### The Mach-O infrastructure

- **MachOBase** — umbrella over `MachOKitExtensions` / `MachOReading` / `MachOResolving` / `MachOPointers` / `Utilities`: everything the ABI model is allowed to see. `MachOSwiftSection` re-exports it.
- **MachOFoundation** — `MachOBase` + `MachOSymbols` + `MachODependencies`: the umbrella for everything above the ABI model.
- **MachOReading / MachOResolving** — reading abstractions; address/offset resolution. `MachOResolving` also holds the symbol *value* types (`Symbol`, `Symbols`, `SymbolOrElement`), which carry no lookup behavior — "the symbols at this offset" is a query, not a read.
- **MachOPointers** — relative and indirect pointer types, plus `SymbolOrElementPointer`.
- **MachOSymbols** — the symbol *index*: table parsing, demangling, the per-image node stores, and `LargeStackTaskExecution`. [Modules/MachOSymbols.md](Documentations/Internal/Modules/MachOSymbols.md).
- **MachOCaches** — dyld shared cache support.
- **MachODependencies** — the one dependency-resolution implementation every feature shares (`DependencyClosure`, the in-process and file locators, `DependencySearchPath`, `SharedDependencyClosure` for consumers of one root that resolve lazily). The file locator filters dyld-cache candidates by platform (`DependencyPlatforms`, from `LC_BUILD_VERSION`): the host's macOS cache is every root's default search path and carries Mac Catalyst UIKit / SwiftUI under `/System/iOSSupport`, which an iOS root used to resolve to by bare name. [Modules/MachODependencies.md](Documentations/Internal/Modules/MachODependencies.md).
- **MachOKitExtensions** (external sibling, `../MachOKitExtensions`) — MachOKit extensions. Two behaviors this repo's tests still pin live there: legacy `LC_DYLD_INFO` bind resolution (`LegacyDyldInfoBindTests`) and ranked dyld-cache image name lookup (`DyldCacheImageSearchTests`). It cannot move back in-repo — `MachOObjCSection` depends on it, which would make a package-level cycle.

Printing and indexing are peers; neither depends on the other.

<important if="you need to build, test, or run this project">

```bash
# Build the project
swift build

# Run all tests (skip IntegrationTests — see below)
swift test --skip IntegrationTests

# Run specific test suites
swift test --filter DemanglingTests
swift test --filter MachOSwiftSectionTests
swift test --filter SwiftDumpTests
swift test --filter SwiftInterfaceTests
swift test --filter SwiftSectionCommandTests

# Run the CLI tool — the subcommands, in full
swift run swift-section dump <binary>                 # types / protocols / conformances
swift run swift-section interface <binary>            # generate a .swiftinterface offline
swift run swift-section snapshot <binary>             # persist an ABI baseline as JSON
swift run swift-section diff <old> <new>              # two-sided ABI diff; either side may be a snapshot
swift run swift-section evolution <v1> <v2> …         # N-version lineage
swift run swift-section transformer tokens            # also: templates | config — the discovery surface

# Each subcommand's --help is the authority on its flags. The one that is easy not to
# know exists: --dependency-search-path (dump / interface / snapshot), which points the
# thunk reader, the static layout engine, the indexer's cross-image facts (a stored
# field whose type is a property wrapper from another image) and the ObjC ancestor
# chain (a standalone file's bound superclass — `override`, the explicit-selector
# verdict) at the images a standalone binary links — a Mach-O file, a dyld cache file,
# or a directory used as a system root. Without it, the thunk reader infers paths from
# where the binary sits and everything falls back to the running system's cache, whose
# images of another platform are never candidates: an iOS binary on a macOS host needs
# its runtime root named here.

# Build release executable
./build-executable-product.sh

# Rebuild the test fixture binary (also: right-click the package in Xcode → regen-baselines)
xcodebuild -project Tests/Projects/SymbolTests/SymbolTests.xcodeproj \
  -scheme SymbolTestsCore -configuration Release \
  -derivedDataPath Tests/Projects/SymbolTests/DerivedData/SymbolTests build

# Regenerate all fixture ABI baselines after a fixture rebuild or toolchain upgrade
swift package --allow-writing-to-package-directory regen-baselines
git diff Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/   # review drift

# Rendering A/B verification, and the harness's own unit tests
python3 Scripts/run-rendering-ab-verification.py <baseline-checkout> <candidate-checkout>
python3 Scripts/test-run-rendering-ab-verification.py
```

- **Never run `Tests/IntegrationTests/`.** It is the maintainer's manual-inspection target: it prints results with no assertions and no preconditions. Every other `*Tests` target asserts properly and is safe to run. Sole exception: `RenderingVerificationTests`, as the MachOImage leg of the A/B verification.
- **The rendering A/B verification is mandatory after any large refactor** touching demangling, printing, indexing, or the reader stack: byte-identical `dump` + `interface` output over real system frameworks through all three reader paths (archived dyld caches, simulator-runtime files, in-process `MachOImage`). Procedure, fallback rules, pitfalls: [SystemFrameworkRenderingVerification.md](Documentations/Internal/SystemFrameworkRenderingVerification.md).
- **Re-run the harness's own unit tests after touching `compare_all_pairs` or the skip-marker writing.** Every hole found there so far was the same shape — the harness reporting a pass over a comparison it never made (zero pairs compared; both sides failing with *different* exit codes, leaving no `.txt` for either glob to see). Its green light is what this file makes acceptance evidence, so a harness that cannot fail is worse than no harness.
- CI runs only a subset of suites. A green CI is not a green full suite; run the full suite locally before claiming one.

</important>

<important if="you are writing or modifying tests">

- Swift Testing runs test bodies on **512 KB cooperative threads**. A test calling a library entry point gets the large-stack executor from that entry's own `LargeStackTaskExecution.run`; a test driving the demangler or printer *directly* in deep recursion does not — wrap such a body in `LargeStackTaskExecution.run` when the hop cost or the 8 MB pool depth is what is being measured. "The suite passed" is not evidence the executor was used.
- **A compiled-on-the-fly fixture dylib must contain at least one class.** A struct-only module produces a dylib with no `__DATA` segment, and the pinned MachOKit release mis-walks that layout's chained-fixup pages, killing the test process with SIGSEGV/SIGBUS from inside `prepare()`. Add ballast if the scenario does not need one.
- **A suite asserting on whole-process state derived from an image must declare `ExclusiveImageAccess(.TheFixture)` — and so must every other suite touching that image.** A one-sided declaration excludes nothing. `.serialized` does not work (it orders within one container only, and `swift test` links everything into one process) and neither does a global actor (these tests are `async`, and `await` yields the actor). Do not assert exclusivity in a doc comment: `grep ExclusiveImageAccess` finds every declared user, grepping a fixture name does not.
- **A `swift test` process never enforces pointer authentication, even built and reported as arm64e** — auth fixups are strip-applied there, so signed slots read back bare. Any "verified because the suite passed as arm64e" claim is a placebo; verify by spawning a real arm64e child process, as `Arm64eSignedVWTPointerTests` does.
- **`SymbolTestsCore` must not enable the CoroutineAccessors feature** — it would move every implementation offset the ABI baselines pin. A suite needing a `…Twc` compiles its own fixture and asserts structurally.
- Tests use `MACHO_SWIFT_SECTION_SILENT_TEST=1` to suppress verbose output, and read Mach-O files from Xcode frameworks and the dyld shared cache for real-world validation.
- Test design in general: the `write-tests` skill.

</important>

<important if="a snapshot or baseline test just went red">

Rule out all three environment drifts **before** attributing red tests to a code change. Each mimics a real regression closely. Full write-up: [FixtureTestingAndContinuousIntegration.md](Documentations/Internal/FixtureTestingAndContinuousIntegration.md).

1. **Stale or missing fixture binary.** `Tests/Projects/SymbolTests/DerivedData/…/SymbolTestsCore` is a gitignored per-machine artifact while the snapshot baselines are versioned, and it is shared machine state — a parallel session may have rebuilt it from another branch.
   - *Stale*: output drops whole trailing types with no `Error:` lines. Diagnose with `strings <binary> | grep -c <TypeName>` for a type added by recent commits under `Tests/Projects/SymbolTests/SymbolTestsCore`; fix by rebuilding.
   - *Missing* (the normal state of a fresh worktree — being gitignored, it is never checked out): every test in a fixture-bound suite fails in milliseconds, including ones touching no fixture, with `NSCocoaErrorDomain Code=4 "The file 'SymbolTestsCore' doesn't exist."`. If the branch has no diff under `Tests/Projects/`, symlink the main checkout's `DerivedData` instead of rebuilding.
2. **Missing local sibling dependencies.** `../MachOKit`, `../MachOObjCSection`, `../swift-demangling` and `../swift-semantic-string` are *conditional* local path dependencies: used only when the sibling directory exists **and** `USING_LOCAL_DEPENDENCIES=1` is in the build environment — otherwise resolution silently falls back to the remote release and output drifts wholesale. Export the variable for every build that must use siblings, detached and `nohup` runs included, and diagnose from the scratch's `workspace-state.json` (`packageRef.kind` reads `fileSystem` vs `remoteSourceControl`). Two traps on top: SwiftPM caches manifest *evaluation* per scratch path, so a long-lived scratch keeps siblings from a session where the variable was set while a fresh one silently resolves remote; and two fresh scratches resolve the newest matching remote versions independently, so an A/B whose sides were resolved minutes apart can compare different upstream versions — copy the baseline's `Package.resolved` over and confirm both files agree.
3. **Fixture build settings drifting from the ones the baselines were generated with.** The ABI baselines record absolute implementation offsets, and those move with build *settings*, not only with sources: `CODE_SIGNING_ALLOWED=NO` shifts every one by +16 bytes (the padding before `__text` is 64 bytes signed versus 80 unsigned, so `__text` starts at `0x13e8` versus `0x13f8`), turning four suites red with no code change. `ARCHS=arm64` and the `-derivedDataPath` value are harmless.
   **CI therefore builds the fixture ad-hoc signed** (`CODE_SIGN_IDENTITY=-` plus `CODE_SIGNING_REQUIRED=NO`): no certificate needed, and it reproduces the signed layout exactly. Do not "fix" a future mismatch by switching CI back to `CODE_SIGNING_ALLOWED=NO` — that trades a build failure for four silently wrong suites. **Regeneration must produce the same layout as CI's build.**

</important>

<important if="you are adding a public method under Sources/MachOSwiftSection/Models/">

That directory is exhaustively covered by `Tests/MachOSwiftSectionTests/Fixtures/`, and `MachOSwiftSectionCoverageInvariantTests` enforces it in both directions (every public method registered; every registered name real; sentinel-tagged suites actually sentinel; sentinel-behavior suites actually tagged). The procedure:

1. Add the method.
2. `swift test --filter MachOSwiftSectionCoverageInvariantTests` to see which Suite needs updating.
3. Add a `@Test` to that Suite — `acrossAllReaders` for fixture-bound types, `usingInProcessOnly` for runtime-only metadata.
4. Append the member name to `registeredTestMethodNames`.
5. `swift package --allow-writing-to-package-directory regen-baselines --suite <Name>`.
6. Re-run the affected Suite.

A type with genuinely nothing to test goes on the sentinel allowlist with a typed `SentinelReason` (`pureDataUtility` / `runtimeOnly` / `needsFixtureExtension`) in `CoverageAllowlistEntries.swift`. Rationale and history: [FixtureTestingAndContinuousIntegration.md](Documentations/Internal/FixtureTestingAndContinuousIntegration.md).

</important>

<important if="you are touching the demangler, node trees, or the symbol index">

Each of these fails **silently**, and several produce a real, fully-qualified, *wrong* type rather than an error.

- **`Node` conforms to `Sequence`, and its iterator is `preorder()`, which yields the node itself first.** `for child in node` is the whole subtree, not the children — read as "the children", position 0 holds the parent and every later position holds the element to its left or a fragment of its subtree. Iterating where positions matter goes through `.children`; the kind-scoped helpers (`first(of:)` / `all(of:)` / `contains(_:)` / `filter(of:)`) are whole-tree searches by design and are right when that IS the intent.
- **A `DemangledSymbol` stored into the declaration model must be detached first** (`detachedFromSharedTable()`). One stored survivor pins the whole shared `SymbolTable`, defeating the per-image reclamation `removeSubIndexer(_:)` exists for. Do NOT detach on the query path. `SymbolTableRetentionTests` catches a forgotten seventh storing site.
- **Any `Dictionary`/`Set` keyed on a `NodeReference` whose keys and lookups can come from different stores must key on `StructuralNodeReferenceKey`, never a bare `NodeReference`** — its intrinsic `Hashable` is store-identity based. Different stores are the norm within one image. Bare keys are safe only for grouping within a single `memberSymbols` batch. Symptoms of getting it wrong differ per site: a dropped `override` keyword, a discarded setter, a doubled `func`, a twice-claimed witness.
- **Do NOT reintroduce `demangleAsNode` / `Node.create` on unbounded inputs.** Sources carries zero cached call sites; a tree that is consumed and dropped stays transient (`demangleAsNodeTransient` / `Node.createTransient`).
- **Do NOT call bare `NodeReference(interning:)` on a batch path** — route through `InternedNodeReferenceCache`.
- **Resolving one type's members/info/attributes must use the node-taking overloads** (`memberSymbols(of:for:node:in:)` and friends). The name-only forms flatten every sub-bucket on purpose: the name key is printed with `.interfaceTypeBuilderOnly`, which strips private discriminators, so same-named private types share a bucket (issue #115).
- **Do not hold a lock across a demangle** — the large-stack hop can block.
- **Changing a struct layout in `MachOSymbols` needs `swift package clean`.** Incremental builds have been observed linking stale downstream objects (runtime SIGSEGV in `outlined destroy`). Moving a public type across modules or flipping a dependency edge does the same. Clean first, diagnose second.

Detail: [Modules/MachOSymbols.md](Documentations/Internal/Modules/MachOSymbols.md), [NodeStoreMigrationPlan.md](Documentations/Internal/NodeStoreMigrationPlan.md), [SharedNodeStoreMigration.md](Documentations/Internal/SharedNodeStoreMigration.md).

</important>

<important if="you are writing or modifying a descriptor wrapper, a layout struct, or a relative pointer in the ABI layer">

- **`@LocatableLayoutWrapping` generates the three storage-level requirements** (`var layout`, `let offset`, `init(layout:offset:)`). Write only the nested `Layout` struct — and **keep the conformance on the declaration**, the macro deliberately does not add it. A member the host declares itself is left alone, with a warning.
- **`LayoutWrapper` is `@dynamicMemberLookup` over `Layout`**, so every layout field already reads as `record.field`. Do NOT re-declare a property that only forwards to `layout`, nor one that only widens a field to `Int` (the house style casts at the use site). A same-named property of a different type shadows the dynamic member and reads as a trap. The lookup does not reach through an existential — code iterating erased conformers needs a genuine protocol member.
- **`resolvedDirectOffset(from:)` needs a key path to a *stored* property of the CONCRETE `Layout`.** One formed in a generic context against a layout *protocol* addresses a witness instead; the lookup answers nil and the force-unwrap behind it traps at runtime — so a shared implementation over a layout protocol cannot use it, each conformer calls it itself. It always answers the DIRECT reading, so a relative-*indirectable* field rules out `isIndirect` first. A descriptor already exposing a named `…Offset` property is what a consumer calls; re-deriving it at the use site is what that property exists to prevent.
- **Trap:** `context.readElement(at:)` inferred at `Optional<Pointer<…>>` reads a different in-memory shape and silently answers nil — annotate the non-optional read and return it.

</important>

<important if="you are reading offsets in an image inside a dyld shared cache">

Every offset in `MachOSwiftSection` is `unslidVirtualAddress - sharedRegionStart`, **not a file offset**. Three other accountings coexist and mixing them fails silently — `adrp` computes its page base from the instruction's own address, so a sub-page error still yields a computable, plausible-looking address pointing into a neighbouring image:

- `segment.fileOffset` / `headerStartOffsetInCache` (subcache file offsets)
- `MachOFile.fileOffset(of:)` (file accounting — **not** the inverse of what `readElements(offset:)` takes)
- `FullDyldCache.address(of:)` (a third)

Use `resolveRebase(fileOffset:)`. Note `ValueMetadataProtocol.descriptor(in:)` routes through `fileOffset(of:)` and so fails `offsetOutOfBounds` on a cache image — a pre-existing gap in reading *absolute* pointers offline, which the ABI model never hits because its own reads are relative. And `ExportedSymbol.offset` is an offset from the **mach header**, which MachOKit hands over unchanged for a cache image; the one correct conversion is `ThunkAddressSpace.address(forExportedSymbolOffset:)`.

</important>

<important if="you are writing a log statement, or reporting a degradation from library code">

- **All logging goes through `@Loggable` + `#log`** (from the **`FoundationToolbox`** product of `FrameworkToolbox` — its declaration lives under `Sources/OSToolbox/` upstream, which misleads; an `OSToolbox` product dependency fails to resolve). Never `os.Logger`, never bare `os_log`, never `print`. The macro expands with an `#available` fallback to `os_log`, which is what covers this package's macOS 10.15 / iOS 13 floor — do not hand-roll that fallback.

  ```swift
  @Loggable(.private, subsystem: "com.machoswiftsection.<module>", category: "<TypeName>")
  final class Foo {
      func bar() {
          #log(.error, "something degraded: \(String(describing: error), privacy: .public)")
      }
  }
  ```

- **A generic type takes the protocol form.** On a *type* the macro expands to a static stored property, which a generic type cannot have; on a *protocol* it expands to computed properties in an extension, so any conformer works. Scope it `fileprivate` when the conformers share the file, `internal` only when they do not — **`private` does not work at either position** (`'logger' is inaccessible due to 'private' protection level`, plus a spurious-looking conformance error).
- **Keep subsystem/category strings stable** across refactors; RuntimeViewer filters its log stream on them.
- **Logging is the floor, not the reporting path.** Anything a host should see is dispatched as a `SwiftIndexEvents` payload and the host decides where it lands; `Dispatcher.dispatch` falls back to `#log` when no handler is attached. What counts as a failure is `Payload.unhandledFailureDescription`, an exhaustive `switch` **on purpose** — a new failure case must opt in explicitly, or it silently escapes that floor.
- **Never use `FileHandle.standardError/Output.write(_:)`** — that overload raises an uncatchable ObjC exception on a closed or broken stream and aborts the host. Use `fputs` / `fwrite`. Pinned by a source scan (`PrintFailureEventTests.libraryModulesWriteToNoProcessStream`) carrying a shrink-only allowlist.
- The CLI's console handler writes to **stderr**: stdout carries the generated Swift / JSON, and writing there corrupts the product output (issue #102).
- **`MachODependencies` sits *below* the event layer**: its failures are data (`searchPathLoadFailures`, `unresolvedLoadNames`), returned to the caller and never logged there.

[EventBasedDegradationReporting.md](Documentations/Internal/EventBasedDegradationReporting.md).

</important>

<important if="you are touching the declaration model, the indexer, or a printer path">

- **Materialization discipline**: at most one materialization per operation (index it / print it / specialize it), threaded through as a local variable. Never a per-access computed property, and never cached back onto the definition — caching re-accumulates, in browse order, exactly the memory the descriptor slimming reclaimed.
- **The printers' error contract inverts by level.** Inside a definition, a failing field fails the whole type. At the top level — `printRoot` and the nested children loops alike — printing catches **per definition**: one type/protocol/extension/nested child that throws drops only itself, never its block. A block-level catch once blanked every type of a legacy binary's interface.
- **A name's `kind` takes no part in its equality.** The node identifies the type; `kind` is derived differently per producer and the two disagree for C-imported types.
- The `Name` types are deliberately **not `Codable`**. A mangled symbol already is the tree's serialized form — persist `mangleAsString(node)` and read it back with `demangleAsNode(_:)` rather than reintroducing a node encoding.
- [Modules/SwiftDeclaration.md](Documentations/Internal/Modules/SwiftDeclaration.md).

</important>

<important if="you are writing async code, or wrapping a library entry point">

Library entry points run their body on the demangler's large-stack task executor via `LargeStackTaskExecution.run` — the demangler probes the *calling* thread's remaining stack per call, and cooperative threads carry only 512 KB, so without it an async print loop pays a thread round trip per printed symbol.

**Never start an unstructured `Task {}` inside a wrapped entry point**: SE-0417 means it does not inherit the preference (child tasks and default actors do). Nesting is a no-op, and below macOS 15 / iOS 18 the body runs unchanged. [LargeStackTaskExecutorAdoption.md](Documentations/Internal/LargeStackTaskExecutorAdoption.md).

Cross-version work is parallel because versions are different files; **intra-version parallelism is not safe** — MachOKit's `MachOFile` reads share one `FileHandle` (seek + read) and `index(in:)`'s guard is a plain check-then-set.

</important>

<important if="you are writing documentation, or finishing any non-trivial batch of work">

**Documentation is a first-class deliverable and ships in the same push as the code.** Judge explicitly whether docs need syncing every time, and say so in the summary even when the answer is no.

All docs live in `Documentations/`, split by audience ([Documentations/README.md](Documentations/README.md) is the index — update it when adding or moving one):

- **`Documentations/` top level** — external/public reference, English or bilingual (`*_zh.md` companion).
- **`Documentations/Internal/`** — maintainer-facing notes, Chinese, **PascalCase** filenames; the default home for working docs. `Internal/Modules/` is the per-module reference series (one module per file, linking to topic docs rather than restating them), `Internal/TaskReports/` the dated per-task retrospectives (`YYYY-MM-DD-<slug>.md`).
- **`Documentations/Evolutions/`** — one proposal per change, `NNNN-kebab-case-slug.md`, Chinese, status machine. **Numbers are assigned at landing** (`draft-<slug>.md` until then); implementation must not start before `Accepted`, and status updates land in the code's own commit.
- **[ProjectEvolutionLog.md](Documentations/Internal/ProjectEvolutionLog.md)** — the chronological ledger; append or update a section every non-trivial batch. **[Glossary.md](Documentations/Glossary.md)** — project-coined terms, registered in the batch that introduces them. **`Changelogs/<version>.md`** — English, per release, when `Version.swift` is bumped and tagged.

Keeping this file's module list and `Documentations/README.md`'s index in sync with the code is part of the same discipline. **Detail belongs in `Documentations/`, not in this file** — what earns a place here is a default an agent gets wrong, not a fact it can look up.

</important>

## Work in progress

**GenericSpecializer** (`Sources/SwiftSpecialization/`) — interactive runtime specialization of generic types. Core implementation complete with tests. Two-step API: `makeRequest()` returns parameters and candidates, `specialize()` executes with the user's selections. Only protocol requirements need witness tables, passed in requirement order; `baseClass` / `layout` / `sameType` need validation only. Generic parameter names are derived from depth/index (A, B, A1, …) because the binary does not preserve them.
