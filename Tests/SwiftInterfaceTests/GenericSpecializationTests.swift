import Foundation
import Testing
import MachOKit
import Dependencies
@_spi(Internals) import MachOSymbols
@_spi(Internals) import MachOCaches
@_spi(Support) @testable import SwiftInterface
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport
@testable import SwiftDump
@testable @_spi(Internals) import SwiftInspection
@testable import Demangling
import OrderedCollections

@Suite(.serialized)
struct GenericSpecializationTests {
    /// One-shot cache of the three `SwiftInterfaceIndexer` shapes used across
    /// `GenericSpecializationTests`. swift-testing instantiates the test class
    /// once per `@Test`, so naive per-test setup re-prepares every indexer
    /// 18 times and dominates suite runtime. The actor preserves correctness
    /// (preparation runs to completion before the indexer is observed) while
    /// guaranteeing each shape is built at most once per process.
    private actor SharedIndexerCache {
        static let shared = SharedIndexerCache()

        private var indexerCache: SwiftInterfaceIndexer<MachOImage>?

        enum CacheError: Error, LocalizedError {
            case missingImage(name: String)

            var errorDescription: String? {
                switch self {
                case .missingImage(let name):
                    return "expected MachOImage(name: \"\(name)\") to be loadable for the test fixture"
                }
            }
        }

        /// Indexer over the current process plus Foundation and libswiftCore.
        func indexer() async throws -> SwiftInterfaceIndexer<MachOImage> {
            if let indexerCache { return indexerCache }
            let indexer = SwiftInterfaceIndexer(in: MachOImage.current())
            try indexer.addSubIndexer(SwiftInterfaceIndexer(in: Self.requireImage(name: "Foundation")))
            try indexer.addSubIndexer(SwiftInterfaceIndexer(in: Self.requireImage(name: "libswiftCore")))
            try await indexer.prepare()
            indexerCache = indexer
            return indexer
        }

        private static func requireImage(name: String) throws -> MachOImage {
            guard let image = MachOImage(name: name) else {
                throw CacheError.missingImage(name: name)
            }
            return image
        }
    }

    /// `MachOImage.current()` for the test process. Trivial to fetch but
    /// kept as a stored property so test bodies can reference it directly
    /// instead of calling `.current()` 17+ times across the suite.
    let machO: MachOImage

    /// Indexer attached to the current process + Foundation + libswiftCore.
    let indexer: SwiftInterfaceIndexer<MachOImage>

    init() async throws {
        self.machO = .current()
        self.indexer = try await SharedIndexerCache.shared.indexer()
    }

    /// Resolves the first struct context descriptor whose name contains
    /// `nameContains`. The fixtures live as nested types on this suite, so a
    /// substring match against the mangled name is sufficient and avoids
    /// pinning each test to the full module-qualified form.
    private func structDescriptor(named nameContains: String) throws -> StructDescriptor {
        try #require(
            try machO.swift.typeContextDescriptors.first {
                try $0.struct?.name(in: machO).contains(nameContains) == true
            }?.struct,
            "expected a struct context descriptor whose name contains \"\(nameContains)\""
        )
    }

    /// Resolves the descriptor along with its generic context. Used by tests
    /// that inspect the generic header (e.g. `numKeyArguments`) in addition
    /// to driving `GenericSpecializer`.
    private func genericStructFixture(
        named nameContains: String
    ) throws -> (descriptor: StructDescriptor, genericContext: GenericContext) {
        let descriptor = try structDescriptor(named: nameContains)
        let genericContext = try #require(
            try descriptor.genericContext(in: machO),
            "expected genericContext on \(nameContains)"
        )
        return (descriptor, genericContext)
    }

    struct TestGenericStruct<A: Collection, B: Equatable, C: Hashable> where A.Element: Hashable, A.Element: Decodable, A.Element: Encodable {
        let a: A
        let b: B
        let c: C
    }

    @Test func main() async throws {
        let descriptor = try #require(try machO.swift.typeContextDescriptors.first { try $0.struct?.name(in: machO).contains("TestGenericStruct") == true }?.struct?.asPointerWrapper(in: machO))

        let genericContext = try #require(try descriptor.genericContext())

        #expect(genericContext.header.numKeyArguments == 9)

        let AMetatype = [Int].self
        let AProtocol = (any Collection).self

        let BMetatype = Double.self
        let BProtocol = (any Equatable).self

        let CMetatype = Data.self
        let CProtocol = (any Hashable).self

        let AMetadata = try Metadata.createInProcess(AMetatype)
        let BMetadata = try Metadata.createInProcess(BMetatype)
        let CMetadata = try Metadata.createInProcess(CMetatype)

        let specializer = GenericSpecializer(indexer: indexer)

        let associatedTypeWitnesses = try specializer.resolveAssociatedTypeWitnesses(for: .struct(descriptor), substituting: [
            "A": AMetadata,
            "B": BMetadata,
            "C": CMetadata,
        ])

        let metadataAccessorFunction = try #require(try descriptor.metadataAccessorFunction())
        let metadata = try metadataAccessorFunction(
            request: .completeAndBlocking, metadatas: [
                AMetadata,
                BMetadata,
                CMetadata,
            ], witnessTables: [
                #require(try RuntimeFunctions.conformsToProtocol(metatype: AMetatype, protocolType: AProtocol)),
                #require(try RuntimeFunctions.conformsToProtocol(metatype: BMetatype, protocolType: BProtocol)),
                #require(try RuntimeFunctions.conformsToProtocol(metatype: CMetatype, protocolType: CProtocol)),
            ] + associatedTypeWitnesses.values.flatMap { $0 }
        )
        try #expect(#require(metadata.value.resolve().struct).fieldOffsets() == [0, 8, 16])
    }

    @Test func makeRequest() async throws {
        let descriptor = try structDescriptor(named: "TestGenericStruct")

        let specializer = GenericSpecializer(
            machO: machO,
            conformanceProvider: IndexerConformanceProvider(indexer: indexer)
        )
        let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))

        for candidate in request.parameters[1].candidates {
            candidate.typeName.name.print()
        }

        // Should have 3 parameters: A, B, C
        #expect(request.parameters.count == 3)

        // Check parameter names follow depth/index naming convention
        #expect(request.parameters[0].name == "A")
        #expect(request.parameters[1].name == "B")
        #expect(request.parameters[2].name == "C")

        // Check requirements exist
        #expect(request.parameters[0].hasProtocolRequirements) // A: Collection
        #expect(request.parameters[1].hasProtocolRequirements) // B: Equatable
        #expect(request.parameters[2].hasProtocolRequirements) // C: Hashable

        // Check associated type requirements
        #expect(!request.associatedTypeRequirements.isEmpty)
    }

    @Test func validation() throws {
        let descriptor = try structDescriptor(named: "TestGenericStruct")

        let specializer = GenericSpecializer(
            machO: machO,
            conformanceProvider: EmptyConformanceProvider()
        )
        let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))

        // Test missing arguments
        let emptySelection: SpecializationSelection = [:]
        let validation = specializer.validate(selection: emptySelection, for: request)
        #expect(!validation.isValid)
        #expect(validation.errors.count == 3) // Missing A, B, C

        // Test valid selection
        let validSelection: SpecializationSelection = [
            "A": .metatype([Int].self),
            "B": .metatype(Double.self),
            "C": .metatype(Data.self),
        ]
        let validValidation = specializer.validate(selection: validSelection, for: request)
        #expect(validValidation.isValid)
    }

    @Test func specialize() async throws {
        let descriptor = try structDescriptor(named: "TestGenericStruct")

        let specializer = GenericSpecializer(indexer: indexer)
        let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))

        let selection: SpecializationSelection = [
            "A": .metatype([Int].self),
            "B": .metatype(Double.self),
            "C": .metatype(Data.self),
        ]

        let result = try specializer.specialize(request, with: selection)

        // Verify resolved arguments
        #expect(result.resolvedArguments.count == 3)
        #expect(result.resolvedArguments[0].parameterName == "A")
        #expect(result.resolvedArguments[1].parameterName == "B")
        #expect(result.resolvedArguments[2].parameterName == "C")

        // A: Collection requires a PWT
        #expect(result.resolvedArguments[0].hasWitnessTables)
        // B: Equatable requires a PWT
        #expect(result.resolvedArguments[1].hasWitnessTables)
        // C: Hashable requires a PWT
        #expect(result.resolvedArguments[2].hasWitnessTables)

        // Verify we can resolve metadata
        let metadata = try result.resolveMetadata()
        let structMetadata = try #require(metadata.struct)
        let fieldOffsets = try structMetadata.fieldOffsets()
        #expect(fieldOffsets == [0, 8, 16])
    }

    @Test func selectionBuilder() throws {
        let selection = SpecializationSelection.builder()
            .set("A", to: [Int].self)
            .set("B", to: String.self)
            .build()

        #expect(selection.hasArgument(for: "A"))
        #expect(selection.hasArgument(for: "B"))
        #expect(!selection.hasArgument(for: "C"))
        #expect(selection.selectedParameterNames.count == 2)
    }

    // MARK: - Unconstrained generics

    struct TestUnconstrainedStruct<A> {
        let a: A
    }

    @Test func unconstrainedSpecialize() async throws {
        let (descriptor, genericContext) = try genericStructFixture(named: "TestUnconstrainedStruct")

        // 1 metadata, 0 PWT
        #expect(genericContext.header.numKeyArguments == 1)

        let specializer = GenericSpecializer(indexer: indexer)
        let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))

        #expect(request.parameters.count == 1)
        #expect(request.parameters[0].name == "A")
        #expect(!request.parameters[0].hasProtocolRequirements)
        #expect(request.associatedTypeRequirements.isEmpty)

        let result = try specializer.specialize(request, with: ["A": .metatype(Int.self)])
        #expect(result.resolvedArguments.count == 1)
        #expect(!result.resolvedArguments[0].hasWitnessTables)

        let metadata = try result.resolveMetadata()
        let structMetadata = try #require(metadata.struct)
        #expect(try structMetadata.fieldOffsets() == [0])
    }

    // MARK: - Single protocol on a single parameter

    struct TestSingleProtocolStruct<A: Hashable> {
        let a: A
    }

    @Test func singleProtocolSpecialize() async throws {
        let (descriptor, genericContext) = try genericStructFixture(named: "TestSingleProtocolStruct")

        // 1 metadata + 1 PWT (Hashable)
        #expect(genericContext.header.numKeyArguments == 2)

        let specializer = GenericSpecializer(indexer: indexer)
        let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))

        #expect(request.parameters.count == 1)
        #expect(request.parameters[0].hasProtocolRequirements)
        #expect(request.parameters[0].protocolRequirements.count == 1)
        #expect(request.associatedTypeRequirements.isEmpty)

        let result = try specializer.specialize(request, with: ["A": .metatype(Int.self)])
        #expect(result.resolvedArguments.count == 1)
        #expect(result.resolvedArguments[0].hasWitnessTables)

        let metadata = try result.resolveMetadata()
        let structMetadata = try #require(metadata.struct)
        #expect(try structMetadata.fieldOffsets() == [0])
    }

    // MARK: - Multiple protocols on the same parameter

    struct TestMultiProtocolStruct<A: Hashable & Decodable & Encodable> {
        let a: A
    }

    @Test func multiProtocolSpecialize() async throws {
        let (descriptor, genericContext) = try genericStructFixture(named: "TestMultiProtocolStruct")

        // 1 metadata + 3 PWT (Hashable, Decodable, Encodable)
        #expect(genericContext.header.numKeyArguments == 4)

        let specializer = GenericSpecializer(indexer: indexer)
        let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))

        #expect(request.parameters.count == 1)
        #expect(request.parameters[0].protocolRequirements.count == 3)
        #expect(request.associatedTypeRequirements.isEmpty)

        let result = try specializer.specialize(request, with: ["A": .metatype(Int.self)])
        #expect(result.resolvedArguments[0].witnessTables.count == 3)

        let metadata = try result.resolveMetadata()
        let structMetadata = try #require(metadata.struct)
        #expect(try structMetadata.fieldOffsets() == [0])
    }

    // MARK: - Class constraint (layout requirement)

    struct TestClassConstraintStruct<A: AnyObject> {
        let a: A
    }

    final class TestRefClass {}

    @Test func classConstraintSpecialize() async throws {
        let (descriptor, genericContext) = try genericStructFixture(named: "TestClassConstraintStruct")

        // 1 metadata, no PWT (layout requirement does not require WT)
        #expect(genericContext.header.numKeyArguments == 1)

        let specializer = GenericSpecializer(indexer: indexer)
        let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))

        #expect(request.parameters.count == 1)
        // Layout requirement is recorded but does not need a witness table
        #expect(!request.parameters[0].hasProtocolRequirements)
        let hasLayout = request.parameters[0].requirements.contains { req in
            if case .layout = req { return true }
            return false
        }
        #expect(hasLayout)

        let result = try specializer.specialize(request, with: ["A": .metatype(TestRefClass.self)])
        #expect(!result.resolvedArguments[0].hasWitnessTables)

        let metadata = try result.resolveMetadata()
        let structMetadata = try #require(metadata.struct)
        #expect(try structMetadata.fieldOffsets() == [0])
    }

    // MARK: - Multi-level associated type

    struct TestNestedAssociatedStruct<A: Sequence> where A.Element: Sequence, A.Element.Element: Hashable {
        let a: A
    }

    @Test func nestedAssociatedTypeRequest() async throws {
        let (descriptor, genericContext) = try genericStructFixture(named: "TestNestedAssociatedStruct")

        // 1 metadata + 3 PWT (A:Sequence, A.Element:Sequence, A.Element.Element:Hashable)
        #expect(genericContext.header.numKeyArguments == 4)

        let specializer = GenericSpecializer(indexer: indexer)
        let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))

        #expect(request.parameters.count == 1)
        #expect(request.parameters[0].protocolRequirements.count == 1)

        // Two associated requirements: A.Element and A.Element.Element
        #expect(request.associatedTypeRequirements.count == 2)

        let pathByDepth = request.associatedTypeRequirements.map(\.path)
        // The single-level path "[Element]" must exist (A.Element: Sequence)
        #expect(pathByDepth.contains(["Element"]))
        // The two-level path "[Element, Element]" must exist (A.Element.Element: Hashable)
        #expect(pathByDepth.contains(["Element", "Element"]))
    }

    @Test func nestedAssociatedTypeSpecialize() async throws {
        let descriptor = try structDescriptor(named: "TestNestedAssociatedStruct")

        let specializer = GenericSpecializer(indexer: indexer)
        let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))

        // A = [[Int]] satisfies: Sequence, Element=[Int] is a Sequence, Element.Element=Int is Hashable
        let result = try specializer.specialize(request, with: ["A": .metatype([[Int]].self)])
        #expect(result.resolvedArguments.count == 1)

        let metadata = try result.resolveMetadata()
        let structMetadata = try #require(metadata.struct)
        // Single field of type [[Int]] occupies one pointer slot
        #expect(try structMetadata.fieldOffsets() == [0])
    }

    // MARK: - Mixed direct + associated requirements

    // MARK: - Two distinct associated-type chains

    struct TestDualAssociatedStruct<A: Sequence, B: Sequence> where A.Element: Hashable, B.Element: Hashable {
        let a: A
        let b: B
    }

    @Test func dualAssociatedSpecialize() async throws {
        let (descriptor, genericContext) = try genericStructFixture(named: "TestDualAssociatedStruct")

        // 2 metadata + 4 PWT (A:Sequence, B:Sequence, A.Element:Hashable, B.Element:Hashable)
        #expect(genericContext.header.numKeyArguments == 6)

        let specializer = GenericSpecializer(indexer: indexer)
        let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))

        #expect(request.parameters.count == 2)
        #expect(request.parameters[0].protocolRequirements.count == 1) // A: Sequence
        #expect(request.parameters[1].protocolRequirements.count == 1) // B: Sequence
        #expect(request.associatedTypeRequirements.count == 2)

        let pathByParam = Dictionary(grouping: request.associatedTypeRequirements, by: \.parameterName)
        #expect(pathByParam["A"]?.first?.path == ["Element"])
        #expect(pathByParam["B"]?.first?.path == ["Element"])

        // A = [Int] (Element = Int), B = [String] (Element = Character).
        let result = try specializer.specialize(request, with: [
            "A": .metatype([Int].self),
            "B": .metatype([String].self),
        ])

        #expect(result.resolvedArguments.count == 2)
        #expect(result.resolvedArguments[0].witnessTables.count == 1)
        #expect(result.resolvedArguments[1].witnessTables.count == 1)

        let metadata = try result.resolveMetadata()
        let structMetadata = try #require(metadata.struct)
        // [Int] occupies 8 bytes, [String] occupies 8 bytes (Array storage pointer)
        #expect(try structMetadata.fieldOffsets() == [0, 8])
    }

    struct TestMixedConstraintsStruct<A: Collection, B: Hashable> where A.Element: Hashable {
        let a: A
        let b: B
    }

    @Test func mixedConstraintsSpecialize() async throws {
        let (descriptor, genericContext) = try genericStructFixture(named: "TestMixedConstraintsStruct")

        // 2 metadata + 3 PWT (A:Collection, B:Hashable, A.Element:Hashable)
        #expect(genericContext.header.numKeyArguments == 5)

        let specializer = GenericSpecializer(indexer: indexer)
        let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))

        #expect(request.parameters.count == 2)
        #expect(request.parameters[0].name == "A")
        #expect(request.parameters[1].name == "B")
        #expect(request.parameters[0].protocolRequirements.count == 1) // Collection
        #expect(request.parameters[1].protocolRequirements.count == 1) // Hashable
        #expect(request.associatedTypeRequirements.count == 1)
        #expect(request.associatedTypeRequirements[0].parameterName == "A")
        #expect(request.associatedTypeRequirements[0].path == ["Element"])

        let result = try specializer.specialize(request, with: [
            "A": .metatype([Int].self),
            "B": .metatype(String.self),
        ])
        #expect(result.resolvedArguments[0].witnessTables.count == 1) // A: Collection
        #expect(result.resolvedArguments[1].witnessTables.count == 1) // B: Hashable

        let metadata = try result.resolveMetadata()
        let structMetadata = try #require(metadata.struct)
        // [Int] is one pointer (8 bytes), String is 16 bytes
        // a at offset 0, b at offset 8
        #expect(try structMetadata.fieldOffsets() == [0, 8])
    }

    @Test func configurableMetadataRequest() async throws {
        let descriptor = try structDescriptor(named: "TestGenericStruct")

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

    @Test func genericCandidateFailFast() async throws {
        let descriptor = try structDescriptor(named: "TestSingleProtocolStruct")

        let specializer = GenericSpecializer(indexer: indexer)
        let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))

        // Pin to specific stdlib types so a failure points clearly at either
        // the fail-fast logic (test body) or a fixture shift (#require message),
        // rather than the generic "no isGeneric candidate" mode the original
        // first-matching-any-candidate form would silently degrade into.
        // `currentName` strips the module prefix (e.g. "Swift.Int" → "Int").
        let genericCandidate = try #require(
            request.parameters[0].candidates.first { $0.typeName.currentName == "Array" && $0.isGeneric },
            "expected Swift.Array candidate flagged isGeneric"
        )
        let nonGenericCandidate = try #require(
            request.parameters[0].candidates.first { $0.typeName.currentName == "Int" && !$0.isGeneric },
            "expected Swift.Int candidate flagged non-generic"
        )

        // Non-generic candidate still resolves successfully.
        let okResult = try specializer.specialize(
            request,
            with: ["A": .candidate(nonGenericCandidate)]
        )
        _ = try okResult.resolveMetadata()

        // Generic candidate throws the new typed error.
        do {
            _ = try specializer.specialize(
                request,
                with: ["A": .candidate(genericCandidate)]
            )
            Issue.record("expected candidateRequiresNestedSpecialization to be thrown")
        } catch let GenericSpecializer<MachOImage>.SpecializerError.candidateRequiresNestedSpecialization(candidate, parameterCount) {
            #expect(candidate.typeName == genericCandidate.typeName)
            #expect(parameterCount >= 1)
        }
    }

    // MARK: - Inverted protocols (~Copyable)

    struct TestInvertedCopyableStruct<A: ~Copyable>: ~Copyable {
        let a: A
    }

    @Test func invertedProtocolsExposed() async throws {
        let descriptor = try structDescriptor(named: "TestInvertedCopyableStruct")

        let specializer = GenericSpecializer(indexer: indexer)
        let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))

        #expect(request.parameters.count == 1)

        let invertible = try #require(request.parameters[0].invertibleProtocols)
        // ~Copyable only: the set encodes which protocols are suppressed, so
        // the parameter declaring `~Copyable` (and not `~Escapable`) must
        // produce exactly `[.copyable]` — using `==` instead of `contains`
        // catches a regression where extra bits leak into the set.
        #expect(invertible == .copyable)

        // Specialize with a Copyable type (Int) — the conditional Copyable
        // extension makes the struct itself Copyable when A is Copyable, so
        // the metadata accessor should succeed.
        let result = try specializer.specialize(request, with: ["A": .metatype(Int.self)])
        let structMetadata = try #require(result.resolveMetadata().struct)
        #expect(try structMetadata.fieldOffsets() == [0])
    }

    // MARK: - Default invertible-protocol case

    @Test func noInvertedRequirementYieldsNil() async throws {
        let descriptor = try structDescriptor(named: "TestGenericStruct")

        let specializer = GenericSpecializer(indexer: indexer)
        let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))

        #expect(request.parameters.count == 3)
        for parameter in request.parameters {
            #expect(parameter.invertibleProtocols == nil)
        }
    }

    // MARK: - Generic-candidate error message

    @Test func candidateErrorMessageMentionsSpecialized() async throws {
        let descriptor = try structDescriptor(named: "TestSingleProtocolStruct")

        let specializer = GenericSpecializer(indexer: indexer)
        let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))

        let genericCandidate = try #require(
            request.parameters[0].candidates.first { $0.typeName.currentName == "Array" && $0.isGeneric },
            "expected Swift.Array candidate flagged isGeneric"
        )

        do {
            _ = try specializer.specialize(
                request,
                with: ["A": .candidate(genericCandidate)]
            )
            Issue.record("expected candidateRequiresNestedSpecialization to be thrown")
        } catch let error as GenericSpecializer<MachOImage>.SpecializerError {
            let description = try #require(error.errorDescription)
            #expect(description.contains("Argument.specialized"))
            #expect(description.contains("Array"))
            #expect(description.contains("generic"))
        }
    }

    // MARK: - Nested generic types (P0 reproduction)
    //
    // The bugs surfaced below all stem from the same root: Swift's binary
    // stores `parameters` and `requirements` cumulatively at every level of a
    // nested generic context (see `swift/lib/IRGen/GenMeta.cpp:7263` —
    // `canSig->forEachParam` walks every visible GP including inherited ones,
    // and `addGenericRequirements` emits the full canonical signature). The
    // current `GenericContext` / `GenericSpecializer` plumbing handles
    // *single-level* parent nesting correctly by accident — the math falls
    // out the same when there is exactly one parent generic context — but
    // breaks at depth ≥ 2.

    /// Two-level nested generic. **Baseline** — single-level parent nesting
    /// happens to produce the right `(depth, index)` mapping because
    /// `parentParameters.last.count` and `parentParameters.flatMap.count`
    /// coincide when there is only one parent generic context. This test
    /// should keep passing on the current implementation.
    struct NestedGenericTwoLevelOuter<A: Hashable> {
        struct NestedGenericTwoLevelInner<B: Equatable> {
            let a: A
            let b: B
        }
    }

    @Test func nestedTwoLevelBaseline() throws {
        let descriptor = try structDescriptor(named: "NestedGenericTwoLevelInner")
        let genericContext = try #require(try descriptor.genericContext(in: machO))

        // Inner sees both A (inherited from Outer) and B (its own), stored
        // cumulatively.
        #expect(genericContext.header.numParams == 2)
        #expect(genericContext.parameters.count == 2)
        #expect(genericContext.requirements.count == 2)
        #expect(genericContext.parentParameters.count == 1)
        #expect(genericContext.parentParameters.first?.count == 1)
        #expect(genericContext.currentParameters.count == 1)
        #expect(genericContext.currentRequirements.count == 1)

        let specializer = GenericSpecializer(
            machO: machO,
            conformanceProvider: EmptyConformanceProvider()
        )
        let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))

        // Two parameters with demangler-canonical names "A" and "A1".
        #expect(request.parameters.count == 2)
        #expect(request.parameters.map(\.name) == ["A", "A1"])
        #expect(request.parameters[0].protocolRequirements.count == 1) // A: Hashable
        #expect(request.parameters[1].protocolRequirements.count == 1) // A1 (= B): Equatable
    }

    /// Three-level nested generic — one type parameter per level, each with
    /// a different protocol constraint. Exercises **P0.1** (the
    /// `currentRequirements` flatMap miscount in `GenericContext.swift:50`)
    /// and **P0.2** (the `buildParameters` (depth, index) iteration over the
    /// cumulative `allParameters` in `GenericSpecializer.swift:131`).
    struct NestedGenericThreeLevelOuter<A: Hashable> {
        struct NestedGenericThreeLevelMiddle<B: Equatable> {
            struct NestedGenericThreeLevelInner<C: Comparable> {
                let a: A
                let b: B
                let c: C
            }
        }
    }

    @Test func nestedThreeLevelCurrentRequirementsLosesInner() throws {
        let descriptor = try structDescriptor(named: "NestedGenericThreeLevelInner")
        let genericContext = try #require(try descriptor.genericContext(in: machO))

        // Sanity — the binary stores parameters and requirements cumulatively.
        #expect(genericContext.parameters.count == 3)     // [A, B, C]
        #expect(genericContext.requirements.count == 3)   // [A:Hashable, B:Equatable, C:Comparable]
        #expect(genericContext.parentParameters.count == 2)
        #expect(genericContext.parentParameters.first?.count == 1) // Outer cumulative = [A]
        #expect(genericContext.parentParameters.last?.count == 2)  // Middle cumulative = [A, B]
        #expect(genericContext.currentParameters.count == 1)       // [C]

        // P0.1 — `currentRequirements` should be `[C: Comparable]` (1 entry).
        // The current impl drops `parentRequirements.flatMap{$0}.count = 1 + 2 = 3`
        // entries from a 3-element cumulative array, leaving an empty list.
        // Correct behaviour mirrors `currentParameters`: drop only
        // `parentRequirements.last?.count` entries.
        #expect(
            genericContext.currentRequirements.count == 1,
            "P0.1: currentRequirements should be [C: Comparable]; flatMap-over-cumulative-parents over-drops at depth ≥ 2."
        )
    }

    @Test func nestedThreeLevelMakeRequestProducesWrongParameters() throws {
        let descriptor = try structDescriptor(named: "NestedGenericThreeLevelInner")

        let specializer = GenericSpecializer(
            machO: machO,
            conformanceProvider: EmptyConformanceProvider()
        )
        let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))

        // P0.2 — `makeRequest` should expose exactly 3 type parameters whose
        // canonical names match what the demangler produces for the binary's
        // `qd_X` / `qd0_X` mangling:
        //   "A"   (depth 0, idx 0) — Outer's A   (mangled `x`)
        //   "A1"  (depth 1, idx 0) — Middle's B  (mangled `qd_0`)
        //   "A2"  (depth 2, idx 0) — Inner's C   (mangled `qd0_0`)
        //
        // The current impl iterates `allParameters` directly. Because the
        // middle entry `[A, B]` is *cumulative* rather than newly-introduced,
        // the loop emits an extra `Parameter` and shifts Middle's B to a wrong
        // (depth, index). Concretely, names come out as ["A", "A1", "B1", "A2"].
        let names = request.parameters.map(\.name)
        #expect(
            request.parameters.count == 3,
            "P0.2: expected 3 generic parameters, got \(request.parameters.count) named \(names)."
        )
        #expect(
            names == ["A", "A1", "A2"],
            "P0.2: expected canonical names [A, A1, A2], got \(names)."
        )

        var parametersByName: [String: SpecializationRequest.Parameter] = [:]
        for parameter in request.parameters {
            parametersByName[parameter.name] = parameter
        }

        // Each canonical parameter should carry exactly one direct protocol
        // requirement. Under the bug, "A" sees A:Hashable twice (cumulative
        // parent merge duplicates it), "A1" sees Middle's B (correctly), and
        // "A2" sees nothing — Inner's C: Comparable is silently dropped by
        // the buggy `currentRequirements` and never reaches `mergedRequirements`.
        #expect(parametersByName["A"]?.protocolRequirements.count == 1)
        #expect(parametersByName["A1"]?.protocolRequirements.count == 1)
        #expect(parametersByName["A2"]?.protocolRequirements.count == 1)
    }

    /// Three-level nested generic with `~Copyable` on every type parameter.
    /// Each layer's `InvertedProtocols` requirement records the suppressed
    /// parameter via a *flat* `genericParamIndex` set by Swift's
    /// `lib/IRGen/GenMeta.cpp:7488-7501` — `sig->getGenericParamOrdinal(genericParam)`
    /// returns the parameter's position across **every** depth.
    ///
    /// Expected:
    ///   "A"   → flat index 0 → invertibleProtocols == .copyable
    ///   "A1"  → flat index 1 → invertibleProtocols == .copyable
    ///   "A2"  → flat index 2 → invertibleProtocols == .copyable
    ///
    /// Observed (P0.3): `collectInvertibleProtocols` derives the flat index
    /// by summing `allParameters.prefix(depth).count`. Cumulative parent
    /// levels over-count; "A2" gets queried as flat 3, "B1" (the bogus extra
    /// parameter introduced by P0.2) gets queried as flat 2, and the actual
    /// Inner C silently falls back to `nil`.
    struct NestedInvertedOuter<A: ~Copyable>: ~Copyable {
        struct NestedInvertedMiddle<B: ~Copyable>: ~Copyable {
            struct NestedInvertedInner<C: ~Copyable>: ~Copyable {
                var a: A
                var b: B
                var c: C
            }
        }
    }

    @Test func nestedThreeLevelInvertedProtocolsPerLevel() throws {
        let descriptor = try structDescriptor(named: "NestedInvertedInner")

        let specializer = GenericSpecializer(
            machO: machO,
            conformanceProvider: EmptyConformanceProvider()
        )
        let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))

        // P0.2 prerequisite — without it the parameter list is malformed
        // before we can even probe invertibleProtocols. We still run the
        // P0.3 assertions below via lookup-by-name so that whichever P0 is
        // fixed first surfaces a clean diagnostic.
        let names = request.parameters.map(\.name)
        #expect(request.parameters.count == 3, "P0.2 prerequisite: got names \(names)")
        #expect(names == ["A", "A1", "A2"], "P0.2 prerequisite: got names \(names)")

        var parametersByName: [String: SpecializationRequest.Parameter] = [:]
        for parameter in request.parameters {
            parametersByName[parameter.name] = parameter
        }

        // P0.3 — every parameter is declared `~Copyable`.
        #expect(
            parametersByName["A"]?.invertibleProtocols == .copyable,
            "Outer's A (flat index 0) is `~Copyable`."
        )
        #expect(
            parametersByName["A1"]?.invertibleProtocols == .copyable,
            "Middle's B (canonical A1, flat index 1) is `~Copyable`."
        )
        #expect(
            parametersByName["A2"]?.invertibleProtocols == .copyable,
            "P0.3: Inner's C (canonical A2, flat index 2) is `~Copyable`; collectInvertibleProtocols looks it up at flat index 3 because of the cumulative parent count."
        )
    }
}

extension GenericSpecializationTests.TestInvertedCopyableStruct: Copyable where A: Copyable {}

extension GenericSpecializationTests.NestedInvertedOuter: Copyable where A: Copyable {}
extension GenericSpecializationTests.NestedInvertedOuter.NestedInvertedMiddle: Copyable where A: Copyable, B: Copyable {}
extension GenericSpecializationTests.NestedInvertedOuter.NestedInvertedMiddle.NestedInvertedInner: Copyable where A: Copyable, B: Copyable, C: Copyable {}
