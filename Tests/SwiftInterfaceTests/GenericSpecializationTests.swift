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
            ] + associatedTypeWitnesses
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

    // MARK: - P3 reproduction: TypePack / Value generics must throw early
    //
    // Pre-fix `buildParameters` skipped non-`type` GenericParamKind entries
    // silently (`guard param.hasKeyArgument, param.kind == .type else { continue }`).
    // For a fixture with `each T`, that meant `request.parameters` came back
    // empty and `request.keyArgumentCount` mismatched the actual binary
    // header — `specialize` would then call the metadata accessor with too
    // few metadata pointers, only failing deep inside the runtime.
    // Post-fix `makeRequest` rejects TypePack/Value parameters at the entry
    // with a typed `SpecializerError.unsupportedGenericParameter`.

    struct TestTypePackStruct<each T> {
        let value: (repeat each T)
    }

    @Test func typePackParameterThrowsEarly() throws {
        let descriptor = try structDescriptor(named: "TestTypePackStruct")

        let specializer = GenericSpecializer(
            machO: machO,
            conformanceProvider: EmptyConformanceProvider()
        )

        do {
            _ = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))
            Issue.record("P3: makeRequest must reject a fixture containing a TypePack parameter")
        } catch let error as GenericSpecializer<MachOImage>.SpecializerError {
            switch error {
            case .unsupportedGenericParameter(let kind):
                #expect(kind == .typePack)
            default:
                Issue.record("P3: expected unsupportedGenericParameter, got \(error)")
            }
        }
    }

    // MARK: - P6 reproduction: validate() catches obvious type mismatches
    //
    // Pre-fix `validate(selection:for:)` only checked missing/extra arguments.
    // Anything the user could possibly get wrong about the *type* of a
    // selection had to wait until `specialize()` failed inside
    // `RuntimeFunctions.conformsToProtocol` with a generic
    // `witnessTableNotFound`. Post-fix the new `runtimePreflight` companion
    // surfaces protocol-conformance mismatches as
    // `SpecializationValidation.Error.protocolRequirementNotSatisfied` and
    // class-layout violations as `.layoutRequirementNotSatisfied`, before
    // the accessor call.

    @Test func runtimePreflightCatchesProtocolMismatch() async throws {
        // TestSingleProtocolStruct<A: Hashable>. Picking a Function type for
        // A (Functions don't conform to Hashable) must trip the preflight.
        let descriptor = try structDescriptor(named: "TestSingleProtocolStruct")
        let specializer = GenericSpecializer(indexer: indexer)
        let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))

        let badSelection: SpecializationSelection = ["A": .metatype((() -> Void).self)]

        let preflight = specializer.runtimePreflight(selection: badSelection, for: request)
        #expect(!preflight.isValid)
        let hasProtocolError = preflight.errors.contains { error in
            if case .protocolRequirementNotSatisfied(_, let proto, _) = error {
                return proto.contains("Hashable")
            }
            return false
        }
        #expect(hasProtocolError, "P6: preflight must report Hashable mismatch for () -> Void")

        // And the user-facing `specialize` should now throw with the same
        // diagnostic instead of letting it surface as `witnessTableNotFound`.
        do {
            _ = try specializer.specialize(request, with: badSelection)
            Issue.record("P6: specialize must reject the bad selection")
        } catch let error as GenericSpecializer<MachOImage>.SpecializerError {
            if case .specializationFailed(let reason) = error {
                #expect(reason.contains("Hashable"))
            } else {
                Issue.record("P6: expected specializationFailed, got \(error)")
            }
        }
    }

    @Test func runtimePreflightCatchesLayoutMismatch() async throws {
        // TestClassConstraintStruct<A: AnyObject>. Picking a value type for A
        // must trip the layout check.
        let descriptor = try structDescriptor(named: "TestClassConstraintStruct")
        let specializer = GenericSpecializer(indexer: indexer)
        let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))

        let badSelection: SpecializationSelection = ["A": .metatype(Int.self)]

        let preflight = specializer.runtimePreflight(selection: badSelection, for: request)
        #expect(!preflight.isValid)
        let hasLayoutError = preflight.errors.contains { error in
            if case .layoutRequirementNotSatisfied = error {
                return true
            }
            return false
        }
        #expect(hasLayoutError, "P6: preflight must report layout mismatch for a value type passed where AnyObject is required")
    }

    // MARK: - P7 reproduction: candidateOptions.excludeGenerics filters generics
    //
    // Without the option, `findCandidates` includes generic types (Array,
    // Dictionary, etc.) whose own descriptor is generic. Selecting one as
    // `Argument.candidate(...)` would then throw
    // `candidateRequiresNestedSpecialization` deep inside `specialize`.
    // The `excludeGenerics` option lets callers ask for "directly
    // specializable" candidates only.

    @Test func excludeGenericsFiltersGenericCandidates() async throws {
        let descriptor = try structDescriptor(named: "TestSingleProtocolStruct")
        let specializer = GenericSpecializer(indexer: indexer)

        let defaultRequest = try specializer.makeRequest(
            for: TypeContextDescriptorWrapper.struct(descriptor)
        )
        let defaultHasGenericCandidate = defaultRequest.parameters[0].candidates.contains { $0.isGeneric }
        #expect(defaultHasGenericCandidate, "P7 baseline: default candidate list should include generic candidates")

        let filteredRequest = try specializer.makeRequest(
            for: TypeContextDescriptorWrapper.struct(descriptor),
            candidateOptions: .excludeGenerics
        )
        let filteredHasGenericCandidate = filteredRequest.parameters[0].candidates.contains { $0.isGeneric }
        #expect(!filteredHasGenericCandidate, "P7: excludeGenerics must drop every isGeneric candidate")
        #expect(!filteredRequest.parameters[0].candidates.isEmpty,
                "P7: there are still non-generic Hashable conformers (Int, String, …) — the filter must not empty the list")
    }

    // MARK: - P8 reproduction: AssociatedTypeRequirement aggregates by (param, path)
    //
    // Pre-fix every individual constraint emitted its own
    // `AssociatedTypeRequirement` even when several constraints shared the
    // same `(parameterName, path)` — `requirements: [Requirement]` was always
    // a singleton array, despite the field being plural. Consumers had to
    // re-group by hand. Post-fix the build pass aggregates by key and
    // preserves canonical (binary) order inside each entry.

    @Test func associatedTypeRequirementsAggregatedByPath() async throws {
        // TestGenericStruct has three constraints on A.Element (Hashable,
        // Decodable, Encodable). Pre-fix `associatedTypeRequirements` would
        // hold three entries with `path == ["Element"]` each carrying one
        // requirement. Post-fix it should hold a single entry whose
        // `requirements` array carries all three.
        let descriptor = try structDescriptor(named: "TestGenericStruct")
        let specializer = GenericSpecializer(
            machO: machO,
            conformanceProvider: EmptyConformanceProvider()
        )
        let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))

        let elementEntries = request.associatedTypeRequirements.filter {
            $0.parameterName == "A" && $0.path == ["Element"]
        }
        #expect(
            elementEntries.count == 1,
            "P8: A.Element constraints must collapse into one AssociatedTypeRequirement, got \(elementEntries.count) entries"
        )
        let aggregate = try #require(elementEntries.first)
        #expect(
            aggregate.requirements.count == 3,
            "P8: aggregated entry should carry all three protocols (Hashable / Decodable / Encodable), got \(aggregate.requirements.count)"
        )
        let names = aggregate.requirements.compactMap { req -> String? in
            if case .protocol(let info) = req { return info.protocolName.name }
            return nil
        }
        // Canonical order is alphabetical-by-protocol within the same LHS.
        #expect(names == names.sorted(), "P8: aggregated requirements must preserve canonical (alphabetical-by-protocol) order")
    }

    // MARK: - P2: nested generic specialize() end-to-end coverage
    //
    // The aa07d74 fix added `makeRequest` assertions for ≥ 3-level nested
    // generics, but never actually called `specialize` on one. This test
    // closes that gap by driving the full pipeline (request → specialize →
    // metadata accessor → field offsets) on the
    // `NestedGenericThreeLevelInner` fixture.

    @Test func nestedThreeLevelSpecializeEndToEnd() async throws {
        let descriptor = try structDescriptor(named: "NestedGenericThreeLevelInner")
        let specializer = GenericSpecializer(indexer: indexer)
        let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))

        let result = try specializer.specialize(request, with: [
            "A": .metatype(Int.self),       // outer's A: Hashable
            "A1": .metatype(Double.self),   // middle's B: Equatable
            "A2": .metatype(String.self),   // inner's C: Comparable
        ])

        #expect(result.resolvedArguments.count == 3)
        #expect(result.resolvedArguments[0].parameterName == "A")
        #expect(result.resolvedArguments[1].parameterName == "A1")
        #expect(result.resolvedArguments[2].parameterName == "A2")
        // Each direct GP requirement contributes exactly one PWT.
        #expect(result.resolvedArguments.allSatisfy { $0.witnessTables.count == 1 })

        let structMetadata = try #require(result.resolveMetadata().struct)
        let fieldOffsets = try structMetadata.fieldOffsets()
        // Layout: a(Int) at 0, b(Double) at 8, c(String) at 16. String
        // occupies 16 bytes but the field offset is the start address.
        #expect(fieldOffsets == [0, 8, 16])
    }

    // MARK: - P5 reproduction: SwiftDump cumulative-parameter dump
    //
    // `dumpGenericParameters(isDumpCurrentLevel: false)` was iterating
    // `allParameters`, whose parent levels are stored cumulatively. At
    // depth ≥ 2 that would re-emit each inherited parameter (e.g. for our
    // three-level `NestedGenericThreeLevelInner`, the dump produced
    // `<A, A, B1, A2>` — `A` re-appearing at depth 1, and Middle's `B`
    // misnamed `B1` because the loop counted offsets by depth-cumulative
    // position rather than per-level introduction). Post-fix the dumper
    // walks per-level "newly introduced" slices, emitting exactly
    // `<A, A1, A2>` to match the demangler's canonical naming.

    @Test func nestedThreeLevelDumpAllLevelsHasNoDuplicates() async throws {
        let descriptor = try structDescriptor(named: "NestedGenericThreeLevelInner")
        let genericContext = try #require(try descriptor.genericContext(in: machO))

        let dumped = try await genericContext.dumpGenericParameters(
            in: machO,
            isDumpCurrentLevel: false
        ).string

        // Expected demangler-canonical order: A, A1, A2.
        let expectedNames = ["A", "A1", "A2"]
        for name in expectedNames {
            #expect(
                dumped.contains(name),
                "P5: dump must include `\(name)` (got `\(dumped)`)"
            )
        }

        // The pre-fix output `<A, A, B1, A2>` contained `B1` (Middle's `B`
        // miscounted), and the bare `A` token was present *twice*. Both
        // are tell-tale signs of cumulative parent re-emission.
        #expect(
            !dumped.contains("B1"),
            "P5: pre-fix cumulative iteration produced a phantom `B1` token (got `\(dumped)`)"
        )

        // Catch the duplicate-`A` regression: a properly de-cumulated dump
        // emits `A` once. The dump output has the form `A, A1, A2` (or
        // similar) — split on `,` and trim, then count tokens equal to
        // bare `A`. The lookbehind regex form would be cleaner but Swift
        // Regex doesn't support lookbehind yet.
        let tokens = dumped
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let bareACount = tokens.filter { $0 == "A" }.count
        #expect(
            bareACount == 1,
            "P5: bare `A` must appear once; pre-fix cumulative iteration produced \(bareACount) occurrences in tokens \(tokens)"
        )
    }

    // MARK: - Associated-type PWT order with same-leaf interleaving
    //
    // Regression coverage for the previously-buggy
    // `GenericSpecializer.resolveAssociatedTypeWitnesses`. An earlier
    // implementation returned `OrderedDictionary<Metadata, [PWT]>` keyed
    // by the *leaf* metadata of each requirement chain, and `specialize`
    // flattened it via `dict.values.flatMap { $0 }`. Per `OrderedDictionary`
    // semantics, updating an existing key keeps it in its original
    // position — so when two distinct chains resolved to the *same* leaf
    // metadata but a third chain *in between* resolved to a different
    // one, the flattened PWT list broke the binary's
    // `compareDependentTypes` order
    // (`swift/lib/AST/GenericSignature.cpp:846`: all GP-rooted
    // requirements rank before nested-type-rooted ones, and within each
    // block by parameter (depth, index)).
    //
    // For the fixture below specialized with A=[Int], B=String, C=[Int]:
    //   A.Element = Int       (M_Int)
    //   B.Element = Character (M_Char)
    //   C.Element = Int       (M_Int — same as A.Element)
    //
    // Binary canonical order is parameter-declaration order:
    //   [Int_Hashable, Char_Hashable, Int_Hashable]
    //
    // Pre-fix flatten produced the buggy
    //   [Int_Hashable, Int_Hashable, Char_Hashable]
    // — the slot the runtime reserved for B.Element's Hashable PWT got
    // Int's Hashable PWT instead, mis-routing any associated-type
    // Hashable lookup performed on the specialized type. `fieldOffsets()`
    // was invariant under the re-ordering (PWT slot widths are uniform),
    // so no other test caught it. Post-fix the function returns a flat
    // `[ProtocolWitnessTable]` collected in `mergedRequirements`
    // iteration order — which is itself the binary's canonical order.

    struct TestTriAssociatedSameLeafStruct<A: Sequence, B: Sequence, C: Sequence>
        where A.Element: Hashable, B.Element: Hashable, C.Element: Hashable
    {
        let a: A
        let b: B
        let c: C
    }

    @Test func associatedWitnessOrderingPreservesBinaryOrder() async throws {
        // `resolveAssociatedTypeWitnesses` calls `genericContext()` (the
        // in-process overload), so the descriptor must be an in-process
        // pointer wrapper — same setup as `main()`.
        let descriptor = try #require(
            try machO.swift.typeContextDescriptors.first {
                try $0.struct?.name(in: machO).contains("TestTriAssociatedSameLeafStruct") == true
            }?.struct?.asPointerWrapper(in: machO),
            "expected TestTriAssociatedSameLeafStruct descriptor"
        )

        let specializer = GenericSpecializer(indexer: indexer)

        // Bind A and C to the same array type so their A.Element /
        // C.Element chains both resolve to Int's metadata; B is bound to
        // String so its B.Element chain resolves to Character — distinct
        // from Int. This is the exact configuration that exposes the
        // pre-fix leaf-grouping bug.
        let aMetadata = try Metadata.createInProcess([Int].self)
        let bMetadata = try Metadata.createInProcess(String.self)
        let cMetadata = try Metadata.createInProcess([Int].self)

        let resolvedWitnesses = try specializer.resolveAssociatedTypeWitnesses(
            for: TypeContextDescriptorWrapper.struct(descriptor),
            substituting: [
                "A": aMetadata,
                "B": bMetadata,
                "C": cMetadata,
            ]
        )

        let intHashablePWT = try #require(
            try RuntimeFunctions.conformsToProtocol(
                metatype: Int.self,
                protocolType: (any Hashable).self
            ),
            "Int must conform to Hashable in the test process"
        )
        let charHashablePWT = try #require(
            try RuntimeFunctions.conformsToProtocol(
                metatype: Character.self,
                protocolType: (any Hashable).self
            ),
            "Character must conform to Hashable in the test process"
        )

        // Binary requirement order — A.Element, B.Element, C.Element —
        // per `compareDependentTypes`. All three share depth 0 and rank
        // by parameter index, so the canonical order is exactly
        // declaration order.
        let expectedBinaryOrder: [ProtocolWitnessTable] = [
            intHashablePWT,   // A.Element = Int
            charHashablePWT,  // B.Element = Character
            intHashablePWT,   // C.Element = Int
        ]
        #expect(
            resolvedWitnesses == expectedBinaryOrder,
            "resolveAssociatedTypeWitnesses must emit PWTs in canonical (binary) requirement order. Pre-fix leaf-keyed `OrderedDictionary` flatten produced [Int_Hashable, Int_Hashable, Char_Hashable] for this fixture, mis-feeding slot 2 (binary reserves it for B.Element: Hashable) with Int's PWT."
        )
    }

    @Test func specializeMatchesManualBinaryOrder() async throws {
        // End-to-end companion to `associatedWitnessOrderingPreservesBinaryOrder`:
        // build the metadata via the API and via a hand-rolled call to
        // the metadata accessor with witness tables in canonical
        // (binary) order, and verify the runtime returns the same
        // metadata pointer for both. Swift's generic-metadata cache keys
        // on the entire `(generic args, witness tables)` tuple — feeding
        // the accessor witness tables in a non-canonical order routes
        // the call to a different cache slot (or, worse, populates a
        // freshly allocated metadata whose internal associated-type
        // witness routing is wrong).
        //
        // Note: `makeRequest` resolves the descriptor via the *file-context*
        // `genericContext(in: machO)` overload, while
        // `metadataAccessorFunction()` (no-arg) reads in-process — so we
        // need a file-form descriptor for `makeRequest` and an
        // in-process pointer wrapper for the manual accessor call.
        let descriptor = try structDescriptor(named: "TestTriAssociatedSameLeafStruct")
        let inProcessDescriptor = descriptor.asPointerWrapper(in: machO)
        let specializer = GenericSpecializer(indexer: indexer)
        let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))

        let aArrayInt = [Int].self
        let bString = String.self
        let cArrayInt = [Int].self

        let aMetadata = try Metadata.createInProcess(aArrayInt)
        let bMetadata = try Metadata.createInProcess(bString)
        let cMetadata = try Metadata.createInProcess(cArrayInt)

        let aSequencePWT = try #require(
            try RuntimeFunctions.conformsToProtocol(metatype: aArrayInt, protocolType: (any Sequence).self),
            "[Int] must conform to Sequence"
        )
        let bSequencePWT = try #require(
            try RuntimeFunctions.conformsToProtocol(metatype: bString, protocolType: (any Sequence).self),
            "String must conform to Sequence"
        )
        let cSequencePWT = try #require(
            try RuntimeFunctions.conformsToProtocol(metatype: cArrayInt, protocolType: (any Sequence).self),
            "[Int] must conform to Sequence"
        )
        let intHashablePWT = try #require(
            try RuntimeFunctions.conformsToProtocol(metatype: Int.self, protocolType: (any Hashable).self),
            "Int must conform to Hashable"
        )
        let charHashablePWT = try #require(
            try RuntimeFunctions.conformsToProtocol(metatype: Character.self, protocolType: (any Hashable).self),
            "Character must conform to Hashable"
        )

        // Manual call: witness tables in canonical (binary) order.
        // Direct-GP block: A:Sequence, B:Sequence, C:Sequence.
        // Associated block: A.Element:Hashable, B.Element:Hashable,
        // C.Element:Hashable.
        let accessor = try #require(
            try inProcessDescriptor.metadataAccessorFunction(),
            "TestTriAssociatedSameLeafStruct must have a metadata accessor function"
        )
        let manualResponse = try accessor(
            request: .completeAndBlocking,
            metadatas: [aMetadata, bMetadata, cMetadata],
            witnessTables: [
                aSequencePWT,
                bSequencePWT,
                cSequencePWT,
                intHashablePWT,   // A.Element
                charHashablePWT,  // B.Element
                intHashablePWT,   // C.Element
            ]
        )
        let manualMetadata = try manualResponse.value.resolve().metadata

        // API call.
        let apiResult = try specializer.specialize(request, with: [
            "A": .metatype(aArrayInt),
            "B": .metatype(bString),
            "C": .metatype(cArrayInt),
        ])
        let apiMetadata = try apiResult.metadata()

        // The runtime's generic-metadata cache returns the same
        // metadata pointer iff the `(args, PWTs)` tuple matches.
        // Pre-fix `specialize` flattens its leaf-keyed dict to
        //   [aSequence, bSequence, cSequence, Int_H, Int_H, Char_H]
        // instead of the canonical
        //   [aSequence, bSequence, cSequence, Int_H, Char_H, Int_H]
        // — different cache key, divergent metadata pointer.
        #expect(
            manualMetadata == apiMetadata,
            "specialize() must produce the same metadata pointer the runtime returns when invoked manually with witness tables in canonical (binary) order; divergence indicates an incorrect PWT order in the API path."
        )
    }

    // MARK: - makeRequest rejects non-generic types (M10)
    //
    // `genericContext(for:)` throws `notGenericType` when the resolved
    // descriptor has no generic context. Any caller that hands a plain
    // (non-generic) struct/enum/class to `makeRequest` should hit this
    // typed error instead of the silent fallthrough that earlier
    // versions of the specializer offered.

    struct TestNonGenericStruct {
        let value: Int
    }

    @Test func makeRequestRejectsNonGenericType() throws {
        let descriptor = try structDescriptor(named: "TestNonGenericStruct")
        let specializer = GenericSpecializer(
            machO: machO,
            conformanceProvider: EmptyConformanceProvider()
        )

        do {
            _ = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))
            Issue.record("expected notGenericType to be thrown for a fixture without generic context")
        } catch let error as GenericSpecializer<MachOImage>.SpecializerError {
            switch error {
            case .notGenericType:
                return
            default:
                Issue.record("expected notGenericType, got \(error)")
            }
        }
    }

    // MARK: - validate() reports extra-argument warnings (M8)
    //
    // `validate(selection:for:)` is the cheap static-only pass and must
    // not silently accept arguments for parameters the request does not
    // declare. Missing arguments surface as errors; arguments for
    // unknown parameters surface as `.extraArgument` warnings (the
    // selection is still considered valid — `isValid == true` — because
    // the extra entry is forwarded to no-one and cannot break the
    // accessor call).

    @Test func validateEmitsExtraArgumentWarning() throws {
        let descriptor = try structDescriptor(named: "TestSingleProtocolStruct")
        let specializer = GenericSpecializer(
            machO: machO,
            conformanceProvider: EmptyConformanceProvider()
        )
        let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))

        // `TestSingleProtocolStruct<A: Hashable>` declares a single GP "A".
        // Adding "Z" to the selection should surface as a warning, not an
        // error, and leave `isValid` unchanged.
        let selection: SpecializationSelection = [
            "A": .metatype(Int.self),
            "Z": .metatype(String.self),
        ]
        let validation = specializer.validate(selection: selection, for: request)

        #expect(validation.isValid, "extra arguments are warnings, not errors")
        #expect(validation.errors.isEmpty)
        let hasExtra = validation.warnings.contains { warning in
            if case .extraArgument(let name) = warning { return name == "Z" }
            return false
        }
        #expect(hasExtra, "validate must emit .extraArgument warning for a parameter not declared by the request")
    }

    // MARK: - Argument case coverage (M2a / M2b / M2c)
    //
    // The four `Argument` cases (`.metatype`, `.metadata`, `.candidate`,
    // `.specialized`) all flow through `resolveMetadata(for:parameterName:)`.
    // Existing tests exercise `.metatype` exhaustively; the three tests
    // below pin the other three paths, including the recursive
    // `.specialized` call that lets a previously-built
    // `SpecializationResult` feed back as a generic argument.

    @Test func argumentMetadataPathProducesSameMetadata() async throws {
        let descriptor = try structDescriptor(named: "TestSingleProtocolStruct")
        let specializer = GenericSpecializer(indexer: indexer)
        let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))

        // Pre-resolved Metadata fed via `.metadata(...)` must produce a
        // metadata pointer indistinguishable from the same selection
        // expressed with `.metatype(...)` — both go through
        // `Metadata.createInProcess(_:)` for the metatype case, so the
        // comparison is identity at the pointer level.
        let intMetadata = try Metadata.createInProcess(Int.self)
        let viaMetadata = try specializer.specialize(request, with: ["A": .metadata(intMetadata)])
        let viaMetatype = try specializer.specialize(request, with: ["A": .metatype(Int.self)])

        let metadataA = try viaMetadata.metadata()
        let metadataB = try viaMetatype.metadata()
        #expect(metadataA == metadataB, "Argument.metadata path must reach the same generic-metadata cache slot as Argument.metatype")

        // And the resolved argument plumbing should record the supplied
        // metadata verbatim — the runtime PWT still has to be looked up,
        // so `hasWitnessTables` reflects the (single, Hashable) protocol.
        #expect(viaMetadata.resolvedArguments[0].metadata == intMetadata)
        #expect(viaMetadata.resolvedArguments[0].hasWitnessTables)
    }

    @Test func argumentCandidatePathSpecializesNonGenericCandidate() async throws {
        let descriptor = try structDescriptor(named: "TestSingleProtocolStruct")
        let specializer = GenericSpecializer(indexer: indexer)

        // Use `.excludeGenerics` so the parameter's candidate list only
        // surfaces directly-specializable types — picking the first such
        // candidate (whatever the indexer produces, alphabetically first
        // among non-generic Hashable conformers) keeps the test
        // independent of stdlib iteration order.
        let request = try specializer.makeRequest(
            for: TypeContextDescriptorWrapper.struct(descriptor),
            candidateOptions: .excludeGenerics
        )
        let nonGenericCandidate = try #require(
            request.parameters[0].candidates.first { !$0.isGeneric },
            "expected at least one non-generic Hashable candidate after .excludeGenerics"
        )

        let result = try specializer.specialize(request, with: ["A": .candidate(nonGenericCandidate)])
        #expect(result.resolvedArguments.count == 1)
        // The resolved argument's metadata should match what
        // Metadata.createInProcess produces for the same concrete type
        // (the type lookup goes through the same metadata accessor).
        // We can't easily reconstruct the candidate's `Any.Type` here,
        // so just verify the PWT plumbing succeeded.
        #expect(result.resolvedArguments[0].hasWitnessTables)
        let structMetadata = try #require(result.resolveMetadata().struct)
        // Single-field struct of any concrete Hashable type: layout is
        // determined by the concrete type's value witness table; we
        // assert offsets are non-empty (== 1 field present).
        #expect(try structMetadata.fieldOffsets().count == 1)
    }

    // MARK: - Three-level nested ~Copyable specialize end-to-end (M3)
    //
    // `nestedThreeLevelInvertedProtocolsPerLevel` covers `makeRequest`
    // for the same fixture, asserting that every per-level
    // `invertibleProtocols` set comes out as `.copyable`. This test
    // closes the gap by running the full pipeline (request → specialize
    // → metadata accessor → field offsets) and verifying the conditional
    // `extension … : Copyable where A: Copyable, B: Copyable, C: Copyable`
    // chain is wired up correctly: binding every parameter to a
    // Copyable type lets the metadata accessor produce a non-nil
    // metadata pointer with the same field layout as the non-inverted
    // three-level fixture.

    @Test func nestedThreeLevelInvertedSpecializeEndToEnd() async throws {
        let descriptor = try structDescriptor(named: "NestedInvertedInner")
        let specializer = GenericSpecializer(indexer: indexer)
        let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))

        let result = try specializer.specialize(request, with: [
            "A": .metatype(Int.self),       // outer's A: ~Copyable, bound to Copyable Int
            "A1": .metatype(Double.self),   // middle's B: ~Copyable, bound to Copyable Double
            "A2": .metatype(String.self),   // inner's C: ~Copyable, bound to Copyable String
        ])

        #expect(result.resolvedArguments.count == 3)
        #expect(result.resolvedArguments.map(\.parameterName) == ["A", "A1", "A2"])
        // None of the three GPs has a witness-table-bearing protocol
        // requirement (they only declare `~Copyable`, which is a
        // capability suppression rather than a constraint).
        #expect(result.resolvedArguments.allSatisfy { !$0.hasWitnessTables })

        // Layout matches the non-inverted three-level fixture:
        // a(Int) at 0, b(Double) at 8, c(String) at 16.
        let structMetadata = try #require(result.resolveMetadata().struct)
        #expect(try structMetadata.fieldOffsets() == [0, 8, 16])
    }

    @Test func argumentSpecializedPathFeedsNestedSpecialization() async throws {
        let descriptor = try structDescriptor(named: "TestUnconstrainedStruct")
        let specializer = GenericSpecializer(indexer: indexer)
        let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))

        // Step 1: build TestUnconstrainedStruct<Int>.
        let inner = try specializer.specialize(request, with: ["A": .metatype(Int.self)])
        let innerMetadata = try inner.metadata()

        // Step 2: feed `inner` back in as the outer's GP. Equivalent to
        // TestUnconstrainedStruct<TestUnconstrainedStruct<Int>>.
        let outer = try specializer.specialize(request, with: ["A": .specialized(inner)])
        let outerMetadata = try outer.metadata()

        // The two metadatas must differ — they parameterize the same
        // type with different concrete arguments.
        #expect(innerMetadata != outerMetadata, "outer and inner specializations resolve to distinct generic metadata slots")

        // The resolved argument records the inner's metadata verbatim.
        #expect(outer.resolvedArguments[0].metadata == innerMetadata)

        // Layout check: outer holds a single field of type
        // TestUnconstrainedStruct<Int>, which is itself a single Int
        // (8 bytes), so the outer field is at offset 0 and occupies one
        // pointer-sized slot.
        let structMetadata = try #require(outer.resolveMetadata().struct)
        #expect(try structMetadata.fieldOffsets() == [0])
    }

    // MARK: - ~Escapable & dual ~Copyable / ~Escapable (M5)
    //
    // `invertedProtocolsExposed` covers the `~Copyable`-only single-
    // parameter case. The two tests below extend coverage to the other
    // two corners of the `InvertibleProtocolSet` matrix:
    //   - `~Escapable`-only — the Escapable bit must surface alone.
    //   - `~Copyable & ~Escapable` — both bits must surface together
    //     (set equality, not containment, to catch a regression where
    //     extra bits leak in).
    //
    // Both fixtures use empty `enum`s rather than empty `struct`s.
    // `~Escapable` types reject any synthesized initializer (the
    // implicit `init` returns `Self`, and `Self: ~Escapable` cannot be
    // returned without an explicit `@_lifetime` annotation), so an
    // empty struct also fails to compile. Empty enums are uninhabited
    // and have no synthesized init, so they pass the frontend check
    // while still emitting a generic-context descriptor that carries
    // the invertible-protocol flag set we want to inspect.

    enum TestInvertedEscapableEnum<A: ~Escapable>: ~Escapable {}

    @Test func invertedEscapableExposed() async throws {
        let descriptor = try #require(
            try machO.swift.typeContextDescriptors.first {
                try $0.enum?.name(in: machO).contains("TestInvertedEscapableEnum") == true
            }?.enum,
            "expected enum descriptor TestInvertedEscapableEnum"
        )
        let specializer = GenericSpecializer(
            machO: machO,
            conformanceProvider: EmptyConformanceProvider()
        )
        let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.enum(descriptor))

        #expect(request.parameters.count == 1)
        let invertible = try #require(request.parameters[0].invertibleProtocols)
        #expect(invertible == .escapable, "single ~Escapable should produce exactly the Escapable bit")
    }

    enum TestInvertedDualEnum<A: ~Copyable & ~Escapable>: ~Copyable & ~Escapable {}

    // MARK: - Enum and class generic types (M1)
    //
    // Existing coverage was struct-only. Both `makeRequest` and
    // `specialize` route through `TypeContextDescriptorWrapper`'s
    // `enum` / `class` cases the same way as `struct`; these two tests
    // pin that the rest of the pipeline (parameter discovery, PWT
    // resolution, metadata accessor invocation) handles enum and class
    // descriptors without struct-specific assumptions.

    enum TestGenericEnum<A: Hashable> {
        case some(A)
        case none
    }

    @Test func enumGenericMakeRequestAndSpecialize() async throws {
        let descriptor = try #require(
            try machO.swift.typeContextDescriptors.first {
                try $0.enum?.name(in: machO).contains("TestGenericEnum") == true
            }?.enum,
            "expected enum descriptor TestGenericEnum"
        )
        let specializer = GenericSpecializer(indexer: indexer)
        let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.enum(descriptor))

        #expect(request.parameters.count == 1)
        #expect(request.parameters[0].name == "A")
        #expect(request.parameters[0].hasProtocolRequirements,
                "A: Hashable must surface as a protocol requirement")
        #expect(request.parameters[0].protocolRequirements.count == 1)

        let result = try specializer.specialize(request, with: ["A": .metatype(Int.self)])
        #expect(result.resolvedArguments.count == 1)
        #expect(result.resolvedArguments[0].hasWitnessTables)

        // The resolved metadata must be an enum metadata kind, not a
        // struct/class one — this is the assertion that proves the
        // wrapper.enum case routed through the pipeline correctly.
        let wrapper = try result.resolveMetadata()
        _ = try #require(wrapper.enum,
                         "expected MetadataWrapper.enum, got \(wrapper)")
    }

    final class TestGenericClass<A: Hashable> {
        let a: A
        init(a: A) { self.a = a }
    }

    @Test func classGenericMakeRequestAndSpecialize() async throws {
        let descriptor = try #require(
            try machO.swift.typeContextDescriptors.first {
                try $0.class?.name(in: machO).contains("TestGenericClass") == true
            }?.class,
            "expected class descriptor TestGenericClass"
        )
        let specializer = GenericSpecializer(indexer: indexer)
        let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.class(descriptor))

        #expect(request.parameters.count == 1)
        #expect(request.parameters[0].name == "A")
        #expect(request.parameters[0].hasProtocolRequirements,
                "A: Hashable must surface as a protocol requirement")
        #expect(request.parameters[0].protocolRequirements.count == 1)

        let result = try specializer.specialize(request, with: ["A": .metatype(Int.self)])
        #expect(result.resolvedArguments.count == 1)
        #expect(result.resolvedArguments[0].hasWitnessTables)

        // The resolved metadata must be a class metadata kind.
        let wrapper = try result.resolveMetadata()
        _ = try #require(wrapper.class,
                         "expected MetadataWrapper.class, got \(wrapper)")
    }

    @Test func invertedDualCopyableAndEscapable() async throws {
        let descriptor = try #require(
            try machO.swift.typeContextDescriptors.first {
                try $0.enum?.name(in: machO).contains("TestInvertedDualEnum") == true
            }?.enum,
            "expected enum descriptor TestInvertedDualEnum"
        )
        let specializer = GenericSpecializer(
            machO: machO,
            conformanceProvider: EmptyConformanceProvider()
        )
        let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.enum(descriptor))

        #expect(request.parameters.count == 1)
        let invertible = try #require(request.parameters[0].invertibleProtocols)
        // Set equality — both bits must be present and nothing else.
        #expect(invertible == InvertibleProtocolSet([.copyable, .escapable]))
    }

    // MARK: - ABI invariant: same-named associated type from two unrelated protocols
    //
    // Locks the Swift compiler's GenericSignature minimization behaviour:
    // when two unrelated protocols both declare `associatedtype Element` and
    // a generic parameter conforms to BOTH, `A.Element` references in the
    // emitted requirements canonicalize to a SINGLE declaring protocol
    // (chosen by RequirementMachine's reduction order — empirically the
    // lexicographically earlier protocol). The binary never emits two
    // distinct LHS forms (`A.[P:Element]` vs `A.[Q:Element]`).
    //
    // This invariant lets `AssociatedTypeRequirementKey = (parameterName,
    // [stepName])` aggregate by name without losing protocol identity:
    // there is only ever one protocol tag per (parameter, name) in the
    // canonical signature, so two requirements landing on the same path
    // genuinely describe constraints on the same dependent member type.
    //
    // If a future Swift toolchain regresses this — emitting both
    // `A.[PWithElement:Element]` and `A.[QWithElement:Element]` separately
    // — the assertion below trips and the aggregation key in
    // `buildAssociatedTypeRequirements` needs to start including the
    // step's protocolNode.

    protocol PWithElement {
        associatedtype Element: Hashable
        func produceElement() -> Element
    }

    protocol QWithElement {
        associatedtype Element: Comparable
        func consumeElement(_: Element)
    }

    struct DualElementStruct<A: PWithElement & QWithElement> where A.Element: Codable {
        let value: A
    }

    @Test func dualProtocolSameNamedAssociatedTypeIsCanonicalized() throws {
        let descriptor = try structDescriptor(named: "DualElementStruct")
        let genericContext = try #require(try descriptor.genericContext(in: machO))

        // Walk every requirement's LHS, collecting the declaring protocol
        // identity for any `A.Element`-rooted dependent member type.
        var protocolIdentities: Set<String> = []
        var elementRequirementCount = 0
        for req in genericContext.requirements {
            let mangled = try req.paramMangledName(in: machO)
            let node = try MetadataReader.demangleType(for: mangled, in: machO)
            guard let path = GenericSpecializer<MachOImage>.extractAssociatedPath(of: node),
                  !path.steps.isEmpty,
                  path.baseParamName == "A",
                  path.steps.first?.name == "Element" else {
                continue
            }
            elementRequirementCount += 1
            protocolIdentities.insert(
                path.steps[0].protocolNode.print(using: .interfaceTypeBuilderOnly)
            )
        }

        // Sanity: with `where A.Element: Codable`, the binary emits two
        // requirements (Decodable + Encodable, the two real PWT-bearing
        // protocols Codable expands to). If this number changes, the
        // fixture's invariant has shifted in a way the test author should
        // re-verify.
        #expect(elementRequirementCount == 2)

        // The actual claim: every `A.Element` requirement references the
        // SAME declaring protocol after canonicalization.
        #expect(
            protocolIdentities.count == 1,
            "GenericSignature minimization should pick one canonical protocol for A.Element; saw \(protocolIdentities)"
        )
    }

    // MARK: - Bug reproduction: #5 runtimePreflight skips .specialized
    //
    // The pre-fix `runtimePreflight` had `.specialized` in its skip-list,
    // claiming it required running an accessor to obtain the metadata. But
    // a `SpecializationResult` already holds a resolved metadata pointer —
    // there's no accessor to run. The skip silently let through specialized
    // arguments whose result type didn't satisfy the target's protocol
    // requirements. Failure surfaced inside `specialize` as the much vaguer
    // `witnessTableNotFound`.

    @Test func runtimePreflightCatchesProtocolMismatchOnSpecializedArgument() async throws {
        let unconstrainedDescriptor = try structDescriptor(named: "TestUnconstrainedStruct")
        let specializer = GenericSpecializer(indexer: indexer)
        let unconstrainedRequest = try specializer.makeRequest(
            for: TypeContextDescriptorWrapper.struct(unconstrainedDescriptor)
        )

        // `TestUnconstrainedStruct<Int>` does NOT conform to Hashable —
        // the struct itself has no Hashable conformance, regardless of A.
        let unconstrainedResult = try specializer.specialize(
            unconstrainedRequest,
            with: ["A": .metatype(Int.self)]
        )

        // Now feed it where Hashable is required.
        let singleDescriptor = try structDescriptor(named: "TestSingleProtocolStruct")
        let singleRequest = try specializer.makeRequest(
            for: TypeContextDescriptorWrapper.struct(singleDescriptor)
        )

        let badSelection: SpecializationSelection = ["A": .specialized(unconstrainedResult)]

        let preflight = specializer.runtimePreflight(selection: badSelection, for: singleRequest)
        #expect(!preflight.isValid, "preflight must catch Hashable mismatch on .specialized argument")

        let hasProtocolError = preflight.errors.contains { error in
            if case .protocolRequirementNotSatisfied(_, let proto, _) = error {
                return proto.contains("Hashable")
            }
            return false
        }
        #expect(hasProtocolError, "expected protocolRequirementNotSatisfied for Hashable")

        // And `specialize` should reject with the same diagnostic, not the
        // vaguer `witnessTableNotFound` it surfaced before the fix.
        do {
            _ = try specializer.specialize(singleRequest, with: badSelection)
            Issue.record("specialize must reject the bad .specialized argument")
        } catch let error as GenericSpecializer<MachOImage>.SpecializerError {
            if case .specializationFailed(let reason) = error {
                #expect(reason.contains("Hashable"))
            } else {
                Issue.record("expected specializationFailed, got \(error)")
            }
        }
    }

    // MARK: - Bug reproduction: #1 specialize doesn't self-check keyArgumentCount
    //
    // The accessor takes `numKeyArguments` slots: `parameters.count`
    // metadatas + `protocol-PWTs + assoc-PWTs`. If our parameter discovery
    // or PWT collection ever miscounts (regression in `buildParameters` /
    // `collectRequirements` / `buildAssociatedTypeRequirements`), we'd send
    // the wrong number of args to the accessor and fail opaquely deep in
    // the runtime. Adding a count assertion converts that silent failure
    // into a typed `specializationFailed` with a clear message.

    @Test func specializeRejectsMismatchedKeyArgumentCount() async throws {
        let descriptor = try structDescriptor(named: "TestSingleProtocolStruct")
        let specializer = GenericSpecializer(indexer: indexer)
        let realRequest = try specializer.makeRequest(
            for: TypeContextDescriptorWrapper.struct(descriptor)
        )

        // Tampered request: claims a different keyArgumentCount than
        // parameters/requirements actually total.
        let tamperedRequest = SpecializationRequest(
            typeDescriptor: realRequest.typeDescriptor,
            parameters: realRequest.parameters,
            associatedTypeRequirements: realRequest.associatedTypeRequirements,
            keyArgumentCount: realRequest.keyArgumentCount + 5
        )

        do {
            _ = try specializer.specialize(tamperedRequest, with: ["A": .metatype(Int.self)])
            Issue.record("specialize must reject mismatched keyArgumentCount before invoking the accessor")
        } catch let error as GenericSpecializer<MachOImage>.SpecializerError {
            if case .specializationFailed(let reason) = error {
                #expect(
                    reason.lowercased().contains("key argument") || reason.lowercased().contains("count"),
                    "error message should mention key argument count, got: \(reason)"
                )
            } else {
                Issue.record("expected specializationFailed, got \(error)")
            }
        }
    }

    // MARK: - Bug reproduction: #4 runtimePreflight silently passes when
    // indexer is missing a required protocol
    //
    // When the protocol referenced by a parameter requirement isn't in the
    // indexer, `runtimePreflight` skips the conformance check entirely —
    // it can't construct the protocol descriptor to call
    // `swift_conformsToProtocol`. The fix surfaces this as a typed warning
    // so the user knows to add another sub-indexer instead of getting a
    // misleading `witnessTableNotFound` from `specialize`.

    @Test func runtimePreflightSurfacesIndexerMissingProtocolWarning() async throws {
        // Build an indexer that has the test image but NOT libswiftCore —
        // so `Hashable` (defined in libswiftCore) won't be found.
        let bareIndexer = SwiftInterfaceIndexer(in: machO)
        try await bareIndexer.prepare()

        // Sanity: `TestSingleProtocolStruct<A: Hashable>` is in `machO`,
        // so makeRequest still works (descriptors are read directly from
        // the binary, not from the indexer).
        let descriptor = try structDescriptor(named: "TestSingleProtocolStruct")
        let specializer = GenericSpecializer(indexer: bareIndexer)
        let request = try specializer.makeRequest(
            for: TypeContextDescriptorWrapper.struct(descriptor)
        )
        #expect(request.parameters.count == 1)
        #expect(request.parameters[0].protocolRequirements.count == 1)

        // Pass a fully valid Hashable conformer. The bug: with libswiftCore
        // missing from the indexer, preflight has no way to look up the
        // protocol descriptor, so it skips the conformance check. That's
        // fine on its own — but the user has no signal that validation is
        // incomplete.
        let preflight = specializer.runtimePreflight(
            selection: ["A": .metatype(Int.self)],
            for: request
        )

        // Expect a warning informing the user that a protocol couldn't be
        // checked because it's not in the indexer.
        let hasMissingProtocolWarning = preflight.warnings.contains { warning in
            if case .protocolNotInIndexer(_, let proto) = warning {
                return proto.contains("Hashable")
            }
            return false
        }
        #expect(
            hasMissingProtocolWarning,
            "preflight must warn when a parameter's protocol requirement is missing from the indexer; got warnings=\(preflight.warnings), errors=\(preflight.errors)"
        )
    }

    // MARK: - Bug reproduction: #15 validate doesn't distinguish
    // associated-type path from a typo
    //
    // `validate` flags any selection key not in `request.parameters` as
    // `.extraArgument`. A user who mistakenly tries to set an
    // associated-type path (`"A.Element"`) gets the same generic warning
    // as someone who typo'd `"Z"`. The path is structured (it appears in
    // `associatedTypeRequirements[*].fullPath`) so a more specific warning
    // is possible.

    @Test func validateGivesSpecificWarningForAssociatedTypePath() async throws {
        let descriptor = try structDescriptor(named: "TestNestedAssociatedStruct")
        let specializer = GenericSpecializer(
            machO: machO,
            conformanceProvider: EmptyConformanceProvider()
        )
        let request = try specializer.makeRequest(
            for: TypeContextDescriptorWrapper.struct(descriptor)
        )

        // Sanity: this fixture has A.Element as a real associated-type path.
        #expect(request.associatedTypeRequirements.contains { $0.fullPath == "A.Element" })

        let selection: SpecializationSelection = [
            "A": .metatype([[Int]].self),
            "A.Element": .metatype(Int.self),
        ]
        let validation = specializer.validate(selection: selection, for: request)
        #expect(validation.isValid, "associated-type path is a warning, not an error")

        let hasSpecific = validation.warnings.contains { warning in
            if case .associatedTypePathInSelection(let path) = warning {
                return path == "A.Element"
            }
            return false
        }
        #expect(
            hasSpecific,
            "validate must distinguish an associated-type path (derived; not user-supplied) from a generic extra argument; got \(validation.warnings)"
        )
    }

    // MARK: - Bug reproduction: #3 extractAssociatedPath returns nil for
    // a bare ProtocolSymbolicReference
    //
    // The Swift demangler in `popAssocTypeName`
    // (`swift/lib/Demangling/Demangler.cpp:2832-2845`) accepts three
    // protocol-shaped nodes for the second child of
    // `DependentAssociatedTypeRef`:
    //   - `.type` (when the symbolic-ref resolver succeeded and returned
    //     a wrapped tree)
    //   - `.protocolSymbolicReference` (resolver returned nil)
    //   - `.objectiveCProtocolSymbolicReference` (resolver returned nil)
    //
    // The current `extractAssociatedPath` only accepts `.type`. The other
    // two — which arise when MetadataReader's resolver fails — fall
    // through to a `nil` return, which then becomes a silent
    // `continue` in `buildAssociatedTypeRequirements` or a typed
    // `unknownParamNodeStructure` error in `resolveAssociatedTypeWitnesses`.
    //
    // This test pins the current behavior; the fix should at least give
    // both call sites a consistent (typed) error rather than silent skip
    // vs. throw.

    @Test func extractAssociatedPathHandlesBareProtocolSymbolicReference() throws {
        // Build the LHS for a hypothetical `A.Element: …` requirement
        // whose protocol child failed to resolve symbolically. The tree
        // mirrors what the demangler emits when the resolver returns nil:
        //   .type
        //     .dependentMemberType
        //       .type → .dependentGenericParamType (depth=0, index=0)
        //       .dependentAssociatedTypeRef
        //         .identifier "Element"
        //         .protocolSymbolicReference 42      ← bare, NOT in .type
        let bareSymbolicRef = Node.create(kind: .protocolSymbolicReference, index: 42)
        let nameNode = Node.create(kind: .identifier, text: "Element")
        let assocRef = Node.create(kind: .dependentAssociatedTypeRef, children: [
            nameNode,
            bareSymbolicRef,
        ])
        let baseDepth = Node.create(kind: .index, index: 0)
        let baseIndex = Node.create(kind: .index, index: 0)
        let baseGP = Node.create(kind: .dependentGenericParamType, children: [baseDepth, baseIndex])
        let dependent = Node.create(kind: .dependentMemberType, children: [
            Node.create(kind: .type, children: [baseGP]),
            assocRef,
        ])
        let outer = Node.create(kind: .type, children: [dependent])

        let path = GenericSpecializer<MachOImage>.extractAssociatedPath(of: outer)

        // Goal of the fix: even when the protocol child is a bare
        // symbolic ref, the path structure is still recoverable
        // (baseParamName + step name). Downstream resolution may still
        // fail at the protocol-descriptor lookup, but the parsing layer
        // shouldn't punt to nil.
        let recovered = try #require(
            path,
            "extractAssociatedPath must recover the parameter/name pair even when the protocol child is a bare ProtocolSymbolicReference; demangler legitimately emits this when its resolver returns nil"
        )
        #expect(recovered.baseParamName == "A")
        #expect(recovered.steps.map(\.name) == ["Element"])
    }
}

extension GenericSpecializationTests.TestInvertedCopyableStruct: Copyable where A: Copyable {}

extension GenericSpecializationTests.NestedInvertedOuter: Copyable where A: Copyable {}
extension GenericSpecializationTests.NestedInvertedOuter.NestedInvertedMiddle: Copyable where A: Copyable, B: Copyable {}
extension GenericSpecializationTests.NestedInvertedOuter.NestedInvertedMiddle.NestedInvertedInner: Copyable where A: Copyable, B: Copyable, C: Copyable {}

extension GenericSpecializationTests.TestInvertedEscapableEnum: Escapable where A: Escapable {}

// Note: `TestInvertedDualEnum` deliberately ships *without* conditional
// `Copyable` / `Escapable` extensions. The fixture's purpose is to
// expose the *regular* invertible-protocol record on its single GP
// (the binary's `<A: ~Copyable & ~Escapable>` declaration), which is
// what `Parameter.invertibleProtocols` reads. Adding the conditional
// extensions back in produces malformed descriptors under the current
// toolchain — the iteration over `typeContextDescriptors` throws when
// it tries to read one of them. If/when that toolchain bug is fixed,
// the conditional extensions can be reinstated to also exercise the
// merged-requirement path through `conditionalInvertibleProtocolsRequirements`.
