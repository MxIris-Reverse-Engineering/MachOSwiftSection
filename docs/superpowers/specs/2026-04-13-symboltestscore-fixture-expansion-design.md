# SymbolTestsCore Fixture Expansion Design

**Date:** 2026-04-13
**Branch:** feature/vtable-offset-and-member-ordering
**Scope:** Expand the SymbolTestsCore test fixture with 44 new Swift source files and 4 additions to existing files, producing broader coverage of Swift mangling patterns and `__swift5_*` metadata shapes consumable by the MachOSwiftSection parser.

## Goal

`SymbolTestsCore` is compiled as a framework and then loaded by `SwiftInterfaceTests` as a Mach-O fixture. Each declaration in `SymbolTestsCore` exists to produce distinctive mangled symbols and Swift metadata descriptors that exercise the parsing pipeline end-to-end (MachOSwiftSection → SwiftDump → SwiftInterface).

The current 18 files already cover a good baseline (structs, classes, enums, protocols, generics, actors, opaque return types, noncopyable types, etc.), but there are significant gaps around:

- Swift features that produce distinctive mangling (KeyPaths, Typealiases, Default arguments, Property observers, Codable synthesis, etc.)
- Binary-layer metadata variants that MachOSwiftSection directly parses (`__swift5_fieldmd`, VTable entries, generic requirement kinds, conditional conformance, default implementations, etc.)

This design adds 44 new Swift source files plus 4 edits to existing files. No new test cases in `Tests/SwiftInterfaceTests/` are required — existing E2E/Integration tests are value-based and tolerant of new declarations. The fixture itself is the deliverable; assertions can be layered on in follow-up PRs if desired.

## Non-Goals

- No additions to the `SymbolTests`, `SymbolTestsHelper`, or `Tests/SwiftInterfaceTests/` targets.
- No new integration/E2E test assertions in this scope (follow-up).
- No changes to `SwiftInterfaceBuilder`, `SwiftInterfaceIndexer`, or other parsing code.
- No macros or C++ interop (would require additional target config).

## Constraints

- Each file must be a `public enum` namespace (matching existing style) with only `public` declarations inside, so the binary always exposes them.
- Must compile with Swift 6.2 / Xcode 26 targets.
- `SymbolTestsCore.xcodeproj` uses `PBXFileSystemSynchronizedRootGroup` — new `.swift` files dropped into `Tests/Projects/SymbolTests/SymbolTestsCore/` are automatically picked up, **no `project.pbxproj` modification is required**.
- Files must not collide with or shadow existing type names (`StructTest`, `ClassTest`, `EnumTest`, etc.).
- Avoid private Swift compiler attributes (`@_` prefix) except where already used in existing files (`@_originallyDefinedIn`, `@_hasStorage` only if necessary).

## File Index (44 new files)

### Category 1 — General Swift Features (files 1–24)

| # | File | Produced mangling / metadata |
|---|------|------------------------------|
| 1 | `KeyPaths.swift` | `KeyPath<T,V>`, `WritableKeyPath`, `ReferenceWritableKeyPath`, `PartialKeyPath`, `AnyKeyPath` as stored fields; `\Type.prop` literal in stored closures |
| 2 | `Typealiases.swift` | Generic typealias, nested typealias, function-type typealias, constrained typealias |
| 3 | `Extensions.swift` | Dedicated `where`-clause conditional extensions, multi-constraint extensions, cross-protocol default implementations |
| 4 | `DefaultArguments.swift` | Default argument generator symbols (`fA_` / `fA0_`) on methods, initializers, subscripts |
| 5 | `PropertyObservers.swift` | `willSet`/`didSet` witness functions; `oldValue`/`newValue` captures |
| 6 | `Initializers.swift` | `convenience`, `required`, `init?`, `init!`, `init throws(E)`, `init() async`, `init() async throws(E)` |
| 7 | `Codable.swift` | Synthesized `init(from:)`, `encode(to:)`, nested `CodingKeys` enum; custom implementations too |
| 8 | `AccessLevels.swift` | `package`, `fileprivate`, `open`, nested access-level variation |
| 9 | `Availability.swift` | `@available` multi-platform, `deprecated`, `unavailable`, `renamed`, `message` |
| 10 | `DistributedActors.swift` | `distributed actor`, `distributed func`, `nonisolated distributed`, `ActorSystem` typealias |
| 11 | `StringInterpolation.swift` | `ExpressibleByStringInterpolation`, custom `StringInterpolationProtocol` |
| 12 | `NestedGenerics.swift` | Deeply nested generic types + conditional nested types + generic typealias inside generics |
| 13 | `Tuples.swift` | Named/unnamed/nested tuples as parameters, return types, fields |
| 14 | `FunctionTypes.swift` | Higher-order signatures, function references, curried functions, method references |
| 15 | `NestedFunctions.swift` | Function-local functions and local types (`_LXXX` local-symbol mangling) |
| 16 | `MetatypeUsage.swift` | `T.Type`, `Type.self`, `any Proto.Type`, `type(of:)` exposure |
| 17 | `ExistentialAny.swift` | `any Proto`, `any Proto & Sendable`, `[any Proto]`, `(any Proto) -> Void` |
| 18 | `SameTypeRequirements.swift` | `where A == B.Element`, `where A.Element == B.Element`, complex same-type chains |
| 19 | `OptionSetAndRawRepresentable.swift` | `OptionSet` and custom `RawRepresentable` synthesis |
| 20 | `DiamondInheritance.swift` | Protocol diamond inheritance, multi-inheritance PWT layout |
| 21 | `WeakUnownedReferences.swift` | `weak`, `unowned`, `unowned(safe)`, `unowned(unsafe)` |
| 22 | `ErrorTypes.swift` | Error enums + `LocalizedError` + `CustomNSError` + `Sendable` Error |
| 23 | `ResultBuilderDSL.swift` | Full result builder (`buildBlock`, `buildOptional`, `buildEither(first:)`, `buildEither(second:)`, `buildArray`, `buildIf`, `buildLimitedAvailability`, `buildFinalResult`, `buildExpression`) |
| 24 | `RethrowingFunctions.swift` | `rethrows`, `async rethrows`, conditional-throws combinations |

### Category 2 — Extended Swift Features (files 25–36)

| # | File | Produced mangling / metadata |
|---|------|------------------------------|
| 25 | `ProtocolComposition.swift` | `A & B & C`, `AnyObject & Proto`, `Sendable & Proto` composition types |
| 26 | `OverloadedMembers.swift` | Same-name different-signature methods, subscripts, initializers |
| 27 | `UnsafePointers.swift` | `UnsafePointer`, `UnsafeMutablePointer`, `OpaquePointer`, `Unmanaged`, `AutoreleasingUnsafeMutablePointer` |
| 28 | `AsyncSequence.swift` | Custom `AsyncSequence` and `AsyncIteratorProtocol` implementations |
| 29 | `PropertyWrapperVariants.swift` | Property wrapper with `projectedValue`, with `init()`, with `static subscript` |
| 30 | `CustomLiterals.swift` | `ExpressibleByIntegerLiteral`, `ByStringLiteral`, `ByArrayLiteral`, `ByDictionaryLiteral` |
| 31 | `StaticMembers.swift` | `static` vs `class` members, static subscripts, static stored/computed |
| 32 | `ClassBoundGenerics.swift` | `T: AnyObject`, `where T: AnyObject & Proto`, complete class-bound combinations |
| 33 | `MarkerProtocols.swift` | Protocols with no requirements (marker protocol style) |
| 34 | `DependentTypeAccess.swift` | `T.Element.Index`, `Self.Iterator.Element`, deeply-chained dependent type access |
| 35 | `DeinitVariants.swift` | `class`/`actor` `deinit`, `isolated deinit` (Swift 6.0+) |
| 36 | `CollectionConformances.swift` | Custom `Collection`, `Sequence`, `BidirectionalCollection` implementations |

### Category 3 — Binary Metadata Variants (files 37–44)

These files are specifically designed to exercise `__swift5_*` section parsing shapes consumed by MachOSwiftSection.

| # | File | Target section / descriptor |
|---|------|------------------------------|
| 37 | `FieldDescriptorVariants.swift` | `__swift5_fieldmd` — `var`/`let`/`weak`/`unowned` fields, mangled-type-name variants, generic payload fields |
| 38 | `GenericRequirementVariants.swift` | `TargetGenericRequirementDescriptor` — full coverage of `Protocol` / `SameType` / `BaseClass` / `Layout` / `SameConformance` / `SameShape` / `InvertibleProtocol` requirement kinds (the last via `~Copyable` / `~Escapable`) |
| 39 | `VTableEntryVariants.swift` | Class `VTableDescriptorHeader` — virtual / override / final / async / throws / mutating entry flags |
| 40 | `ConditionalConformanceVariants.swift` | `__swift5_proto` with conditional requirement table — multi-constraint witness-table patterns |
| 41 | `DefaultImplementationVariants.swift` | `__swift5_protos` default-implementation extensions — constrained (`where Self:`) default implementations |
| 42 | `FrozenResilienceContrast.swift` | `TargetTypeContextDescriptorFlags` — identical field layouts as `@frozen` vs default resilient, to contrast descriptor shape |
| 43 | `AssociatedTypeWitnessPatterns.swift` | `__swift5_assocty` — 5 witness patterns: concrete type, nested type, typealias, recursive, dependent-on-another-AT |
| 44 | `BuiltinTypeFields.swift` | `__swift5_builtin` (indirect) — fields of `Int`/`Float`/`Double`/`Bool`/`UInt8`/`Int64`/tuples |

## Edits to Existing Files (not new files)

| File | Additions |
|------|-----------|
| `Classes.swift` | `required init`, method default arguments, `class func` |
| `Enums.swift` | Large `@frozen` enum, generic payload enum, case-as-function-reference |
| `FunctionFeatures.swift` | `@MainActor` closure parameter, function default arguments |
| `Protocols.swift` | `where Self:` constraint on requirement, multi primary-associated-type protocol |

## File Template / Style

All new files follow the existing namespace-enum style:

```swift
import Foundation // only when needed

public enum Feature {
    // Types nested inside the namespace
    public struct SomeTest {
        public var field: Int
        public init(field: Int) { self.field = field }
    }
}
```

- **Always use** `public enum <Feature>` as the outer namespace.
- **Never** introduce top-level types outside the namespace enum (to avoid colliding with existing top-level `TestsValues` in `BasicTypes.swift`).
- **Always** use full descriptive variable names (per project coding standard).
- **Always** use `public` for every nested declaration (so descriptors emit to the binary).
- **Do not** import modules other than `Foundation` / `Distributed` / `Observation` unless required for a specific binding.
- **Do not** add initial-value logic with side effects; prefer `fatalError()` where runtime behavior is irrelevant (the fixture is never run).

## Build Validation

After writing all files, the fixture must be rebuilt so downstream tests observe the new symbols:

```bash
xcodebuild \
  -project Tests/Projects/SymbolTests/SymbolTests.xcodeproj \
  -scheme SymbolTests \
  -configuration Release \
  -derivedDataPath Tests/Projects/SymbolTests/DerivedData \
  build 2>&1 | xcsift
```

Success criterion: the Xcode build succeeds, and `swift test --filter SymbolTestsCoreE2ETests` still passes without regression. A single failing compile in a new file should not cascade to block the rest — each file is independent and can be fixed in isolation.

## Risks and Mitigations

1. **Compiler-version-specific syntax.** `distributed actor` requires `import Distributed`; `isolated deinit` requires Swift 6.0+. Mitigation: target Swift 6.2 explicitly per `CLAUDE.md`; if any syntax proves unsupported, omit that specific construct from the file and document it in a comment.
2. **Name collisions.** A new type with the same name as an existing type in another namespace could confuse indexer tests that use `hasSuffix` lookups. Mitigation: prefix new type names with their feature namespace where ambiguity is possible (e.g., `KeyPathTest` not `Test`).
3. **Symbol-free declarations.** Some Swift constructs (local type aliases inside function bodies, purely-generic phantom types) may not appear in `__swift5_*` sections. Mitigation: each new file exposes at least one top-level `public` declaration guaranteed to emit a type descriptor.
4. **Excessive file growth.** 44 new files is a large diff. Mitigation: each file is self-contained and ~20–60 lines; the total line addition is bounded at ~2000 lines.
5. **Existing assertions breakage.** Some E2E tests check that certain type names are present, but none check that the total count matches a specific number. Mitigation: verify by running the full `SwiftInterfaceTests` suite after the fixture rebuild.
