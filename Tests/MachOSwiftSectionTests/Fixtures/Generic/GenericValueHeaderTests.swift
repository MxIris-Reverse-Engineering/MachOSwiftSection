import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftSectionTestingSupport
import SwiftSectionFixtureSupport

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
@FixtureSuite
final class GenericValueHeaderTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
    /// Helper: extract the `GenericValueHeader` from `FixedSizeArray`'s
    /// generic context against both readers.
    private func loadValueHeaders() throws -> (file: GenericValueHeader, image: GenericValueHeader) {
        let fileDescriptor = try BaselineFixturePicker.struct_FixedSizeArray(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.struct_FixedSizeArray(in: machOImage)
        let fileGenericContext = try required(try fileDescriptor.typeGenericContext(in: fileContext))
        let imageGenericContext = try required(try imageDescriptor.typeGenericContext(in: imageContext))
        let fileHeader = try required(fileGenericContext.valueHeader)
        let imageHeader = try required(imageGenericContext.valueHeader)
        return (file: fileHeader, image: imageHeader)
    }

    @Test func offset() async throws {
        let headers = try loadValueHeaders()
        let result = try acrossAllReaders(headers.file, headers.image) { $0.offset }
        #expect(result == GenericValueHeaderBaseline.fixedSizeArrayHeader.offset)
    }

    @Test func layout() async throws {
        let headers = try loadValueHeaders()
        let numValues = try acrossAllReaders(headers.file, headers.image) { $0.layout.numValues }
        #expect(numValues == GenericValueHeaderBaseline.fixedSizeArrayHeader.layoutNumValues)
    }
}
