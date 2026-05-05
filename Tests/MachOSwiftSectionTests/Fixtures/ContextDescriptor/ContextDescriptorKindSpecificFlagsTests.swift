import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `ContextDescriptorKindSpecificFlags`.
///
/// `ContextDescriptorKindSpecificFlags` is a sum type with three case-
/// extraction accessors (`protocolFlags`, `typeFlags`, `anonymousFlags`).
/// We sample off `Structs.StructTest`'s descriptor — a struct kind whose
/// flags resolve to the `.type(...)` case (so `typeFlags != nil`, the
/// other two `nil`). PublicMemberScanner does NOT emit MethodKey entries
/// for enum cases.
@Suite
final class ContextDescriptorKindSpecificFlagsTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "ContextDescriptorKindSpecificFlags"
    static var registeredTestMethodNames: Set<String> {
        ContextDescriptorKindSpecificFlagsBaseline.registeredTestMethodNames
    }

    /// Helper: extract the `ContextDescriptorKindSpecificFlags` from
    /// `Structs.StructTest`'s descriptor against both readers.
    private func loadStructTestKindSpecificFlags() throws -> (file: ContextDescriptorKindSpecificFlags, image: ContextDescriptorKindSpecificFlags) {
        let fileDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOImage)
        let fileFlags = try required(fileDescriptor.layout.flags.kindSpecificFlags)
        let imageFlags = try required(imageDescriptor.layout.flags.kindSpecificFlags)
        return (file: fileFlags, image: imageFlags)
    }

    @Test func protocolFlags() async throws {
        let flags = try loadStructTestKindSpecificFlags()
        let presence = try acrossAllReaders(
            file: { flags.file.protocolFlags != nil },
            image: { flags.image.protocolFlags != nil }
        )
        #expect(presence == ContextDescriptorKindSpecificFlagsBaseline.structTest.hasProtocolFlags)
    }

    @Test func typeFlags() async throws {
        let flags = try loadStructTestKindSpecificFlags()
        let presence = try acrossAllReaders(
            file: { flags.file.typeFlags != nil },
            image: { flags.image.typeFlags != nil }
        )
        #expect(presence == ContextDescriptorKindSpecificFlagsBaseline.structTest.hasTypeFlags)
    }

    @Test func anonymousFlags() async throws {
        let flags = try loadStructTestKindSpecificFlags()
        let presence = try acrossAllReaders(
            file: { flags.file.anonymousFlags != nil },
            image: { flags.image.anonymousFlags != nil }
        )
        #expect(presence == ContextDescriptorKindSpecificFlagsBaseline.structTest.hasAnonymousFlags)
    }
}
