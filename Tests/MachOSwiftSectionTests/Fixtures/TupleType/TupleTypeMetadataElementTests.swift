import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `TupleTypeMetadata.Element`.
///
/// `Element` is the nested struct describing a single tuple element
/// (its metadata pointer plus byte offset). `PublicMemberScanner`
/// keys nested types by their inner struct name, so the
/// `testedTypeName` here is `"Element"`.
@Suite
final class TupleTypeMetadataElementTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "Element"
    static var registeredTestMethodNames: Set<String> {
        TupleTypeMetadataElementBaseline.registeredTestMethodNames
    }

    @Test func type() async throws {
        let element = TupleTypeMetadata.Element(
            type: .init(address: TupleTypeMetadataElementBaseline.typeAddress),
            offset: TupleTypeMetadataElementBaseline.elementOffset
        )
        #expect(element.type.address == TupleTypeMetadataElementBaseline.typeAddress)
    }

    @Test func offset() async throws {
        let element = TupleTypeMetadata.Element(
            type: .init(address: TupleTypeMetadataElementBaseline.typeAddress),
            offset: TupleTypeMetadataElementBaseline.elementOffset
        )
        #expect(element.offset == TupleTypeMetadataElementBaseline.elementOffset)
    }
}
