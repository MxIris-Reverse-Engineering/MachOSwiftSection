import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `StructDescriptor`.
///
/// Members directly declared in `StructDescriptor.swift` (excluding the
/// `@MemberwiseInit`-style synthesized initializer) are `offset` and `layout`.
/// Protocol-extension methods that surface here at compile-time —
/// `name(in:)`, `fields(in:)`, etc. — live on
/// `TypeContextDescriptorProtocol` and are exercised in Task 9 under
/// `TypeContextDescriptorProtocolTests`.
@Suite
final class StructDescriptorTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "StructDescriptor"
    static var registeredTestMethodNames: Set<String> {
        StructDescriptorBaseline.registeredTestMethodNames
    }

    /// `StructDescriptor.offset` is the file/image position of the descriptor
    /// record. Cross-reader equality holds: both `MachOFile` and `MachOImage`
    /// resolve the same offset (in-process pointer arithmetic relative to the
    /// MachO base also produces the same offset value).
    @Test func offset() async throws {
        let fileSubject = try BaselineFixturePicker.struct_StructTest(in: machOFile)
        let imageSubject = try BaselineFixturePicker.struct_StructTest(in: machOImage)

        let result = try acrossAllReaders(
            file: { fileSubject.offset },
            image: { imageSubject.offset }
        )

        #expect(result == StructDescriptorBaseline.structTest.offset)
    }

    /// `StructDescriptor.layout` is the in-memory record. Compare individual
    /// `Layout` fields (the whole struct contains relative pointer values
    /// which encode displacements to other parts of the binary, so direct
    /// equality is meaningful here for `numFields` / `fieldOffsetVector` /
    /// `flags`).
    @Test func layout() async throws {
        let fileSubject = try BaselineFixturePicker.struct_StructTest(in: machOFile)
        let imageSubject = try BaselineFixturePicker.struct_StructTest(in: machOImage)

        // Cross-reader equality on the metadata-relevant scalar fields.
        let numFields = try acrossAllReaders(
            file: { fileSubject.layout.numFields },
            image: { imageSubject.layout.numFields }
        )
        let fieldOffsetVector = try acrossAllReaders(
            file: { fileSubject.layout.fieldOffsetVector },
            image: { imageSubject.layout.fieldOffsetVector }
        )
        let flagsRaw = try acrossAllReaders(
            file: { fileSubject.layout.flags.rawValue },
            image: { imageSubject.layout.flags.rawValue }
        )

        // Baseline literal equality.
        #expect(Int(numFields) == StructDescriptorBaseline.structTest.layoutNumFields)
        #expect(Int(fieldOffsetVector) == StructDescriptorBaseline.structTest.layoutFieldOffsetVector)
        #expect(flagsRaw == StructDescriptorBaseline.structTest.layoutFlagsRawValue)
    }
}
