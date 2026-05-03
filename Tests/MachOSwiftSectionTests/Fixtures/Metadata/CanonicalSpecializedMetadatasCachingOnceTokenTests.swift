import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `CanonicalSpecializedMetadatasCachingOnceToken`.
///
/// Trailing-objects payload appended to descriptors with the
/// `hasCanonicalMetadataPrespecializations` bit. The `SymbolTestsCore`
/// fixture declares no prespecializations, so no live token is materialised;
/// the Suite asserts the type's structural members behave correctly against
/// a synthetic memberwise instance.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
@Suite
final class CanonicalSpecializedMetadatasCachingOnceTokenTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "CanonicalSpecializedMetadatasCachingOnceToken"
    static var registeredTestMethodNames: Set<String> {
        CanonicalSpecializedMetadatasCachingOnceTokenBaseline.registeredTestMethodNames
    }

    @Test func offset() async throws {
        let token = CanonicalSpecializedMetadatasCachingOnceToken(
            layout: .init(token: .init(relativeOffset: 0)),
            offset: 0xCAFE
        )
        #expect(token.offset == 0xCAFE)
    }

    @Test func layout() async throws {
        let token = CanonicalSpecializedMetadatasCachingOnceToken(
            layout: .init(token: .init(relativeOffset: 0x42)),
            offset: 0
        )
        #expect(token.layout.token.relativeOffset == 0x42)
    }
}
