# CI Snapshot Testing Design

## Overview

Snapshot tests on CI are driven **only** by the `SymbolTestsCore` framework built from `Tests/Projects/SymbolTests/SymbolTests.xcodeproj`. Snapshots for system dyld cache images and bundled Xcode frameworks are explicitly **out of scope** because the binaries they depend on drift across macOS / Xcode updates and cannot be reproduced by a CI runner.

Coverage requirement: every source file in `Tests/Projects/SymbolTests/SymbolTestsCore/` (one file per Swift language / ABI feature category) must have a dedicated snapshot that fails when that category's emitted metadata changes.

## Why only SymbolTestsCore

| Source | Reproducible on CI? | Dimensions of drift |
|---|---|---|
| System dyld cache (`.current`) | No — contents change with every macOS patch | macOS version, kernel/cache layout, framework updates |
| Xcode bundled frameworks | No — change with every Xcode release | Xcode version, swiftlang version |
| `SymbolTestsCore` (checked-in Swift sources) | **Yes** — built from pinned source with pinned Xcode | Only the pinned Xcode/swiftlang version |

Collapsing the problem to a single deterministic source means:
- Snapshots live in the main repo under `Tests/**/Snapshots/__Snapshots__/` and are committed alongside source changes.
- No external fixtures package, no version-keyed directories, no auto-recording workflow.
- A snapshot diff is a direct signal: "the metadata this library emits for a given Swift construct just changed."

## Architecture

```
MachOSwiftSection (main repo)
    │
    ├── Tests/Projects/SymbolTests/
    │       ├── SymbolTests.xcodeproj            (3 targets)
    │       ├── SymbolTestsCore/*.swift          (feature categories — the fixture source)
    │       ├── SymbolTestsHelper/*.swift        (support types referenced by SymbolTestsCore)
    │       └── DerivedData/.../Release/
    │               └── SymbolTestsCore.framework/Versions/A/SymbolTestsCore   ← the Mach-O binary
    │
    └── Tests/
        ├── SwiftDumpTests/Snapshots/
        │   ├── SymbolTestsCoreDumpSnapshotTests.swift
        │   └── __Snapshots__/SymbolTestsCoreDumpSnapshotTests/
        │       ├── actorsSnapshot.1.txt
        │       ├── enumsSnapshot.1.txt
        │       └── …                            (one file per category)
        └── SwiftInterfaceTests/Snapshots/
            ├── SymbolTestsCoreInterfaceSnapshotTests.swift
            └── __Snapshots__/SymbolTestsCoreInterfaceSnapshotTests/
                └── interfaceSnapshot.1.txt      (single full-module interface)
```

## Building the Fixture Binary

`SymbolTestsCore.framework` is an Xcode-project artifact, so `swift test` alone cannot produce it. CI (and any fresh developer checkout) must build it first.

**Pre-test step added to `macOS.yml`:**

```bash
xcodebuild \
  -project Tests/Projects/SymbolTests/SymbolTests.xcodeproj \
  -scheme SymbolTestsCore \
  -configuration Release \
  -derivedDataPath Tests/Projects/SymbolTests/DerivedData \
  -destination 'generic/platform=macOS' \
  build
```

### Path anchoring — how tests locate the binary

`MachOFileName.SymbolTestsCore` stores a **relative path**: `../../Tests/Projects/SymbolTests/DerivedData/SymbolTests/Build/Products/Release/SymbolTestsCore.framework/Versions/A/SymbolTestsCore`.

That path is **not** resolved against the current working directory. `MachOTestingSupport/Extensions.swift::loadFromFile(named:)` resolves it against `#filePath` of that source file, i.e. `Sources/MachOTestingSupport/Extensions.swift`. `../../` therefore climbs out of `Sources/MachOTestingSupport/` and lands at the repository root, then descends into `Tests/Projects/SymbolTests/DerivedData/…`.

Consequences:
- The `xcodebuild -derivedDataPath Tests/Projects/SymbolTests/DerivedData` argument is interpreted by `xcodebuild` relative to **its own CWD**, which must be the repo root when the workflow step runs (GitHub Actions' default working directory is the checkout root, so this lines up with the runtime lookup).
- The two paths agree **because both end up pointing at `<repo root>/Tests/Projects/SymbolTests/DerivedData/…`** — one via `#filePath`-relative resolution at runtime, the other via CWD-relative resolution at build time. Any CI step that runs `xcodebuild` from a different CWD (e.g. inside `Tests/Projects/SymbolTests/`) will break the alignment.

### Implicit dependency

`SymbolTests.xcscheme` declares `buildImplicitDependencies = "YES"`, so building the `SymbolTestsCore` target transitively produces `SymbolTestsHelper.framework`. The runtime dynamic-link search path inside `SymbolTestsCore` already includes `@rpath`, and both frameworks end up in the same `Build/Products/Release/` directory, so no extra `DYLD_FRAMEWORK_PATH` plumbing is needed.

### Other notes

- The scheme list is visible in `Tests/Projects/SymbolTests/SymbolTests.xcodeproj/xcshareddata/xcschemes/` — `SymbolTestsCore.xcscheme` is already a shared scheme and therefore available to headless `xcodebuild`.
- `-destination 'generic/platform=macOS'` avoids picking a concrete simulator. `MachOFileTests` then selects `.arm64` via `preferredArchitecture`; GitHub's `macos-15` runners are Apple Silicon so the preferred slice exists.
- Cache the `DerivedData` directory in the workflow to avoid a full rebuild on every run (see `macOS.yml` outline below).
- Do **not** pipe `xcodebuild` through `xcsift` on CI — `xcsift` is a local convenience and is not installed on GitHub-hosted runners. If the raw log is too noisy, use `-quiet` instead.

## Test Architecture

### Namespace-filtered collectors

49 of the 54 `SymbolTestsCore/*.swift` files open with `public enum <Filename> { … }`, making the top-level enum name match the file name and therefore also the `@Test func <lowercasedFirst>Snapshot()` handler. Five files deviate:

- `AsyncSequence.swift` / `Codable.swift` / `StringInterpolation.swift` — the enum name differs from the filename (`AsyncSequenceTests`, `CodableTests`, `StringInterpolations`) to avoid stdlib-type collisions (`Swift.AsyncSequence`, `Swift.Codable`, `String.StringInterpolation`). Their snapshot tests pass the real enum name as `inNamespace:` while keeping the `@Test func` named after the filename.
- `GlobalDeclarations.swift` — no `TypeContextDescriptor` emitted. Handled as an edge case; per-category dump is expected empty.
- `NeverExtensions.swift` — all declarations are `extension Never: …`; descriptors belong to `Swift.Never`, so a mangled-symbol fallback matches any `$ss5NeverO*`-stem symbol in the conforming-type reference (i.e. `_$ss5NeverO*` as it appears in the Mach-O symbol table, where the leading `_` is the C-style symbol-name prefix).

See "Edge-case categories" below for the `GlobalDeclarations.swift` / `NeverExtensions.swift` details.

Add to `MachOTestingSupport/SnapshotDumpableTests.swift`:

```swift
extension SnapshotDumpableTests {
    /// Walks the parent chain of a type context descriptor wrapper and returns the name of
    /// the top-level enclosing type (the category namespace), or nil if the symbol lives
    /// at module scope — in which case it should be considered part of the
    /// "GlobalDeclarations" bucket by the caller.
    package func rootNamespace<MachO: MachOSwiftSectionRepresentableWithCache>(
        of descriptor: TypeContextDescriptorWrapper,
        in machO: MachO
    ) throws -> String?

    /// Same as above but keyed on a ProtocolDescriptor (used when filtering the
    /// protocols / associatedTypes sections).
    package func rootNamespace<MachO: MachOSwiftSectionRepresentableWithCache>(
        of descriptor: ProtocolDescriptor,
        in machO: MachO
    ) throws -> String?

    /// Category-filtered variants of the existing collect* methods. Each first enumerates
    /// the full descriptor list and keeps only entries whose rootNamespace matches `category`.
    package func collectDumpTypes<MachO: MachOSwiftSectionRepresentableWithCache>(
        for machO: MachO,
        inNamespace category: String,
        options: DumpableTypeOptions = [.enum, .struct, .class]
    ) async throws -> String
    package func collectDumpProtocols<MachO: MachOSwiftSectionRepresentableWithCache>(
        for machO: MachO,
        inNamespace category: String
    ) async throws -> String
    package func collectDumpProtocolConformances<MachO: MachOSwiftSectionRepresentableWithCache>(
        for machO: MachO,
        inNamespace category: String
    ) async throws -> String
    package func collectDumpAssociatedTypes<MachO: MachOSwiftSectionRepresentableWithCache>(
        for machO: MachO,
        inNamespace category: String
    ) async throws -> String

    /// Combined per-category dump used by the snapshot tests. Concatenates the four
    /// sections with `// MARK:` headers; omits sections whose filtered output is empty.
    package func collectDump<MachO: MachOSwiftSectionRepresentableWithCache>(
        for machO: MachO,
        inNamespace category: String
    ) async throws -> String
}
```

Note the parameter types: the existing `collect*` implementations in the codebase take `TypeContextDescriptorWrapper` (an enum of `.enum`/`.struct`/`.class`) for types and a `ProtocolDescriptor` for protocols. The namespace filter therefore branches on the descriptor flavour rather than using one generic `TypeContextDescriptorProtocol`.

The combined `collectDump(for:inNamespace:)` is the primary entry point used by snapshot tests; individual collectors remain available for targeted assertions.

### ProtocolConformance attribution

A `ProtocolConformanceDescriptor` binds a *conforming type* to a *protocol*. Both sides have a namespace. The filter uses the **conforming type's** root namespace:

- `extension Extensions.ExtensionConstrainedStruct: Extensions.ExtensionProtocol` → both sides live under `Extensions`, no ambiguity.
- `extension Never: Protocols.ProtocolTest` (from `NeverExtensions.swift`) → conforming type is `Swift.Never`, root namespace is therefore **not** `NeverExtensions`. Handled by the edge-case rule below, not by the default filter.

Rationale: attributing a conformance to the conforming type follows the same convention used when browsing the dump output — one instance of the type's metadata gathers all the conformances declared for it.

### Edge-case categories

| File | Why it doesn't fit | How its snapshot is produced |
|---|---|---|
| `GlobalDeclarations.swift` | Declares only `public let / var / func` — no TypeContextDescriptor is emitted. | The per-category dump is intentionally empty. Coverage for globals comes from the full-module **interface** snapshot (where globals are printed). The `@Test func globalDeclarationsSnapshot()` still exists and asserts against the empty (or near-empty) combined output — a diff would surface unexpected new TypeContextDescriptor emissions for globals. |
| `NeverExtensions.swift` | All declarations are `extension Never: …`; descriptors live under `Swift.Never`, not a `NeverExtensions` namespace. | The filter takes a fallback list: `ProtocolConformanceDescriptor`s whose conforming type is `Swift.Never` are attributed to the `NeverExtensions` bucket. Implementation: `collectDumpProtocolConformances(for:inNamespace: "NeverExtensions")` switches to the explicit Never-based predicate. This is the only category with a non-namespace attribution rule. |

If another fixture file is ever added that doesn't use the `public enum <Category>` pattern, it must either be rewritten to fit the pattern or added as a new edge case here (and to the coverage-invariant test).

### Dump snapshot suite

One suite, one `@Test` per category. The whole class is a mechanical mapping from the file list.

```swift
@Suite(.serialized, .snapshots(record: .missing))
final class SymbolTestsCoreDumpSnapshotTests: MachOFileTests, SnapshotDumpableTests, @unchecked Sendable {
    override class var fileName: MachOFileName { .SymbolTestsCore }

    @Test func actorsSnapshot() async throws {
        let output = try await collectDump(for: machOFile, inNamespace: "Actors")
        assertSnapshot(of: output, as: .lines)
    }

    @Test func associatedTypeWitnessPatternsSnapshot() async throws {
        let output = try await collectDump(for: machOFile, inNamespace: "AssociatedTypeWitnessPatterns")
        assertSnapshot(of: output, as: .lines)
    }

    // … one @Test per category, 54 total
}
```

### Interface snapshot suite

`SwiftInterfaceBuilder` emits the whole module at once; splitting by namespace would require new builder plumbing that isn't justified for this fixture. Keep a single snapshot per module:

```swift
@Suite(.serialized, .snapshots(record: .missing))
final class SymbolTestsCoreInterfaceSnapshotTests: MachOFileTests, SnapshotInterfaceTests, @unchecked Sendable {
    override class var fileName: MachOFileName { .SymbolTestsCore }

    @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
    @Test func interfaceSnapshot() async throws {
        let output = try await collectInterfaceString(in: machOFile)
        assertSnapshot(of: output, as: .lines)
    }
}
```

The interface snapshot acts as an end-to-end regression check across every category simultaneously. When it breaks, the corresponding per-category dump snapshot usually points at the root cause.

## CI Workflow Changes

### `macOS.yml` — full job outline

```yaml
jobs:
  macos_test:
    runs-on: ${{ matrix.os }}
    strategy:
      fail-fast: false
      matrix:
        os: [macos-15]
        xcode-version: ["16.3"]
    env:
      MACHO_SWIFT_SECTION_SILENT_TEST: 1
      GH_TOKEN: ${{ github.token }}
    steps:
      - uses: actions/checkout@v4
      - uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: ${{ matrix.xcode-version }}

      - name: Resolve SPM dependencies
        run: swift package update

      - name: Cache SymbolTests DerivedData
        uses: actions/cache@v4
        with:
          path: Tests/Projects/SymbolTests/DerivedData
          key: symboltests-${{ matrix.xcode-version }}-${{ hashFiles('Tests/Projects/SymbolTests/**/*.swift', 'Tests/Projects/SymbolTests/**/*.pbxproj') }}

      - name: Build SymbolTestsCore fixture
        working-directory: ${{ github.workspace }}
        run: |
          set -o pipefail
          xcodebuild \
            -project Tests/Projects/SymbolTests/SymbolTests.xcodeproj \
            -scheme SymbolTestsCore \
            -configuration Release \
            -derivedDataPath Tests/Projects/SymbolTests/DerivedData \
            -destination 'generic/platform=macOS' \
            -quiet \
            build

      - name: Upload xcodebuild logs on failure
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: symboltests-derived-data-logs
          path: Tests/Projects/SymbolTests/DerivedData/Logs
          if-no-files-found: ignore

      - name: Swift test (debug)
        run: swift test -c debug --build-path .build-test-debug

      - name: Swift test (release)
        run: swift test -c release --build-path .build-test-release
```

Key points:
- `swift package update` runs before `swift test` per the project-level SPM workflow convention; otherwise stale `.build/checkouts/` can cause hard-to-diagnose resolution failures.
- `working-directory: ${{ github.workspace }}` is explicit on the fixture-build step so the `../../`-anchored path stays aligned with the `#filePath`-based runtime lookup (see "Path anchoring" above).
- `-quiet` keeps the `xcodebuild` output compact without relying on `xcsift` (which is not installed on GitHub-hosted runners).
- `set -o pipefail` ensures a failed `xcodebuild` fails the step even if something is piped later.
- The cache key hashes both the SymbolTestsCore source files and `project.pbxproj` so any change invalidates the cache.
- The upload-logs step runs only on failure and is tolerant of missing directories, which keeps happy-path runs uncluttered.

### No recording workflow

With deterministic snapshots, there is no `snapshot-record.yml`. When a Swift compiler change legitimately alters emitted metadata, the developer regenerates snapshots locally:

```bash
SNAPSHOT_TESTING_RECORD=all swift test \
    --filter SymbolTestsCoreDumpSnapshotTests \
    --filter SymbolTestsCoreInterfaceSnapshotTests
```

`swift test --filter` takes a substring matched against the test identifier and accepts multiple occurrences. Using the two concrete class names (rather than a regex) avoids ambiguity and will not accidentally pick up unrelated suites. Updated `__Snapshots__/` files get committed in the same PR as the triggering source change.

## Coverage Matrix

Every row below must have (a) a dedicated `@Test func <category>Snapshot()` in `SymbolTestsCoreDumpSnapshotTests` and (b) at least one type / protocol / conformance / associated type visible in the combined dump output (otherwise the category's source file is suspect).

Unless a row in the "Dump snapshot" column explicitly annotates a `namespace:`, the `inNamespace:` argument passed by the corresponding `@Test` is the filename (without the `.swift` extension). The three annotated rows (`AsyncSequence.swift`, `Codable.swift`, `StringInterpolation.swift`) deviate because their top-level `public enum` uses a different identifier to avoid colliding with stdlib types — see "Namespace-filtered collectors" above.

| # | Category source file | Dump snapshot | Appears in interface |
|---|---|---|---|
| 1 | Actors.swift | `actorsSnapshot` | yes |
| 2 | AssociatedTypeWitnessPatterns.swift | `associatedTypeWitnessPatternsSnapshot` | yes |
| 3 | AsyncSequence.swift | `asyncSequenceSnapshot` (namespace: `AsyncSequenceTests`) | yes |
| 4 | Attributes.swift | `attributesSnapshot` | yes |
| 5 | BasicTypes.swift | `basicTypesSnapshot` | yes |
| 6 | BuiltinTypeFields.swift | `builtinTypeFieldsSnapshot` | yes |
| 7 | ClassBoundGenerics.swift | `classBoundGenericsSnapshot` | yes |
| 8 | Classes.swift | `classesSnapshot` | yes |
| 9 | Codable.swift | `codableSnapshot` (namespace: `CodableTests`) | yes |
| 10 | CollectionConformances.swift | `collectionConformancesSnapshot` | yes |
| 11 | Concurrency.swift | `concurrencySnapshot` | yes |
| 12 | ConditionalConformanceVariants.swift | `conditionalConformanceVariantsSnapshot` | yes |
| 13 | CustomLiterals.swift | `customLiteralsSnapshot` | yes |
| 14 | DefaultImplementationVariants.swift | `defaultImplementationVariantsSnapshot` | yes |
| 15 | DeinitVariants.swift | `deinitVariantsSnapshot` | yes |
| 16 | DependentTypeAccess.swift | `dependentTypeAccessSnapshot` | yes |
| 17 | DiamondInheritance.swift | `diamondInheritanceSnapshot` | yes |
| 18 | DistributedActors.swift | `distributedActorsSnapshot` | yes |
| 19 | Enums.swift | `enumsSnapshot` | yes |
| 20 | ErrorTypes.swift | `errorTypesSnapshot` | yes |
| 21 | ExistentialAny.swift | `existentialAnySnapshot` | yes |
| 22 | Extensions.swift | `extensionsSnapshot` | yes |
| 23 | FieldDescriptorVariants.swift | `fieldDescriptorVariantsSnapshot` | yes |
| 24 | FunctionFeatures.swift | `functionFeaturesSnapshot` | yes |
| 25 | FunctionTypes.swift | `functionTypesSnapshot` | yes |
| 26 | GenericFieldLayout.swift | `genericFieldLayoutSnapshot` | yes |
| 27 | GenericRequirementVariants.swift | `genericRequirementVariantsSnapshot` | yes |
| 28 | Generics.swift | `genericsSnapshot` | yes |
| 29 | GlobalDeclarations.swift | `globalDeclarationsSnapshot` | yes |
| 30 | Initializers.swift | `initializersSnapshot` | yes |
| 31 | KeyPaths.swift | `keyPathsSnapshot` | yes |
| 32 | MarkerProtocols.swift | `markerProtocolsSnapshot` | yes |
| 33 | MetatypeUsage.swift | `metatypeUsageSnapshot` | yes |
| 34 | NestedFunctions.swift | `nestedFunctionsSnapshot` | yes |
| 35 | NestedGenerics.swift | `nestedGenericsSnapshot` | yes |
| 36 | NeverExtensions.swift | `neverExtensionsSnapshot` | yes |
| 37 | Noncopyable.swift | `noncopyableSnapshot` | yes |
| 38 | OpaqueReturnTypes.swift | `opaqueReturnTypesSnapshot` | yes |
| 39 | Operators.swift | `operatorsSnapshot` | yes |
| 40 | OptionSetAndRawRepresentable.swift | `optionSetAndRawRepresentableSnapshot` | yes |
| 41 | OverloadedMembers.swift | `overloadedMembersSnapshot` | yes |
| 42 | PropertyWrapperVariants.swift | `propertyWrapperVariantsSnapshot` | yes |
| 43 | ProtocolComposition.swift | `protocolCompositionSnapshot` | yes |
| 44 | Protocols.swift | `protocolsSnapshot` | yes |
| 45 | ResultBuilderDSL.swift | `resultBuilderDSLSnapshot` | yes |
| 46 | SameTypeRequirements.swift | `sameTypeRequirementsSnapshot` | yes |
| 47 | StaticMembers.swift | `staticMembersSnapshot` | yes |
| 48 | StringInterpolation.swift | `stringInterpolationSnapshot` (namespace: `StringInterpolations`) | yes |
| 49 | Structs.swift | `structsSnapshot` | yes |
| 50 | Subscripts.swift | `subscriptsSnapshot` | yes |
| 51 | Tuples.swift | `tuplesSnapshot` | yes |
| 52 | UnsafePointers.swift | `unsafePointersSnapshot` | yes |
| 53 | VTableEntryVariants.swift | `vTableEntryVariantsSnapshot` | yes |
| 54 | WeakUnownedReferences.swift | `weakUnownedReferencesSnapshot` | yes |

Total: 54 per-category dump snapshots + 1 full-module interface snapshot = **55 files** under `__Snapshots__/`.

### Coverage invariant

Completeness is enforced by a dedicated Swift test (not a shell step) so it runs in the same `swift test` invocation as the snapshot tests themselves — contributors get the failure locally before pushing. Skeleton:

```swift
// Tests/SwiftDumpTests/Snapshots/SymbolTestsCoreCoverageInvariantTests.swift
import Foundation
import Testing
@testable import MachOTestingSupport

@Suite
struct SymbolTestsCoreCoverageInvariantTests {
    /// `@Test` method names declared on SymbolTestsCoreDumpSnapshotTests that intentionally
    /// have no backing category source file (edge-case shims, if any).
    private static let allowlist: Set<String> = []

    @Test func everyCategoryHasASnapshotTest() throws {
        let fixtureDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Snapshots/
            .deletingLastPathComponent()   // SwiftDumpTests/
            .deletingLastPathComponent()   // Tests/
            .appendingPathComponent("Tests/Projects/SymbolTests/SymbolTestsCore")

        let categories = try FileManager.default
            .contentsOfDirectory(at: fixtureDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()

        let expectedMethods = Set(categories.map { "\($0.lowercasedFirst)Snapshot" })
        let actualMethods = SymbolTestsCoreDumpSnapshotTests.registeredTestMethodNames

        let missing = expectedMethods.subtracting(actualMethods).subtracting(Self.allowlist)
        #expect(missing.isEmpty, "Missing per-category snapshot tests: \(missing.sorted())")
    }
}
```

Implementation notes:
- `SymbolTestsCoreDumpSnapshotTests.registeredTestMethodNames` is a `static let` populated at type-load time; it can be as simple as a hand-maintained array — the coverage test fails loudly if it drifts from the filesystem.
- `lowercasedFirst` lowercases the leading character so `Actors.swift` → `actorsSnapshot`, matching the `@Test func` naming in the dump suite.
- Running the check from a Swift test keeps it platform-agnostic and reusable for local development.
- The `allowlist` is there for safety: if a SymbolTestsCore file is ever renamed or split, the invariant shouldn't block an otherwise-valid PR while the migration is in flight.

## Cleanup

Remove the DSC- and Xcode-sourced snapshot tests and their snapshots:

- Delete classes:
  - `Tests/SwiftDumpTests/Snapshots/DyldCacheDumpSnapshotTests.swift`
  - `Tests/SwiftDumpTests/Snapshots/XcodeMachOFileDumpSnapshotTests.swift`
  - `Tests/SwiftInterfaceTests/Snapshots/DyldCacheInterfaceSnapshotTests.swift`
  - `Tests/SwiftInterfaceTests/Snapshots/XcodeMachOFileInterfaceSnapshotTests.swift`
- Delete the corresponding `__Snapshots__/` directories of those four classes.
- Rename the existing `MachOFileDumpSnapshotTests` → `SymbolTestsCoreDumpSnapshotTests` (same with the interface counterpart); migrate the old single `typesSnapshot/protocolsSnapshot/…` snapshot files into the new per-category layout by regenerating once locally with `SNAPSHOT_TESTING_RECORD=all`.
- Leave `.gitignore` untouched — local `__Snapshots__` stay tracked, which is the desired behaviour.

## Migration Plan

1. **Add namespace-filtered collectors** in `MachOTestingSupport` (`SnapshotDumpableTests.swift`). No test changes yet; existing tests keep passing.
2. **Add CI build step** for `SymbolTestsCore.framework` plus the DerivedData cache. Verify `macOS.yml` is green with the current test set still in place.
3. **Introduce `SymbolTestsCoreDumpSnapshotTests`** with one `@Test` per category, run locally with `SNAPSHOT_TESTING_RECORD=all` to generate all 54 snapshot files, and commit them.
4. **Rename** `MachOFileInterfaceSnapshotTests` → `SymbolTestsCoreInterfaceSnapshotTests` (trivial; its existing single snapshot can stay).
5. **Delete** the DSC / Xcode snapshot classes and their `__Snapshots__` subdirectories.
6. **Add the coverage-invariant check** described above so future fixture additions fail CI until a matching snapshot test is registered.

## Reproducibility Notes

- **Swift compiler / swiftlang upgrades** may legitimately change emitted metadata. When that happens, regenerate snapshots locally per the "No recording workflow" section and commit the updated files as part of the Xcode-bump PR.
- **Pin the CI `xcode-version` explicitly** — never use `latest-stable`. Any bump is an intentional, reviewable change.
- **Section-layout order is linker-determined.** `machO.swift.typeContextDescriptors` returns descriptors in the order they appear in `__swift5_types`, and that order comes from `ld` / `ld-prime`. For a given Xcode + source combination it is stable; across Xcode updates it may shuffle. If ordering churn becomes a frequent source of snapshot diffs (i.e. linker changes dominate over metadata changes), consider sorting the output by mangled name before snapshotting — but keep the default "as-emitted" ordering until that noise shows up in practice, since it preserves more signal.
- **Architecture pinning.** `MachOFileTests.preferredArchitecture` is `.arm64`, and `macos-15` runners are Apple Silicon, so the `.arm64` slice is always what gets snapshotted. A matrix entry that added an Intel runner would produce a different binary and therefore a different snapshot — avoid doing that without separating the snapshots.
- **`MACHO_SWIFT_SECTION_SILENT_TEST=1`** stays set on CI to keep snapshot test output clean.

## Developer Bootstrap

For contributors running tests locally without Xcode preopened on the `SymbolTests` project:

```bash
# One-time (or whenever SymbolTestsCore/ sources change):
xcodebuild \
  -project Tests/Projects/SymbolTests/SymbolTests.xcodeproj \
  -scheme SymbolTestsCore \
  -configuration Release \
  -derivedDataPath Tests/Projects/SymbolTests/DerivedData \
  -destination 'generic/platform=macOS' \
  build

# Then the normal test flow:
swift package update
swift test
```

Package this into `Scripts/build-test-fixtures.sh` (a sibling of the existing `build-executable-product.sh`) so new contributors have a one-command entry point. The README's "Running tests" section should reference the script and explain that skipping it causes `MachOFileTests` to throw at `init()` with a "file not found" error at `Tests/Projects/SymbolTests/DerivedData/.../SymbolTestsCore`.
