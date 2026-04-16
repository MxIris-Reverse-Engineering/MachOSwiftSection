# SwiftInterface Dump Improvements — 2026-04-13

Spec derived from running the `SwiftInterfaceBuilderTestSuite.MachOFileTests/buildString` test against `Tests/Projects/SymbolTests/SymbolTestsCore` and diffing the output against the source fixtures. The initial investigation produced ~20 improvement items organized across three priority tiers (P0/P1/P2) plus a cross-cutting cleanup list. The P0 tier has already been implemented and merged; this document scopes the remaining work.

All file/line references are against the state of the repo on 2026-04-13.

---

## Current status

**Implemented in this session** (see commit on `feature/vtable-offset-and-member-ordering`):

| # | Item | Summary |
|---|---|---|
| P0-1 | `unowned` / `unowned(unsafe)` field types | `TypeNodePrintable` now handles `.unowned` / `.unmanaged`; `StructDumper` / `ClassDumper` print the `unowned` / `unowned(unsafe)` keyword; new `DemangleOptions.removeReferenceStoragePrefix`; `FieldFlags` gained `isUnowned` / `isUnownedUnsafe` / `isArtificial` |
| P0-3 | `$defaultActor` field empty type | `TypeNodePrintable` now handles `.builtinTypeName` / `.builtinTupleType`. Produces `Builtin.DefaultActorStorage` |
| P0-4 | Nested generic missing `<A2>` | `TargetGenericContext.currentParameters` now uses `parentParameters.last?.count` instead of the accumulated flatMap count. Root cause: each parent descriptor's `parameters` is already cumulative (emitted via `addGenericParameters` using `canSig->forEachParam`), so the flatMap was double-counting |

**Known not fixable** (see bottom of document): P0-2 `init!` vs `init?`. Binary mangling does not distinguish them.

**Remaining items are scoped below in three phases.**

---

## Phase 1 — `SwiftInterface` / `SwiftDump` surface fixes

These items are fully represented in binary metadata and only require changes to the printer / dumper / demangler layers. No new metadata reading.

### P1-5. `@escaping` on parameter closures

**Symptom.** A function parameter of function type is printed without `@escaping`, even though Swift requires the modifier whenever an escaping closure is passed.

**Source fixture.** `Tests/Projects/SymbolTests/SymbolTestsCore/FunctionFeatures.swift`
```swift
public class ClosureParameterTest {
    public func acceptEscaping(_ callback: @escaping () -> Void) { ... }
    public func acceptAutoclosure(_ condition: @autoclosure () -> Bool) -> Bool { ... }
    public func acceptEscapingAutoclosure(_ condition: @escaping @autoclosure () -> Bool) { ... }
}
```

**Current dump.**
```swift
func acceptEscaping(_: () -> ())
func acceptEscapingAutoclosure(_: @autoclosure () -> Swift.Bool)
```

**Expected.**
```swift
func acceptEscaping(_: @escaping () -> ())
func acceptEscapingAutoclosure(_: @escaping @autoclosure () -> Swift.Bool)
```

**Evidence the information is present.**
- Swift ABI mangling default for function types **is** escaping. A non-escaping closure is mangled with a distinct node kind `NoEscapeFunctionType` (`swift/docs/ABI/Mangling.rst:712`, `type ::= function-signature 'X' 'E'`).
- `swift-demangling/Sources/Demangling/Main/Demangle/Demangler.swift` already parses `'XE'` into `.noEscapeFunctionType` (grep hits in `Node+Kind.swift`).
- `FunctionTypeFlags.escapingMask` (bit 26) also exists in `Sources/MachOSwiftSection/Models/Function/FunctionTypeFlags.swift:26` and has a `isEscaping` getter at `:47`, but this is redundant with the node-kind distinction for parameter positions.

**Modification points.**
1. `Sources/SwiftInterface/NodePrintables/FunctionTypeNodePrintable.swift` — already handles `.noEscapeFunctionType` and several other specialized function-type node kinds. Add an `isInParameterPosition` context flag (part of `FunctionTypeNodePrintableContext`) that is set to `true` when the caller is printing a parameter list. When the flag is set and the node is a plain `.functionType` (not `.noEscapeFunctionType`, not `.autoClosureType`, not `.escapingAutoClosureType`, etc.), prefix the output with `@escaping `.
2. `Sources/SwiftInterface/NodePrinter/FunctionNodePrinter.swift`, the `printLabelList` path — this is where each parameter type is walked. It must propagate `isInParameterPosition = true` into the context passed to the nested printer invocation.
3. Handle the `@autoclosure` + `@escaping` combination: when the inner node is `.autoClosureType` (non-escaping autoclosure) inside a parameter, leave it alone; when the inner node is `.escapingAutoClosureType`, the dumper already prints `@autoclosure`, but needs to additionally prefix `@escaping`.

**Verification.**
- `Tests/Projects/SymbolTests/SymbolTestsCore/FunctionFeatures.swift::ClosureParameterTest` — all three closure methods should show correct attributes.
- Add a new targeted test case to `SwiftInterfaceTests` (e.g., extend the snapshot assertion for `ClosureParameterTest`).

**Risk.** False positives on `@convention(c)` / `@convention(block)` function types — those are always non-escaping at ABI level but appear as `.cFunctionPointer` / `.objCBlock` / `.escapingObjCBlock` node kinds, not plain `.functionType`, so the condition in (1) naturally excludes them. Verify by checking `ConventionFunctionTest` dump does not gain a spurious `@escaping`.

**Effort.** Small (half a day). Mostly plumbing the context flag.

---

### P1-6. `DependentMemberType` printed as a verbose protocol-annotated chain

**Symptom.** A dependent member type is rendered with its protocol witness repeated on every segment instead of the simplified form Swift source uses.

**Source fixture.** `Tests/Projects/SymbolTests/SymbolTestsCore/DependentTypeAccess.swift`
```swift
public struct DependentAccessTest<Element: OuterProtocol> {
    public var middleLeaf: Element.Middle.Leaf?
    public init(middleLeaf: Element.Middle.Leaf?, ...) { ... }
}
```

**Current dump.**
```swift
struct DependentAccessTest<A> where A: ...OuterProtocol {
    var middleLeaf: A.OuterProtocol.Middle.MiddleProtocol.Leaf?
    var innerValue: A.OuterProtocol.Inner.InnerProtocol.Value?
    init(middleLeaf: A.Middle.Leaf?, innerValue: A.Inner.Value?)   // <-- ctor uses the short form
}
```

Note the **inconsistency**: field types use the long form, the init signature uses the short form. The extreme case is `UnderlyingPrimaryAssociatedTypeTest` in `OpaqueReturnTypes.swift` where the dump emits
```
... == B.ProtocolTest.Body.ProtocolTest.Body.ProtocolTest.Body.ProtocolTest.Body.ProtocolTest.Body.ProtocolTest.Body
```
which is ~100 characters of protocol repetition.

**Evidence for simplification.**
- The upstream Swift `NodePrinter.cpp` emits the same verbose form at `lib/Demangling/NodePrinter.cpp:3091-3097` — it does **not** canonicalize. Swift `swiftinterface` files work around this by pre-canonicalizing the type in the source-layer printer (not the demangling printer).
- Pattern for simplification: for a chain `A.Middle.MiddleProtocol.Leaf`, the middle segment `MiddleProtocol` is the protocol that owns the associated type `Leaf`. Because every `DependentMemberType` node carries both the base and the associated-type reference (as a protocol + identifier pair), the protocol is redundant whenever only one protocol in `A`'s constraint chain declares the `Leaf` associated type — which is the common case.

**Modification points.**
1. `Sources/SwiftInterface/NodePrintables/DependentGenericNodePrintable.swift:33-34` — currently delegates to the base demangler's `printDependentMemberType`. Instead, add a custom walker that:
   - Collects the chain of `DependentMemberType` nodes from innermost to outermost.
   - For each segment, takes only the associated-type identifier (not the protocol qualifier).
   - Emits `A.Middle.Leaf` with no protocol names.
2. Preserve the protocol qualifier **only** if the same identifier is declared by multiple protocols in the generic signature (disambiguation case), which would require looking up the owning generic signature. For a first pass, always drop the protocol — the ambiguous case is rare and can be added later.
3. Add a configuration flag `printDependentMemberTypeProtocolQualifier` defaulting to `false` to allow emitting the verbose form for debugging.

**Verification.**
- `DependentAccessTest`: both field and init must print `A.Middle.Leaf?` / `A.Inner.Value?`.
- `DeepDependentAccessTest`: `A.Middle.Branch.Final?`.
- `UnderlyingPrimaryAssociatedTypeTest`: the massive protocol-repetition tail should collapse.
- `NestedSameTypeTest` (same-type constraint chain) should remain correct.
- Keep an eye on `dependentMemberTypeDepth` tracking in `NodePrintable.swift:18` — the existing mechanism may interact with the new walker.

**Risk.** Producing ambiguous output when a type's associated-type chain actually relies on the protocol qualifier for disambiguation. Low for SymbolTestsCore, unknown for SwiftUICore. The configuration flag provides escape hatch.

**Effort.** Medium (1 day). Main work is writing the walker and deciding how to handle ambiguity.

---

### P1-7. `consuming` / `borrowing` parameter modifier

**Symptom.** Parameters declared with `consuming` (or `borrowing`) lose the
keyword in the dump and print as a bare type. `__owned` / `__shared` (the
demangler-level spellings) are wrong for a Swift source-facing interface
file — Swift 5.9+ writes `consuming` / `borrowing` at source level.

**Source fixture.** `Tests/Projects/SymbolTests/SymbolTestsCore/FunctionFeatures.swift`
provides `FunctionFeatures.OwnershipParameterTest` with method-level
`consuming` parameters (single, multi, with-label, static). In addition,
`OptionSetAndRawRepresentable.OptionSetTest`'s `Swift.SetAlgebra`
protocol witnesses carry `__owned`-mangled parameters from the stdlib
side and exercise the same node-printer path:
- `func union(_: consuming Self) -> Self`
- `func symmetricDifference(_: consuming Self) -> Self`
- `func insert(_: consuming Self.Element) -> ...`
- `func update(with: consuming Self.Element) -> Self.Element?`
- `func formUnion(_: consuming Self)`
- `init<A1>(_: consuming A1) where A1: Swift.Sequence, ...`

**Current dump (before fix).**
```swift
func union(_: __owned Self) -> Self
func insert(_: __owned Self.Element) -> ...
init<A1>(_: __owned A1) where A1: Swift.Sequence, ...
```

**Evidence the information is present.**
- `swift/docs/ABI/Mangling.rst:783` — the `list-type` production allows
  per-parameter ownership convention flags: `'n'` (owned), `'h'`
  (shared), `'k'` (inout), `'g'` (guaranteed), etc.
- `swift-demangling/Sources/Demangling/Main/Demangle/Demangler.swift:226,230`
  — the demangler already handles `'h'` → `.shared` and `'n'` → `.owned`.
  No demangler change needed.
- `Sources/SwiftInterface/NodePrintables/NodePrintable.swift:37-38`
  already had a `.owned → "__owned "` branch but no `.shared` branch.

**ABI limitation 1 — `init` parameter modifiers are not recoverable.**
The Swift compiler does **not** emit the `n` flag in mangled
constructor symbols. Verified empirically with `swiftc` + `nm` +
`xcrun swift-demangle`:

| Declaration | mangled `n`? | demangle tree has `.owned`? |
|---|---|---|
| `func single(_ box: consuming Box)` | yes | yes |
| `func twoParams(_ box: consuming Box, label: Int)` | yes | yes |
| `S.methodSingle(_ box: consuming Box)` | yes | yes |
| `S.init(box: consuming Box)` | **no** | **no** |
| `S.init(box: consuming Box, label: Int)` | **no** | **no** |

Concretely, `NoncopyableGenericTest.init(value: consuming T)` mangles to
`_$s15SymbolTestsCore11NoncopyableO0D11GenericTestVAARi_zrlE5valueAEy_xGx_tcfC`,
whose demangle tree's `ArgumentTuple → Tuple → TupleElement → Type` is a
bare `DependentGenericParamType` with no `.owned` wrapper. For
`~Copyable` types in particular, by-value parameters are implicitly
consuming (a noncopyable value cannot be copied), so the compiler treats
the keyword as the default and never mangles it.

**ABI limitation 2 — source-level `borrowing` is also not recoverable.**
The `h` flag in the mangling spec is reachable only from the *legacy*
`__shared` spelling, **not** from Swift 5.9+'s `borrowing`. Verified
empirically: a `func b(_ s: borrowing S) -> Int` produces a mangled name
**byte-identical** to the same function with no ownership modifier
(`_$s1h1bySiAA1SVF`), while a `func c(_ s: __shared S) -> Int` does
include the `h` flag (`_$s1h1cySiAA1SVhF`) and demangles back to
`__shared S`. So the printer's `.shared → "borrowing "` rewrite still
works, but only for binaries whose source uses the old `__shared`
spelling — most notably stdlib/Foundation functions like
`Foundation.String.init(format: __shared String, ...)`. Pure
`borrowing`-only sources (including `OwnershipParameterTest` if it
were extended) cannot be verified, because `borrowing` produces no
node to print.

**Modification points.**
1. `Sources/SwiftInterface/NodePrintables/NodePrintable.swift` — change
   the `.owned` branch's prefix from `"__owned "` to `"consuming "`,
   and add a new `.shared` branch with prefix `"borrowing "`. The
   demangler dependency is unchanged: SwiftInterface is the
   source-facing layer, swift-demangling continues to print
   `__owned` / `__shared` for general-purpose use.

**Verification.**
- `FunctionFeatures.OwnershipParameterTest.consumeBox(_:)`,
  `consumeWithLabel(_:label:)`, `twoConsuming(_:_:)`, and the static
  `staticConsume(_:)` all print `consuming` before the `Box` parameter.
- `OptionSetTest`'s SetAlgebra witnesses (above) print `consuming`
  instead of `__owned`. (The full dump `grep -c "__owned\|__shared"`
  must return 0.)
- `FunctionFeatures.InoutFunctionTest.swap/modify` continue to print
  `inout Swift.Int` — `inout` is a separate node kind (`.inOut`) and
  is unaffected.
- `NoncopyableGenericTest.init(value:)` continues to print without
  `consuming` — see ABI limitation 1. Do **not** treat this as a bug.
- The `.shared → borrowing` rewrite is verified only via the dyld-cache
  snapshot tests where Foundation `__shared` parameters appear; not by
  SymbolTestsCore — see ABI limitation 2.

**Risk.** Low. The change is one switch case + one new switch case.

**Effort.** Small (~1 hour). No demangler dependency change needed.

---

### P1-8. `deinit` members not collected

**Symptom.** Classes and noncopyable structs with `deinit` show nothing for the destructor; the dump has no `deinit` line at all.

**Source fixture.** `Tests/Projects/SymbolTests/SymbolTestsCore/Noncopyable.swift`
```swift
public struct NoncopyableTest: ~Copyable {
    deinit {}
    ...
}
```

Also class types like `PropertyObserverClassTest`, `KeyPathReferenceTest`, etc. have implicit destructors.

**Current dump.** No `deinit` appears.

**Evidence the information is present.**
- `swift/docs/ABI/Mangling.rst:373-375` — deinit entities are mangled as:
  - `entity-spec ::= 'fD'` → `Deallocator`
  - `entity-spec ::= 'fd'` → `Destructor`
- `swift/lib/Demangling/Demangler.cpp:4180-4184` demangles `'fD'` / `'fd'` into `Node.Kind.Deallocator` / `Node.Kind.Destructor`.
- `swift/lib/Demangling/NodePrinter.cpp:1677-1686` prints them as `"__deallocating_deinit"` / `"deinit"`.
- The symbol is usually present in the `__TEXT,__text` section and indexed by `MachOSymbols`.
- `Sources/SwiftInterface/Components/Definitions/TypeDefinition.swift` already has a `hasDestructor: Bool` property (near L54) and populates `hasDeallocator` from `symbolIndexStore.memberSymbols(of: .deallocator, ...)` inside `index(in:)` (near L202). The infrastructure exists but `hasDestructor` is never set and no symbol is materialized as a member.

**Modification points.**
1. `Sources/SwiftInterface/Components/Definitions/TypeDefinition.swift` — in the `index(in:)` method, after the existing `hasDeallocator` check:
   ```swift
   hasDestructor = !symbolIndexStore.memberSymbols(of: .destructor, for: typeName.name, in: machO).isEmpty
   ```
   assuming `SymbolIndexStore.MemberKind` already has `.destructor`. If not, add it.
2. `Sources/SwiftInterface/SwiftInterfacePrinter.swift` — the member printing paths (`printMembersByOffset` / `printMembersByCategory`) currently enumerate allocators, variables, functions, subscripts. Add a terminal step that emits:
   ```swift
   if definition.hasDestructor {
       BreakLine()
       Indent(level: level)
       Keyword("deinit")
   }
   ```
   The address of the destructor symbol should be emitted via `AddressComment` if `printMemberAddress` is on.
3. `Sources/MachOSwiftSection/Models/Type/Class/Method/MethodDescriptorKind.swift` — currently has `method`, `init`, `getter`, `setter`, `modifyCoroutine`, `readCoroutine`. Swift class vtables do **not** emit destructors as method descriptor entries (destructors are in the class heap metadata, not the vtable), so no change is needed here. Deinit is found via the symbol table, not the vtable.
4. For noncopyable structs: destructors are still emitted as symbols but are not class-hosted. Add a second symbol lookup pass via `symbolIndexStore.memberSymbols(of: .destructor, ...)` and attach the result to the `TypeDefinition` regardless of whether the type is a class.

**Verification.**
- `Noncopyable.NoncopyableTest` should now show a `deinit` line.
- Check that non-destructor-containing classes/structs do not gain a spurious `deinit`.
- Cross-reference: `Sources/MachOSymbols/` for how destructor symbols are indexed. The demangled symbol kind should be `.destructor` or `.deallocator`.

**Risk.** Low. This is additive.

**Effort.** Small (half a day).

---

### P1-9. Identical `typealias` extensions are emitted multiple times

**Symptom.** Conforming types gain 2–4 identical `extension` blocks containing the same typealiases.

**Source fixture.** `Tests/Projects/SymbolTests/SymbolTestsCore/CollectionConformances.swift::CustomBidirectionalCollectionTest` conforms to `Sequence` + `Collection` + `BidirectionalCollection`, and `CustomRandomAccessCollectionTest` conforms to four protocols.

**Current dump.**
```swift
extension ...CustomBidirectionalCollectionTest {
    typealias Element = Swift.String
    typealias Index = Swift.Int
    typealias SubSequence = ...
    typealias Indices = ...
}
extension ...CustomBidirectionalCollectionTest {
    typealias Element = Swift.String      // duplicate
    typealias Index = Swift.Int           // duplicate
    typealias Iterator = ...
    typealias SubSequence = ...           // duplicate
    typealias Indices = ...               // duplicate
}
```

The emitted sets come from one per-protocol synthesized-associated-type extension (e.g. one for `Sequence`'s `Element`/`Iterator`, one for `Collection`'s `Element`/`Index`/etc., one for `BidirectionalCollection`). The Swift compiler emits these separately because each protocol's witness table points to its own associated-type records.

**Goal.** Merge extensions that share the same extended type and where-clause, deduplicating typealias entries (matching by name + type).

**Modification points.**
1. `Sources/SwiftInterface/Components/Definitions/ExtensionDefinition.swift` and `SwiftInterfaceIndexer.swift` — during indexing, group extensions by `(extendedType, whereClauseFingerprint)` and union their associated-type entries.
2. `SwiftInterfacePrinter.swift::printExtensionDefinition` — when emitting an extension that carries merged associated-type witnesses, deduplicate by (name, resolved-type-string) before printing.

**Verification.**
- `CustomBidirectionalCollectionTest` should show **one** typealias extension containing the union set.
- `CustomRandomAccessCollectionTest` same.
- `Enums.OptionSetTest` — the duplicate `typealias Element = ...` should be collapsed.

**Risk.** If two extensions have the same extended type but genuinely different where clauses, they must **not** be merged. The fingerprint must incorporate the entire where clause textual (or canonicalized) form.

**Effort.** Medium (1 day). Main work is getting the grouping key right.

---

### P1-10. Synthesized `Equatable` / `Hashable` members appear in both the type body and the conformance extension

**Symptom.** For auto-synthesized conformances, `==`, `hash(into:)`, `hashValue`, `_rawHashValue` show up twice — once inside the type declaration (with address) and again in the `extension X: Hashable { ... }` block (also with address).

**Source fixture.** `Tests/Projects/SymbolTests/SymbolTestsCore/Enums.swift::NoPayloadEnumTest`, `RawValueEnumTest`, many others.

**Current dump.**
```swift
enum NoPayloadEnumTest {
    case north, south, east, west

    // Address: 0x3B94
    static func == (_:, _:) -> Swift.Bool
    // Address: 0x3BA8
    func hash(into: inout Swift.Hasher)
    // Address (getter): 0x3BD0
    var hashValue: Swift.Int { get }
}
extension ...NoPayloadEnumTest: Swift.Equatable {
    // Address: 0x6DEC
    static func == (_: Self, _: Self) -> Swift.Bool
}
extension ...NoPayloadEnumTest: Swift.Hashable {
    // Address: 0x6DF0
    func _rawHashValue(seed: Swift.Int) -> Swift.Int
    // Address: 0x6E04
    func hash(into: inout Swift.Hasher)
    ...
}
```

The two sets even have different addresses, because one is the concrete witness implementation attached to the nominal type and the other is the generic witness thunk in the conformance witness table.

**Goal.** For synthesized `Equatable` / `Hashable` (and analogous: `Codable`, `CaseIterable`, `RawRepresentable`, `CodingKey`), prefer the **conformance extension** as the canonical location and suppress the duplicate inside the type body. The type body should only retain members that the user actually declared in source.

**Evidence.** The synthesized thunks emit under the conformance descriptor, while the witness impls emit under the nominal type. Swift's own `.swiftinterface` text files do this the other way around — they list the member inside the type body and omit the conformance extension details. Either convention is valid; the important thing is no duplication.

**Heuristic for detection.**
- Compare method descriptors vs. symbols in the nominal type's symbol set. A method that exists **only** as a witness symbol (i.e., is referenced from the conformance's witness table but is not in the class vtable / protocol witness table of the type itself) is a synthesized thunk.
- Alternatively, match on demangled kind: the conformance-extension versions print with a `Self` parameter type, whereas the nominal-type-body versions print with the concrete type. Dedup by `(memberName, labelList, staticness)` regardless of parameter type variation.

**Modification points.**
1. `Sources/SwiftInterface/Components/Definitions/TypeDefinition.swift::applyThunkAttributes` — already cross-references thunk symbols with built definitions. Extend the same approach: before accepting a member into `functions` / `staticFunctions`, check whether an equivalent member also exists in the type's declared conformance extensions, and drop the body-side entry in that case.
2. Configuration flag: `deduplicateSynthesizedProtocolMembers: Bool` defaulting to `true` (most users want clean output). Set to `false` in a debug dump mode to see both addresses.

**Verification.**
- `NoPayloadEnumTest`, `RawValueEnumTest`, `SimpleErrorTest`, `CodableEnumTest.*CodingKeys` must show `==` / `hash(into:)` / `hashValue` / `_rawHashValue` only once (in the extension).
- User-declared `==` overrides in types that also auto-synthesize Equatable must still appear (do not over-dedup).

**Risk.** Medium. The heuristic must not eat user-declared `Equatable.==` overrides. Add a test fixture with a custom `==` implementation inside the type body to guard against regression.

**Effort.** Medium-large (1–2 days).

---

### P1-11. `printFieldOffset` / `printTypeLayout` / `printEnumLayout` never fire — **moved to L-11**

These three config flags fundamentally require an in-process `MachOImage` and cannot be serviced from a file-mode `MachOFile`. See [L-11](#l-11-printfieldoffset--printtypelayout--printenumlayout-require-a-running-machoimage) in Known limitations.

---

## Phase 2 — new metadata reading

These items require extending `Sources/MachOSwiftSection/Models/*` to read bits of the binary that the project does not currently parse.

### P2-12. Global actor isolation (scoped down — mostly ABI-limited)

**Original symptom.** Methods on `@MainActor`-annotated types and methods explicitly tagged `@MainActor` do not show the isolation attribute.

**Status after investigation.** Largely **ABI-limited**. The earlier plan assumed that `TargetFunctionGlobalActorMetadata` + `FunctionTypeFlags::GlobalActorMask` could be read for arbitrary class methods. This is incorrect: those live on **function type metadata records**, which only exist for function type *values* (e.g. `var closure: @MainActor () -> Int`). Swift class method descriptors do **not** embed function type metadata — they embed flags + an impl pointer, and the signature is reconstructed from the impl symbol's mangled name. Method-level global-actor isolation is simply not in the mangled name for sync or async class methods (verified empirically with `swiftc` + `swift demangle` for both class-level and per-method `@MainActor`).

#### What already works

Function type values with a global actor ARE mangled and printed correctly today. The mangled form contains `ScMYc...` (class-actor reference `ScM` + `globalActorFunctionType` `Yc`), and `Sources/SwiftInterface/NodePrintables/FunctionTypeNodePrintable.swift:42,113-115` already dispatches on `.globalActorFunctionType` to emit `@Swift.MainActor`. Covered cases:

- **Closure parameters** — `FunctionFeatures.MainActorClosureTest.acceptMainActorClosure(_:)` prints as `func acceptMainActorClosure(_: @Swift.MainActor @Sendable () -> ())`. ✓
- **Closure return types / typealiases / property types** — any spot where the source writes `@MainActor () -> T` at the function type position.

No code change is required for these; the existing node printer handles them.

#### ABI limitation 1 — class-level `@MainActor`

```swift
@MainActor public class C { public func f() -> Int { 0 } }
```

There is **no `ClassFlags` bit** for class-level global-actor isolation, and the class descriptor does not reference a global actor type. The class is indistinguishable from a plain class in the binary. Acknowledged in the "Known limitations" section below.

#### ABI limitation 2 — method-level `@MainActor` on a class method

```swift
public class D {
    @MainActor public func g() -> Int { 0 }
}
```

The method impl symbol is `_$s8TestMain1DC1gSiyF`, which demangles to `D.g() -> Int` — no `ScM`, no `Yc`, no isolation marker. Empirically verified with `swiftc -emit-library` + `nm`. The same holds for `async` variants (`YaF` — async bit set, global-actor bit absent). There is no secondary symbol, no trailing metadata, no hidden descriptor that carries this information. `TargetFunctionGlobalActorMetadata` is only populated for function *type values*, not class method descriptors, so reading it would not recover this data either.

Method descriptors carry `MethodDescriptorFlags` (`Sources/MachOSwiftSection/Models/Type/Class/Method/MethodDescriptorFlags.swift`) which has room for kind / isInstance / isAsync / isDynamic / extra discriminator — there is **no** global-actor bit and no reference to an actor type.

#### Recoverable subset: protocol conformance global-actor isolation

```swift
@MainActor extension Foo: SomeProtocol { ... }
```

This **is** recoverable. `ProtocolConformanceFlags::hasGlobalActorIsolation` (bit 19) is set and the conformance descriptor has a trailing **reference to the global actor type** (see `swift/include/swift/ABI/Metadata.h` — `TargetProtocolConformanceDescriptor::getGlobalActorIsolationType`). Evidence already in the project:

- `Sources/MachOSwiftSection/Models/ProtocolConformance/ProtocolConformanceFlags.swift:27,81-83` — flag is defined and a public `hasGlobalActorIsolation` getter exists.
- `Sources/MachOSwiftSection/Models/ProtocolConformance/ProtocolConformance.swift` (or its descriptor) — does **not** yet read the trailing `globalActorIsolation` reference.

This subset is the only piece that can be honestly implemented. Scope:

1. Extend `ProtocolConformanceDescriptor` (and its trailing-object layout) to read the trailing `RelativeDirectPointer<MangledName>` (conditional on `hasGlobalActorIsolation`).
2. Expose `globalActorTypeName: MangledName?` / `globalActorTypeNode: Node?` on `ProtocolConformance`.
3. In `SwiftInterfacePrinter.printExtensionDefinition`, when `extensionDefinition.protocolConformance?.globalActorTypeNode` is non-nil, emit `@<resolved actor type>` in front of the `extension` keyword.

#### Verification (scoped to the recoverable subset)

- `FunctionFeatures.MainActorClosureTest` — already prints `@Swift.MainActor` in closure parameter positions; no code change required (regression guard).
- `Actors.MainActorAnnotatedTest.method` — **will not gain** `@MainActor`. Document in fixture comments.
- `Actors.GlobalActorAnnotatedClass.method` — **will not gain** `@CustomGlobalActor`. Document in fixture comments.
- New fixture (or reuse of existing): `@MainActor extension Foo: SomeProtocol { ... }` — the `extension` block should print `@Swift.MainActor extension Foo: SomeProtocol`.

#### Effort (scoped)

Small-medium (half a day): conformance descriptor layout extension + node-emit path in the extension printer. Skipped portion (method-level) costs 0 because it is not feasible.

---

### P2-13. `distributed actor` / `distributed func`

**Symptom.** `public distributed actor X` prints as plain `actor X`; `public distributed func remoteMethod` prints as plain `func remoteMethod`.

**Source fixture.** `Tests/Projects/SymbolTests/SymbolTestsCore/DistributedActors.swift`.

**Evidence.**
- Actor classification: `swift/include/swift/ABI/MetadataValues.h:1973-1981` — `ClassFlags::Class_IsActor` (bit 7) and `Class_IsDefaultActor` (bit 8). A distributed actor is specifically a class with both bits set plus a non-local-only actor-system conformance. There is **no** dedicated `IsDistributedActor` class bit; the distinction is recovered by presence of a `DistributedActor` conformance and/or the distributed-thunk symbols.
- Distributed method: `swift/include/swift/ABI/MetadataValues.h:3054-3062` — `ActorFunctionFlags::Distributed` (bit 0) on function metadata. Additionally, `DistributedThunk` / `DistributedAccessor` node kinds in `swift-demangling/Sources/Demangling/Node/Node+Kind.swift` mark the emitted thunk/accessor symbols. Presence of a `DistributedThunk(f)` for method `f` in the symbol table implies `f` is `distributed`.
- `Sources/MachOSwiftSection/Models/Type/Class/ClassDescriptor.swift:65-66` — already exposes `isActor`. This is read from `ContextDescriptorFlags.kindSpecificFlags` bit layout.
- `Sources/MachOSwiftSection/Models/Type/Class/ClassFlags.swift:6-22` — only defines 5 flags and does **not** currently include `IsActor` or `IsDefaultActor`.

**Modification points.**
1. `Sources/MachOSwiftSection/Models/Type/Class/ClassFlags.swift` — add the full bit layout (see `MetadataValues.h:1930-2000` for the authoritative list): `IsSwiftPreStableABI`, `UsesSwiftRefcounting`, `HasCustomObjCName`, `IsActor`, `IsDefaultActor`, and the resilience bits.
2. `ClassDescriptor` — read `ClassFlags` via the class metadata (when accessible) or via the `metadataPositiveSizeInWordsOrExtraClassFlags` field for resilient-superclass types.
3. New inferrer: distinguish "actor" (Class_IsActor set, no distributed thunks) from "distributed actor" (Class_IsActor set AND at least one `DistributedThunk` symbol for a method of the class). Record the finding on the `TypeDefinition`.
4. `ClassDumper.declaration:44-46` — extend the `isActor` branch to check the distributed-actor flag and emit `Keyword("distributed") Space() Keyword(.actor)`.
5. `MethodDescriptorFlags` or a new `ActorFunctionFlags` reader — for method descriptors associated with the actor class, the `Distributed` bit must be read. Alternatively, match on the presence of a `DistributedThunk` symbol pointing at that method's impl address.
6. `ClassDumper.dumpMethodKeyword:392` — when the method is flagged as distributed, emit `Keyword("distributed") Space()` before `func`.

**Verification.**
- `DistributedActors.DistributedActorTest` → `public distributed actor DistributedActorTest`.
- Its `remoteMethod` / `remoteThrowingMethod` / `parameterizedMethod` → `public distributed func ...`.
- `Actors.ActorTest` (non-distributed) → continues to print `actor ActorTest` and its methods without `distributed`.

**Risk.** Medium. The distributed-thunk ↔ original-method correlation needs careful implementation: the thunk's demangled node points back at the original method via a wrapping structure, not a symbolic reference.

**Effort.** Medium-large (2 days). Main work is the thunk correlation + class-flag plumbing.

---

### P2-14. `@objc` attribute from `ClassFlags::HasCustomObjCName` — **deferred, low priority**

**Status (2026-04-15).** After investigation, the implementation cost does not justify the value for this repo's workflow. Skipped indefinitely. Revisit only if a concrete downstream use case appears (e.g. a dyld-cache target where `@objc("CustomName")` classes are common and the custom name is actually needed for reverse engineering).

**Why deferred:**
1. **`HasCustomObjCName` is not the same as `@objc`.** The flag is set **only** for `@objc("CustomName") class Foo: NSObject`, i.e. when the user gave an explicit Obj-C alias. Plain `@objc class Foo: NSObject` (no custom name) and methods/properties marked `@objc` do **not** set the flag. A Swift class without `NSObject` ancestry cannot legally be `@objc` at all, so the attribute is redundant for the cases where `@objc` is already visible from the `: NSObject` superclass.
2. **No independent class-level `@objc` bit exists.** The secondary-signal path (scan for `.objCAttribute` thunk symbols and mark the class as `@objc` if any exist) is what `TypeDefinition.applyThunkAttributes` already does for methods/properties — it does not recover zero-member `@objc class`es and does not recover a custom ObjC name.
3. **Recovering `@objc("CustomName")` requires address matching.** `ObjCClass64.Layout.swiftClassFlags` is available in file mode via `MachOObjCSection`, but correlating each `ObjCClass64` back to a Swift `ClassDescriptor` means bridging through `symbolIndexStore.symbols(of: .typeMetadata, in: machO)` (`_$s<mangled>N` records) or computing the Swift metadata's offset from the class accessor function — both are new infrastructure with ABI-level pitfalls (offset from ObjC class start to Swift metadata entry point, pointer authentication, rebase handling).
4. **Fixture cost.** Current `Attributes.ObjCAttributeClass: NSObject` only exercises method-level `@objc` (already handled via thunk attributes). A new fixture `@objc("Name") public class Foo: NSObject { ... }` would have to be added and `SymbolTestsCore.framework` rebuilt, and all snapshot outputs updated.

**If revived in the future**, the implementation path would be:
- Read `ObjCClass64.Layout.swiftClassFlags` by walking `machO.objc.classes64` (file mode) / `classes` (image mode).
- Correlate the `ObjCClass64` to a Swift `ClassDescriptor` via the nominal-type-metadata symbol (`_$s...N`) lookup in `SymbolIndexStore`, matching by offset.
- Read the ObjC class's `classROData.name(in: machO)` to recover the user-visible custom name.
- Emit `@objc("CustomName")` from `TypeAttributeInferrer` by exposing a new `objcCustomName: String?` field on `TypeDefinition`.
- Fixture: add `@objc("CustomObjCName") public class Foo: NSObject { ... }` to `Attributes.swift`.

The original spec is retained below for reference.

---

**Symptom.** `@objc`-annotated classes do not show the attribute (exception: classes inheriting from `NSObject` are obvious from the superclass, but an explicit `@objc` on a Swift-native class is lost).

**Source fixture.** `Tests/Projects/SymbolTests/SymbolTestsCore/Attributes.swift::ObjCAttributeClass`.

**Evidence.**
- `swift/include/swift/ABI/MetadataValues.h:349-378` — `ClassFlags::HasCustomObjCName` (0x4) and `UsesSwiftRefcounting` (0x2).
- `Sources/MachOSwiftSection/Models/Type/Class/ClassFlags.swift:6-22` — the enum cases `hasCustomObjCName` and `usesSwiftRefcounting` are already defined but never bound to a descriptor reader.
- `Sources/SwiftInterface/AttributeInference/TypeAttributeInferrer.swift:147-154` — comment acknowledges the information lives in runtime `swiftClassFlags` but no reader exists.

**Modification points.**
1. After P2-13 exposes `ClassFlags` on `ClassDescriptor`, read `HasCustomObjCName` / `UsesSwiftRefcounting`.
2. `TypeAttributeInferrer` — emit `SwiftAttribute.objc` when `HasCustomObjCName` is set.
3. Also extend the existing thunk-based `@objc` / `@nonobjc` inference in `TypeDefinition.applyThunkAttributes` to cover methods (not just members); both paths should agree.

**Verification.**
- `Attributes.ObjCAttributeClass` should gain `@objc` at the class level.
- `Classes.ExternalObjCSubclassTest: __C.NSObject` — already inherits `NSObject`, no redundant `@objc`.
- Methods `@objc func objcMethod()` already work through the thunk path; do not regress.

**Risk.** Low. Additive.

**Effort.** Small (half a day, assuming P2-13 already added the `ClassFlags` reader).

---

## Phase 3 — cross-cutting cleanup

Items that are neither missing modifiers nor missing declarations, but improve the overall quality / consistency of the output.

### P3-15. Comment label capitalization consistency

**Symptom.** The same comment kind is rendered with different capitalization:
```
// VTable Offset: 14            ← PascalCase
// protocol witness table offset: 0x18    ← lowercase
// Address: 0x1234
// Address (getter): 0x5678
// field offset: 0x0             ← lowercase
```

**Root cause.** `Sources/SwiftInterface/SwiftInterfacePrinter.swift:250`:
```swift
let offsetCommentPrefix = isProtocol ? "protocol witness table offset" : "field offset"
```
and `VTableOffsetComment` literal uses `"VTable Offset"`.

**Goal.** Pick one convention for all comments and apply it consistently. Recommendation: PascalCase with abbreviations capitalized (matches the vtable / address comments):
- `VTable offset`
- `PWT offset`  (short form; consistent with `VTable offset`; mention full `protocol witness table` only in help docs)
- `Field offset`
- `Address`
- `Address (getter)` / `Address (setter)` / `Address (modify)`

**Modification points.**
1. `SwiftInterfacePrinter.swift:250` — update both branches of `offsetCommentPrefix`.
2. `VTableOffsetComment` definition (search for it in `Semantic` / `SwiftInterfacePrinter.swift`) — ensure label matches.
3. Search for any hardcoded `"vtable"` / `"VTable Offset"` / `"protocol witness"` strings across `Sources/SwiftInterface/` and normalize.
4. Existing snapshot tests will break — update the snapshot files or add a `printLabelCapitalization` override for backward compat.

**Risk.** Low, but invalidates any external tooling or saved snapshots that grep on these labels. Consider gating behind a `labelCasing: .pascalCase / .lowercase` config.

**Effort.** Small (2 hours, plus snapshot updates).

---

### P3-16. Duplicate `init(actorSystem:)` on distributed actors

**Symptom.** Distributed actor classes show `init(actorSystem:)` twice — once with a vtable offset, once without.

```swift
actor DistributedActorTest {
    var $defaultActor: Builtin.DefaultActorStorage
    ...
    // VTable Offset: 18
    // Address: 0x18060
    init(actorSystem: Distributed.LocalTestingDistributedActorSystem)    // synthesized required init
    ...
    // Address: 0x18F0C
    init(actorSystem: Distributed.LocalTestingDistributedActorSystem)    // resolve-path init
}
```

**Explanation.** The distributed actor compiler synthesizes two initializers:
1. A `required init(actorSystem:)` that routes through `resolve(id:using:)`.
2. A vtable-registered synthesized initializer used as the direct entry point.

Both have the same Swift signature but different SIL roles and different implementation addresses. The dump currently emits both without any annotation to distinguish them.

**Goal.** Either (a) deduplicate to a single entry or (b) annotate each with a comment indicating its role (`// synthesized default init`, `// resolve-path init`).

Recommendation: keep both, annotate them. Reverse engineers care about both addresses.

**Modification points.**
1. `Sources/SwiftInterface/SwiftInterfacePrinter.swift::printMembersByOffset` / `printMembersByCategory` — when emitting a constructor, look at the demangled node's parent context: distributed-actor synthesized inits have a specific `DistributedAccessor` / `DistributedThunk` parent (or a distinguishing mangled discriminator).
2. Emit an `InlineComment("synthesized default init")` or `InlineComment("distributed resolve init")` before each duplicate.
3. Alternatively, add a dedup pass keyed by `(name, labelList, paramTypes, staticness)` in the constructor list builder — but **only** for the distributed-actor case (controlled by flag).

**Risk.** Low. Additive annotations only.

**Effort.** Small (half a day).

---

### P3-17. `ResultBuilderDSL.FullResultBuilderTest` has duplicated `buildBlock`

**Symptom.**
```swift
@resultBuilder
struct FullResultBuilderTest {
    ...
    // Address: 0x23E9C
    static func buildBlock(_: [Swift.Int]...) -> [Swift.Int]
    ...
    // Address: 0x241B0
    static func buildBlock(_: [Swift.Int]...) -> [Swift.Int]     // duplicate
}
```

The source file declares `buildBlock` exactly once.

**Investigation needed.** Verify whether the two entries correspond to:
- Two distinct method descriptors pointing at the same impl (shared / inlined body), or
- Two distinct symbol indexes picked up by separate code paths (e.g. one from vtable enumeration, one from symbol-table scan).

**Modification points.**
1. Add a dedup pass in `DefinitionBuilder.functions` keyed on `(demangled node canonical form, impl offset)`. When two entries resolve to the same `(name, labelList, paramTypes, impl address)`, keep one.
2. If the entries have **different** impl addresses but the same mangled name, preserve both (the compiler really did emit two specializations).

**Verification.**
- `FullResultBuilderTest.buildBlock` should appear once.
- `PartialResultBuilder` (if any) should still show all overloads.
- No regressions in the general `OverloadedMembers` section (real overloads must be preserved).

**Risk.** Medium — getting the dedup key wrong kills real overloads.

**Effort.** Small (half a day of investigation + dedup rule).

---

### P3-18. Raw `print(duration)` output leaks into the test dump

**Symptom.** The test dump contains `1.404236291 seconds` as a top-level string, because `SwiftInterfaceBuilder.prepare()`'s duration is printed via `print()` inside the test helper.

**Origin.** `Tests/SwiftInterfaceTests/SwiftInterfaceBuilderTests.swift:47-51` — the helper measures and prints before returning.

**Fix.** Route the duration through `SwiftInterfaceEvents` instead of stdout, or drop the print in silent-test mode (`MACHO_SWIFT_SECTION_SILENT_TEST=1`).

**Modification points.**
1. `Tests/SwiftInterfaceTests/SwiftInterfaceBuilderTests.swift:47` — wrap the `print(duration)` in `if !silentTest { ... }`.
2. Longer-term: `SwiftInterfaceBuilder.prepare()` should dispatch a `.prepareFinished(duration:)` event that the test can subscribe to.

**Risk.** Trivial.

**Effort.** 10 minutes.

---

## Known limitations (binary metadata cannot recover)

These items were requested in the original analysis but **cannot** be implemented from MachO Swift metadata alone. The root cause and, where applicable, the alternate data source are documented.

### L-1. `init!` vs `init?`

**Why not.** New Swift mangling (`swift/include/swift/Demangling/StandardTypesMangling.def:56`) has only `q → Optional`. There is no independent `ImplicitlyUnwrappedOptional` mangling. Old Swift 3.x demangler (`swift/lib/Demangling/OldDemangler.cpp:918`) had `Q → ImplicitlyUnwrappedOptional`, but that path is not used by the new runtime. Source-level `init!(...)` compiles to the same binary form as `init?(...)`; the `!` information is lost during name mangling. `swift-demangling`'s `SugarType.implicitlyUnwrappedOptional` only exists on the AST side, never on the binary side.

**Alternate sources** (not in MachO metadata):
- `.swiftinterface` text files (if available) explicitly encode `init!`.
- DWARF debug info encodes source-level type information including IUO.
- Heuristic: parameter naming convention (e.g. `unsafe*`). Unreliable; not recommended.

**Status.** The existing `FunctionNodePrinter.initFailabilityKind` infrastructure was added during the P0 work in preparation for a future hybrid printer that can consume either `.swiftinterface` or DWARF as an auxiliary input, but the `.implicitlyUnwrappedOptional` branch will never fire from MachO-only input. Leave in place as a forward-compatibility hook.

---

### L-2. `@frozen` attribute

**Why not.** `TypeContextDescriptorFlags` does not have an `IsFrozen` bit. `ProtocolContextDescriptorFlags::IsResilient` exists for protocols but is irrelevant for struct / enum frozen. For struct/enum, the frozen vs resilient distinction is carried implicitly: non-library-evolution modules are always frozen; library-evolution modules carry `HasResilientSuperclass` only on classes.

**Alternate sources.** `.swiftinterface` files carry `@frozen` explicitly.

**Proxy.** For a binary-only workflow, one could infer "likely frozen" from the absence of a type metadata initializer (frozen types don't need one) — weak signal, do not rely on it for printing the keyword.

---

### L-3. Class-level `@MainActor` / `@CustomGlobalActor`

**Why not.** `ClassFlags` in `MetadataValues.h` has no global-actor bit. The `TargetFunctionGlobalActorMetadata` trailing object is per-function-type, not per-class. Swift's global-actor attribute is enforced at the type checker / code generator level; once the class metadata is emitted, the annotation is gone.

Method-level `@MainActor` isolation **is** recoverable (see P2-12).

---

### L-4. `indirect enum` at type level

**Why not.** `TargetEnumDescriptor` (`swift/include/swift/ABI/Metadata.h:4954-4957`) only carries `NumPayloadCasesAndPayloadSizeOffset` + `NumEmptyCases`. No `IsIndirect` bit at the enum level. A per-case `indirect` flag exists in the field record's case payload metadata and the current dump already prints it per-case. For an enum declared `indirect enum X { ... }` (all cases implicitly indirect), there is no way to know whether the user wrote `indirect enum` or just marked every case individually; the binary form is identical.

**Proxy.** If every payload case's value witness table indicates boxed payloads, one could emit `indirect enum X { ... }` in the declaration. Too fragile to pursue.

---

### L-5. `open` vs `public`

**Why not.** Swift mangling and all descriptor flags treat `open` and `public` identically — they are source-level concepts for subclassing/overriding control, not runtime concepts. Once the class is emitted, the difference is not recoverable.

**Alternate sources.** `.swiftinterface`.

---

### L-6. `@objc enum` cases

**Why not.** `swift/lib/IRGen/GenReflection.cpp:1831-1836` explicitly skips emitting a `FieldDescriptor` for enums where `strategy.isReflectable() == false`, and `@objc` Int-raw-value enums fall into this bucket (see `GenEnum.cpp:1420-1425` for the `isReflectable()` override returning `false` for C-style enums). Therefore the case names do not appear in `__swift5_fieldmd`.

**Alternate sources.** Read the Objective-C runtime side: `__objc_classlist` for the underlying Obj-C class, `_OBJC_$_CATEGORY_` for methods, and the Obj-C runtime's enum metadata encoding (`@encode(...)`-style introspection). Requires extending the project to parse the Obj-C side, which is out of scope for a Swift-only tool.

---

### L-7. `mutating` / `consuming` / `borrowing` on methods (self ownership)

**Why not.** `swift/lib/Demangling/Demangler.cpp::demangleFunctionEntity` (around line 4162-4250) does not encode self-ownership. The SIL function type carries `@owned` / `@guaranteed` / `@inout` conventions on the self parameter, but these do not survive into the stable mangling used for runtime symbols.

**Not to be confused with:**
- P1-7 above (`consuming` on a **parameter**) — this *is* in the mangling and is recoverable.
- `mutating` / `consuming` / `borrowing` on **methods** — *not* in the mangling.

---

### L-8. `@available`

**Why not.** No availability attribute appears in `__swift5_types`, `__swift5_fieldmd`, `__swift5_proto`, or any descriptor. Availability is a source-level attribute used by the compiler for diagnostics and by the linker for weak-link resolution, but not written into reflective metadata.

**Alternate sources.** `.swiftinterface` text, or weak-link stubs in the symbol table (very weak signal for function-level availability).

---

### L-9. `@inlinable` / `@usableFromInline`

**Why not.** `@inlinable` is compiler-only (it enables cross-module inlining; no runtime trace). `@usableFromInline` affects emission but the runtime has no way to distinguish an `@usableFromInline internal` member from a `public` member — both appear in `__swift5_types` if referenced by an `@inlinable` function.

---

### L-10. Top-level and nested `public typealias` declarations

**Why not.** `__swift5_types` registers only nominal types (struct / class / enum / protocol). `public typealias Foo = Bar<X>` does not get a descriptor. Only `associatedtype` witnesses carry typealias-like records (inside protocol conformance descriptors) and those *are* recovered today.

**Alternate sources.** `.swiftinterface`.

---

### L-11. `printFieldOffset` / `printTypeLayout` / `printEnumLayout` require a running `MachOImage`

**Why not.** Field offsets, full type layout, and multi-payload enum layout all depend on the Swift runtime's metadata instantiation path. The static descriptor fields in `__swift5_types` are **not** authoritative for these:

- **Field offsets.** `TargetStructDescriptor::FieldOffsetVectorOffset` is a *vector offset* into the metadata record, not the offsets themselves. The actual per-field offsets are populated by `swift_initStructMetadata` / `swift_initClassMetadata` at runtime, which consults each field's value witness table (size / alignment / stride) and may reorder or pad fields based on platform ABI, noncopyability, and resilience strategy. There is no binary-safe way to pre-compute this from the descriptor alone.
- **Class fields with resilient superclasses.** Offsets are relative to the superclass's (also runtime-resolved) size — unknowable statically.
- **Type layout for generic types.** Obviously requires a concrete instantiation, which only exists at runtime.
- **Type layout for non-generic types.** The value witness table itself is a relative pointer to a runtime-populated structure; the size/stride/flags fields read from the VWT symbol are not populated until `swift_getCanonicalPrespecializedGenericMetadata` (or the analogous struct/enum initializer) runs.
- **Multi-payload enum layout.** `EnumLayoutCalculator` needs the payload cases' VWTs resolved, which again routes through runtime metadata. Even for `@frozen` enums, the spare-bit computation depends on `size`/`stride`/`extraInhabitantCount` of payload types, and those are only authoritative post-instantiation.

**What actually works.** The existing `StructDumper.fieldOffsets` / `ClassDumper.fieldOffsets` / `EnumDumper.fields` code paths all do the right thing when `machO.asMachOImage != nil` (i.e., when the dumper was invoked against a `MachOImage` bound to the running process). That is the supported execution mode for these flags.

**What does not work.** Invoking `printFieldOffset` / `printTypeLayout` / `printEnumLayout` against a file-mode `MachOFile` (e.g., when the binary is not the current process, or is from a different architecture). The flags silently produce no output rather than error, which is a usability bug — see follow-up below.

**Follow-up.** Rename or error out: when the input is a `MachOFile` and any of these flags is on, either (a) log a `SwiftInterfaceEvent` warning stating the flag is ignored in file mode, or (b) rename the flags to `printRuntimeFieldOffset` / etc. to make the runtime requirement explicit at the API level. This is a documentation/ergonomics fix, not a functional implementation, and does not expand the set of supported inputs.

**Alternate sources** (out of scope for this roadmap):
- Attach to a live process via `MachOImage` and let the existing code path run.
- Parse `__swift5_reflstr` + actual runtime dump output (e.g., from `swift-reflection-dump`). The reflection runtime already computes these offsets and can be queried.
- DWARF `DW_AT_data_member_location` on debug builds — available only in debug binaries.

---

## Prioritization

The order below reflects uniqueness × user value × implementation cost.

1. **P1-8 (deinit)** — Small, additive, unblocks understanding of class lifecycle. The `hasDestructor` flag already exists.
2. **P1-5 (`@escaping`)** — Small, high visibility. Every closure parameter is wrong today.
3. **P3-15 (label capitalization)** — Cosmetic but trivial. Do it when touching nearby code.
4. **P1-7 (consuming param)** — Small, scoped. Needed for noncopyable API fidelity.
5. **P1-9 (duplicate typealias extensions)** — Medium, visible cleanup.
6. **P2-12 (method-level `@MainActor`)** — Medium-large but high value for modern code.
7. **P2-13 (`distributed actor` / `distributed func`)** — Medium-large. Depends on expanded `ClassFlags` reader.
8. **P1-6 (DependentMemberType canonicalization)** — Medium, visible on protocol-heavy targets (SwiftUICore).
9. **P1-10 (synthesized member dedup)** — Medium. Risk of eating user code; gate behind a flag.
10. **P3-16 (distributed actor duplicate init)** — Small cosmetic.
11. **P3-17 (duplicate `buildBlock`)** — Small, needs investigation first.
12. **P3-18 (test helper `print(duration)`)** — Trivial.

Removed from the list:
- **P1-11** moved to [L-11](#l-11-printfieldoffset--printtypelayout--printenumlayout-require-a-running-machoimage) — the underlying data requires a running `MachOImage`.
- **P2-14** deferred indefinitely — `HasCustomObjCName` only covers the `@objc("CustomName")` variant, and recovering the custom name requires non-trivial address matching between `ObjCClass64` and Swift `ClassDescriptor`. See the P2-14 section for the full rationale.

---

## Not in scope for this roadmap

- ObjC interop side (would enable L-6, L-9 partially). Separate project.
- `.swiftinterface` merging / DWARF ingestion (would enable L-1, L-2, L-3, L-5, L-8, L-10). Requires architectural work beyond a single printer upgrade.
- Format changes to `Roadmaps/2026-04-10-feature-candidates.md` items (ABI diff, hidden-API finder, PWT content reconstruction). Those are product-level features; this roadmap only scopes correctness of the existing `buildString` output.
