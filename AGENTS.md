# AGENTS.md
This file provides guidance to coding agents when working with code in this repository.

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

`SwiftLayout` (static field-offset engine) is a peer that depends on
`SwiftInspection` + `MachOSwiftSection` (+ `MachOObjCSection` for ObjC-ancestor
instance sizes). It backs the static ABI-analysis path and is consumed by
`SwiftDeclarationRendering`, whose `FieldLayoutRenderer` is reader-specialized:
the `MachOImage` path renders field-offset / type-layout / expanded-tree / enum-layout
comments from in-process runtime metadata, while the `MachOFile` (offline) path
computes the same comments statically through SwiftLayout — so `swift-section dump`
/ `interface` on a file now emit real field offsets without loading the process.
The offline path also renders **generic** types' layouts where SwiftLayout can
resolve them unspecialized (class-bound parameters, parameter metatypes,
generic enums via `enumCaseLayoutResult`), computes payload/enum layouts in the
descriptor's context (`typeLayout(forMangledTypeName:inContextOfDescriptor:)`),
and emits a `Field offset: unknown (<reason>)` comment for a field it genuinely
cannot place (distinguishing "engine cannot know" from "flag off").
See [Documentations/Internal/FieldLayoutRendererReaderSpecialization.md](Documentations/Internal/FieldLayoutRendererReaderSpecialization.md).

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
- `EnumLayoutCalculator` - Predicts enum memory layouts from the runtime's formulas (single-payload XI/overflow, multi-payload spare-bits/tagged). Per-case projections carry `declaredName` (source-level case name), `isPayloadCase`, and a `patternResolution`: `.exactBytes` when `memoryChanges` is authoritative, `.unresolvedExtraInhabitant` when only the extra-inhabitant *index* is known — a formula over the XI *count* cannot recover the concrete bytes (a class reference's XI are small invalid addresses, `String`'s are `_StringObject` discriminator patterns, nested payloads compose recursively), so the offline path renders an honest "not resolved offline" note instead of fabricating patterns. Audited line-by-line against `EnumImpl.h`/`Enum.cpp`/`GenEnum.cpp`/`TypeLowering.cpp` (see [Documentations/Internal/EnumLayoutAuditFixes.md](Documentations/Internal/EnumLayoutAuditFixes.md)): empty cases record the **whole** payload area (tagged zero-extension + spare-bits zero-APInt scatter both fix every payload byte), spare-bits payload cases carry per-byte `fixedBitMasks` (only the common spare bits are fixed — a tag byte shared with live payload storage is never claimed whole, e.g. two-`Bool` payloads), `calculateSinglePayload` takes no `size` (callers cross-check `LayoutResult.impliedTotalSize(payloadAreaSize:)` against the enum's VWT size and discard mismatches), and the runtime backend resolves an `indirect` payload's XI as `heapObjectExtraInhabitantCount` (`INT_MAX` on 64-bit Darwin) — an indirect single-payload enum is an XI layout (`leaf` = null box pointer), not the overflow layout it was once misdescribed as; an unresolvable payload XI is recovered exactly from the enum's own VWT (`payloadXI = enumXI + emptyCases` when payload-sized) or the layout is not rendered at all
- `RuntimeEnumCaseProjector` - Resolves those patterns **exactly** when the enum's metadata is live in-process: dual-baseline (`0x00`/`0xFF`) `destructiveInjectEnumTag` injection diffs out each case's fixed bytes, `getEnumTag` round-trip guards empty cases, ptrauth (arm64e) degrades to `nil`. Used by `RuntimeFieldLayoutBackend` for single-payload enums via `LayoutResult.applyingExactCasePatterns` (multi-payload patterns come exact from the `__swift5_mpenum` spare-bit mask already); this is what renders `Text.Style.LineStyle`-style comments as `bytes[0x8..<0x10] = 0x1` instead of a placeholder. See [Documentations/Internal/RuntimeEnumCaseProjection.md](Documentations/Internal/RuntimeEnumCaseProjection.md)
- `Transformer.SwiftEnumLayout` (in `SemanticTransformer`, bridged here) - Token-template rendering for enum-layout comments: three template levels (strategy line / per-case block / per-fixed-byte line) with `${token}` placeholders, plus five presets — `detailed` (the built-in default, unit-test-guaranteed identical to `EnumCaseProjection.description`, which is implemented over it), `explained` (partially-fixed bytes narrated as bit ranges: `bits 7-4 are always 0100; the other bits (3-0) hold payload data`), `standard` (no per-byte lines), `inline` (one line per case with the byte summary inline after the header: `` Case 1 `implicit` (empty case #0): bytes[0x8..<0x10] = 0x1 ``, via the colon-friendly `${fixedBytesPhrase}` token), `compact` (one line per case, no byte information). `SwiftInspection`'s bridge (`Transformer+EnumLayoutProjection.swift`) builds the template inputs from `LayoutResult`/`EnumCaseProjection`; wiring goes through `applyTransformers` (see the `SemanticTransformer` module below) and the CLI's `--enum-layout-style`. Conditional content uses line-tokens (`${encodingLine}`, `${patternNoteLine}`) — lines left empty after substitution are dropped; a case template referencing no byte tokens gets the note/byte lines auto-appended (`appendsOmittedDetails`, the historical RuntimeViewer behavior), and a mask-unaware per-byte template never renders a partially-fixed byte (the engine falls back to the mask-scoped built-in wording)
- `ClassHierarchyDumper` - Dumps class inheritance hierarchies
- `MetadataReader` - Reads runtime metadata from MachOImage

**SwiftLayout** - Static aggregate-layout engine (offline field offsets, no runtime)
- `StaticLayoutCalculator` - Entry point: computes struct/class stored-property field offsets from a Mach-O file without loading the process or calling the metadata accessor. `fieldLayout(of:)` lays out a non-generic descriptor; `fieldLayout(of:genericArguments:)` lays out a **concrete generic instantiation** (`Foo<Int>`) by supplying its depth-0 type-argument `Node`s, and `fieldLayout(forInstantiationMangledName:)` does the same from a binary's bound-generic mangled reference (resolving the descriptor in its defining image). All share one environment-threaded per-field path (`accumulateFieldLayout`, default `.empty` ⇒ unchanged non-generic behavior) with per-field degradation
- `StaticTypeLayoutResolver` - Recursive `mangled name → StaticTypeLayout` solver (`Node.Kind` dispatch, memoized, cycle-guarded); class references stop at one pointer
- `BasicLayout` - Offline port of the runtime `performBasicLayout` (struct/class/tuple field accumulation). Also derives the value-aggregate **extra-inhabitant count = max over fields** (`swift_initStructMetadata` "use the field with the most", same rule as tuples) and carries it on `AggregateLayout` so `asStaticTypeLayout()` reports it — previously struct XI defaulted to 0 and was never propagated, which mis-sized any single-payload enum whose payload was a struct with extra inhabitants (e.g. `SwiftUI.Text.Style.TextStyleFont` over `Font`, a struct wrapping a class reference: computed 9 bytes instead of 8, cascading every later `Text.Style` offset). Guarded by `WholeTypeLayoutVsRuntimeTests` (size/stride/alignment of every fixture struct+enum vs the runtime VWT — the offset suite skips enums, so single-payload enum sizes were previously unchecked)
- `KnownLayoutTable` / `BuiltinTypeLayoutIndex` - Frozen stdlib layouts + per-image `__swift5_builtin` whole-type layouts. The builtin section carries the compiler-embedded layout (size/stride/align/XI) of types reflection cannot derive structurally — **imported C value types** (`__C.CGRect`, `__C.Decimal`) and **multi-payload enums** — keyed by the demangled qualified name (the descriptor's `typeName` is a symbolic reference whose raw string is empty). The resolver consults it (per origin image) before its structural struct/enum paths, so those types resolve as opaque whole-type values. Frozen `String`/`Character` carry XI `MaxNumExtraInhabitants` (0x7FFFFFFF, the `_StringObject` discriminator's reserved patterns) — a too-small count (the old `1`) broke any single-payload enum with ≥2 empty cases over a `String` payload. **Leaf XI values are now exact runtime counts** (verified against live value-witness tables + IRGen/runtime sources, 64-bit Darwin): managed pointers — class/heap references, container buffer refs, thick metatypes/existential metadata words, C function pointers, blocks, `Unmanaged`/`unowned(unsafe)` — saturate at 0x7FFF_FFFF (`getHeapObjectExtraInhabitantCount`, `LeastValidPointerValue` = 4 GiB); the unsafe-pointer family (`StaticTypeLayout.rawPointer`) reserves only null (XI 1 — the old 0x1000 approximation mis-sized an enum with two empty cases over a raw pointer to 8 instead of 9); thick functions (`StaticTypeLayout.thickFunction`) carry the saturated count on the function-pointer word (the old XI 0 mis-sized `Optional<() -> Void>` to 17 and pushed trailing fields from offset 16 to 24 — a real offset bug); `weak` storage (`StaticTypeLayout.weakReference`) has XI 0 and is not bitwise-takable; `unowned` (safe) storage (`StaticTypeLayout.unownedReference`) has exactly XI 1 (ObjC-interop-conservative IRGen `getReferenceStorageExtraInhabitantCount` — note RemoteInspection's `TypeLowering.cpp` wrongly claims it inherits the reference's count); `Builtin.Word` is an integer (XI 0); an uninhabited (0-case) enum has XI 0 (`SingletonEnumImplStrategy` with no singleton). `WholeTypeLayoutVsRuntimeTests` therefore asserts the full quintuple — size/stride/alignment/**extraInhabitantCount**/**isBitwiseTakable** — against the runtime VWT for every fixture struct+enum
- `EnumLayoutBridge` - No-payload + single-payload (incl. `Optional`) enum layout (runtime `getEnumTagCounts` formulas). Multi-payload enums resolve via the builtin whole-type descriptor first; when absent, `multiPayloadEnumLayout` computes them structurally by reusing `SwiftInspection.EnumLayoutCalculator` (`GenEnum.cpp`/`TypeLowering.cpp` port) over the largest payload + the `MultiPayloadEnumDescriptor` (`__swift5_mpenum`) common spare bits, deriving size/stride itself (`LayoutResult` carries neither) while the extra-inhabitant count comes exact from `LayoutResult.extraInhabitantCount` — computed per strategy inside the calculator (IRGen `getFixedExtraInhabitantCount` for spare-bits/hybrid, the runtime tagged formula, single-payload leftovers), so `Optional<MPE>` wrapping stays exact even on the structural fallback; the official offline implementation (RemoteInspection `TypeLowering.cpp`) never derives spare-bits XI structurally. A **generic instantiation** never takes the builtin or spare-bits paths: the runtime's `swift_initEnumMetadataMultiPayload` always appends tag bytes (spare-bit layout needs compile-time payload knowledge), and the unused tag values become the enum's extra inhabitants — both ported, so `Optional<Environment<Bool>.Content>`-style wrapping stays exact
- `ExistentialLayoutBridge` - Existential containers (`any P`, compositions, `AnyObject`, `any Error`) + existential metatypes, ported from the runtime reflection lowering (`ExistentialTypeInfoBuilder`): opaque `32 + 8N`, class-bound `8·(1+N)`, error `8`; class-boundness derived from each protocol's class constraint. Imported ObjC protocols (`any NSCopying`, `__C.<Name>` `.protocol` nodes) are always class-bound and contribute no Swift witness table; **Swift-declared `@objc` protocols** (`SwiftUI.PlatformAccessibilityElementProtocol & NSObject`) emit no Swift protocol descriptor either, so a class-constraint miss falls back to the `__objc_protolist` index (`ObjCProtocolIndex`, legacy `_TtP<module><name>_` names parsed back to qualified names) — a hit is likewise class-bound with no witness table. **Constrained/extended existentials** (`any Boxed<Int>`, encoded via a `symbolicExtendedExistentialType` shape reference) reuse the same container size as the unconstrained form — the shape's inner `ProtocolList` is extracted and routed back through `existentialLayout` (`extendedExistentialLayout`; the requirement list does not affect layout)
- `DependentMemberTypeBridge` - Resolves an associated-type field (`dependentMemberType`, e.g. `struct S<C: Collection> { var i: C.Index }`) reached as a concrete instantiation: after substitution leaves `dependentMemberType(concreteBase, Protocol.Assoc)`, it looks up the conformance's `__swift5_assocty` witness (via `ImageUniverse.resolveAssociatedTypeWitness`, the fourth resolution seam), demangles the witness in the image declaring the conformance, then substitutes the base's own generic arguments into it (`Array`'s `Element` witness is `Array`'s parameter → `Int16`). Degrades when the base is unsubstituted or the conformance's assocty record is reflection-stripped
- `ObjCClassIndex` - Phase-4 Objective-C ancestor support: reads a class's instance `class_ro_t.instanceSize` from `__objc_classlist` (bare name → start layout), resolving the realized `class_rw_t` form for classes dyld has realized in-process. Uses `instanceSize` (where a Swift subclass's first field begins), **not** `instanceStart`; value matches `ObjCClass.info(in:).instanceSize` without parsing methods/ivars. `objc.classes64`/ro accessors are concrete `MachOFile`/`MachOImage` overloads, so the builder is split per reader
- `ObjCProtocolIndex` - Phase-8 `@objc` protocol support: indexes `__objc_protolist` by Swift qualified name (parsing the legacy `_TtP<module><name>_` mangling; native ObjC protocols' plain names are skipped — they demangle as `__C` references and never reach the lookup). Recognition is the whole payload: a Swift-declared `@objc` protocol emits no `__swift5_protos` descriptor, is always class-bound, and contributes no witness table. Reader-split like `ObjCClassIndex`
- `ImageUniverse` / `ImageReference` - Type/protocol/ObjC-class/assocty-witness/ObjC-protocol lookup seam (five resolvers: `resolveType`, `resolveProtocolClassConstraint`, `resolveObjCClassInstanceSize`, `resolveAssociatedTypeWitness`, `isObjCProtocolDeclared`). `ImageReference` indexes one image's type descriptors (`__swift5_types`), protocol class constraints (`__swift5_protos`), ObjC class instance sizes (`__objc_classlist`), associated-type witnesses (`__swift5_assocty`, keyed `conforming|protocol|assoc`), and `@objc` protocol declarations (`__objc_protolist`); `ImageUniverse` is either single-image (`singleImage`) or a **dependency closure** (`dependencyClosure`) that merges a root plus its transitive dependencies, **indexing each dependency lazily** (root eager, dependencies folded in resolution order only when a lookup misses, all five indexes merged together) so a several-hundred-image OS closure is not eagerly demangled
- `ImageUniverse+DependencyClosure` - Closure factories: in-process (`dependencyClosure(root: MachOImage)`, resolves dependencies through the active dyld) and offline (`dependencyClosure(root: MachOFile, searchPaths:)`, resolves through explicit on-disk paths + the dyld shared cache, the latter indexed once by bare name). `LayoutDependencySearchPath` is SwiftLayout-local (no `SwiftInterface` dependency). Dependency load names are matched by **bare name** (`MachOImage(name:)` semantics); `MachOFile.imagePath` is the install name, not a filesystem path
- `GenericArgumentEnvironment` - Phase-5/6 concrete bound-generic field substitution: a non-generic type with a `MyBox<Int>` field resolves it by capturing the instantiated node's `(depth, index) → Node` argument map (`make(forInstantiatedTypeNode:)`) and deep-rewriting the base type's `dependentGenericParamType` field nodes (purely syntactic — no metadata accessor / PWT, so no new `SwiftSpecialization`/`SwiftGenericSupport` dependency). Arguments may be plain types, **value arguments** (`Foo<5>`, bound as `.integer`/`.negativeInteger` nodes, SE-0452), or **flat packs** (SE-0393). Substitution is a hand-rolled **top-down** recursion (not the bottom-up `Node.Rewriter` — pack expansion is context-sensitive: instance `i` of an expansion resolves a pack-bound parameter to its `i`-th element, which a bottom-up pass cannot distinguish from literal packs in shapes like `(repeat Pair<each T>)`): concrete pack expansions expand in place inside `.tuple` (flattened elements, empty pack → empty tuple, single-unlabeled-element result collapses to the element itself, matching the runtime's one-tuple identity) and inside `.pack` literals (the `Foo<repeat each T>` forwarding shape flattens). Only a pack argument still containing an unexpanded expansion degrades the environment. **Arguments are collected per level along the nominal parent chain** (outermost bound-generic level = depth 0), so a nested type of a specialized parent whose fields *use* the parent's parameter — `Environment<Bool>.Content`, a plain `.enum` node with no argument list of its own — binds the parent's arguments, and a two-level instantiation (`Outer<Int8>.Inner<Int64>`) binds each level at its own depth; only parameters of contexts the mangling genuinely does not carry (a local type in a generic function) stay degraded. Instantiations memoize under a remangled instantiation key (`memoizedInstantiationLayout`, skipping the frozen table); a leading bare-name `KnownLayoutTable` check keeps `Array<Int>`/`UnsafePointer<T>` argument-independent. `superclassStartLayout` substitutes the superclass reference first (`class Sub<T>: Base<T>`). Also fixes a latent single-payload-enum bug (the payload reads the correct parameter, not blindly the first type argument). `make(forDepthZeroTypeArguments:)` builds the same depth-0 map directly from a caller-supplied argument-`Node` list (backing `StaticLayoutCalculator`'s top-level generic-instantiation entries), not only from a `boundGeneric*` node. Compiler-enforced simplifications: a generic *type* declares at most one type pack, and enums cannot declare one at all
- `ClassBoundGenericParameterAnalysis` - Phase-9 **unspecialized** requirement-signature layout mining: derives, in one pass over `genericContext.requirements`, the `RequirementSignatureLayoutFacts` a generic descriptor's signature pins about each parameter **without any argument** — both (a) **class-bound parameters** and (b) **concrete same-type pins**. (a) A generic parameter constrained to a class layout (`Element: AnyObject`), a superclass (`Element: SomeClass`, a `baseClass` requirement), or a class-bound protocol (`Element: SomeClassBoundProtocol`, Swift or imported/`@objc` ObjC) is necessarily a single object reference, so a field typed by it — **and every field after it** — lays out exactly even when the type is dumped with no generic arguments; class-boundness is classified from the requirement kind + resolved content (`layout(.class)` / `baseClass` / a class-bound `protocol`; a cross-image protocol symbol is recovered by name through the universe's `resolveProtocolClassConstraint` + `isObjCProtocolDeclared` seams), the parameter rewrites to a placeholder `.class` node the resolver lays out as `.pointerSized` (`swift_getHeapObjectExtraInhabitantCount`, saturated 0x7FFF_FFFF on 64-bit Darwin). (b) A parameter pinned to a **concrete** type by a `sameType` requirement (`Value == Foundation.Date` / `== Range<Int>`, contributed by a **constrained extension** — a type nested in `extension Foo where Value == Date` inherits the requirement) is that type in every valid use, so its unwrapped RHS node becomes a genuine **substitution** (only when the RHS is fully concrete — a `sameType` RHS that references another parameter / dependent member cannot stand alone and is skipped; a dependent-member *subject* like `T.Element == X` says nothing about `T` and is skipped too). Both facts read from bare-parameter subjects carrying absolute `(depth, index)` (matching field records, so nested contexts need no bookkeeping). Seeded via `GenericArgumentEnvironment.augmented(withRequirementFacts:)` at every field-reading entry point (`StaticLayoutCalculator.fieldLayout(ofStruct:/ofClass:)` + the resolver's `computeStructLayout` / `computeClassLayout` / `computeEnumLayout` choke points, so generic superclasses and ObjC-ancestor subclasses benefit too), all through the same top-down substitution (reaching inside optionals/tuples/`Array<Element>`/function types). A genuine instantiation argument always wins over both fallbacks (it cannot contradict a same-type pin). Empirically same-type pinning is small (only ~23 of 579 `sameType` requirements across 5 frameworks are bare-param-to-concrete — 75% are dependent-member subjects the assocty bridge covers, 21% are abstract param-to-param), but it is a correct completion: the two facts together are everything the requirement signature determines without arguments. `sameType`-to-a-concrete-class (a representation-and-value pin) flows through as a substitution just like any other concrete pin. Same-**value** pins (`extension Foo where count == 5` — a `sameType` requirement with `isValueRequirement` set whose RHS mangles an integer) flow through the same extraction with zero extra code: the `.integer` RHS passes the fully-concrete check and binds like a phase-6 value argument, so a nested type's `InlineArray<count, Int16>` field resolves unspecialized (and the interface printer now renders SE-0452 integer nodes — `SwiftPrinting.NodePrintable` previously dropped them, printing `ValueGenericBuffer<>` / `where A == `)
- Fixed arrays / value generics: the resolver dispatches `builtinFixedArray` (`Builtin.FixedArray<count, Element>`: count ≤ 0 → empty; else `size == stride == element.stride × count` with no tail-padding reclamation even at count 1, alignment/bitwise-takability from the element, **XI from the first element** — ported from `swift_getFixedArrayTypeMetadata`, consistent with IRGen `convertBuiltinFixedArrayType` and RemoteInspection `ArrayTypeInfo`), and special-cases `Swift.InlineArray` onto the same formula (layout-identical to its only stored field; its descriptor lives in the stdlib, like `Optional`'s, so single-image scopes work). Tuple XI is the max over elements (runtime `swift_getTupleTypeMetadata` semantics; previously hardcoded 0). Zero-sized fields report offset 0, mirroring the compiler-emitted vector (IRGen `ElementLayout::completeEmpty`), not the accumulator position `performBasicLayout` would report. Note the official offline lowering (RemoteInspection `TypeLowering.cpp`) rejects packs outright — this path is validated directly against runtime substitution semantics
- Metatype fields (thin vs thick): a `T.Type` field's storage is decided by the **syntactic kind of the metatype's instance in the field record**, which `GenericArgumentEnvironment.substitute` deliberately leaves un-substituted (a `.metatype` node passes through untouched). A metatype is **thin** (zero-sized, no storage) only when its instance is a statically-concrete value type (struct/enum/tuple/builtin) — IRGen references its metadata directly; it is **thick** (one metadata pointer, `.pointerSized` with the saturated `swift_getHeapObjectExtraInhabitantCount` = 0x7FFF_FFFF) when the instance is a class or a **generic parameter / dependent member** (an archetype). The archetype case is fixed across every instantiation — empirically `Element.Type` occupies 8 bytes in `Foo<Int>` and `Foo<Int8>` alike (IRGen lowers the field once at metadata-pattern time with the parameter as an archetype) — so a generic type's metatype-of-parameter field resolves **exactly without specialization**, and a literal concrete metatype (`Int64.Type`) stays thin even inside a generic type. This replaced an earlier (wrong) model that keyed thinness off the aggregate's genericity; the instance-kind model matches the runtime in both lowering worlds and cleared the survey's residual `metatype(DependentGenericParamType)` degradations
- Per-field degradation: unresolved fields (a top-level generic type's own unsubstituted **non-class-bound** `T`/`each T`/`let N`, depth>0 nested-context parameters, expansions whose count never became concrete) report `FieldResolution.unknown` instead of failing the whole type. Existentials (incl. imported ObjC protocols), the default-actor storage builtin, C-function-pointer / ObjC-block fields, **cross-module field/superclass/protocol types (via the dependency closure)**, **ObjC-ancestor classes** (a Swift class deriving from `NSObject` et al. starts its own fields at the ObjC ancestor's `instanceSize`, located via the closure's libobjc), **multi-payload enums + imported C value types** (via `BuiltinTypeLayoutIndex` whole-type layouts), **concrete bound-generic instantiations as fields** (via `GenericArgumentEnvironment`), **value-generic / parameter-pack instantiations** (`ValueGenericBuffer<5>`, `InlineArray<3, Int64>`, `VariadicPack<Int32, Int8, Int64>`, both as fields and as top-level requests), **associated-type fields** (`C.Index`/`C.Element` of a concrete instantiation, via `DependentMemberTypeBridge` + `__swift5_assocty`), **constrained/extended existentials** (`any Boxed<Int>`), **nested types of a specialized generic parent** (`Outer<Int>.Inner`, whose qualified name keeps the parent chain — including nested types whose fields *use* the parent's arguments, `Environment<Bool>.Content`, via the parent-chain environment), **Swift-declared `@objc` protocol existentials** (via the `__objc_protolist` fallback), and — new in phase 9 — **class-bound generic parameters laid out unspecialized** (`Element: AnyObject` / `: SomeClass` / `: SomeClassBoundProtocol`, via `ClassBoundGenericParameterAnalysis`; the parameter field and everything after it resolve without any argument), **concrete same-type-pinned parameters** (`Value == Date`, from a constrained extension — a real substitution mined from the requirement signature), and **parameter-metatype fields** (`T.Type`, always thick) are resolved; cross-module resilient classes' offsets are computed against the dependency's actual binary ("this specific deployment" semantics). Empirically, over the same 5-framework survey (5416 non-generic types, 10954 fields) the phase-7 fixes cut field degradation from ~10% to ~4%, and the phase-8 fixes (parent-chain arguments + `@objc` protocol fallback) to **0%** — every remaining degradation class requires arguments the binary does not carry. Phase 9 extends coverage to **generic** types dumped without arguments: a class-bound parameter (and a metatype-of-parameter field, always thick) no longer degrades its field. A separate **generic-type survey** (2963 generic types across the same 5 frameworks) measures this second front: of 7255 generic struct/class fields, ~52% resolve unspecialized (every field whose type does not need an argument — concrete fields, class-bound parameters, parameter metatypes, nested class-bound levels), and the residual is dominated by genuinely-argument-dependent `genericParameterUnsubstituted` (bare `T`/`q_`/`qd__`) plus its `precedingFieldUnresolved` cascade. The classes still genuinely unresolvable without specialization are unconstrained or non-class-bound parameters (`T`, `T: Equatable`, value/pack parameters), which need an argument the unspecialized dump has not got
- See [Documentations/Internal/StaticLayoutEngine.md](Documentations/Internal/StaticLayoutEngine.md) and [Documentations/Internal/StaticLayoutDependencyClosure.md](Documentations/Internal/StaticLayoutDependencyClosure.md)

**SemanticTransformer** - Output-transformer modules for the **Swift** comment kinds (the `Transformer` namespace RuntimeViewer's settings UI edits; the templates render library-side, RuntimeViewer keeps only the UI via an `@_exported` re-export)
- Token-template comment modules: `SwiftFieldOffset`, `SwiftVTableOffset`, `SwiftMemberAddress`, `SwiftTypeLayout` (optional value-witness-flag inputs render `"unknown"` when the caller cannot know them), `SwiftEnumLayout` (three template levels + presets, see the `SwiftInspection` bridge above)
- `Transformer.SwiftConfiguration` - aggregate settings, hand-written missing-key-tolerant `Codable` (compatible with RuntimeViewer's previously persisted MetaCodable JSON — property names are the storage keys, do not rename them). The ObjC-side modules (`CType`, `ObjCIvarOffset`), `ObjCConfiguration`, and the full persistence aggregate `Configuration` deliberately stay in RuntimeViewerCore for now (declared as extensions of this namespace), pending a library-side home for the ObjC rendering pipeline
- Wiring: `applyTransformers(_:)` on `DeclarationRenderConfiguration` (SwiftDeclarationRendering, where the closure factories live) and `SwiftDeclarationPrintConfiguration` (SwiftPrinting) materializes enabled modules into the existing closure-transformer slots — emission sites unchanged. Dependency-free, so it sits at the bottom of the module graph. See [Documentations/Internal/SemanticTransformerMigration.md](Documentations/Internal/SemanticTransformerMigration.md)

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
