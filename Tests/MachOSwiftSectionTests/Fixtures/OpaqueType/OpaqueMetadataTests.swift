import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftSectionTestingSupport
import SwiftSectionFixtureSupport

/// Fixture-based Suite for `OpaqueMetadata`.
///
/// `OpaqueMetadata` is a runtime-allocated metadata; no static carrier
/// is reachable from the SymbolTestsCore section walks. The Suite
/// asserts structural members against a synthetic memberwise instance.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
@Suite
@FixtureSuite
final class OpaqueMetadataTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
    @Test func offset() async throws {
        let metadata = OpaqueMetadata(
            layout: .init(kind: 0x300),
            offset: 0xCAFE
        )
        #expect(metadata.offset == 0xCAFE)
    }

    @Test func layout() async throws {
        let metadata = OpaqueMetadata(
            layout: .init(kind: 0x300),
            offset: 0
        )
        #expect(metadata.layout.kind == 0x300)
    }
}
