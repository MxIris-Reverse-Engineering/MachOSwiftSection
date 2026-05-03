import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `GenericBoxHeapMetadata`.
///
/// Runtime-allocated metadata; no static carrier is reachable from
/// SymbolTestsCore. The Suite asserts structural members behave
/// against a synthetic memberwise instance.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
@Suite
final class GenericBoxHeapMetadataTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "GenericBoxHeapMetadata"
    static var registeredTestMethodNames: Set<String> {
        GenericBoxHeapMetadataBaseline.registeredTestMethodNames
    }

    @Test func offset() async throws {
        let metadata = GenericBoxHeapMetadata(
            layout: .init(
                kind: 0x500,
                offset: 0x10,
                boxedType: .init(address: 0x1000)
            ),
            offset: 0xCAFE
        )
        #expect(metadata.offset == 0xCAFE)
    }

    @Test func layout() async throws {
        let metadata = GenericBoxHeapMetadata(
            layout: .init(
                kind: 0x500,
                offset: 0x20,
                boxedType: .init(address: 0x2000)
            ),
            offset: 0
        )
        #expect(metadata.layout.kind == 0x500)
        #expect(metadata.layout.offset == 0x20)
        #expect(metadata.layout.boxedType.address == 0x2000)
    }
}
