import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `GenericValueDescriptor`.
///
/// `GenericValueDescriptor` is the per-value record carried in the
/// trailing `values` array of a generic context whose
/// `GenericContextDescriptorFlags.hasValues` bit is set. The Suite reads
/// the first value descriptor off the
/// `GenericValueFixtures.FixedSizeArray<let N: Int, T>` generic struct
/// (Phase B7) and asserts cross-reader equality on `offset`,
/// `layout.type`, and `type.rawValue`.
@Suite
final class GenericValueDescriptorTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "GenericValueDescriptor"
    static var registeredTestMethodNames: Set<String> {
        GenericValueDescriptorBaseline.registeredTestMethodNames
    }

    /// Helper: extract the first `GenericValueDescriptor` from
    /// `FixedSizeArray`'s generic context against both readers.
    private func loadFirstValue() throws -> (file: GenericValueDescriptor, image: GenericValueDescriptor) {
        let fileDescriptor = try BaselineFixturePicker.struct_FixedSizeArray(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.struct_FixedSizeArray(in: machOImage)
        let fileContext = try required(try fileDescriptor.typeGenericContext(in: machOFile))
        let imageContext = try required(try imageDescriptor.typeGenericContext(in: machOImage))
        let fileValue = try required(fileContext.values.first)
        let imageValue = try required(imageContext.values.first)
        return (file: fileValue, image: imageValue)
    }

    @Test func offset() async throws {
        let values = try loadFirstValue()
        let result = try acrossAllReaders(
            file: { values.file.offset },
            image: { values.image.offset }
        )
        #expect(result == GenericValueDescriptorBaseline.fixedSizeArrayFirstValue.offset)
    }

    @Test func layout() async throws {
        let values = try loadFirstValue()
        let layoutType = try acrossAllReaders(
            file: { values.file.layout.type },
            image: { values.image.layout.type }
        )
        #expect(layoutType == GenericValueDescriptorBaseline.fixedSizeArrayFirstValue.layoutType)
    }

    @Test func type() async throws {
        let values = try loadFirstValue()
        let typeRaw = try acrossAllReaders(
            file: { values.file.type.rawValue },
            image: { values.image.type.rawValue }
        )
        #expect(typeRaw == GenericValueDescriptorBaseline.fixedSizeArrayFirstValue.typeRawValue)
    }
}
