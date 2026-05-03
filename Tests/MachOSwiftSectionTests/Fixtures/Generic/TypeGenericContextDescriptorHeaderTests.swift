import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `TypeGenericContextDescriptorHeader`.
///
/// `TypeGenericContextDescriptorHeader` extends the plain
/// `GenericContextDescriptorHeader` layout with two `RelativeOffset`
/// pointers (`instantiationCache` and `defaultInstantiationPattern`) for
/// the runtime metadata-instantiation hooks. The Suite reads the header
/// off the `GenericFieldLayout.GenericStructLayoutRequirement<A: AnyObject>`
/// generic struct's `typeGenericContext` and asserts cross-reader equality
/// on `offset` and the four scalar fields exposed via the
/// `GenericContextDescriptorHeaderLayout` protocol.
@Suite
final class TypeGenericContextDescriptorHeaderTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "TypeGenericContextDescriptorHeader"
    static var registeredTestMethodNames: Set<String> {
        TypeGenericContextDescriptorHeaderBaseline.registeredTestMethodNames
    }

    /// Helper: extract the `TypeGenericContextDescriptorHeader` from
    /// `GenericStructLayoutRequirement` against both readers.
    private func loadGenericStructLayoutRequirementHeaders() throws -> (file: TypeGenericContextDescriptorHeader, image: TypeGenericContextDescriptorHeader) {
        let fileDescriptor = try BaselineFixturePicker.struct_GenericStructLayoutRequirement(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.struct_GenericStructLayoutRequirement(in: machOImage)
        let fileContext = try required(try fileDescriptor.typeGenericContext(in: machOFile))
        let imageContext = try required(try imageDescriptor.typeGenericContext(in: machOImage))
        return (file: fileContext.header, image: imageContext.header)
    }

    @Test func offset() async throws {
        let headers = try loadGenericStructLayoutRequirementHeaders()
        let result = try acrossAllReaders(
            file: { headers.file.offset },
            image: { headers.image.offset }
        )
        #expect(result == TypeGenericContextDescriptorHeaderBaseline.genericStructLayoutRequirement.offset)
    }

    @Test func layout() async throws {
        let headers = try loadGenericStructLayoutRequirementHeaders()

        let numParams = try acrossAllReaders(
            file: { headers.file.layout.numParams },
            image: { headers.image.layout.numParams }
        )
        let numRequirements = try acrossAllReaders(
            file: { headers.file.layout.numRequirements },
            image: { headers.image.layout.numRequirements }
        )
        let numKeyArguments = try acrossAllReaders(
            file: { headers.file.layout.numKeyArguments },
            image: { headers.image.layout.numKeyArguments }
        )
        let flagsRawValue = try acrossAllReaders(
            file: { headers.file.layout.flags.rawValue },
            image: { headers.image.layout.flags.rawValue }
        )

        #expect(numParams == TypeGenericContextDescriptorHeaderBaseline.genericStructLayoutRequirement.layoutNumParams)
        #expect(numRequirements == TypeGenericContextDescriptorHeaderBaseline.genericStructLayoutRequirement.layoutNumRequirements)
        #expect(numKeyArguments == TypeGenericContextDescriptorHeaderBaseline.genericStructLayoutRequirement.layoutNumKeyArguments)
        #expect(flagsRawValue == TypeGenericContextDescriptorHeaderBaseline.genericStructLayoutRequirement.layoutFlagsRawValue)
    }
}
