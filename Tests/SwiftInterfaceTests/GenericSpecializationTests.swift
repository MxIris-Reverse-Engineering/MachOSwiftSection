import Foundation
import Testing
import MachOKit
import Dependencies
@_spi(Internals) import MachOSymbols
@_spi(Internals) import MachOCaches
@_spi(Support) @testable import SwiftInterface
@testable import MachOSwiftSection
@testable import MachOTestingSupport
@testable import SwiftDump
@testable import SwiftInspection
@testable import Demangling
import OrderedCollections

struct TestGenericStruct<A, B, C> where A: Collection, B: Equatable, C: Hashable, A.Element: Hashable, A.Element: Decodable, A.Element: Encodable {
    let a: A
    let b: B
    let c: C
}

final class GenericSpecializationTests: MachOImageTests, @unchecked Sendable {
    override class var imageName: MachOImageName { .SwiftUICore }

    @Test func main() async throws {
        let machO = MachOImage.current()

        let indexer = SwiftInterfaceIndexer(in: machO)

        try indexer.addSubIndexer(SwiftInterfaceIndexer(in: #require(MachOImage(name: "Foundation"))))
        try indexer.addSubIndexer(SwiftInterfaceIndexer(in: #require(MachOImage(name: "libswiftCore"))))

        try await indexer.prepare()

        let descriptor = try #require(try machO.swift.typeContextDescriptors.first { try $0.struct?.name(in: machO) == "TestGenericStruct" }?.struct?.asPointerWrapper(in: machO))

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
}

// MARK: - GenericSpecializer API Tests

@Suite
struct GenericSpecializerAPITests {
    @Test func makeRequest() throws {
        let machO = MachOImage.current()

        let descriptor = try #require(try machO.swift.typeContextDescriptors.first { try $0.struct?.name(in: machO) == "TestGenericStruct" }?.struct)

        let specializer = GenericSpecializer(
            machO: machO,
            conformanceProvider: EmptyConformanceProvider()
        )
        let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))

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

        let descriptor = try #require(try machO.swift.typeContextDescriptors.first { try $0.struct?.name(in: machO) == "TestGenericStruct" }?.struct)

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

        let descriptor = try #require(try machO.swift.typeContextDescriptors.first { try $0.struct?.name(in: machO) == "TestGenericStruct" }?.struct)

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
}
