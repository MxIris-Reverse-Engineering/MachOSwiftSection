import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `ForeignClassMetadata`.
///
/// `ForeignClassMetadata` (kind 0x203) is the metadata kind the Swift
/// compiler emits for CoreFoundation foreign classes (CFString,
/// CFArray, CFDictionary, etc.) imported into Swift. The metadata
/// itself lives in CoreFoundation; Swift uses
/// `unsafeBitCast(CFString.self, to: UnsafeRawPointer.self)` to obtain
/// the metadata pointer at runtime.
///
/// **Reader asymmetry:** the metadata source originates from
/// CoreFoundation, not the SymbolTestsCore Mach-O. `MachOFile` /
/// `MachOImage` cannot reach it through SymbolTestsCore's section
/// walks. The Suite therefore uses `usingInProcessOnly` and asserts
/// against runtime-resolved metadata.
///
/// Phase B6 introduced `ForeignTypes.swift` to surface CFString /
/// CFArray references in the fixture (so the bridging type usage is
/// documented), and added the `coreFoundationCFString` picker for the
/// canonical InProcess carrier.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
@Suite
final class ForeignClassMetadataTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "ForeignClassMetadata"
    static var registeredTestMethodNames: Set<String> {
        ForeignClassMetadataBaseline.registeredTestMethodNames
    }

    @Test func layout() async throws {
        let kindRaw = try usingInProcessOnly { context in
            let metadata = try ForeignClassMetadata.resolve(
                at: InProcessMetadataPicker.coreFoundationCFString,
                in: context
            )
            return metadata.layout.kind
        }
        // The runtime-allocated ForeignClassMetadata for CFString
        // carries kind 0x203 (`MetadataKind.foreignClass`).
        #expect(kindRaw == ForeignClassMetadataBaseline.coreFoundationCFString.kindRawValue)
    }

    @Test func offset() async throws {
        let resolvedOffset = try usingInProcessOnly { context in
            try ForeignClassMetadata.resolve(
                at: InProcessMetadataPicker.coreFoundationCFString,
                in: context
            ).offset
        }
        // For InProcess resolution, `offset` is the bit-pattern of the
        // runtime metadata pointer itself.
        let expectedOffset = Int(bitPattern: InProcessMetadataPicker.coreFoundationCFString)
        #expect(resolvedOffset == expectedOffset)
    }

    /// `classDescriptor(in:)` resolves the `descriptor` field of the
    /// foreign class metadata to a `ClassDescriptor`. CFString's
    /// descriptor lives in CoreFoundation. We assert that resolution
    /// succeeds and returns a non-zero descriptor flags word — the
    /// concrete flags are an ABI of CoreFoundation, not of this
    /// codebase, so we pin only "successfully resolves to a non-zero
    /// flags descriptor" rather than a literal flags value.
    @Test func classDescriptor() async throws {
        let flagsRaw = try usingInProcessOnly { context in
            let metadata = try ForeignClassMetadata.resolve(
                at: InProcessMetadataPicker.coreFoundationCFString,
                in: context
            )
            let descriptor = try metadata.classDescriptor(in: context)
            return descriptor.layout.flags.rawValue
        }
        // CFString's descriptor flags are a CoreFoundation-side ABI
        // detail; we just verify a real descriptor was reached.
        #expect(flagsRaw != 0)
    }
}
