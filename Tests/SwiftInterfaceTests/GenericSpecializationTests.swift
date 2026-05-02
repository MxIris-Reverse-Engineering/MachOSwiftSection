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

final class GenericSpecializationTests: MachOImageTests, @unchecked Sendable {
    override class var imageName: MachOImageName { .SwiftUICore }

    struct TestGenericStruct<A, B, C> where A: Collection, B: Equatable, C: Hashable, A.Element: Hashable, A.Element: Decodable, A.Element: Encodable {
        let a: A
        let b: B
        let c: C
    }

    @Test func main() async throws {
        let machO = MachOImage.current()

        let indexer = SwiftInterfaceIndexer(in: machO)

        try indexer.addSubIndexer(SwiftInterfaceIndexer(in: #require(MachOImage(name: "Foundation"))))
        try indexer.addSubIndexer(SwiftInterfaceIndexer(in: #require(MachOImage(name: "libswiftCore"))))

        try await indexer.prepare()

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
        let machO = MachOImage.current()

        let descriptor = try #require(try machO.swift.typeContextDescriptors.first { try $0.struct?.name(in: machO).contains("TestGenericStruct") == true }?.struct)

        let indexer = SwiftInterfaceIndexer(in: machO)

        try await indexer.prepare()

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
        let machO = MachOImage.current()

        let descriptor = try #require(try machO.swift.typeContextDescriptors.first { try $0.struct?.name(in: machO).contains("TestGenericStruct") == true }?.struct)

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
        let machO = MachOImage.current()

        let descriptor = try #require(try machO.swift.typeContextDescriptors.first { try $0.struct?.name(in: machO).contains("TestGenericStruct") == true }?.struct)

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
        let machO = MachOImage.current()

        let descriptor = try #require(try machO.swift.typeContextDescriptors.first { try $0.struct?.name(in: machO).contains("TestUnconstrainedStruct") == true }?.struct)
        let genericContext = try #require(try descriptor.genericContext(in: machO))

        // 1 metadata, 0 PWT
        #expect(genericContext.header.numKeyArguments == 1)

        let indexer = SwiftInterfaceIndexer(in: machO)
        try await indexer.prepare()

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
        let machO = MachOImage.current()

        let descriptor = try #require(try machO.swift.typeContextDescriptors.first { try $0.struct?.name(in: machO).contains("TestSingleProtocolStruct") == true }?.struct)
        let genericContext = try #require(try descriptor.genericContext(in: machO))

        // 1 metadata + 1 PWT (Hashable)
        #expect(genericContext.header.numKeyArguments == 2)

        let indexer = SwiftInterfaceIndexer(in: machO)
        try indexer.addSubIndexer(SwiftInterfaceIndexer(in: #require(MachOImage(name: "libswiftCore"))))
        try await indexer.prepare()

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

    struct TestMultiProtocolStruct<A> where A: Hashable, A: Decodable, A: Encodable {
        let a: A
    }

    @Test func multiProtocolSpecialize() async throws {
        let machO = MachOImage.current()

        let descriptor = try #require(try machO.swift.typeContextDescriptors.first { try $0.struct?.name(in: machO).contains("TestMultiProtocolStruct") == true }?.struct)
        let genericContext = try #require(try descriptor.genericContext(in: machO))

        // 1 metadata + 3 PWT (Hashable, Decodable, Encodable)
        #expect(genericContext.header.numKeyArguments == 4)

        let indexer = SwiftInterfaceIndexer(in: machO)
        try indexer.addSubIndexer(SwiftInterfaceIndexer(in: #require(MachOImage(name: "libswiftCore"))))
        try await indexer.prepare()

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
        let machO = MachOImage.current()

        let descriptor = try #require(try machO.swift.typeContextDescriptors.first { try $0.struct?.name(in: machO).contains("TestClassConstraintStruct") == true }?.struct)
        let genericContext = try #require(try descriptor.genericContext(in: machO))

        // 1 metadata, no PWT (layout requirement does not require WT)
        #expect(genericContext.header.numKeyArguments == 1)

        let indexer = SwiftInterfaceIndexer(in: machO)
        try await indexer.prepare()

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

    struct TestNestedAssociatedStruct<A> where A: Sequence, A.Element: Sequence, A.Element.Element: Hashable {
        let a: A
    }

    @Test func nestedAssociatedTypeRequest() async throws {
        let machO = MachOImage.current()

        let descriptor = try #require(try machO.swift.typeContextDescriptors.first { try $0.struct?.name(in: machO).contains("TestNestedAssociatedStruct") == true }?.struct)
        let genericContext = try #require(try descriptor.genericContext(in: machO))

        // 1 metadata + 3 PWT (A:Sequence, A.Element:Sequence, A.Element.Element:Hashable)
        #expect(genericContext.header.numKeyArguments == 4)

        let indexer = SwiftInterfaceIndexer(in: machO)
        try indexer.addSubIndexer(SwiftInterfaceIndexer(in: #require(MachOImage(name: "libswiftCore"))))
        try await indexer.prepare()

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
        let machO = MachOImage.current()

        let descriptor = try #require(try machO.swift.typeContextDescriptors.first { try $0.struct?.name(in: machO).contains("TestNestedAssociatedStruct") == true }?.struct)

        let indexer = SwiftInterfaceIndexer(in: machO)
        try indexer.addSubIndexer(SwiftInterfaceIndexer(in: #require(MachOImage(name: "libswiftCore"))))
        try await indexer.prepare()

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

    struct TestDualAssociatedStruct<A, B> where A: Sequence, B: Sequence, A.Element: Hashable, B.Element: Hashable {
        let a: A
        let b: B
    }

    @Test func dualAssociatedSpecialize() async throws {
        let machO = MachOImage.current()

        let descriptor = try #require(try machO.swift.typeContextDescriptors.first { try $0.struct?.name(in: machO).contains("TestDualAssociatedStruct") == true }?.struct)
        let genericContext = try #require(try descriptor.genericContext(in: machO))

        // 2 metadata + 4 PWT (A:Sequence, B:Sequence, A.Element:Hashable, B.Element:Hashable)
        #expect(genericContext.header.numKeyArguments == 6)

        let indexer = SwiftInterfaceIndexer(in: machO)
        try indexer.addSubIndexer(SwiftInterfaceIndexer(in: #require(MachOImage(name: "libswiftCore"))))
        try await indexer.prepare()

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

    struct TestMixedConstraintsStruct<A, B> where A: Collection, A.Element: Hashable, B: Hashable {
        let a: A
        let b: B
    }

    @Test func mixedConstraintsSpecialize() async throws {
        let machO = MachOImage.current()

        let descriptor = try #require(try machO.swift.typeContextDescriptors.first { try $0.struct?.name(in: machO).contains("TestMixedConstraintsStruct") == true }?.struct)
        let genericContext = try #require(try descriptor.genericContext(in: machO))

        // 2 metadata + 3 PWT (A:Collection, B:Hashable, A.Element:Hashable)
        #expect(genericContext.header.numKeyArguments == 5)

        let indexer = SwiftInterfaceIndexer(in: machO)
        try indexer.addSubIndexer(SwiftInterfaceIndexer(in: #require(MachOImage(name: "libswiftCore"))))
        try await indexer.prepare()

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
        // `TestGenericStruct<A, B, C>` declares no `~Copyable` / `~Escapable`,
        // so every parameter retains every invertible protocol by default and
        // `Parameter.invertibleProtocols` must be `nil` on each — the typical
        // Swift case the doc comment promises.
        let machO = MachOImage.current()

        let descriptor = try #require(try machO.swift.typeContextDescriptors.first {
            try $0.struct?.name(in: machO).contains("TestGenericStruct") == true
        }?.struct)

        let indexer = SwiftInterfaceIndexer(in: machO)
        try await indexer.prepare()

        let specializer = GenericSpecializer(indexer: indexer)
        let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))

        #expect(request.parameters.count == 3)
        for parameter in request.parameters {
            #expect(parameter.invertibleProtocols == nil)
        }
    }

    // MARK: - Generic-candidate error message

    @Test func candidateErrorMessageMentionsSpecialized() async throws {
        // The thrown `candidateRequiresNestedSpecialization` carries a
        // human-readable description that must guide callers toward
        // `Argument.specialized(...)` and name the offending candidate.
        // Locking the description text via `errorDescription` keeps any
        // future rewording from silently breaking surfaced UI strings.
        let machO = MachOImage.current()

        let descriptor = try #require(try machO.swift.typeContextDescriptors.first {
            try $0.struct?.name(in: machO).contains("TestSingleProtocolStruct") == true
        }?.struct)

        let indexer = SwiftInterfaceIndexer(in: machO)
        try indexer.addSubIndexer(SwiftInterfaceIndexer(in: #require(MachOImage(name: "libswiftCore"))))
        try await indexer.prepare()

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
}

extension GenericSpecializationTests.TestInvertedCopyableStruct: Copyable where A: Copyable {}
