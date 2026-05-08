# GenericSpecializer Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply six lightweight cleanups (#5, #6, #7, #9, #10, #12) to `GenericSpecializer` per spec `docs/superpowers/specs/2026-05-02-generic-specializer-cleanup-design.md`, expanding the public API to surface `~Copyable` / `~Escapable`, merging conditional invertible requirements, splitting muddy switch arms, fail-fast on generic candidates, allowing caller-supplied `MetadataRequest`, and removing dead code.

**Architecture:** All changes are localised to two existing files under `Sources/SwiftInterface/GenericSpecializer/` plus the test file. No new files, no new modules, no ABI-level changes.

**Tech Stack:** Swift 6.2+, swift-testing (`@Test` / `#expect` / `#require`), SwiftPM (`swift build` / `swift test`).

---

## File Structure

**Modified:**

- `Sources/SwiftInterface/GenericSpecializer/GenericSpecializer.swift` — most edits live here: the `buildRequirement` switch, `buildParameters` second pass for invertible protocols, `findCandidates` populating `isGeneric`, `resolveCandidate` fail-fast, `specialize` signature, three call sites that read requirements, deletion of `convertLayoutKind`, two new `SpecializerError` cases.
- `Sources/SwiftInterface/GenericSpecializer/Models/SpecializationRequest.swift` — `Parameter` gains `invertibleProtocols`, `Candidate` gains `isGeneric`.
- `Tests/SwiftInterfaceTests/GenericSpecializationTests.swift` — three new `@Test` methods and one new fixture.

**Not modified:**

- `Sources/SwiftInterface/GenericSpecializer/ConformanceProvider.swift` — no API surface change here.
- `Sources/SwiftInterface/GenericSpecializer/Models/SpecializationSelection.swift`,
  `SpecializationResult.swift`, `SpecializationValidation.swift` — untouched.

Six tasks ordered by risk and dependency: pure deletions and comment splits first, then API additions, then the test-bearing changes that build on the API.

---

## Task 1: Remove dead `convertLayoutKind` (#12)

**Files:**

- Modify: `Sources/SwiftInterface/GenericSpecializer/GenericSpecializer.swift:272-277`

- [ ] **Step 1: Confirm zero callers**

Run: `rg -n 'convertLayoutKind' Sources/ Tests/`
Expected output: only the definition lines (272-277) — no call sites.

- [ ] **Step 2: Delete the function**

Remove these exact lines from `GenericSpecializer.swift`:

```swift
    /// Convert runtime layout kind to our model
    private func convertLayoutKind(_ kind: GenericRequirementLayoutKind) -> SpecializationRequest.LayoutKind {
        switch kind {
        case .class:
            return .class
        }
    }
```

- [ ] **Step 3: Build and run the specializer test class**

Run: `swift build 2>&1 | xcsift`
Expected: build succeeds, no warnings.

Run: `swift test --filter SwiftInterfaceTests.GenericSpecializationTests 2>&1 | xcsift`
Expected: all 11 existing tests pass (`main`, `makeRequest`, `validation`, `specialize`, `selectionBuilder`, `unconstrainedSpecialize`, `singleProtocolSpecialize`, `multiProtocolSpecialize`, `classConstraintSpecialize`, `nestedAssociatedTypeRequest`, `nestedAssociatedTypeSpecialize`, `dualAssociatedSpecialize`, `mixedConstraintsSpecialize`).

- [ ] **Step 4: Commit**

```bash
git add Sources/SwiftInterface/GenericSpecializer/GenericSpecializer.swift
git commit -m "refactor(SwiftInterface): drop unused convertLayoutKind helper"
```

---

## Task 2: Split `sameConformance` / `sameShape` / `invertedProtocols` arms (#7)

**Files:**

- Modify: `Sources/SwiftInterface/GenericSpecializer/GenericSpecializer.swift:265-268`

- [ ] **Step 1: Replace the combined branch**

Replace this block in `buildRequirement`:

```swift
        case .sameConformance, .sameShape, .invertedProtocols:
            // These are more advanced requirements that we don't need for basic specialization
            return nil
        }
```

with three independent arms:

```swift
        case .sameConformance:
            // Derived from SameType / BaseClass; compiler forces hasKeyArgument=false,
            // so it never participates in metadata accessor key arguments.
            return nil

        case .sameShape:
            // Pack-shape constraint between two TypePacks. Relevant only to variadic
            // generics, which are out of scope for this specializer.
            return nil

        case .invertedProtocols:
            // Capability declaration (~Copyable / ~Escapable) — surfaced on
            // Parameter.invertibleProtocols rather than as a Requirement, because
            // it relaxes rather than constrains the parameter.
            return nil
        }
```

- [ ] **Step 2: Build and run tests**

Run: `swift test --filter SwiftInterfaceTests.GenericSpecializationTests 2>&1 | xcsift`
Expected: all existing tests pass — this is a comment-only change.

- [ ] **Step 3: Commit**

```bash
git add Sources/SwiftInterface/GenericSpecializer/GenericSpecializer.swift
git commit -m "refactor(SwiftInterface): split combined nil-return requirement branch"
```

---

## Task 3: Configurable `MetadataRequest` on `specialize` (#10)

**Files:**

- Modify: `Sources/SwiftInterface/GenericSpecializer/GenericSpecializer.swift:391` (signature) and `:458` (call site).
- Test: `Tests/SwiftInterfaceTests/GenericSpecializationTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `GenericSpecializationTests.swift`, after the `selectionBuilder` test (around line 191):

```swift
    @Test func configurableMetadataRequest() async throws {
        let machO = MachOImage.current()

        let descriptor = try #require(try machO.swift.typeContextDescriptors.first {
            try $0.struct?.name(in: machO).contains("TestGenericStruct") == true
        }?.struct)

        let indexer = SwiftInterfaceIndexer(in: machO)
        try indexer.addSubIndexer(SwiftInterfaceIndexer(in: #require(MachOImage(name: "Foundation"))))
        try indexer.addSubIndexer(SwiftInterfaceIndexer(in: #require(MachOImage(name: "libswiftCore"))))
        try await indexer.prepare()

        let specializer = GenericSpecializer(indexer: indexer)
        let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))

        let selection: SpecializationSelection = [
            "A": .metatype([Int].self),
            "B": .metatype(Double.self),
            "C": .metatype(Data.self),
        ]

        // Default request (existing behaviour)
        let defaultResult = try specializer.specialize(request, with: selection)
        let defaultOffsets = try #require(defaultResult.resolveMetadata().struct).fieldOffsets()

        // Explicit non-blocking complete request
        let nonBlocking = MetadataRequest(state: .complete, isBlocking: false)
        let explicitResult = try specializer.specialize(
            request,
            with: selection,
            metadataRequest: nonBlocking
        )
        let explicitOffsets = try #require(explicitResult.resolveMetadata().struct).fieldOffsets()

        #expect(defaultOffsets == [0, 8, 16])
        #expect(explicitOffsets == defaultOffsets)
    }
```

- [ ] **Step 2: Run the test, expect a build failure**

Run: `swift test --filter SwiftInterfaceTests.GenericSpecializationTests/configurableMetadataRequest 2>&1 | xcsift`
Expected: compile error along the lines of *"extra argument 'metadataRequest' in call"* — the parameter does not exist yet.

- [ ] **Step 3: Add the parameter to `specialize`**

In `GenericSpecializer.swift:391` change the signature:

```swift
    public func specialize(
        _ request: SpecializationRequest,
        with selection: SpecializationSelection,
        metadataRequest: MetadataRequest = .completeAndBlocking
    ) throws -> SpecializationResult {
```

In the same function, find the main accessor call (currently `GenericSpecializer.swift:457-461`):

```swift
        let response = try accessorFunction(
            request: .completeAndBlocking,
            metadatas: metadatas,
            witnessTables: witnessTables,
        )
```

and replace `request: .completeAndBlocking` with `request: metadataRequest`:

```swift
        let response = try accessorFunction(
            request: metadataRequest,
            metadatas: metadatas,
            witnessTables: witnessTables,
        )
```

Leave `resolveCandidate` (around line 516) and `resolveAssociatedTypeStep` (around line 715) untouched — per spec §5 they keep their current internal requests.

- [ ] **Step 4: Run the new test**

Run: `swift test --filter SwiftInterfaceTests.GenericSpecializationTests/configurableMetadataRequest 2>&1 | xcsift`
Expected: PASS.

- [ ] **Step 5: Run the full specializer test class to confirm no regressions**

Run: `swift test --filter SwiftInterfaceTests.GenericSpecializationTests 2>&1 | xcsift`
Expected: all tests pass, including the new one.

- [ ] **Step 6: Commit**

```bash
git add Sources/SwiftInterface/GenericSpecializer/GenericSpecializer.swift Tests/SwiftInterfaceTests/GenericSpecializationTests.swift
git commit -m "feat(SwiftInterface): allow caller-supplied MetadataRequest in specialize"
```

---

## Task 4: Merge conditional invertible protocol requirements (#6)

**Files:**

- Modify: `Sources/SwiftInterface/GenericSpecializer/GenericSpecializer.swift` — three call sites (lines 94, 285, 593).

- [ ] **Step 1: Add the merge helper**

Insert this private static helper inside `GenericSpecializer` (anywhere in the `extension GenericSpecializer` block that contains `buildParameters`; placing it right above `buildParameters` is clearest):

```swift
    /// All requirements visible to the specializer: the cumulative
    /// `allRequirements` chain plus any conditional requirements stored
    /// under `hasConditionalInvertedProtocols`. The current scope keeps
    /// every candidate Copyable / Escapable, so conditional requirements
    /// always evaluate active and can be merged unconditionally.
    private static func mergedRequirements(
        from genericContext: GenericContext
    ) -> [GenericRequirementDescriptor] {
        genericContext.allRequirements.flatMap { $0 }
            + genericContext.conditionalInvertibleProtocolsRequirements
    }
```

- [ ] **Step 2: Use the helper in `buildParameters`**

In `GenericSpecializer.swift:91-97` replace:

```swift
                let requirements = try collectRequirements(
                    for: paramName,
                    from: genericContext.allRequirements.flatMap { $0 },
                    parameterIndex: index,
                    depth: depth
                )
```

with:

```swift
                let requirements = try collectRequirements(
                    for: paramName,
                    from: Self.mergedRequirements(from: genericContext),
                    parameterIndex: index,
                    depth: depth
                )
```

- [ ] **Step 3: Use the helper in `buildAssociatedTypeRequirements`**

In `GenericSpecializer.swift:285` replace:

```swift
        let genericRequirements = genericContext.allRequirements.flatMap { $0 }
```

with:

```swift
        let genericRequirements = Self.mergedRequirements(from: genericContext)
```

- [ ] **Step 4: Use the helper in `resolveAssociatedTypeWitnesses`**

The third call site lives on the `MachO == MachOImage` extension (around `GenericSpecializer.swift:593`) and works with `GenericContext` already loaded into the current process via `genericContextInProcess`. Both this and the file-side `GenericContext` are the same type alias `TargetGenericContext<GenericContextDescriptorHeader>`, so the helper applies directly.

Replace this line:

```swift
        let requirements = try genericContextInProcess.requirements.map { try GenericRequirement(descriptor: $0) }
```

with:

```swift
        let requirements = try Self.mergedRequirements(from: genericContextInProcess)
            .map { try GenericRequirement(descriptor: $0) }
```

(`mergedRequirements` is defined on `extension GenericSpecializer` without a `MachO == MachOImage` constraint, so it's reachable from both extension blocks.)

- [ ] **Step 5: Build and run all specializer tests**

Run: `swift build 2>&1 | xcsift`
Expected: build succeeds, no warnings.

Run: `swift test --filter SwiftInterfaceTests.GenericSpecializationTests 2>&1 | xcsift`
Expected: all existing tests still pass. None of the existing fixtures rely on `conditionalInvertibleProtocolsRequirements`, so this change is behaviour-neutral against the current suite. Direct verification is added by Task 6's fixture.

- [ ] **Step 6: Commit**

```bash
git add Sources/SwiftInterface/GenericSpecializer/GenericSpecializer.swift
git commit -m "feat(SwiftInterface): merge conditional invertible requirements"
```

---

## Task 5: Generic-candidate fail-fast (#9)

**Files:**

- Modify: `Sources/SwiftInterface/GenericSpecializer/Models/SpecializationRequest.swift` — `Candidate` gains `isGeneric`.
- Modify: `Sources/SwiftInterface/GenericSpecializer/GenericSpecializer.swift` — new `SpecializerError` case, `findCandidates` populates `isGeneric`, `resolveCandidate` throws on generic descriptors.
- Test: `Tests/SwiftInterfaceTests/GenericSpecializationTests.swift`

- [ ] **Step 1: Write the failing test**

Append after the `configurableMetadataRequest` test:

```swift
    @Test func genericCandidateFailFast() async throws {
        let machO = MachOImage.current()

        let descriptor = try #require(try machO.swift.typeContextDescriptors.first {
            try $0.struct?.name(in: machO).contains("TestSingleProtocolStruct") == true
        }?.struct)

        let indexer = SwiftInterfaceIndexer(in: machO)
        try indexer.addSubIndexer(SwiftInterfaceIndexer(in: #require(MachOImage(name: "libswiftCore"))))
        try await indexer.prepare()

        let specializer = GenericSpecializer(indexer: indexer)
        let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))

        // Pick a generic candidate from the candidate list (e.g. Optional or Array
        // — anything generic that conforms to Hashable). We deliberately do not
        // assert that *some* candidate is generic in case the candidate set
        // changes; we only assert the property holds for any generic ones we find.
        let genericCandidate = request.parameters[0].candidates.first { $0.isGeneric }
        let nonGenericCandidate = request.parameters[0].candidates.first { !$0.isGeneric }

        // At minimum the standard library exposes both shapes for Hashable.
        try #require(genericCandidate != nil, "expected at least one generic candidate")
        try #require(nonGenericCandidate != nil, "expected at least one non-generic candidate")

        // Non-generic candidate still resolves successfully.
        let okResult = try specializer.specialize(
            request,
            with: ["A": .candidate(nonGenericCandidate!)]
        )
        _ = try okResult.resolveMetadata()

        // Generic candidate throws the new typed error.
        do {
            _ = try specializer.specialize(
                request,
                with: ["A": .candidate(genericCandidate!)]
            )
            Issue.record("expected candidateRequiresNestedSpecialization to be thrown")
        } catch let GenericSpecializer<MachOImage>.SpecializerError.candidateRequiresNestedSpecialization(candidate, parameterCount) {
            #expect(candidate.typeName == genericCandidate!.typeName)
            #expect(parameterCount >= 1)
        }
    }
```

- [ ] **Step 2: Run the test, expect a build failure**

Run: `swift test --filter SwiftInterfaceTests.GenericSpecializationTests/genericCandidateFailFast 2>&1 | xcsift`
Expected: compile errors — `isGeneric` is not a member of `Candidate`, `candidateRequiresNestedSpecialization` is not a `SpecializerError` case.

- [ ] **Step 3: Add `isGeneric` to `Candidate`**

In `Sources/SwiftInterface/GenericSpecializer/Models/SpecializationRequest.swift`, replace the existing `Candidate` declaration (currently lines 122-143):

```swift
    /// A candidate type that can be used for specialization
    public struct Candidate: Sendable, Hashable {
        /// Type name
        public let typeName: TypeName

        /// Source of this candidate
        public let source: Source

        public init(
            typeName: TypeName,
            source: Source,
        ) {
            self.typeName = typeName
            self.source = source
        }

        /// Source of candidate type
        public enum Source: Sendable, Hashable {
            case image(String)
        }
    }
```

with:

```swift
    /// A candidate type that can be used for specialization
    public struct Candidate: Sendable, Hashable {
        /// Type name
        public let typeName: TypeName

        /// Source of this candidate
        public let source: Source

        /// True when the candidate's type descriptor is itself generic.
        /// Selecting such a candidate via `Argument.candidate(...)` will
        /// throw `candidateRequiresNestedSpecialization` from `specialize`.
        public let isGeneric: Bool

        public init(
            typeName: TypeName,
            source: Source,
            isGeneric: Bool = false
        ) {
            self.typeName = typeName
            self.source = source
            self.isGeneric = isGeneric
        }

        /// Source of candidate type
        public enum Source: Sendable, Hashable {
            case image(String)
        }
    }
```

(Default value `false` keeps the existing call sites in `findCandidates` source-compatible until they are updated in Step 5.)

- [ ] **Step 4: Add the `SpecializerError` case**

In `Sources/SwiftInterface/GenericSpecializer/GenericSpecializer.swift`, find the `SpecializerError` enum (currently `:800-808`). Add the new case after `case candidateResolutionFailed(...)`:

```swift
        case candidateRequiresNestedSpecialization(
            candidate: SpecializationRequest.Candidate,
            parameterCount: Int
        )
```

Add a matching `errorDescription` arm in the `switch self` block (currently `:810-829`), after the existing `candidateResolutionFailed` arm:

```swift
            case .candidateRequiresNestedSpecialization(let candidate, let parameterCount):
                return "Candidate \(candidate.typeName.name) is generic with \(parameterCount) parameter(s); pass Argument.specialized(...) instead of Argument.candidate(...)"
```

- [ ] **Step 5: Populate `isGeneric` in `findCandidates`**

In `GenericSpecializer.swift:311-339`, both branches currently use `guard ... != nil` and discard the type definition. Bind it instead so we can read the descriptor's flags.

Replace the entire `findCandidates` body:

```swift
    private func findCandidates(satisfying protocols: [ProtocolName]) -> [SpecializationRequest.Candidate] {
        guard !protocols.isEmpty else {
            // No constraints - return all indexed types
            return conformanceProvider.allTypeNames.compactMap { typeName -> SpecializationRequest.Candidate? in
                guard conformanceProvider.typeDefinition(for: typeName) != nil else {
                    return nil
                }
                let imagePath = conformanceProvider.imagePath(for: typeName) ?? ""
                return SpecializationRequest.Candidate(
                    typeName: typeName,
                    source: .image(imagePath)
                )
            }
        }

        // Find types conforming to all protocols
        let conformingTypes = conformanceProvider.types(conformingToAll: protocols)

        return conformingTypes.compactMap { typeName -> SpecializationRequest.Candidate? in
            guard conformanceProvider.typeDefinition(for: typeName) != nil else {
                return nil
            }
            let imagePath = conformanceProvider.imagePath(for: typeName) ?? ""
            return SpecializationRequest.Candidate(
                typeName: typeName,
                source: .image(imagePath)
            )
        }
    }
```

with:

```swift
    private func findCandidates(satisfying protocols: [ProtocolName]) -> [SpecializationRequest.Candidate] {
        guard !protocols.isEmpty else {
            // No constraints - return all indexed types
            return conformanceProvider.allTypeNames.compactMap { typeName -> SpecializationRequest.Candidate? in
                guard let typeDefinition = conformanceProvider.typeDefinition(for: typeName) else {
                    return nil
                }
                let imagePath = conformanceProvider.imagePath(for: typeName) ?? ""
                let isGeneric = typeDefinition.type.typeContextDescriptorWrapper.typeContextDescriptor.layout.flags.isGeneric
                return SpecializationRequest.Candidate(
                    typeName: typeName,
                    source: .image(imagePath),
                    isGeneric: isGeneric
                )
            }
        }

        // Find types conforming to all protocols
        let conformingTypes = conformanceProvider.types(conformingToAll: protocols)

        return conformingTypes.compactMap { typeName -> SpecializationRequest.Candidate? in
            guard let typeDefinition = conformanceProvider.typeDefinition(for: typeName) else {
                return nil
            }
            let imagePath = conformanceProvider.imagePath(for: typeName) ?? ""
            let isGeneric = typeDefinition.type.typeContextDescriptorWrapper.typeContextDescriptor.layout.flags.isGeneric
            return SpecializationRequest.Candidate(
                typeName: typeName,
                source: .image(imagePath),
                isGeneric: isGeneric
            )
        }
    }
```

- [ ] **Step 6: Make `resolveCandidate` fail fast on generic candidates**

In `GenericSpecializer.swift:487-519`, replace:

```swift
    private func resolveCandidate(_ candidate: SpecializationRequest.Candidate, parameterName: String) throws -> Metadata {
        // Find the type definition from indexer
        guard let indexer else {
            throw SpecializerError.candidateResolutionFailed(
                candidate: candidate,
                reason: "Indexer not available for candidate resolution"
            )
        }

        // Look up type definition
        guard let typeDefinitionEntry = indexer.allAllTypeDefinitions[candidate.typeName] else {
            throw SpecializerError.candidateResolutionFailed(
                candidate: candidate,
                reason: "Type not found in indexer"
            )
        }

        let typeDefinition = typeDefinitionEntry.value

        // Get accessor function from type definition's type context
        let accessorFunction = try typeDefinition.type.typeContextDescriptorWrapper.typeContextDescriptor.metadataAccessorFunction(in: typeDefinitionEntry.machO)
        guard let accessorFunction else {
            throw SpecializerError.candidateResolutionFailed(
                candidate: candidate,
                reason: "Cannot get metadata accessor function"
            )
        }

        // For non-generic types, just call the accessor
        let response = try accessorFunction(request: .completeAndBlocking)
        let wrapper = try response.value.resolve()
        return try wrapper.metadata
    }
```

with:

```swift
    private func resolveCandidate(_ candidate: SpecializationRequest.Candidate, parameterName: String) throws -> Metadata {
        // Find the type definition from indexer
        guard let indexer else {
            throw SpecializerError.candidateResolutionFailed(
                candidate: candidate,
                reason: "Indexer not available for candidate resolution"
            )
        }

        // Look up type definition
        guard let typeDefinitionEntry = indexer.allAllTypeDefinitions[candidate.typeName] else {
            throw SpecializerError.candidateResolutionFailed(
                candidate: candidate,
                reason: "Type not found in indexer"
            )
        }

        let typeDefinition = typeDefinitionEntry.value
        let typeContext = typeDefinition.type.typeContextDescriptorWrapper.typeContextDescriptor

        // Generic candidates need nested specialization; surface a typed error
        // rather than letting the no-argument accessor call below fail with
        // a generic message.
        if let genericContext = try typeContext.genericContext(in: typeDefinitionEntry.machO) {
            throw SpecializerError.candidateRequiresNestedSpecialization(
                candidate: candidate,
                parameterCount: Int(genericContext.header.numParams)
            )
        }

        // Get accessor function from type definition's type context
        let accessorFunction = try typeContext.metadataAccessorFunction(in: typeDefinitionEntry.machO)
        guard let accessorFunction else {
            throw SpecializerError.candidateResolutionFailed(
                candidate: candidate,
                reason: "Cannot get metadata accessor function"
            )
        }

        // Non-generic: call accessor with no arguments
        let response = try accessorFunction(request: .completeAndBlocking)
        let wrapper = try response.value.resolve()
        return try wrapper.metadata
    }
```

- [ ] **Step 7: Run the new test**

Run: `swift test --filter SwiftInterfaceTests.GenericSpecializationTests/genericCandidateFailFast 2>&1 | xcsift`
Expected: PASS.

- [ ] **Step 8: Run the full specializer test class**

Run: `swift test --filter SwiftInterfaceTests.GenericSpecializationTests 2>&1 | xcsift`
Expected: all existing tests pass, including the new one. The default `isGeneric: Bool = false` parameter on `Candidate.init` keeps any existing positional call sites compiling unchanged.

- [ ] **Step 9: Commit**

```bash
git add Sources/SwiftInterface/GenericSpecializer/GenericSpecializer.swift Sources/SwiftInterface/GenericSpecializer/Models/SpecializationRequest.swift Tests/SwiftInterfaceTests/GenericSpecializationTests.swift
git commit -m "feat(SwiftInterface): fail fast on generic candidates with typed error"
```

---

## Task 6: Surface `invertibleProtocols` on `Parameter` (#5)

**Files:**

- Modify: `Sources/SwiftInterface/GenericSpecializer/Models/SpecializationRequest.swift` — `Parameter` gains `invertibleProtocols`.
- Modify: `Sources/SwiftInterface/GenericSpecializer/GenericSpecializer.swift` — `buildParameters` second pass that fills the field.
- Test: `Tests/SwiftInterfaceTests/GenericSpecializationTests.swift` — new fixture and test.

- [ ] **Step 1: Add the test fixture and failing test**

The fixture and `@Test` method are added inside the existing `GenericSpecializationTests` class (a `final class` is itself Copyable, so nesting a `~Copyable` struct inside it is fine). The conditional `Copyable` conformance is declared in a top-level extension because conditional conformance can only be declared at file scope.

Append inside `GenericSpecializationTests` (after the `mixedConstraintsSpecialize` test, just before the closing `}` of the class):

```swift
    // MARK: - Inverted protocols (~Copyable)

    struct TestInvertedCopyableStruct<A: ~Copyable>: ~Copyable {
        let a: A
    }

    @Test func invertedProtocolsExposed() async throws {
        let machO = MachOImage.current()

        let descriptor = try #require(try machO.swift.typeContextDescriptors.first {
            try $0.struct?.name(in: machO).contains("TestInvertedCopyableStruct") == true
        }?.struct)

        let indexer = SwiftInterfaceIndexer(in: machO)
        try await indexer.prepare()

        let specializer = GenericSpecializer(indexer: indexer)
        let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))

        #expect(request.parameters.count == 1)

        let invertible = try #require(request.parameters[0].invertibleProtocols)
        // ~Copyable means the .copyable bit is not set in the surfaced set.
        #expect(!invertible.contains(.copyable))

        // Specialize with a Copyable type (Int) — the conditional Copyable
        // extension makes the struct itself Copyable when A is Copyable, so
        // the metadata accessor should succeed.
        let result = try specializer.specialize(request, with: ["A": .metatype(Int.self)])
        let structMetadata = try #require(result.resolveMetadata().struct)
        #expect(try structMetadata.fieldOffsets() == [0])
    }
```

Then append at file scope (after the closing `}` of the class):

```swift
extension GenericSpecializationTests.TestInvertedCopyableStruct: Copyable where A: Copyable {}
```

- [ ] **Step 2: Run the test, expect a build failure**

Run: `swift test --filter SwiftInterfaceTests.GenericSpecializationTests/invertedProtocolsExposed 2>&1 | xcsift`
Expected: compile error — `invertibleProtocols` is not a member of `Parameter`.

- [ ] **Step 3: Add `invertibleProtocols` to `Parameter`**

In `Sources/SwiftInterface/GenericSpecializer/Models/SpecializationRequest.swift`, modify the `Parameter` struct (currently lines 36-78). The new field plus an updated initialiser:

```swift
    public struct Parameter: Sendable {
        /// Parameter name (e.g., "A", "B", "A1" - based on depth and index)
        public let name: String

        /// Parameter index in generic signature
        public let index: Int

        /// Depth level (for nested generic contexts)
        public let depth: Int

        /// Requirements on this parameter (ordered - PWT passed in this order)
        public let requirements: [Requirement]

        /// Candidate types that satisfy all requirements
        public var candidates: [Candidate]

        /// Invertible protocols (~Copyable / ~Escapable) that the parameter
        /// declares. The set carries the bits that ARE present — e.g.
        /// `<A: ~Copyable>` produces a set without `.copyable`. `nil` means
        /// the parameter has no `invertedProtocols` requirement and retains
        /// every invertible protocol by default (the typical Swift case).
        public let invertibleProtocols: InvertibleProtocolSet?

        public init(
            name: String,
            index: Int,
            depth: Int,
            requirements: [Requirement],
            candidates: [Candidate] = [],
            invertibleProtocols: InvertibleProtocolSet? = nil
        ) {
            self.name = name
            self.index = index
            self.depth = depth
            self.requirements = requirements
            self.candidates = candidates
            self.invertibleProtocols = invertibleProtocols
        }

        /// Protocol requirements that require witness tables (in order)
        public var protocolRequirements: [Requirement] {
            requirements.filter {
                if case .protocol = $0 { return true }
                return false
            }
        }

        /// Whether this parameter has any protocol requirements
        public var hasProtocolRequirements: Bool {
            !protocolRequirements.isEmpty
        }
    }
```

`MachOSwiftSection` is already imported by this file (line 3), which exposes `InvertibleProtocolSet` — no new import needed.

- [ ] **Step 4: Fill the field from `buildParameters`**

In `GenericSpecializer.swift:79-120` extend the body of `buildParameters` so that after collecting requirements and candidates a second pass extracts any `.invertedProtocols` requirement targeting the parameter being constructed.

Replace this block at the existing tail of the inner loop:

```swift
                parameters.append(SpecializationRequest.Parameter(
                    name: paramName,
                    index: index,
                    depth: depth,
                    requirements: requirements,
                    candidates: candidates
                ))
```

with:

```swift
                let invertibleProtocols = Self.collectInvertibleProtocols(
                    for: index,
                    depth: depth,
                    in: genericContext
                )

                parameters.append(SpecializationRequest.Parameter(
                    name: paramName,
                    index: index,
                    depth: depth,
                    requirements: requirements,
                    candidates: candidates,
                    invertibleProtocols: invertibleProtocols
                ))
```

Add the new helper as a `private static` function inside the same `extension GenericSpecializer`, just after `mergedRequirements`:

```swift
    /// Pick out the `~Copyable` / `~Escapable` declaration for the
    /// generic parameter at `(depth, index)`, intersecting if multiple
    /// `invertedProtocols` requirements target the same parameter.
    /// Returns `nil` when no requirement targets this parameter.
    private static func collectInvertibleProtocols(
        for index: Int,
        depth: Int,
        in genericContext: GenericContext
    ) -> InvertibleProtocolSet? {
        // The binary stores the parameter index as a flat 16-bit value
        // across all depth levels: it equals the cumulative count of
        // parameters in prior depths plus the current depth's index.
        let priorDepthParameterCount = genericContext.allParameters
            .prefix(depth)
            .reduce(0) { $0 + $1.count }
        let flatIndex = UInt16(priorDepthParameterCount + index)

        var result: InvertibleProtocolSet?
        for descriptor in mergedRequirements(from: genericContext)
        where descriptor.layout.flags.kind == .invertedProtocols {
            guard case .invertedProtocols(let inverted) = descriptor.content else { continue }
            guard inverted.genericParamIndex == flatIndex else { continue }

            if let existing = result {
                result = existing.intersection(inverted.protocols)
            } else {
                result = inverted.protocols
            }
        }
        return result
    }
```

- [ ] **Step 5: Run the new test**

Run: `swift test --filter SwiftInterfaceTests.GenericSpecializationTests/invertedProtocolsExposed 2>&1 | xcsift`
Expected: PASS — `invertibleProtocols` is non-`nil` for the fixture, `.copyable` is absent, specialization with `Int` succeeds.

- [ ] **Step 6: Run the full specializer test class**

Run: `swift test --filter SwiftInterfaceTests.GenericSpecializationTests 2>&1 | xcsift`
Expected: every test passes — the new optional field defaults to `nil` for fixtures without `invertedProtocols`, so the existing tests are unaffected.

- [ ] **Step 7: Commit**

```bash
git add Sources/SwiftInterface/GenericSpecializer/GenericSpecializer.swift Sources/SwiftInterface/GenericSpecializer/Models/SpecializationRequest.swift Tests/SwiftInterfaceTests/GenericSpecializationTests.swift
git commit -m "feat(SwiftInterface): surface invertible protocols on Parameter"
```

---

## Done

After Task 6 the working tree should have six commits, each scoped to one numbered fix from the spec. Final verification:

- [ ] **Step 1: Final full-suite run**

Run: `swift test --filter SwiftInterfaceTests 2>&1 | xcsift`
Expected: all tests in `SwiftInterfaceTests` pass.

- [ ] **Step 2: Confirm spec coverage**

| Spec section | Plan task | Status |
|---|---|---|
| Design §1 invertibleProtocols on Parameter | Task 6 | ✓ |
| Design §2 conditional invertible merge | Task 4 | ✓ |
| Design §3 split nil-return arms | Task 2 | ✓ |
| Design §4 generic candidate fail-fast | Task 5 | ✓ |
| Design §5 configurable MetadataRequest | Task 3 | ✓ |
| Design §6 remove dead code | Task 1 | ✓ |
| Testing §3.1 inverted protocols exposure | Task 6 step 1 | ✓ |
| Testing §3.2 fail-fast on generic candidate | Task 5 step 1 | ✓ |
| Testing §3.3 configurable MetadataRequest | Task 3 step 1 | ✓ |
| Testing §3.4 conditional invertible (e2e) | Task 6 fixture's conditional `Copyable` extension exercises §2 merge | ✓ |
