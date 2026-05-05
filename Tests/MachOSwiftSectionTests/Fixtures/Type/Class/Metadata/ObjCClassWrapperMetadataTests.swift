import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `ObjCClassWrapperMetadata`.
///
/// `ObjCClassWrapperMetadata` (kind 0x305) is the metadata kind the
/// Swift runtime allocates for plain ObjC classes — i.e. ObjC classes
/// referenced from Swift without a Swift-side class context descriptor.
/// `unsafeBitCast(NSObject.self, to: UnsafeRawPointer.self)` returns a
/// pointer to such metadata.
///
/// **Reader asymmetry:** the metadata source originates from the
/// in-process Swift runtime; `MachOFile`/`MachOImage` cannot reach it
/// (the wrapper is allocated lazily by the runtime, not serialised in
/// any Mach-O section).
///
/// Phase B3 introduced `ObjCClassWrappers.swift` to surface NSObject-
/// derived types in the fixture; the metadata of NSObject itself
/// (reached via `Foundation`'s in-process metadata) is the canonical
/// `ObjCClassWrapperMetadata` carrier.
@Suite
final class ObjCClassWrapperMetadataTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "ObjCClassWrapperMetadata"
    static var registeredTestMethodNames: Set<String> {
        ObjCClassWrapperMetadataBaseline.registeredTestMethodNames
    }

    @Test func layout() async throws {
        let kindRaw = try usingInProcessOnly { context in
            let metadata = try ObjCClassWrapperMetadata.resolve(
                at: InProcessMetadataPicker.foundationNSObjectWrapper,
                in: context
            )
            return metadata.layout.kind
        }
        // The runtime-allocated ObjCClassWrapperMetadata for NSObject
        // carries kind 0x305 (`MetadataKind.objcClassWrapper`).
        #expect(kindRaw == ObjCClassWrapperMetadataBaseline.foundationNSObject.kindRawValue)
    }

    @Test func offset() async throws {
        let resolvedOffset = try usingInProcessOnly { context in
            try ObjCClassWrapperMetadata.resolve(
                at: InProcessMetadataPicker.foundationNSObjectWrapper,
                in: context
            ).offset
        }
        // For InProcess resolution, `offset` is the bit-pattern of the
        // runtime metadata pointer itself.
        let expectedOffset = Int(bitPattern: InProcessMetadataPicker.foundationNSObjectWrapper)
        #expect(resolvedOffset == expectedOffset)
    }
}
