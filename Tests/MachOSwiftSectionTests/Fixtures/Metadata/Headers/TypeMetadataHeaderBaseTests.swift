import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftSectionTestingSupport
import SwiftSectionFixtureSupport

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
@FixtureSuite
final class TypeMetadataHeaderBaseTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
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
