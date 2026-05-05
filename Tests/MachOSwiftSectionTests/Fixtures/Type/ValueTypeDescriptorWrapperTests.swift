import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `ValueTypeDescriptorWrapper`.
///
/// `ValueTypeDescriptorWrapper` is the 2-case sum type covering the
/// `enum`/`struct` value-type kinds (no `class` arm). It lives in the
/// same file as `TypeContextDescriptorWrapper` but is a distinct type —
/// PublicMemberScanner attributes its public members to a separate
/// `ValueTypeDescriptorWrapper` MethodKey namespace.
///
/// Picker: `Structs.StructTest`'s descriptor wrapped in `.struct(...)`.
@Suite
final class ValueTypeDescriptorWrapperTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "ValueTypeDescriptorWrapper"
    static var registeredTestMethodNames: Set<String> {
        ValueTypeDescriptorWrapperBaseline.registeredTestMethodNames
    }

    private func loadStructTestWrappers() throws -> (file: ValueTypeDescriptorWrapper, image: ValueTypeDescriptorWrapper) {
        let file = try BaselineFixturePicker.struct_StructTest(in: machOFile)
        let image = try BaselineFixturePicker.struct_StructTest(in: machOImage)
        return (file: .struct(file), image: .struct(image))
    }

    // MARK: - Alternate-projection vars

    @Test func contextDescriptor() async throws {
        let wrappers = try loadStructTestWrappers()
        let result = try acrossAllReaders(
            file: { wrappers.file.contextDescriptor.offset },
            image: { wrappers.image.contextDescriptor.offset }
        )
        #expect(result == ValueTypeDescriptorWrapperBaseline.structTest.descriptorOffset)
    }

    @Test func namedContextDescriptor() async throws {
        let wrappers = try loadStructTestWrappers()
        let result = try acrossAllReaders(
            file: { wrappers.file.namedContextDescriptor.offset },
            image: { wrappers.image.namedContextDescriptor.offset }
        )
        #expect(result == ValueTypeDescriptorWrapperBaseline.structTest.descriptorOffset)
    }

    @Test func typeContextDescriptor() async throws {
        let wrappers = try loadStructTestWrappers()
        let result = try acrossAllReaders(
            file: { wrappers.file.typeContextDescriptor.offset },
            image: { wrappers.image.typeContextDescriptor.offset }
        )
        #expect(result == ValueTypeDescriptorWrapperBaseline.structTest.descriptorOffset)
    }

    @Test func asTypeContextDescriptorWrapper() async throws {
        let wrappers = try loadStructTestWrappers()
        // Lifting to `TypeContextDescriptorWrapper` should preserve kind.
        let result = try acrossAllReaders(
            file: { wrappers.file.asTypeContextDescriptorWrapper.isStruct },
            image: { wrappers.image.asTypeContextDescriptorWrapper.isStruct }
        )
        #expect(result == true)
    }

    @Test func asContextDescriptorWrapper() async throws {
        let wrappers = try loadStructTestWrappers()
        let result = try acrossAllReaders(
            file: { wrappers.file.asContextDescriptorWrapper.contextDescriptor.offset },
            image: { wrappers.image.asContextDescriptorWrapper.contextDescriptor.offset }
        )
        #expect(result == ValueTypeDescriptorWrapperBaseline.structTest.descriptorOffset)
    }

    // MARK: - Methods

    @Test func parent() async throws {
        let wrappers = try loadStructTestWrappers()
        let presence = try acrossAllReaders(
            file: { (try wrappers.file.parent(in: machOFile)) != nil },
            image: { (try wrappers.image.parent(in: machOImage)) != nil }
        )
        #expect(presence == ValueTypeDescriptorWrapperBaseline.structTest.hasParent)

        // ReadingContext-based overload also exercised.
        let imageCtxPresence = (try wrappers.image.parent(in: imageContext)) != nil
        #expect(imageCtxPresence == ValueTypeDescriptorWrapperBaseline.structTest.hasParent)
    }

    @Test func genericContext() async throws {
        let wrappers = try loadStructTestWrappers()
        let presence = try acrossAllReaders(
            file: { (try wrappers.file.genericContext(in: machOFile)) != nil },
            image: { (try wrappers.image.genericContext(in: machOImage)) != nil }
        )
        #expect(presence == ValueTypeDescriptorWrapperBaseline.structTest.hasGenericContext)

        // ReadingContext-based overload also exercised.
        let imageCtxPresence = (try wrappers.image.genericContext(in: imageContext)) != nil
        #expect(imageCtxPresence == ValueTypeDescriptorWrapperBaseline.structTest.hasGenericContext)
    }

    @Test func resolve() async throws {
        // Static `resolve(...)` overloads collapse to one MethodKey.
        let fileDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOImage)

        let fileWrapper: ValueTypeDescriptorWrapper = try ValueTypeDescriptorWrapper.resolve(from: fileDescriptor.offset, in: machOFile)
        let imageWrapper: ValueTypeDescriptorWrapper = try ValueTypeDescriptorWrapper.resolve(from: imageDescriptor.offset, in: machOImage)

        #expect(fileWrapper.isStruct == true)
        #expect(imageWrapper.isStruct == true)
        #expect(fileWrapper.contextDescriptor.offset == ValueTypeDescriptorWrapperBaseline.structTest.descriptorOffset)
        #expect(imageWrapper.contextDescriptor.offset == ValueTypeDescriptorWrapperBaseline.structTest.descriptorOffset)
    }
}
