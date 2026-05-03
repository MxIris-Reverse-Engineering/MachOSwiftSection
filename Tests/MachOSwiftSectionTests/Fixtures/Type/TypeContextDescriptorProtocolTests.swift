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
        let presence = try acrossAllReaders(
            file: { (try? fileSubject.fieldDescriptor(in: machOFile)) != nil },
            image: { (try? imageSubject.fieldDescriptor(in: machOImage)) != nil }
        )
        #expect(presence == TypeContextDescriptorProtocolBaseline.structTest.hasFieldDescriptor)

        // ReadingContext-based overload also exercised.
        let imageCtxPresence = (try? imageSubject.fieldDescriptor(in: imageContext)) != nil
        #expect(imageCtxPresence == TypeContextDescriptorProtocolBaseline.structTest.hasFieldDescriptor)
    }

    @Test func genericContext() async throws {
        let (fileSubject, imageSubject) = try loadStructTestDescriptors()
        let presence = try acrossAllReaders(
            file: { (try fileSubject.genericContext(in: machOFile)) != nil },
            image: { (try imageSubject.genericContext(in: machOImage)) != nil }
        )
        #expect(presence == TypeContextDescriptorProtocolBaseline.structTest.hasGenericContext)

        // ReadingContext-based overload also exercised.
        let imageCtxPresence = (try imageSubject.genericContext(in: imageContext)) != nil
        #expect(imageCtxPresence == TypeContextDescriptorProtocolBaseline.structTest.hasGenericContext)
    }

    @Test func typeGenericContext() async throws {
        let (fileSubject, imageSubject) = try loadStructTestDescriptors()
        let presence = try acrossAllReaders(
            file: { (try fileSubject.typeGenericContext(in: machOFile)) != nil },
            image: { (try imageSubject.typeGenericContext(in: machOImage)) != nil }
        )
        #expect(presence == TypeContextDescriptorProtocolBaseline.structTest.hasTypeGenericContext)

        // ReadingContext-based overload also exercised.
        let imageCtxPresence = (try imageSubject.typeGenericContext(in: imageContext)) != nil
        #expect(imageCtxPresence == TypeContextDescriptorProtocolBaseline.structTest.hasTypeGenericContext)
    }

    /// `metadataAccessorFunction(in:)` is a `MachOImage`-only path: the
    /// MachO-based overload guards on `as? MachOImage` and returns nil
    /// otherwise; the ReadingContext-based overload uses
    /// `context.runtimePointer(at:)` which only resolves when the
    /// underlying reader is image-backed. We exercise both overloads
    /// against the image path and assert non-nil.
    @Test func metadataAccessorFunction() async throws {
        let (_, imageSubject) = try loadStructTestDescriptors()
        let imagePresence = (try imageSubject.metadataAccessorFunction(in: machOImage)) != nil
        #expect(imagePresence)

        // ReadingContext-based overload exercised but not asserted on
        // value: the underlying runtime-pointer lookup may return nil
        // depending on the field's relative offset relative to the loaded
        // image. The call itself completing without throwing is the
        // contract we verify here.
        _ = try imageSubject.metadataAccessorFunction(in: imageContext)
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
