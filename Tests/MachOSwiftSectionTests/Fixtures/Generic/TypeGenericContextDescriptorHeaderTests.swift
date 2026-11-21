import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftSectionTestingSupport
import SwiftSectionFixtureSupport

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
@FixtureSuite
final class TypeGenericContextDescriptorHeaderTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
    /// Helper: extract the `TypeGenericContextDescriptorHeader` from
    /// `GenericStructLayoutRequirement` against both readers.
    private func loadGenericStructLayoutRequirementHeaders() throws -> (file: TypeGenericContextDescriptorHeader, image: TypeGenericContextDescriptorHeader) {
        let fileDescriptor = try BaselineFixturePicker.struct_GenericStructLayoutRequirement(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.struct_GenericStructLayoutRequirement(in: machOImage)
        let fileGenericContext = try required(try fileDescriptor.typeGenericContext(in: fileContext))
        let imageGenericContext = try required(try imageDescriptor.typeGenericContext(in: imageContext))
        return (file: fileGenericContext.header, image: imageGenericContext.header)
    }

    @Test func offset() async throws {
        let headers = try loadGenericStructLayoutRequirementHeaders()
        let result = try acrossAllReaders(headers.file, headers.image) { $0.offset }
        #expect(result == TypeGenericContextDescriptorHeaderBaseline.genericStructLayoutRequirement.offset)
    }

    @Test func layout() async throws {
        let headers = try loadGenericStructLayoutRequirementHeaders()

        let numParams = try acrossAllReaders(headers.file, headers.image) { $0.layout.numParams }
        let numRequirements = try acrossAllReaders(headers.file, headers.image) { $0.layout.numRequirements }
        let numKeyArguments = try acrossAllReaders(headers.file, headers.image) { $0.layout.numKeyArguments }
        let flagsRawValue = try acrossAllReaders(headers.file, headers.image) { $0.layout.flags.rawValue }

        #expect(numParams == TypeGenericContextDescriptorHeaderBaseline.genericStructLayoutRequirement.layoutNumParams)
        #expect(numRequirements == TypeGenericContextDescriptorHeaderBaseline.genericStructLayoutRequirement.layoutNumRequirements)
        #expect(numKeyArguments == TypeGenericContextDescriptorHeaderBaseline.genericStructLayoutRequirement.layoutNumKeyArguments)
        #expect(flagsRawValue == TypeGenericContextDescriptorHeaderBaseline.genericStructLayoutRequirement.layoutFlagsRawValue)

        // The instantiation cache is mutable runtime state and reads as zero
        // in the file; only where it sits is a static fact.
        let instantiationCacheOffset = try acrossAllReaders(headers.file, headers.image) { header in
            header.resolvedDirectOffset(from: \.instantiationCache)
        }
        #expect(instantiationCacheOffset == TypeGenericContextDescriptorHeaderBaseline.genericStructLayoutRequirement.instantiationCacheOffset)

        // The entry point to the whole generic-pattern family. The pattern
        // Suites reach their carriers through exactly this field, so a wrong
        // answer here would surface there too.
        let patternOffset = try acrossAllReaders(headers.file, headers.image) { header in
            header.resolvedDirectOffset(from: \.defaultInstantiationPattern)
        }
        #expect(patternOffset == TypeGenericContextDescriptorHeaderBaseline.genericStructLayoutRequirement.defaultInstantiationPatternOffset)

        // Resolving what it points at must produce a struct pattern, since
        // the carrier is a struct.
        let pattern = try GenericValueMetadataPattern.resolve(at: try required(patternOffset), in: fileContext)
        #expect(pattern.metadataKind == .struct)
    }

}
