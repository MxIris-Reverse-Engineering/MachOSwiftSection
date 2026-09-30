import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `GenericPackShapeHeader`.
///
/// The Suite reads the pack-shape header off the
/// `ParameterPackRequirementTest<each Element>` generic struct's
/// `typeGenericContext.typePackHeader`.
@Suite
final class GenericPackShapeHeaderTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "GenericPackShapeHeader"
    static var registeredTestMethodNames: Set<String> {
        GenericPackShapeHeaderBaseline.registeredTestMethodNames
    }

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
        let result = try acrossAllReaders(file: { headers.file.offset }, image: { headers.image.offset })
        #expect(result == GenericPackShapeHeaderBaseline.parameterPackHeader.offset)
    }

    @Test func layout() async throws {
        let headers = try loadHeaders()

        let numPacks = try acrossAllReaders(
            file: { headers.file.layout.numPacks },
            image: { headers.image.layout.numPacks }
        )
        let numShapeClasses = try acrossAllReaders(
            file: { headers.file.layout.numShapeClasses },
            image: { headers.image.layout.numShapeClasses }
        )

        #expect(numPacks == GenericPackShapeHeaderBaseline.parameterPackHeader.layoutNumPacks)
        #expect(numShapeClasses == GenericPackShapeHeaderBaseline.parameterPackHeader.layoutNumShapeClasses)
    }
}
