import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `TypeContextDescriptorProtocol`.
///
/// Per the protocol-extension attribution rule (see `BaselineGenerator.swift`),
/// `metadataAccessorFunction`, `fieldDescriptor`, `genericContext`,
/// `typeGenericContext`, and the seven derived booleans
/// (`hasSingletonMetadataInitialization`, `hasForeignMetadataInitialization`,
/// `hasImportInfo`,
/// `hasCanonicalMetadataPrespecializationsOrSingletonMetadataPointer`,
/// `hasLayoutString`, `hasCanonicalMetadataPrespecializations`,
/// `hasSingletonMetadataPointer`) are declared in
/// `extension TypeContextDescriptorProtocol { ... }` and attribute to the
/// protocol, not to concrete descriptors.
///
/// Picker: `Structs.StructTest`'s descriptor.
@Suite
final class TypeContextDescriptorProtocolTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "TypeContextDescriptorProtocol"
    static var registeredTestMethodNames: Set<String> {
        TypeContextDescriptorProtocolBaseline.registeredTestMethodNames
    }

    private func loadStructTestDescriptors() throws -> (file: StructDescriptor, image: StructDescriptor) {
        let file = try BaselineFixturePicker.struct_StructTest(in: machOFile)
        let image = try BaselineFixturePicker.struct_StructTest(in: machOImage)
        return (file: file, image: image)
    }

    @Test func fieldDescriptor() async throws {
        let (fileSubject, imageSubject) = try loadStructTestDescriptors()
        let presence = try acrossAllContexts(
            file: { (try? fileSubject.fieldDescriptor(in: fileContext)) != nil },
            image: { (try? imageSubject.fieldDescriptor(in: imageContext)) != nil }
        )
        #expect(presence == TypeContextDescriptorProtocolBaseline.structTest.hasFieldDescriptor)
    }

    @Test func genericContext() async throws {
        let (fileSubject, imageSubject) = try loadStructTestDescriptors()
        let presence = try acrossAllContexts(
            file: { (try fileSubject.genericContext(in: fileContext)) != nil },
            image: { (try imageSubject.genericContext(in: imageContext)) != nil }
        )
        #expect(presence == TypeContextDescriptorProtocolBaseline.structTest.hasGenericContext)
    }

    @Test func typeGenericContext() async throws {
        let (fileSubject, imageSubject) = try loadStructTestDescriptors()
        let presence = try acrossAllContexts(
            file: { (try fileSubject.typeGenericContext(in: fileContext)) != nil },
            image: { (try imageSubject.typeGenericContext(in: imageContext)) != nil }
        )
        #expect(presence == TypeContextDescriptorProtocolBaseline.structTest.hasTypeGenericContext)
    }

    /// `metadataAccessorFunction(in:)` is a `MachOImage`-only path: it uses
    /// `context.runtimePointer(at:)`, which only resolves when the
    /// underlying reader is image-backed and answers nil for a file
    /// context. We exercise it against the image context and assert
    /// non-nil.
    @Test func metadataAccessorFunction() async throws {
        let (_, imageSubject) = try loadStructTestDescriptors()
        let imagePresence = (try imageSubject.metadataAccessorFunction(in: imageContext)) != nil
        #expect(imagePresence)
    }

    // MARK: - Derived booleans (StructTest witnesses; all read false)

    @Test func hasSingletonMetadataInitialization() async throws {
        let (fileSubject, imageSubject) = try loadStructTestDescriptors()
        let result = try acrossAllReaders(
            file: { fileSubject.hasSingletonMetadataInitialization },
            image: { imageSubject.hasSingletonMetadataInitialization }
        )
        #expect(result == TypeContextDescriptorProtocolBaseline.structTest.hasSingletonMetadataInitialization)
    }

    @Test func hasForeignMetadataInitialization() async throws {
        let (fileSubject, imageSubject) = try loadStructTestDescriptors()
        let result = try acrossAllReaders(
            file: { fileSubject.hasForeignMetadataInitialization },
            image: { imageSubject.hasForeignMetadataInitialization }
        )
        #expect(result == TypeContextDescriptorProtocolBaseline.structTest.hasForeignMetadataInitialization)
    }

    @Test func hasImportInfo() async throws {
        let (fileSubject, imageSubject) = try loadStructTestDescriptors()
        let result = try acrossAllReaders(
            file: { fileSubject.hasImportInfo },
            image: { imageSubject.hasImportInfo }
        )
        #expect(result == TypeContextDescriptorProtocolBaseline.structTest.hasImportInfo)
    }

    /// `typeImportInfo` on a plain Swift struct is `nil`; on the C-imported
    /// `Decimal` (the `NSDecimal` typedef) it carries the ABI name and the
    /// C-typedef namespace, identically through every reader.
    @Test func typeImportInfo() async throws {
        let (fileSubject, imageSubject) = try loadStructTestDescriptors()
        let swiftResult = try acrossAllContexts(
            file: { try fileSubject.typeImportInfo(in: fileContext) },
            image: { try imageSubject.typeImportInfo(in: imageContext) }
        )
        #expect(swiftResult == nil)
        #expect(TypeContextDescriptorProtocolBaseline.structTest.typeImportInfoABIName == nil)

        let foreignFile = try BaselineFixturePicker.struct_ForeignDecimal(in: machOFile)
        let foreignImage = try BaselineFixturePicker.struct_ForeignDecimal(in: machOImage)
        let foreignResult = try acrossAllContexts(
            file: { try foreignFile.typeImportInfo(in: fileContext) },
            image: { try foreignImage.typeImportInfo(in: imageContext) }
        )
        let expected = TypeContextDescriptorProtocolBaseline.foreignDecimal
        #expect(foreignResult?.abiName == expected.typeImportInfoABIName)
        #expect(foreignResult?.symbolNamespace == expected.typeImportInfoSymbolNamespace)
        #expect(foreignResult?.relatedEntityName == expected.typeImportInfoRelatedEntityName)
        #expect(foreignResult?.isCTypedef == true)
        #expect(foreignResult?.isRelatedEntity == false)
    }

    @Test func hasCanonicalMetadataPrespecializationsOrSingletonMetadataPointer() async throws {
        let (fileSubject, imageSubject) = try loadStructTestDescriptors()
        let result = try acrossAllReaders(
            file: { fileSubject.hasCanonicalMetadataPrespecializationsOrSingletonMetadataPointer },
            image: { imageSubject.hasCanonicalMetadataPrespecializationsOrSingletonMetadataPointer }
        )
        #expect(result == TypeContextDescriptorProtocolBaseline.structTest.hasCanonicalMetadataPrespecializationsOrSingletonMetadataPointer)
    }

    @Test func hasLayoutString() async throws {
        let (fileSubject, imageSubject) = try loadStructTestDescriptors()
        let result = try acrossAllReaders(
            file: { fileSubject.hasLayoutString },
            image: { imageSubject.hasLayoutString }
        )
        #expect(result == TypeContextDescriptorProtocolBaseline.structTest.hasLayoutString)
    }

    @Test func hasCanonicalMetadataPrespecializations() async throws {
        let (fileSubject, imageSubject) = try loadStructTestDescriptors()
        let result = try acrossAllReaders(
            file: { fileSubject.hasCanonicalMetadataPrespecializations },
            image: { imageSubject.hasCanonicalMetadataPrespecializations }
        )
        #expect(result == TypeContextDescriptorProtocolBaseline.structTest.hasCanonicalMetadataPrespecializations)
    }

    @Test func hasSingletonMetadataPointer() async throws {
        let (fileSubject, imageSubject) = try loadStructTestDescriptors()
        let result = try acrossAllReaders(
            file: { fileSubject.hasSingletonMetadataPointer },
            image: { imageSubject.hasSingletonMetadataPointer }
        )
        #expect(result == TypeContextDescriptorProtocolBaseline.structTest.hasSingletonMetadataPointer)
    }
}
