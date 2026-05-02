import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `TypeContextDescriptor`.
///
/// `TypeContextDescriptor` is the bare type-descriptor header common to
/// struct/enum/class kinds. Members directly declared in
/// `TypeContextDescriptor.swift` are `offset`/`layout` plus the
/// `enumDescriptor`/`structDescriptor`/`classDescriptor` kind-projection
/// methods (each with MachO + InProcess + ReadingContext overloads that
/// collapse to one MethodKey under PublicMemberScanner's name-only key).
///
/// Protocol-extension methods like `name(in:)`, `fields(in:)`,
/// `metadataAccessorFunction(in:)` live on `TypeContextDescriptorProtocol`
/// and are exercised in `TypeContextDescriptorProtocolTests`.
///
/// Picker: `Structs.StructTest`. Reading the bare `TypeContextDescriptor`
/// header at its offset gives us `structDescriptor()` non-nil and the
/// other two kind-projections nil.
@Suite
final class TypeContextDescriptorTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "TypeContextDescriptor"
    static var registeredTestMethodNames: Set<String> {
        TypeContextDescriptorBaseline.registeredTestMethodNames
    }

    /// Helper: read the bare `TypeContextDescriptor` header at the
    /// `Structs.StructTest` offset against both readers.
    private func loadStructTestDescriptors() throws -> (file: TypeContextDescriptor, image: TypeContextDescriptor) {
        let fileSubject = try BaselineFixturePicker.struct_StructTest(in: machOFile)
        let imageSubject = try BaselineFixturePicker.struct_StructTest(in: machOImage)
        let file: TypeContextDescriptor = try machOFile.readWrapperElement(offset: fileSubject.offset)
        let image: TypeContextDescriptor = try machOImage.readWrapperElement(offset: imageSubject.offset)
        return (file: file, image: image)
    }

    @Test func offset() async throws {
        let descriptors = try loadStructTestDescriptors()
        let result = try acrossAllReaders(
            file: { descriptors.file.offset },
            image: { descriptors.image.offset }
        )
        #expect(result == TypeContextDescriptorBaseline.structTest.offset)
    }

    @Test func layout() async throws {
        let descriptors = try loadStructTestDescriptors()
        // Cross-reader equality on the only stable scalar field
        // (`flags.rawValue`); other layout fields are relative pointers
        // whose value varies by reader.
        let flagsRaw = try acrossAllReaders(
            file: { descriptors.file.layout.flags.rawValue },
            image: { descriptors.image.layout.flags.rawValue }
        )
        #expect(flagsRaw == TypeContextDescriptorBaseline.structTest.layoutFlagsRawValue)
    }

    /// `enumDescriptor(in:)` returns `nil` for our struct fixture (kind
    /// guard fails). Witnesses the false branch; the `enum` true branch
    /// is exercised end-to-end via the Type/Enum Suites.
    @Test func enumDescriptor() async throws {
        let descriptors = try loadStructTestDescriptors()
        let presence = try acrossAllReaders(
            file: { (try descriptors.file.enumDescriptor(in: machOFile)) != nil },
            image: { (try descriptors.image.enumDescriptor(in: machOImage)) != nil }
        )
        #expect(presence == TypeContextDescriptorBaseline.structTest.hasEnumDescriptor)

        // ReadingContext-based overload also exercised.
        let imageCtxPresence = (try descriptors.image.enumDescriptor(in: imageContext)) != nil
        #expect(imageCtxPresence == TypeContextDescriptorBaseline.structTest.hasEnumDescriptor)
    }

    /// `structDescriptor(in:)` returns the underlying `StructDescriptor`
    /// for our struct fixture. Witnesses the true branch.
    @Test func structDescriptor() async throws {
        let descriptors = try loadStructTestDescriptors()
        let presence = try acrossAllReaders(
            file: { (try descriptors.file.structDescriptor(in: machOFile)) != nil },
            image: { (try descriptors.image.structDescriptor(in: machOImage)) != nil }
        )
        #expect(presence == TypeContextDescriptorBaseline.structTest.hasStructDescriptor)

        // ReadingContext-based overload also exercised.
        let imageCtxPresence = (try descriptors.image.structDescriptor(in: imageContext)) != nil
        #expect(imageCtxPresence == TypeContextDescriptorBaseline.structTest.hasStructDescriptor)
    }

    /// `classDescriptor(in:)` returns `nil` for our struct fixture (kind
    /// guard fails). Witnesses the false branch; the `class` true branch
    /// is exercised end-to-end via the Type/Class Suites.
    @Test func classDescriptor() async throws {
        let descriptors = try loadStructTestDescriptors()
        let presence = try acrossAllReaders(
            file: { (try descriptors.file.classDescriptor(in: machOFile)) != nil },
            image: { (try descriptors.image.classDescriptor(in: machOImage)) != nil }
        )
        #expect(presence == TypeContextDescriptorBaseline.structTest.hasClassDescriptor)

        // ReadingContext-based overload also exercised.
        let imageCtxPresence = (try descriptors.image.classDescriptor(in: imageContext)) != nil
        #expect(imageCtxPresence == TypeContextDescriptorBaseline.structTest.hasClassDescriptor)
    }
}
