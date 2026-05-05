import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `ContextDescriptorKind`.
///
/// `ContextDescriptorKind` is a `UInt8`-backed enum. PublicMemberScanner does
/// NOT emit MethodKey entries for enum cases (only for `func`/`var`/`init`/
/// `subscript`), so we only register `description` and `mangledType`.
///
/// The kind value is sampled off `Structs.StructTest`'s descriptor — a
/// `.struct` kind whose `description == "struct"` and `mangledType == "V"`.
@Suite
final class ContextDescriptorKindTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "ContextDescriptorKind"
    static var registeredTestMethodNames: Set<String> {
        ContextDescriptorKindBaseline.registeredTestMethodNames
    }

    /// Helper: extract the `ContextDescriptorKind` from
    /// `Structs.StructTest`'s descriptor against both readers.
    private func loadStructTestKinds() throws -> (file: ContextDescriptorKind, image: ContextDescriptorKind) {
        let fileDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOImage)
        return (file: fileDescriptor.layout.flags.kind, image: imageDescriptor.layout.flags.kind)
    }

    @Test func description() async throws {
        let kinds = try loadStructTestKinds()
        let result = try acrossAllReaders(
            file: { kinds.file.description },
            image: { kinds.image.description }
        )
        #expect(result == ContextDescriptorKindBaseline.structTest.description)
    }

    @Test func mangledType() async throws {
        let kinds = try loadStructTestKinds()
        let result = try acrossAllReaders(
            file: { kinds.file.mangledType },
            image: { kinds.image.mangledType }
        )
        #expect(result == ContextDescriptorKindBaseline.structTest.mangledType)
    }
}
