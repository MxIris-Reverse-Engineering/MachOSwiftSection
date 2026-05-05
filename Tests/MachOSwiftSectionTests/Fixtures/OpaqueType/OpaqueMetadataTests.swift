import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `OpaqueMetadata`.
///
/// `OpaqueMetadata` is a runtime-allocated metadata; no static carrier
/// is reachable from the SymbolTestsCore section walks. The Suite
/// asserts structural members against a synthetic memberwise instance.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
@Suite
final class OpaqueMetadataTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "OpaqueMetadata"
    static var registeredTestMethodNames: Set<String> {
        OpaqueMetadataBaseline.registeredTestMethodNames
    }

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
