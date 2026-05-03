import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `ExtendedExistentialTypeMetadata`.
///
/// `ExtendedExistentialTypeMetadata` carries the metadata for constrained
/// existentials (e.g. `any P<Int>`, `any P where P.Element == Int`). The
/// runtime allocates these on demand via `swift_getExtendedExistentialType`
/// and there's no static section emission — no live carrier is reachable
/// from the SymbolTestsCore section walks. The Suite asserts the type's
/// structural members behave correctly against a synthetic memberwise
/// instance.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
@Suite
final class ExtendedExistentialTypeMetadataTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "ExtendedExistentialTypeMetadata"
    static var registeredTestMethodNames: Set<String> {
        ExtendedExistentialTypeMetadataBaseline.registeredTestMethodNames
    }

    @Test func offset() async throws {
        let metadata = ExtendedExistentialTypeMetadata(
            layout: .init(kind: 0x307, shape: .init(address: 0x1000)),
            offset: 0xCAFE
        )
        #expect(metadata.offset == 0xCAFE)
    }

    @Test func layout() async throws {
        let metadata = ExtendedExistentialTypeMetadata(
            layout: .init(kind: 0x307, shape: .init(address: 0x2000)),
            offset: 0
        )
        #expect(metadata.layout.kind == 0x307)
        #expect(metadata.layout.shape.address == 0x2000)
    }
}
