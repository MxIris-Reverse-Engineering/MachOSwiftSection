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

        let descriptor = try #require(try machO.swift.typeContextDescriptors.first { try $0.struct?.name(in: machO) == "TestGenericStruct" }?.struct)

        let genericContext = try #require(try descriptor.genericContext(in: machO))

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

        let associatedTypeWitnesses = try await indexer.resolveAssociatedTypeWitnesses(for: .struct(descriptor), substituting: [
            "A": AMetadata,
            "B": BMetadata,
            "C": CMetadata,
        ], in: machO)

        let metadataAccessorFunction = try #require(try descriptor.asPointerWrapper(in: machO).metadataAccessorFunction())
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

extension OptionSet {
    func removing(_ current: Self.Element) -> Self {
        var copy = self
        copy.remove(current)
        return copy
    }
}
