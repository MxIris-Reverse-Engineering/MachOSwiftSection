import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `GenericValueHeader`.
///
/// `GenericValueHeader` is the trailing-object header announcing the
/// integer-value-parameter array on a generic context whose
/// `GenericContextDescriptorFlags.hasValues` bit is set. The Suite reads
/// the header off the
/// `GenericValueFixtures.FixedSizeArray<let N: Int, T>` generic struct
/// (Phase B7) and asserts cross-reader equality on `offset` and
/// `layout.numValues`.
@Suite
final class GenericValueHeaderTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "GenericValueHeader"
    static var registeredTestMethodNames: Set<String> {
        GenericValueHeaderBaseline.registeredTestMethodNames
    }

    /// Helper: extract the `GenericValueHeader` from `FixedSizeArray`'s
    /// generic context against both readers.
    private func loadValueHeaders() throws -> (file: GenericValueHeader, image: GenericValueHeader) {
        let fileDescriptor = try BaselineFixturePicker.struct_FixedSizeArray(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.struct_FixedSizeArray(in: machOImage)
        let fileContext = try required(try fileDescriptor.typeGenericContext(in: machOFile))
        let imageContext = try required(try imageDescriptor.typeGenericContext(in: machOImage))
        let fileHeader = try required(fileContext.valueHeader)
        let imageHeader = try required(imageContext.valueHeader)
        return (file: fileHeader, image: imageHeader)
    }

    @Test func offset() async throws {
        let headers = try loadValueHeaders()
        let result = try acrossAllReaders(
            file: { headers.file.offset },
            image: { headers.image.offset }
        )
        #expect(result == GenericValueHeaderBaseline.fixedSizeArrayHeader.offset)
    }

    @Test func layout() async throws {
        let headers = try loadValueHeaders()
        let numValues = try acrossAllReaders(
            file: { headers.file.layout.numValues },
            image: { headers.image.layout.numValues }
        )
        #expect(numValues == GenericValueHeaderBaseline.fixedSizeArrayHeader.layoutNumValues)
    }
}
