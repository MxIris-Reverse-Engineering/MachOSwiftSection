import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `GenericPackShapeDescriptor`.
///
/// The Suite reads the first pack-shape descriptor off the
/// `ParameterPackRequirementTest<each Element>` generic struct's
/// `typeGenericContext.typePacks` array.
@Suite
final class GenericPackShapeDescriptorTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "GenericPackShapeDescriptor"
    static var registeredTestMethodNames: Set<String> {
        GenericPackShapeDescriptorBaseline.registeredTestMethodNames
    }

    private func loadFirstPack() throws -> (file: GenericPackShapeDescriptor, image: GenericPackShapeDescriptor) {
        let fileDescriptor = try BaselineFixturePicker.struct_ParameterPackRequirementTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.struct_ParameterPackRequirementTest(in: machOImage)
        let fileContext = try required(try fileDescriptor.typeGenericContext(in: machOFile))
        let imageContext = try required(try imageDescriptor.typeGenericContext(in: machOImage))
        let filePack = try required(fileContext.typePacks.first)
        let imagePack = try required(imageContext.typePacks.first)
        return (file: filePack, image: imagePack)
    }

    @Test func offset() async throws {
        let packs = try loadFirstPack()
        let result = try acrossAllReaders(file: { packs.file.offset }, image: { packs.image.offset })
        #expect(result == GenericPackShapeDescriptorBaseline.parameterPackFirstShape.offset)
    }

    @Test func layout() async throws {
        let packs = try loadFirstPack()

        let kindRaw = try acrossAllReaders(
            file: { packs.file.layout.kind },
            image: { packs.image.layout.kind }
        )
        let index = try acrossAllReaders(
            file: { packs.file.layout.index },
            image: { packs.image.layout.index }
        )
        let shapeClass = try acrossAllReaders(
            file: { packs.file.layout.shapeClass },
            image: { packs.image.layout.shapeClass }
        )
        let unused = try acrossAllReaders(
            file: { packs.file.layout.unused },
            image: { packs.image.layout.unused }
        )

        #expect(kindRaw == GenericPackShapeDescriptorBaseline.parameterPackFirstShape.layoutKind)
        #expect(index == GenericPackShapeDescriptorBaseline.parameterPackFirstShape.layoutIndex)
        #expect(shapeClass == GenericPackShapeDescriptorBaseline.parameterPackFirstShape.layoutShapeClass)
        #expect(unused == GenericPackShapeDescriptorBaseline.parameterPackFirstShape.layoutUnused)
    }

    @Test func kind() async throws {
        let packs = try loadFirstPack()
        let result = try acrossAllReaders(
            file: { packs.file.kind.rawValue },
            image: { packs.image.kind.rawValue }
        )
        #expect(result == GenericPackShapeDescriptorBaseline.parameterPackFirstShape.kindRawValue)
    }
}
