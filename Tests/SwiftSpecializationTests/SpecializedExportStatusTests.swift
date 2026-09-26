@_spi(Support) @testable import SwiftSpecialization
@_spi(Support) @testable import SwiftDeclaration
@_spi(Support) @testable import SwiftIndexing
import Foundation
import Testing
import MachOKit
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// A specialized definition shares its generic definition's descriptor, so it
/// must carry the same `exportStatus` (evolution proposal
/// `exported-declaration-flag`) — resolving it again would only re-derive the
/// same verdict from the same symbol, and constructing it with the
/// no-verdict default would silently make every specialization unjudgeable.
@Suite(.serialized)
struct SpecializedExportStatusTests: GenericSpecializationTestingEnvironment {
    @Test func specializedDefinitionInheritsTheGenericDefinitionsStatus() async throws {
        let resolvedIndexer = try await indexer
        let baseDefinition = try #require(
            resolvedIndexer.allTypeDefinitions.first { $0.key.name.contains("TestUnconstrainedStruct") }?.value,
            "expected the indexer to hold TestUnconstrainedStruct"
        )
        let specializer = GenericSpecializer(indexer: resolvedIndexer)
        let request = try specializer.makeRequest(for: baseDefinition.typeContextDescriptorWrapper)
        let specializationResult = try specializer.specialize(request, with: ["A": .metatype(Int.self)])

        let specialized = try await baseDefinition.specialize(with: specializationResult, in: machO)

        #expect(specialized.isSpecialized)
        #expect(specialized.exportStatus == baseDefinition.exportStatus)
    }
}
