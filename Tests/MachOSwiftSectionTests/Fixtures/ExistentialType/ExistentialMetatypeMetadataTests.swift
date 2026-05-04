import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `ExistentialMetatypeMetadata`.
///
/// Phase C3: real InProcess test against `Any.Type.self` (the
/// runtime-allocated `ExistentialMetatypeMetadata` whose `instanceType`
/// points at `Any.self`). We resolve via
/// `InProcessMetadataPicker.stdlibAnyMetatype` and assert the wrapper's
/// observable `layout` (kind + instanceType pointer + flags) and `offset`
/// (runtime metadata pointer bit-pattern) against ABI literals pinned in
/// the regenerated baseline.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
@Suite
final class ExistentialMetatypeMetadataTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "ExistentialMetatypeMetadata"
    static var registeredTestMethodNames: Set<String> {
        ExistentialMetatypeMetadataBaseline.registeredTestMethodNames
    }

    @Test func layout() async throws {
        let resolved = try usingInProcessOnly { context in
            try ExistentialMetatypeMetadata.resolve(at: InProcessMetadataPicker.stdlibAnyMetatype, in: context)
        }
        // The runtime existential-metatype metadata's layout: kind decodes
        // to `MetadataKind.existentialMetatype` (0x306); `instanceType`
        // points to `Any.self`'s metadata; flags raw value matches
        // `Any.self`'s flags (mirrored into the metatype layout).
        #expect(resolved.kind.rawValue == ExistentialMetatypeMetadataBaseline.stdlibAnyMetatype.kindRawValue)
        let expectedInstanceTypeAddress = UInt64(UInt(bitPattern: InProcessMetadataPicker.stdlibAnyExistential))
        #expect(resolved.layout.instanceType.address == expectedInstanceTypeAddress)
        #expect(resolved.layout.flags.rawValue == ExistentialMetatypeMetadataBaseline.stdlibAnyMetatype.flagsRawValue)
    }

    @Test func offset() async throws {
        let resolvedOffset = try usingInProcessOnly { context in
            try ExistentialMetatypeMetadata.resolve(at: InProcessMetadataPicker.stdlibAnyMetatype, in: context).offset
        }
        // For InProcess resolution, `offset` is the bit-pattern of the
        // runtime metadata pointer itself.
        let expectedOffset = Int(bitPattern: InProcessMetadataPicker.stdlibAnyMetatype)
        #expect(resolvedOffset == expectedOffset)
    }
}
