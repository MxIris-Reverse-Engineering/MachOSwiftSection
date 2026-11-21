import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftSectionTestingSupport
import SwiftSectionFixtureSupport

/// Fixture-based Suite for `GenericPackShapeHeader`.
///
/// The Suite reads the pack-shape header off the
/// `ParameterPackRequirementTest<each Element>` generic struct's
/// `typeGenericContext.typePackHeader`.
@Suite
@FixtureSuite
final class GenericPackShapeHeaderTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
    private func loadHeaders() throws -> (file: GenericPackShapeHeader, image: GenericPackShapeHeader) {
        let fileDescriptor = try BaselineFixturePicker.struct_ParameterPackRequirementTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.struct_ParameterPackRequirementTest(in: machOImage)
        let fileGenericContext = try required(try fileDescriptor.typeGenericContext(in: fileContext))
        let imageGenericContext = try required(try imageDescriptor.typeGenericContext(in: imageContext))
        let fileHeader = try required(fileGenericContext.typePackHeader)
        let imageHeader = try required(imageGenericContext.typePackHeader)
        return (file: fileHeader, image: imageHeader)
    }

    @Test func offset() async throws {
        let headers = try loadHeaders()
        let result = try acrossAllReaders(headers.file, headers.image) { $0.offset }
        #expect(result == GenericPackShapeHeaderBaseline.parameterPackHeader.offset)
    }

    @Test func layout() async throws {
        let headers = try loadHeaders()

        let numPacks = try acrossAllReaders(headers.file, headers.image) { $0.layout.numPacks }
        let numShapeClasses = try acrossAllReaders(headers.file, headers.image) { $0.layout.numShapeClasses }

        #expect(numPacks == GenericPackShapeHeaderBaseline.parameterPackHeader.layoutNumPacks)
        #expect(numShapeClasses == GenericPackShapeHeaderBaseline.parameterPackHeader.layoutNumShapeClasses)
    }
}
