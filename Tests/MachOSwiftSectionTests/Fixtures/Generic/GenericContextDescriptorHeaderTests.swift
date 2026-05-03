import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `GenericContextDescriptorHeader`.
///
/// `GenericContextDescriptorHeader` is the 8-byte base header carried at
/// the start of every `GenericContext` payload. The Suite reads the
/// header from the first generic extension context in the fixture
/// (extensions-on-generic-types declared with `where` clauses) and
/// asserts cross-reader equality on `offset` and the four scalar layout
/// fields (`numParams`, `numRequirements`, `numKeyArguments`, `flags`).
@Suite
final class GenericContextDescriptorHeaderTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "GenericContextDescriptorHeader"
    static var registeredTestMethodNames: Set<String> {
        GenericContextDescriptorHeaderBaseline.registeredTestMethodNames
    }

    /// Helper: extract the `GenericContextDescriptorHeader` from the first
    /// generic extension context against both readers, mirroring the
    /// generator's pick logic.
    private func loadFirstExtensionGenericHeaders() throws -> (file: GenericContextDescriptorHeader, image: GenericContextDescriptorHeader) {
        let fileHeader = try GenericContextDescriptorHeaderBaselineGenerator.pickHeader(in: machOFile)
        let imageHeader = try GenericContextDescriptorHeaderBaselineGenerator.pickHeader(in: machOImage)
        return (file: fileHeader, image: imageHeader)
    }

    @Test func offset() async throws {
        let headers = try loadFirstExtensionGenericHeaders()
        let result = try acrossAllReaders(
            file: { headers.file.offset },
            image: { headers.image.offset }
        )
        #expect(result == GenericContextDescriptorHeaderBaseline.firstExtensionGenericHeader.offset)
    }

    @Test func layout() async throws {
        let headers = try loadFirstExtensionGenericHeaders()

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

        #expect(numParams == GenericContextDescriptorHeaderBaseline.firstExtensionGenericHeader.layoutNumParams)
        #expect(numRequirements == GenericContextDescriptorHeaderBaseline.firstExtensionGenericHeader.layoutNumRequirements)
        #expect(numKeyArguments == GenericContextDescriptorHeaderBaseline.firstExtensionGenericHeader.layoutNumKeyArguments)
        #expect(flagsRawValue == GenericContextDescriptorHeaderBaseline.firstExtensionGenericHeader.layoutFlagsRawValue)
    }
}
