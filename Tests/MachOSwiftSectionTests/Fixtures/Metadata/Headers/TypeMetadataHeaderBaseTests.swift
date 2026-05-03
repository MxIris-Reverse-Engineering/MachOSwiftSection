import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `TypeMetadataHeaderBase`.
///
/// `TypeMetadataHeaderBase` is the minimal value-witness-pointer prefix
/// shared by every metadata header hierarchy. The Suite asserts the
/// structural members behave correctly against a synthetic memberwise
/// instance — live `valueWitnesses` pointer values are reachable through
/// MachOImage but aren't reader-stable.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
@Suite
final class TypeMetadataHeaderBaseTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "TypeMetadataHeaderBase"
    static var registeredTestMethodNames: Set<String> {
        TypeMetadataHeaderBaseBaseline.registeredTestMethodNames
    }

    @Test func offset() async throws {
        let base = TypeMetadataHeaderBase(
            layout: .init(valueWitnesses: .init(address: 0)),
            offset: 0xBEEF
        )
        #expect(base.offset == 0xBEEF)
    }

    @Test func layout() async throws {
        let base = TypeMetadataHeaderBase(
            layout: .init(valueWitnesses: .init(address: 0xCAFE)),
            offset: 0
        )
        #expect(base.layout.valueWitnesses.address == 0xCAFE)
    }
}
