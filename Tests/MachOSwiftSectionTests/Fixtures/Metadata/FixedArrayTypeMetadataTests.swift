import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `FixedArrayTypeMetadata`.
///
/// `FixedArrayTypeMetadata` (kind `0x308`) is the runtime metadata for the
/// experimental `FixedArray<N, T>` Swift built-in. The `SymbolTestsCore`
/// fixture does not declare any such types, so no live instance is reachable
/// through the static section walks — the Suite asserts the type's
/// structural members behave correctly against a synthetic memberwise
/// instance.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
@Suite
final class FixedArrayTypeMetadataTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "FixedArrayTypeMetadata"
    static var registeredTestMethodNames: Set<String> {
        FixedArrayTypeMetadataBaseline.registeredTestMethodNames
    }

    @Test func offset() async throws {
        let metadata = FixedArrayTypeMetadata(
            layout: .init(kind: 0x308, count: 0, element: .init(address: 0)),
            offset: 0xCAFE
        )
        #expect(metadata.offset == 0xCAFE)
    }

    @Test func layout() async throws {
        let metadata = FixedArrayTypeMetadata(
            layout: .init(kind: 0x308, count: 4, element: .init(address: 0x42)),
            offset: 0
        )
        #expect(metadata.layout.kind == 0x308)
        #expect(metadata.layout.count == 4)
    }
}
