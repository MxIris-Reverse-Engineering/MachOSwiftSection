import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `MetatypeMetadata`.
///
/// `MetatypeMetadata` (kind `0x304`) is the runtime metadata kind for
/// metatype values (`T.Type`). It is materialised by the runtime when
/// reflection asks for a metatype's metadata; a static MachO walk of the
/// fixture never surfaces a live instance. We validate the structural
/// members against a synthetic memberwise instance.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
@Suite
final class MetatypeMetadataTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "MetatypeMetadata"
    static var registeredTestMethodNames: Set<String> {
        MetatypeMetadataBaseline.registeredTestMethodNames
    }

    @Test func offset() async throws {
        let metadata = MetatypeMetadata(
            layout: .init(kind: 0x304, instanceType: .init(address: 0)),
            offset: 0xCAFE
        )
        #expect(metadata.offset == 0xCAFE)
    }

    @Test func layout() async throws {
        let metadata = MetatypeMetadata(
            layout: .init(kind: 0x304, instanceType: .init(address: 0x42)),
            offset: 0
        )
        #expect(metadata.layout.kind == 0x304)
    }
}
