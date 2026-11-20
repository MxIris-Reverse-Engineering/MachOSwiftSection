import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftSectionTestingSupport
import SwiftSectionFixtureSupport

/// Fixture-based Suite for `TypeMetadataLayoutPrefix`.
///
/// `TypeMetadataLayoutPrefix` is the single-`layoutString`-pointer prefix
/// preceding every type metadata header. The Suite asserts the structural
/// members behave correctly against a synthetic memberwise instance — live
/// `layoutString` pointer values are reachable through MachOImage but
/// aren't reader-stable.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
@Suite
@FixtureSuite
final class TypeMetadataLayoutPrefixTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
    @Test func offset() async throws {
        let prefix = TypeMetadataLayoutPrefix(
            layout: .init(layoutString: .init(address: 0)),
            offset: 0xFEED
        )
        #expect(prefix.offset == 0xFEED)
    }

    @Test func layout() async throws {
        let prefix = TypeMetadataLayoutPrefix(
            layout: .init(layoutString: .init(address: 0x80)),
            offset: 0
        )
        #expect(prefix.layout.layoutString.address == 0x80)
    }
}
