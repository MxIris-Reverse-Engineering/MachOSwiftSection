# Bound Generic Candidates in GenericSpecializer — 2026-05-11

Spec for letting `GenericSpecializer` accept `Array<Int>` / `Dictionary<String, Int>` style "已绑定具体类型实参的泛型" as the selected type for an outer generic parameter (e.g. `Outer<T>` with `T = Array<Int>`), without forcing callers to hand-build the inner `SpecializationResult` themselves.

All file/line references are against the state of the repo on 2026-05-11.

---

## Current behaviour

Existing infrastructure (under `Sources/SwiftInterface/GenericSpecializer/`):

- `SpecializationRequest.Candidate` already exposes `isGeneric: Bool` (`Models/SpecializationRequest.swift:180`).
- `findCandidates` (`GenericSpecializer.swift:551`) includes generic candidates by default; callers can drop them via `CandidateOptions.excludeGenerics`.
- `resolveCandidate` (`GenericSpecializer.swift:1325`) throws `SpecializerError.candidateRequiresNestedSpecialization` when a generic candidate is supplied through `Argument.candidate(...)`, instructing the user to switch to `Argument.specialized(SpecializationResult)`.
- `Argument.specialized` is functional today — `Tests/SwiftInterfaceTests/GenericSpecializationTests.swift:906` and the "nested generic specialize() end-to-end" suite exercise it — but requires the caller to:
  1. Build the inner `SpecializationRequest` themselves via a second `makeRequest`.
  2. Call `specialize` on the inner generic.
  3. Wrap the resulting `SpecializationResult` into `.specialized(...)` and pass it to the outer selection.

The candidate list surfaced by `makeRequest` therefore shows `Array` (generic) but never `Array<Int>` (bound); UI layers either filter the bound-generic case out via `excludeGenerics` or replicate the three-step ceremony themselves.

## Goal

Make `Array<Int>` and arbitrarily nested forms (`Dictionary<String, Array<Int>>`, etc.) a first-class selection that flows through the same `SpecializationSelection` API as the leaf cases, with no manual `specialize` ping-pong.

---

## Solution space

| # | Approach | Selection shape | Recursion handling | Status |
|---|---|---|---|---|
| 1 | Helper that turns `(genericCandidate, innerSelection)` into a `SpecializationResult` and re-wraps it as `Argument.specialized` | unchanged | caller-driven loop | dropped — subsumed by 2 |
| 2 | New `Argument.boundGeneric(baseCandidate:innerArguments:)` case in `SpecializationSelection` | declarative tree | specializer recurses internally | **active** |
| 3 | New `Argument.mangled(MangledName)` / `Argument.typeNode(Node)` resolved through `swift_getTypeByMangledNameInContext` | flat, externally-typed | runtime handles substitution | TODO |
| 4 | `Candidate` carries a lazy `nestedRequest`; UI auto-expands; `SpecializationSelection` becomes tree-shaped end to end | tree | automatic | TODO |

Approaches 3 and 4 are independent of 2 and target different consumer profiles (3 = "any type the runtime can mangle", 4 = "UI walks request trees"). They are scoped as follow-ups in their own sections at the bottom of this document.

---

## Approach 2 — `Argument.boundGeneric` (active)

### Modification 2-1. `Models/SpecializationSelection.swift`

Extend the `Argument` enum with one new case (current cases live at lines 35–44):

```swift
public enum Argument: @unchecked Sendable {
    case metatype(Any.Type)
    case metadata(Metadata)
    case candidate(SpecializationRequest.Candidate)
    case specialized(SpecializationResult)
    /// Bind a generic candidate (e.g. `Array`, `Dictionary`) to a
    /// nested selection. The specializer recursively builds an inner
    /// `SpecializationRequest` from `baseCandidate`'s descriptor and
    /// substitutes `innerArguments`; the resulting metadata feeds the
    /// outer key-arguments buffer in place of a concrete leaf type.
    case boundGeneric(
        baseCandidate: SpecializationRequest.Candidate,
        innerArguments: [String: Argument]
    )
}
```

Extend `SpecializationSelection.Builder` with a matching convenience:

```swift
@discardableResult
public func set(
    _ parameterName: String,
    to candidate: SpecializationRequest.Candidate,
    boundTo innerArguments: [String: Argument]
) -> Builder
```

No change to `subscript(parameterName:)`, `hasArgument(for:)`, or the dictionary literal initializer.

### Modification 2-2. `GenericSpecializer.swift` switch sites

Five switches in `GenericSpecializer.swift` need a new branch. Behaviour is consistent across all of them: `.boundGeneric` should behave **as if** the caller had separately built and supplied an `Argument.specialized(...)` for the same inner selection, with the only difference being that the recursion is now driven by the specializer.

| # | Location | Current behaviour | `.boundGeneric` behaviour |
|---|---|---|---|
| (a) | `resolveMetadata` — `GenericSpecializer.swift:1308` | `.candidate` → `resolveCandidate`; `.specialized` → `result.metadata()` | Build inner `SpecializationRequest` from `baseCandidate.typeName`'s descriptor, wrap `innerArguments` into a `SpecializationSelection`, recursively call `specialize(_:with:)`, return `result.metadata()` |
| (b) | `runtimePreflight` pre-pass — `GenericSpecializer.swift:720–762` | `.candidate` skipped; `.metatype` / `.metadata` / `.specialized` populate `metadataByName` | Recursively run `validate` + `runtimePreflight` on the inner selection, then call `try inner.metadata()` and insert into `metadataByName`. Failures are aggregated as `metadataResolutionFailed` carrying a dotted path prefix (`"A.B"`) |
| (c) | `runUnifiedConstraintCheck` bail-out — `GenericSpecializer.swift:890–894` | Any `.candidate` causes the whole pass to bail (candidate accessors are side-effectful in preflight) | `.boundGeneric` does **not** trigger the bail — it can produce a final metadata for `swift_getTypeByMangledNameInContext` substitution, same as `.specialized`. Only naked `.candidate` continues to bail |
| (d) | `validate` — `GenericSpecializer.swift:644` | Checks missing/extra arguments and associated-type-path warning | For `.boundGeneric`, recursively `validate` the inner selection against the inner request; flatten errors and warnings with dotted parameter paths |
| (e) | `SpecializerError` — `GenericSpecializer.swift:1668` | — | Add `case boundGenericInnerFailed(parameterName: String, underlying: Error)` so inner failures keep their typed identity instead of being string-collapsed |

#### (a) Recursion contract

Inner request construction uses the existing path:

```swift
let innerTypeDescriptor = try resolveCandidateDescriptor(baseCandidate)
let innerRequest = try makeRequest(for: innerTypeDescriptor)
let innerSelection = SpecializationSelection(arguments: innerArguments)
let innerResult = try specialize(innerRequest, with: innerSelection)
return try innerResult.metadata()
```

`resolveCandidateDescriptor` factors out the indexer lookup currently embedded in `resolveCandidate` (`GenericSpecializer.swift:1325-1353`). The "candidate is itself generic" branch that today throws `candidateRequiresNestedSpecialization` becomes the **expected** path for `.boundGeneric`; the bare-`.candidate` path keeps throwing.

#### (b) Preflight semantics

The pre-pass must not partially advance state. If inner preflight reports any error, the outer pass:

1. Records a single `metadataResolutionFailed(parameterName: "<outer>", reason: "<inner errors joined>")` against the outer builder.
2. Does **not** insert anything into `metadataByName` for that parameter — keeping cross-parameter checks (sameType GP-vs-GP) consistent with how `.candidate` is treated.

Inner warnings are forwarded with a `"<outer>." prefix` so the surface remains debuggable.

#### (c) Constraint-check participation

Because `.boundGeneric` can be resolved to a concrete `Any.Type` before `runUnifiedConstraintCheck` runs, the runtime substitution path (`swift_getTypeByMangledNameInContext`) sees a fully-formed metadata in the arguments buffer. The check is therefore strictly stronger than the current `.specialized`-only support: a `where T == Array<Int>` constraint on the outer signature can now be validated even when the user spelled `T` through `.boundGeneric`.

#### (d) Static validation recursion

`validate` was previously cheap and synchronous; recursion keeps that property as long as the inner request can be built without descriptor resolution. To avoid forcing descriptor lookups in the static pass:

- If the inner request can be cached on the outer `Candidate` (Approach 4 direction), reuse it.
- Otherwise build the inner request lazily inside `validate` and cache it on a per-call basis. Failure to build the inner request becomes a structural error (`boundGenericInnerFailed` with a `requestConstructionFailed` underlying case).

### Modification 2-3. `SpecializationResult.ResolvedArgument` → tree (Decision: B)

`ResolvedArgument` currently flattens to `(parameterName, metadata, witnessTables)`. Switch to **tree shape**: add an optional `innerResult` field that captures the recursively-resolved inner `SpecializationResult`.

```swift
public struct ResolvedArgument: @unchecked Sendable {
    public let parameterName: String
    public let metadata: Metadata
    public let witnessTables: [ProtocolWitnessTable]
    /// Present when the argument came from `Argument.boundGeneric` or
    /// `Argument.specialized`; nil for `metatype` / `metadata` /
    /// non-generic `candidate`. Walks the binding tree.
    public let innerResult: SpecializationResult?

    public init(
        parameterName: String,
        metadata: Metadata,
        witnessTables: [ProtocolWitnessTable] = [],
        innerResult: SpecializationResult? = nil
    ) { ... }
}
```

Rationale:

1. The specializer is currently SPI (`@_spi(Support)`), so the API impact is bounded.
2. External consumers — including the existing snapshot/builder paths — already inspect `resolvedArguments` to render nested types in the interface output. Discarding the inner tree would force them to re-derive it from the original `SpecializationSelection`, duplicating work and decoupling rendering from what the runtime actually produced.
3. `.metatype` / `.metadata` keep `innerResult == nil`; the change is purely additive for those cases.

### Modification 2-4. PWT ordering invariant

Bound-generic parameters do not introduce new key-argument slots in the **outer** signature: the outer accessor still expects exactly one metadata pointer per outer generic parameter, plus the outer's own PWTs. Inner PWTs are consumed by the inner `specialize` call's own accessor invocation and never bleed into the outer arguments buffer. This preserves the canonical-order invariant documented at `GenericSpecializer.swift:1224-1240` (the `compareDependentTypesRec` ordering): `buildKeyArgumentsBuffer` does not need any change beyond reading the new metadata from `resolveMetadata`'s recursion.

### Modification 2-5. Recursion termination & cycle safety

`.boundGeneric` chains terminate when an inner `Argument` is one of:

- `.metatype` / `.metadata` (concrete metadata, no further work),
- `.candidate` referencing a **non-generic** type descriptor (single accessor call),
- `.specialized` (already-resolved tree).

Cycles like `Array<Array<Array<...>>>` cannot be constructed without an explicit user-built tree of `.boundGeneric` cases — each level requires the caller to commit to a concrete leaf at the bottom. Defensive depth-limit guards are **not** required for correctness, but a configurable `maxBindingDepth` (default 16) on `GenericSpecializer` is a low-cost ergonomic guard against runaway recursion from buggy callers; emit `SpecializerError.specializationFailed(reason: "binding depth exceeded")` when crossed.

### Verification

New tests live next to `Tests/SwiftInterfaceTests/GenericSpecializationTests.swift`:

1. **`Outer<T> = Array<Int>`** — `.boundGeneric(Array, ["A": .metatype(Int.self)])` resolves and matches the manually-built `.specialized` path's metadata pointer.
2. **`Outer<T> = Dictionary<String, Array<Int>>`** — two-level nested `.boundGeneric`; result equals the manually-staged equivalent.
3. **PWT slot count parity** — running the new path through `buildKeyArgumentsBuffer` produces `metadatas.count + witnessTables.count == request.keyArgumentCount` (existing invariant at `GenericSpecializer.swift:1297-1302`).
4. **`runtimePreflight` catches mismatched conformance** — `.boundGeneric` of a generic whose substituted result fails a protocol requirement reports `protocolRequirementNotSatisfied`, not a stringified inner error.
5. **`runUnifiedConstraintCheck` validates `where T == Array<Int>`** — the constraint passes when `T` is supplied via `.boundGeneric(Array, ["A": .metatype(Int.self)])` and fails (with a typed error) when supplied as `.boundGeneric(Array, ["A": .metatype(String.self)])`.
6. **Inner failure surfaces typed** — supplying an inner argument that violates an inner requirement produces `boundGenericInnerFailed` with a recognizable `underlying` chain, not a flat string.
7. **`ResolvedArgument.innerResult` is populated** — for `.boundGeneric` and `.specialized` selections, the inner tree is reachable; for `.metatype` / `.metadata`, `innerResult == nil`.

### Effort

Medium. Largest single piece is the recursion in `resolveMetadata` plus matching adjustments in `runtimePreflight` / `runUnifiedConstraintCheck` / `validate`. The Models change and the tree-shaped `ResolvedArgument` are straightforward.

### Risks

- **Preflight cost.** Recursive validation pays for one full `validate` + `runtimePreflight` per binding level. The cost is bounded by user-built tree depth; acceptable for the SPI's interactive use cases. If batch consumers appear, add a memoization key on `(descriptor, hashedInnerArguments)`.
- **Error message clarity.** Without dotted path prefixes, errors at depth 3 read as "missing argument for `A`" with no indication of which generic level. The dotted-path convention above mitigates this; verify in test 6's snapshot.
- **API churn.** `ResolvedArgument.innerResult` adds a stored field. Because the specializer is SPI, this is acceptable; revisit if the API is ever promoted to stable.

---

## Approach 3 — runtime-direct mangled / node arguments (TODO)

Sketch retained here so the work isn't lost; not started.

### Motivation

`.boundGeneric` can only target types whose descriptors are known to the indexer. Function types (`(Int) -> String`), tuples (`(Int, String)`), and stdlib types not in any sub-indexer cannot be selected by descriptor — but the Swift runtime can resolve them from a mangled name via `swift_getTypeByMangledNameInContext`, which the specializer already uses in `runUnifiedConstraintCheck` (`GenericSpecializer.swift:1031`).

### Direction

Add to `SpecializationSelection.Argument`:

```swift
case mangled(MangledName)
case typeNode(Node)
```

`.typeNode` re-mangles through `Remangler` before handing the bytes to the runtime. Internal resolution path:

```swift
case .mangled(let mangledName):
    guard let resolvedType = try RuntimeFunctions.getTypeByMangledNameInContext(
        mangledName,
        genericContext: ..., // pass an empty / type-free context
        genericArguments: ...,
        in: machO
    ) else { throw SpecializerError.specializationFailed(...) }
    return try Metadata.createInProcess(resolvedType)
```

### Open questions

- **Generic context for substitution.** `getTypeByMangledNameInContext` accepts a generic context — for free-standing arguments (no outer GPs in the name), passing `nil` may or may not work for every reachable type. Empirical sweep required.
- **PWT derivation.** When the mangled type satisfies a protocol requirement on the outer parameter, the runtime gives back `Any.Type`, not the witness table. `resolveWitnessTable` (`GenericSpecializer.swift:1371`) already covers this via `RuntimeFunctions.conformsToProtocol` — reuse without modification.
- **Error surface.** Runtime resolution failures return `nil`/throw with low-detail context; expose a typed `SpecializerError.mangledArgumentResolutionFailed(mangledName:, reason:)` so callers can distinguish from descriptor-level failures.
- **UI dependency.** Callers need a way to produce mangled names or `Node` trees. Either expose a helper on `Demangling.Remangler` or document a recommended path (e.g. demangle a user-supplied string and feed the resulting `Node` to `.typeNode`).

### Risks

- Loss of static introspection. `.mangled` arguments do not expose a descriptor, so the candidate-list view cannot show them with the same metadata as descriptor-based candidates.
- Runtime trust boundary widens: arbitrary mangled bytes flow into `swift_getTypeByMangledNameInContext`. Add input validation (demangle round-trip) before invoking the runtime.

### Effort

Medium. The runtime call already exists; the work is in API surface, error handling, and Remangler ergonomics.

---

## Approach 4 — tree-shaped `Candidate` with lazy nested requests (TODO)

Sketch retained here; not started.

### Motivation

Approach 2 puts the recursion in `SpecializationSelection` but leaves `Candidate` flat — UI layers that want to show "expandable" generic candidates (`Array` → "open" → pick `Element`) must build the inner request themselves by calling `makeRequest` on the candidate's descriptor. Approach 4 hoists that into the candidate.

### Direction

Promote `Candidate` to carry an optional lazy nested request:

```swift
public struct Candidate: Sendable, Hashable {
    public let typeName: TypeName
    public let source: Source
    public let isGeneric: Bool
    /// Lazy: `nil` for non-generic candidates; otherwise a thunk that
    /// builds the inner `SpecializationRequest` on demand. Lazy
    /// evaluation prevents `Array<Array<...>>`-style infinite descent
    /// during `findCandidates`.
    public let nestedRequest: (@Sendable () throws -> SpecializationRequest)?
}
```

`SpecializationSelection` becomes tree-shaped at the type level (rather than via the `.boundGeneric` enum case). Approach 4 effectively merges Approach 2's selection model with a UX layer that drives the binding from the candidate side.

### Open questions

- **`Hashable` requirement.** `nestedRequest` is a closure and cannot participate in hashing — move it to a separate sidecar dictionary keyed by candidate identity, or relax `Hashable`.
- **Cycle safety.** `findCandidates` must not eagerly walk nested requests; the lazy thunk plus an explicit `expandCandidate(_:)` entrypoint preserves the existing O(types) cost.
- **Composability with 2.** If both 2 and 4 ship, `.boundGeneric` and the tree-shape `Candidate` describe overlapping state. Decide whether Approach 4 replaces `.boundGeneric` or layers on top of it (the latter is simpler — Approach 4 becomes pure UI affordance).

### Risks

- `Candidate: Hashable` breakage if the closure cannot be excluded cleanly.
- Increased coupling between `Candidate` and `GenericSpecializer` (the closure must capture the specializer or its inputs).

### Effort

Medium-large. Touches Models, `findCandidates`, and every consumer of `Candidate` (UI especially).

---

## Out of scope for this roadmap

- TypePack / Value generic parameters as bound generic arguments. `makeRequest` already rejects these at the source side (`GenericSpecializer.swift:77`); bound-generic recursion inherits the same restriction.
- File-mode (`MachO == MachOFile`) execution. The recursion in Approach 2 routes through `specialize`, which is `MachO == MachOImage`-only. Bound-generic selections are restricted to image mode by construction — same constraint as `.specialized` today.
- Caching of repeated inner specializations across outer calls. Possible future optimization; not required for correctness.
