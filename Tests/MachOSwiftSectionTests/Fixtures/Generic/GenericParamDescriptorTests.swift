import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `GenericParamDescriptor`.
///
/// Each `GenericParamDescriptor` is a one-byte record packed at the start
/// of every generic context. The Suite reads two representative entries:
/// one for a type parameter with `hasKeyArgument` set
/// (`GenericStructLayoutRequirement.parameters[0]`), one for a typePack
/// parameter (`ParameterPackRequirementTest.parameters[0]`).
@Suite
final class GenericParamDescriptorTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "GenericParamDescriptor"
    static var registeredTestMethodNames: Set<String> {
        GenericParamDescriptorBaseline.registeredTestMethodNames
    }

    // MARK: - Helpers

    private func loadLayoutRequirementParam0() throws -> (file: GenericParamDescriptor, image: GenericParamDescriptor) {
        let fileDescriptor = try BaselineFixturePicker.struct_GenericStructLayoutRequirement(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.struct_GenericStructLayoutRequirement(in: machOImage)
        let fileContext = try required(try fileDescriptor.typeGenericContext(in: machOFile))
        let imageContext = try required(try imageDescriptor.typeGenericContext(in: machOImage))
        let fileParam = try required(fileContext.parameters.first)
        let imageParam = try required(imageContext.parameters.first)
        return (file: fileParam, image: imageParam)
    }

    private func loadParameterPackParam0() throws -> (file: GenericParamDescriptor, image: GenericParamDescriptor) {
        let fileDescriptor = try BaselineFixturePicker.struct_ParameterPackRequirementTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.struct_ParameterPackRequirementTest(in: machOImage)
        let fileContext = try required(try fileDescriptor.typeGenericContext(in: machOFile))
        let imageContext = try required(try imageDescriptor.typeGenericContext(in: machOImage))
        let fileParam = try required(fileContext.parameters.first)
        let imageParam = try required(imageContext.parameters.first)
        return (file: fileParam, image: imageParam)
    }

    // MARK: - Ivars

    @Test func offset() async throws {
        let layout = try loadLayoutRequirementParam0()
        let layoutResult = try acrossAllReaders(
            file: { layout.file.offset },
            image: { layout.image.offset }
        )
        #expect(layoutResult == GenericParamDescriptorBaseline.layoutRequirementParam0.offset)

        let pack = try loadParameterPackParam0()
        let packResult = try acrossAllReaders(
            file: { pack.file.offset },
            image: { pack.image.offset }
        )
        #expect(packResult == GenericParamDescriptorBaseline.parameterPackParam0.offset)
    }

    @Test func layout() async throws {
        let layout = try loadLayoutRequirementParam0()
        let layoutRaw = try acrossAllReaders(
            file: { layout.file.layout.rawValue },
            image: { layout.image.layout.rawValue }
        )
        #expect(layoutRaw == GenericParamDescriptorBaseline.layoutRequirementParam0.layoutRawValue)

        let pack = try loadParameterPackParam0()
        let packRaw = try acrossAllReaders(
            file: { pack.file.layout.rawValue },
            image: { pack.image.layout.rawValue }
        )
        #expect(packRaw == GenericParamDescriptorBaseline.parameterPackParam0.layoutRawValue)
    }

    @Test func hasKeyArgument() async throws {
        let layout = try loadLayoutRequirementParam0()
        let layoutResult = try acrossAllReaders(
            file: { layout.file.hasKeyArgument },
            image: { layout.image.hasKeyArgument }
        )
        #expect(layoutResult == GenericParamDescriptorBaseline.layoutRequirementParam0.hasKeyArgument)

        let pack = try loadParameterPackParam0()
        let packResult = try acrossAllReaders(
            file: { pack.file.hasKeyArgument },
            image: { pack.image.hasKeyArgument }
        )
        #expect(packResult == GenericParamDescriptorBaseline.parameterPackParam0.hasKeyArgument)
    }

    @Test func kind() async throws {
        let layout = try loadLayoutRequirementParam0()
        let layoutResult = try acrossAllReaders(
            file: { layout.file.kind.rawValue },
            image: { layout.image.kind.rawValue }
        )
        #expect(layoutResult == GenericParamDescriptorBaseline.layoutRequirementParam0.kindRawValue)

        let pack = try loadParameterPackParam0()
        let packResult = try acrossAllReaders(
            file: { pack.file.kind.rawValue },
            image: { pack.image.kind.rawValue }
        )
        #expect(packResult == GenericParamDescriptorBaseline.parameterPackParam0.kindRawValue)
    }
}
