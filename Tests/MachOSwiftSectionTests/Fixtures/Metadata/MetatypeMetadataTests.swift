import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `MetatypeMetadata`.
///
/// Phase C2: real InProcess test against `type(of: Int.self)` (the
/// runtime-allocated `MetatypeMetadata` whose `instanceType` is
/// `Int.self`). We resolve via `InProcessMetadataPicker.stdlibIntMetatype`
/// and assert the wrapper's observable `layout` (kind + instanceType
/// pointer) and `offset` (runtime metadata pointer bit-pattern) against
/// ABI literals pinned in the regenerated baseline.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
@Suite
final class MetatypeMetadataTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "MetatypeMetadata"
    static var registeredTestMethodNames: Set<String> {
        MetatypeMetadataBaseline.registeredTestMethodNames
    }

    @Test func layout() async throws {
        let resolved = try usingInProcessOnly { context in
            try MetatypeMetadata.resolve(at: InProcessMetadataPicker.stdlibIntMetatype, in: context)
        }
        // The runtime-allocated metatype metadata's layout.kind decodes
        // to MetadataKind.metatype (0x304); its layout.instanceType
        // points to `Int.self`.
        #expect(resolved.kind.rawValue == MetatypeMetadataBaseline.stdlibIntMetatype.kindRawValue)
        let expectedInstanceTypeAddress = UInt64(UInt(bitPattern: unsafeBitCast(Int.self, to: UnsafeRawPointer.self)))
        #expect(resolved.layout.instanceType.address == expectedInstanceTypeAddress)
    }

    @Test func offset() async throws {
        let resolvedOffset = try usingInProcessOnly { context in
            try MetatypeMetadata.resolve(at: InProcessMetadataPicker.stdlibIntMetatype, in: context).offset
        }
        // For InProcess resolution, `offset` is the bit-pattern of the
        // runtime metadata pointer itself (since the in-process
        // ReadingContext stores addresses as offsets verbatim).
        let expectedOffset = Int(bitPattern: InProcessMetadataPicker.stdlibIntMetatype)
        #expect(resolvedOffset == expectedOffset)
    }
}
