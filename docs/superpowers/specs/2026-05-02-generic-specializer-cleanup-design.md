# GenericSpecializer Cleanup and API Polish

**Date:** 2026-05-02
**Status:** Approved, pending implementation
**Branch:** `feature/generic-specializer`

## Problem

`GenericSpecializer`'s main path — Type generic parameters, direct protocol
constraints, and multi-level associated-type witness tables — is functional
and covered by `Tests/SwiftInterfaceTests/GenericSpecializationTests.swift`.
A diff against the Swift Runtime ABI nevertheless surfaces several lightweight
gaps that hurt API quality without affecting current passing tests:

- `~Copyable` / `~Escapable` parameter capability declarations
  (`GenericRequirementKind.invertedProtocols`) are silently dropped:
  `buildRequirement` in
  `Sources/SwiftInterface/GenericSpecializer/GenericSpecializer.swift:265-268`
  returns `nil` for `.sameConformance`, `.sameShape`, and `.invertedProtocols`
  in one combined branch, so callers cannot tell whether a parameter allows
  non-Copyable types.
- `GenericContext` reads
  `conditionalInvertibleProtocolsRequirements`
  (`Sources/MachOSwiftSection/Models/Generic/GenericContext.swift:30`) but
  `GenericSpecializer.makeRequest` only consults `genericContext.allRequirements`,
  so any conditional requirement stored under that header is invisible to the
  specializer.
- A private helper `convertLayoutKind`
  (`GenericSpecializer.swift:272-277`) has no callers.
- `MetadataRequest` is hard-coded to `.completeAndBlocking` at
  `GenericSpecializer.swift:458`, leaving callers no way to request
  `.complete` or `.abstract` when needed (e.g. to avoid blocking inside
  recursive specialization).
- A generic `Candidate` (e.g. `Array`, `Optional`) cannot be resolved by
  `resolveCandidate` — line 516 calls
  `accessorFunction(request: .completeAndBlocking)` with no arguments, which
  is correct only for non-generic types. The resulting failure surfaces as a
  generic "Cannot get metadata accessor function" message, not as an
  actionable error directing the caller toward
  `Argument.specialized(...)` or nested specialization.
- The combined `case .sameConformance, .sameShape, .invertedProtocols`
  branch reads as "everything we don't support yet", but the three kinds have
  very different reasons for being skipped. The single-line comment makes
  future maintenance harder.

This document scopes a self-contained cleanup that surfaces missing
information, removes dead code, and improves error and request signatures.

## Goals

- Surface `~Copyable` / `~Escapable` parameter capability information on
  `SpecializationRequest.Parameter`.
- Include `conditionalInvertibleProtocolsRequirements` in the requirement set
  consumed by the specializer.
- Split `sameConformance` / `sameShape` / `invertedProtocols` into individual
  `case` arms with intent-revealing comments.
- Let callers pass a `MetadataRequest` to `specialize(...)`.
- Detect generic candidates eagerly in `resolveCandidate` and throw a typed,
  actionable error.
- Remove the unused `convertLayoutKind` helper.

## Non-Goals

- Variadic generic parameters (`each T`, `GenericParamKind.typePack`).
- Value generic parameters (`let N: Int`, `GenericParamKind.value`).
- `isPackRequirement` / `isValueRequirement` flag handling.
- `validate(...)` substantive validation (typed errors for `.protocol`,
  `.sameType`, `.baseClass`, `.layout`); tracked separately.
- PWT caching across `RuntimeFunctions.conformsToProtocol` calls; tracked
  separately.
- Querying whether a candidate type itself conforms to `Copyable` /
  `Escapable` (would require new indexer surface).
- Full nested-candidate specialization (would require `Candidate` to carry
  sub-arguments). The fail-fast in this spec is the prerequisite for that
  future work.

## Design

### 1. Surface inverted protocols on `Parameter` (#5)

`SpecializationRequest.Parameter` gains one optional field:

```swift
public struct Parameter: Sendable {
    // existing fields...
    public let invertibleProtocols: InvertibleProtocolSet?
}
```

The set carries the **bits that ARE present** in the type (e.g. a parameter
declared `<T: ~Copyable>` produces a set that does **not** contain
`.copyable`). `nil` means the parameter has no `invertedProtocols`
requirement at all (i.e. it is a normal parameter that retains every
invertible protocol by default).

Population: at the end of `buildParameters`, iterate the merged requirement
list a second time and pick out `kind == .invertedProtocols`. Each such
requirement carries `genericParamIndex: UInt16` and an
`InvertibleProtocolSet`. Match the index against the parameter's flat depth/
index pair and write the set onto the corresponding `Parameter`. If multiple
inverted requirements target the same parameter (theoretically possible
across enclosing contexts), intersect the sets.

`Requirement` enum is **not** changed. The existing
`case .invertedProtocols` branch in `buildRequirement` keeps returning `nil`
but with a comment explaining that the information is surfaced one level up.

### 2. Merge conditional invertible protocol requirements (#6)

Introduce a single private helper:

```swift
private static func mergedRequirements(from genericContext: GenericContext)
    -> [GenericRequirementDescriptor]
{
    genericContext.allRequirements.flatMap { $0 }
        + genericContext.conditionalInvertibleProtocolsRequirements
}
```

Replace the three current call sites in `GenericSpecializer.swift` that read
`genericContext.allRequirements.flatMap { $0 }`:

- `buildParameters` (line 94)
- `buildAssociatedTypeRequirements` (line 285)
- `resolveAssociatedTypeWitnesses` (line 593, via
  `genericContextInProcess.requirements`)

The third call site lives on the `MachO == MachOImage` extension and reads
`genericContextInProcess.requirements` (a flat array, not nested). To stay
consistent we apply the same merge inline:

```swift
let mergedDescriptors = genericContextInProcess.requirements
    + genericContextInProcess.conditionalInvertibleProtocolsRequirements
let requirements = try mergedDescriptors.map {
    try GenericRequirement(descriptor: $0)
}
```

This treats every conditional requirement as active. The current scope rules
out non-Copyable / non-Escapable candidates (#1-#4 are out of scope), so all
candidates retain Copyable / Escapable by default and the conditional
predicates always evaluate true. When future work introduces non-default
candidates, the merge can be made conditional on the candidate's invertible
set.

### 3. Split `.sameConformance` / `.sameShape` / `.invertedProtocols` (#7)

Replace
`GenericSpecializer.swift:265-268`:

```swift
case .sameConformance, .sameShape, .invertedProtocols:
    // These are more advanced requirements that we don't need for basic specialization
    return nil
```

with three independent arms:

```swift
case .sameConformance:
    // Derived from SameType / BaseClass; compiler forces hasKeyArgument = false,
    // so it never participates in metadata accessor key arguments.
    return nil

case .sameShape:
    // Pack-shape constraint between two TypePacks. Relevant only to variadic
    // generics, which are out of scope for this specializer.
    return nil

case .invertedProtocols:
    // Capability declaration (~Copyable / ~Escapable) — surfaced one level up
    // on Parameter.invertibleProtocols rather than as a Requirement, because
    // it relaxes rather than constrains the parameter.
    return nil
```

No behavioural change.

### 4. Generic candidate fail-fast (#9)

`SpecializationRequest.Candidate` gains a `Bool` field:

```swift
public struct Candidate: Sendable, Hashable {
    public let typeName: TypeName
    public let source: Source
    public let isGeneric: Bool
}
```

`findCandidates` populates `isGeneric` by reading
`typeDefinition.type.typeContextDescriptorWrapper.typeContextDescriptor.flags.isGeneric`
(provided by `ContextDescriptorFlags` at
`Sources/MachOSwiftSection/Models/ContextDescriptor/ContextDescriptorFlags.swift:65`).
The field is informational — it lets callers gray-out generic candidates in
UI before attempting to use them.

`GenericSpecializer.SpecializerError` gains:

```swift
case candidateRequiresNestedSpecialization(
    candidate: SpecializationRequest.Candidate,
    parameterCount: Int
)
```

`resolveCandidate` checks
`try descriptor.genericContext(in: typeDefinitionEntry.machO) != nil` before
calling `metadataAccessorFunction`. If the candidate is generic, it throws
`candidateRequiresNestedSpecialization` carrying the candidate and the count
of generic parameters from the descriptor's generic context header. The
existing fall-through to a no-argument `accessorFunction(request:)` call is
removed for generic candidates.

`parameterCount` lets callers preallocate UI for the nested selection step.

### 5. Configurable `MetadataRequest` on `specialize` (#10)

`specialize` signature changes:

```swift
public func specialize(
    _ request: SpecializationRequest,
    with selection: SpecializationSelection,
    metadataRequest: MetadataRequest = .completeAndBlocking
) throws -> SpecializationResult
```

The new parameter is forwarded only to the **main** accessor invocation at
`GenericSpecializer.swift:458`. Internal calls keep their original requests:

- `resolveCandidate`'s `accessorFunction(request: .completeAndBlocking)`
  stays — candidate metadata must be complete to be used as a key argument.
- `resolveAssociatedTypeStep`'s `getAssociatedTypeWitness(request: .init(),
  ...)` stays — abstract is correct for type-witness extraction.

This matches the semantics of `swift_getGenericMetadata`'s `request`
parameter: the caller controls only the freshness state of the **returned**
metadata, not transitive runtime calls.

### 6. Remove dead code (#12)

Delete `convertLayoutKind` at `GenericSpecializer.swift:272-277`. No callers.

## Testing

All new tests live in
`Tests/SwiftInterfaceTests/GenericSpecializationTests.swift`. The other four
items (#6 merge, #7 comments, #10 default parameter, #12 dead code) are
behaviour-preserving refactors covered by the existing test suite.

### Inverted protocols exposure (#5)

```swift
struct TestNonCopyableStruct<A: ~Copyable> { let a: A }
```

Tests:

- `request.parameters[0].invertibleProtocols` is non-`nil`.
- The set does **not** contain `.copyable`.
- `specialize` with `A = Int` (a Copyable type) still succeeds.

### Generic candidate fail-fast (#9)

Set up a request whose candidates include a generic standard-library type
(e.g. `Array` against `A: Collection`). Assertions:

- The matching `Candidate.isGeneric == true`.
- Calling `specialize(request, with: ["A": .candidate(arrayCandidate)])`
  throws `candidateRequiresNestedSpecialization`, not
  `candidateResolutionFailed`.

### Configurable `MetadataRequest` (#10)

Run `TestGenericStruct<A,B,C>` specialization with the default request, then
again with `metadataRequest: .complete` (non-blocking). Both runs must
produce identical `fieldOffsets() == [0, 8, 16]`.

### Conditional invertible requirements (#6)

If a fixture exposing `conditionalInvertibleProtocolsRequirements` can be
authored within Swift 5.9+ language constraints (e.g.
`struct S<A>: ~Copyable where A: P { ... }`), the test asserts the
resulting `Parameter.requirements` includes the merged conditional entries.
If `~Copyable` placement constraints prevent a minimal example,
this test degrades to an end-to-end specialization that exercises the merge
path without directly inspecting the merged list.

## Risks and Migration

- **`Candidate` and `Parameter` shape changes are public API.** Both
  structures live under `@_spi(Support)` indirectly via
  `SpecializationRequest`, but the new fields are sources-compatible only
  for callers that use the synthesised memberwise initialiser positionally.
  Existing call sites in tests use named arguments, so the impact is minimal.
- **Conditional merge is unconditional.** As noted in §2, this is correct
  for the current candidate set. The merge helper is the natural extension
  point when non-default candidates are introduced.
- **No ABI-level change.** No new key arguments are passed; no metadata
  accessor invocation order is altered. The main accessor still receives
  `[metadatas...] + [witnessTables...]` in the same order as today.
