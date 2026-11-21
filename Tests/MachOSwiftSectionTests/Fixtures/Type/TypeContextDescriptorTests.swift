import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftSectionTestingSupport
import SwiftSectionFixtureSupport

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
@FixtureSuite
final class TypeContextDescriptorTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
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
        let result = try acrossAllReaders(descriptors.file, descriptors.image) { $0.offset }
        #expect(result == TypeContextDescriptorBaseline.structTest.offset)
    }

    @Test func layout() async throws {
        let descriptors = try loadStructTestDescriptors()
        // Cross-reader equality on the only stable scalar field
        // (`flags.rawValue`); other layout fields are relative pointers
        // whose value varies by reader.
        let flagsRaw = try acrossAllReaders(descriptors.file, descriptors.image) { $0.layout.flags.rawValue }
        #expect(flagsRaw == TypeContextDescriptorBaseline.structTest.layoutFlagsRawValue)
    }

    /// `enumDescriptor(in:)` returns `nil` for our struct fixture (kind
    /// guard fails). Witnesses the false branch; the `enum` true branch
    /// is exercised end-to-end via the Type/Enum Suites.
    @Test func enumDescriptor() async throws {
        let descriptors = try loadStructTestDescriptors()
        let presence = try acrossAllContexts(descriptors.file, descriptors.image) { descriptor, context in
            (try descriptor.enumDescriptor(in: context)) != nil
        }
        #expect(presence == TypeContextDescriptorBaseline.structTest.hasEnumDescriptor)
    }

    /// `structDescriptor(in:)` returns the underlying `StructDescriptor`
    /// for our struct fixture. Witnesses the true branch.
    @Test func structDescriptor() async throws {
        let descriptors = try loadStructTestDescriptors()
        let presence = try acrossAllContexts(descriptors.file, descriptors.image) { descriptor, context in
            (try descriptor.structDescriptor(in: context)) != nil
        }
        #expect(presence == TypeContextDescriptorBaseline.structTest.hasStructDescriptor)
    }

    /// `classDescriptor(in:)` returns `nil` for our struct fixture (kind
    /// guard fails). Witnesses the false branch; the `class` true branch
    /// is exercised end-to-end via the Type/Class Suites.
    @Test func classDescriptor() async throws {
        let descriptors = try loadStructTestDescriptors()
        let presence = try acrossAllContexts(descriptors.file, descriptors.image) { descriptor, context in
            (try descriptor.classDescriptor(in: context)) != nil
        }
        #expect(presence == TypeContextDescriptorBaseline.structTest.hasClassDescriptor)
    }
}
