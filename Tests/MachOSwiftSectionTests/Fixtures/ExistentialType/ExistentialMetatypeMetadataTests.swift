import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `ExistentialMetatypeMetadata`.
///
/// `ExistentialMetatypeMetadata` is the runtime metadata for a
/// `(any P).Type` value — the metatype of an opaque/class-bound
/// existential. Live carriers require materialising the metatype
/// through Swift's runtime, which is reachable only from a loaded
/// process and not from the static section walks. The Suite asserts
/// the type's structural members behave correctly against a synthetic
/// memberwise instance.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
@Suite
final class ExistentialMetatypeMetadataTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "ExistentialMetatypeMetadata"
    static var registeredTestMethodNames: Set<String> {
        ExistentialMetatypeMetadataBaseline.registeredTestMethodNames
    }

    @Test func offset() async throws {
        let metadata = ExistentialMetatypeMetadata(
            layout: .init(
                kind: 0x306,
                instanceType: .init(address: 0x1000),
                flags: .init(rawValue: 0x0000_0001)
            ),
            offset: 0xCAFE
        )
        #expect(metadata.offset == 0xCAFE)
    }

    @Test func layout() async throws {
        let metadata = ExistentialMetatypeMetadata(
            layout: .init(
                kind: 0x306,
                instanceType: .init(address: 0x2000),
                flags: .init(rawValue: 0x0000_0003)
            ),
            offset: 0
        )
        #expect(metadata.layout.kind == 0x306)
        #expect(metadata.layout.flags.numberOfWitnessTables == 0x3)
    }
}
