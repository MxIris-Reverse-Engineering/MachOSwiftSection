# ReadingContext API Coverage for `MachOSwiftSection/Models`

**Date:** 2026-05-02
**Status:** Approved, pending implementation
**Branch:** `feature/reading-context-api` (to be created from `main`)

## Problem

Today, types and descriptors in
`Sources/MachOSwiftSection/Models/` expose two parallel API families:

1. **MachO-based**, parameterized over the backing file/image:
   ```swift
   func foo<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> X
   ```
2. **InProcess**, no parameters, reading directly through the descriptor's
   runtime pointer (`asPointer`):
   ```swift
   func foo() throws -> X
   ```

A third family — `ReadingContext`-based — has been introduced incrementally
(see `Sources/MachOReading/ReadingContext/ReadingContext.swift`) and is meant
to be the unified abstraction across the two reading modes:

```swift
func foo<Context: ReadingContext>(in context: Context) throws -> X
```

Today only ~15 of the ~60 model files that have a MachO API also expose a
ReadingContext API. The remaining ~45 files are silently incomplete: any
caller who already adopts the `ReadingContext` abstraction must drop down to
the MachO/InProcess APIs, defeating the purpose.

This document scopes a focused completion pass: add the missing
`ReadingContext` overloads across `MachOSwiftSection/Models/`, mirroring the
pattern already established in
`Sources/MachOSwiftSection/Models/Type/TypeContextDescriptorProtocol.swift`
and friends. While doing so, introduce one small protocol extension —
`runtimePointer(at:)` — needed to express runtime-pointer-returning methods
(notably `metadataAccessorFunction`) under the unified abstraction.

## Goals

- Provide a `ReadingContext`-based overload for every model method that
  currently has a `MachOSwiftSectionRepresentableWithCache` overload, across
  `MachOSwiftSection/Models/`.
- Keep behavior identical to the existing implementations: the new overloads
  are purely additive surface — no existing call sites change.
- Add a minimal extension (`ReadingContext.runtimePointer(at:)`) so that
  methods returning a runtime pointer (`metadataAccessorFunction`, and any
  similar metadata pointer methods uncovered during the pass) can be
  expressed cleanly without per-call type dispatch.
- Land the work in reviewable, build-passing batches grouped by sub-directory.

## Non-Goals

- Touching modules outside `MachOSwiftSection/Models/`. The infrastructure
  (`MachOReading`, `MachOPointers`, `MachOResolving`) already exposes
  ReadingContext entry points — this work consumes them, it does not change
  them — except for the single `runtimePointer(at:)` addition described
  below.
- Touching higher-level modules (`SwiftDump`, `SwiftInspection`,
  `SwiftInterface`, `swift-section`). They keep using the existing MachO/
  InProcess APIs. A follow-up branch can migrate them later.
- Refactoring the existing MachO or InProcess overloads. They stay as-is.
- Adding new unit tests. The new overloads are mechanical mirrors of
  existing, tested code, and the underlying primitives
  (`Resolvable.resolve(at:in:)`, `ReadingContext.read*`) are already covered
  by their own tests.

## Design

### 1. Pattern for the common case

For every method of the shape:

```swift
public func foo<MachO: MachOSwiftSectionRepresentableWithCache>(
    in machO: MachO
) throws -> X {
    try layout.field.resolve(from: offset + layout.offset(of: .field), in: machO)
}
```

add a sibling overload:

```swift
public func foo<Context: ReadingContext>(
    in context: Context
) throws -> X {
    let address = try context.addressFromOffset(offset + layout.offset(of: .field))
    return try layout.field.resolve(at: address, in: context)
}
```

Substitution rules — applied mechanically per call:

| MachO call | ReadingContext equivalent |
|---|---|
| `machO.readElement(offset: o)` | `context.readElement(at: try context.addressFromOffset(o))` |
| `machO.readWrapperElement(offset: o)` | `context.readWrapperElement(at: try context.addressFromOffset(o))` |
| `machO.readElements(offset: o, numberOfElements: n)` | `context.readElements(at: try context.addressFromOffset(o), numberOfElements: n)` |
| `machO.readWrapperElements(offset: o, numberOfElements: n)` | `context.readWrapperElements(at: try context.addressFromOffset(o), numberOfElements: n)` |
| `machO.readString(offset: o)` | `context.readString(at: try context.addressFromOffset(o))` |
| `pointer.resolve(from: o, in: machO)` | `pointer.resolve(at: try context.addressFromOffset(o), in: context)` |
| Recursive `someMethod(in: machO)` | `someMethod(in: context)` |

Local offset arithmetic on `Int` (`currentOffset.offset(of:)`,
`currentOffset.align(to:)`, `currentOffset += ...`) stays unchanged: the
final translation to a context-specific address happens at the read site.

Each new overload sits in a `// MARK: - ReadingContext Support` section
inside the file. Existing MachO/InProcess code is left untouched.

### 2. Extension to support runtime-pointer methods

Some methods return a runtime function pointer
(`metadataAccessorFunction` is the canonical example) and only make sense
when the underlying reader is mapped into the current process. The MachO
overload special-cases `MachO is MachOImage`; the InProcess overload uses
`asPointer`.

To express this under the unified abstraction without per-call
`as?` dispatch, add a single optional capability to the protocol:

```swift
extension ReadingContext {
    /// Converts a context-specific address to a runtime `UnsafeRawPointer`,
    /// when the context is mapped into the current process.
    ///
    /// - `InProcessContext`: returns the address itself (already a pointer).
    /// - `MachOContext<MachOImage>`: returns `machO.ptr + address`.
    /// - `MachOContext<MachOFile>` / other readers: returns `nil`.
    public func runtimePointer(at address: Address) throws -> UnsafeRawPointer? {
        nil
    }
}
```

`InProcessContext` and `MachOContext` provide concrete overrides:

```swift
extension InProcessContext {
    public func runtimePointer(at address: UnsafeRawPointer) throws -> UnsafeRawPointer? {
        address
    }
}

extension MachOContext {
    public func runtimePointer(at address: Int) throws -> UnsafeRawPointer? {
        if let machOImage = machO as? MachOImage {
            return machOImage.ptr + UnsafeRawPointer.Stride(address)
        }
        return nil
    }
}
```

The runtime `as?` cast inside `MachOContext` is unavoidable because the
generic parameter `MachO` is unconstrained at the type level; specializing
the extension with `where MachO == MachOImage` would not produce a witness
for the `MachOContext<MachOImage>: ReadingContext` conformance because the
witness is bound at the unconstrained conformance site.

`runtimePointer(at:)` is **not** added as a `requirement` of the
`ReadingContext` protocol — adding it as an extension method with a default
implementation keeps the change non-breaking for any external conformer.

With this in place, runtime-pointer methods translate cleanly:

```swift
public func metadataAccessorFunction<Context: ReadingContext>(
    in context: Context
) throws -> MetadataAccessorFunction? {
    let fieldAddress = try context.addressFromOffset(offset + layout.offset(of: .accessFunctionPtr))
    let relativeOffset: Int32 = try context.readElement(at: fieldAddress)
    let targetAddress = context.advanceAddress(fieldAddress, by: Int(relativeOffset))
    return try context.runtimePointer(at: targetAddress).map { MetadataAccessorFunction(ptr: $0) }
}
```

For `MachOContext<MachOFile>` this returns `nil`, matching today's MachO
overload. For `InProcessContext` and `MachOContext<MachOImage>` it returns
the function pointer, matching the InProcess overload's behavior.

The implementation pass will identify the small set of similar
runtime-pointer-returning methods (likely confined to a few metadata
descriptors) and apply the same pattern.

### 3. Files in scope

The 45 files needing new overloads live in these sub-directories of
`Sources/MachOSwiftSection/Models/`:

- `Anonymous/`, `Module/`, `Extension/`
- `ContextDescriptor/` (`ContextProtocol.swift`, `ContextWrapper.swift`)
- `Type/Class/` (descriptor, methods, metadata protocols)
- `Type/Enum/`, `Type/Struct/`
- `Type/` root (`TypeContextDescriptor.swift`, `TypeContextWrapper.swift`,
  `TypeReference.swift`, `ValueMetadataProtocol.swift`)
- `Protocol/`, `ProtocolConformance/`
- `Generic/` (`GenericRequirement.swift` — the descriptor already has it)
- `FieldDescriptor/`, `FieldRecord/`, `AssociatedType/`
- `Metadata/` (protocols and wrappers)
- `ExistentialType/`, `ForeignType/`, `TupleType/`, `OpaqueType/`,
  `BuiltinType/`

The complete list is the output of:

```sh
grep -rL "ReadingContext" $(grep -rl "MachOSwiftSectionRepresentableWithCache" \
  Sources/MachOSwiftSection/Models)
```

at the start of the implementation. The implementation plan will pin a
verified file list per batch.

### 4. Batch plan (commit grouping)

Each batch is a single commit and must build cleanly (`swift build`) before
moving on. Batches are grouped to keep diffs cohesive and reviewable:

1. **Reading-context infrastructure** — add `runtimePointer(at:)` extension
   in `MachOReading` (no model file changes yet).
2. `Anonymous/`, `Module/`, `Extension/` (simple context wrappers).
3. `ContextDescriptor/` (`ContextProtocol.swift`, `ContextWrapper.swift`).
4. `Type/Class/*` (descriptor, methods, metadata protocols).
5. `Type/Enum/*`, `Type/Struct/*`.
6. `Type/` root files (descriptor, wrapper, references, metadata
   protocols), including `metadataAccessorFunction` overload using
   `runtimePointer(at:)`.
7. `Protocol/`, `ProtocolConformance/`.
8. `Generic/` (`GenericRequirement.swift`),
   `FieldDescriptor/`, `FieldRecord/`, `AssociatedType/`.
9. `Metadata/` (protocols, wrappers).
10. `ExistentialType/`, `ForeignType/`, `TupleType/`, `OpaqueType/`,
    `BuiltinType/`.

If any batch turns out larger or smaller than expected, the plan can
re-balance — the only invariant is "one batch = one passing build".

## Validation

- `swift package update && swift build` after each batch.
- `swift test` once at the end of the work, to confirm the existing
  `MachOSwiftSectionTests`, `SwiftDumpTests`, and `SwiftInterfaceTests`
  suites still pass (they exercise the underlying MachO/InProcess paths
  that the new overloads reduce to).
- Spot check: pick one or two of the new overloads (e.g.
  `TypeContextDescriptorProtocol.fieldDescriptor(in:)` once added) and
  confirm they delegate to the same primitives as the existing MachO
  overload by reading the diff.

## Risks and mitigations

- **Risk:** A method's MachO overload has subtle behavior (e.g. early
  return on a bind/rebase resolver, special-case for `MachOImage`) that the
  mechanical translation skips.
  - *Mitigation:* During each batch, read the existing overload end-to-end
    before mirroring it. Anything that does not fit the substitution table
    above gets a per-method note in the commit message.
- **Risk:** `runtimePointer(at:)` extension default returns `nil` and a
  caller silently loses functionality for `MachOContext<MachOFile>`.
  - *Mitigation:* This matches today's behavior — the existing
    `metadataAccessorFunction(in: MachO)` already returns `nil` for
    `MachOFile`. Documented explicitly on the extension.
- **Risk:** A future contributor adds a new `ReadingContext` conformer and
  expects `runtimePointer(at:)` to be a requirement.
  - *Mitigation:* The doc comment on the extension states the contract;
    making it an extension (not a requirement) is intentional to avoid a
    breaking change.
