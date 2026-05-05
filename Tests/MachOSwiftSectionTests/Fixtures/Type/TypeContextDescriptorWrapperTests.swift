import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `TypeContextDescriptorWrapper`.
///
/// `TypeContextDescriptorWrapper` is the 3-case sum type covering the
/// `enum`/`struct`/`class` type-descriptor kinds. Members include three
/// alternate-projection vars, the `asContextDescriptorWrapper` projection,
/// the `asPointerWrapper(in:)` func, the `parent`/`genericContext`/
/// `typeGenericContext` instance methods, and the `resolve` static family
/// in the `Resolvable` extension.
///
/// The `ValueTypeDescriptorWrapper` enum declared in the same file is
/// covered by `ValueTypeDescriptorWrapperTests`.
///
/// Picker: `Structs.StructTest`'s descriptor wrapped in `.struct(...)`.
@Suite
final class TypeContextDescriptorWrapperTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "TypeContextDescriptorWrapper"
    static var registeredTestMethodNames: Set<String> {
        TypeContextDescriptorWrapperBaseline.registeredTestMethodNames
    }

    private func loadStructTestWrappers() throws -> (file: TypeContextDescriptorWrapper, image: TypeContextDescriptorWrapper) {
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
        #expect(result == TypeContextDescriptorWrapperBaseline.structTest.descriptorOffset)
    }

    @Test func namedContextDescriptor() async throws {
        let wrappers = try loadStructTestWrappers()
        let result = try acrossAllReaders(
            file: { wrappers.file.namedContextDescriptor.offset },
            image: { wrappers.image.namedContextDescriptor.offset }
        )
        #expect(result == TypeContextDescriptorWrapperBaseline.structTest.descriptorOffset)
    }

    @Test func typeContextDescriptor() async throws {
        let wrappers = try loadStructTestWrappers()
        let result = try acrossAllReaders(
            file: { wrappers.file.typeContextDescriptor.offset },
            image: { wrappers.image.typeContextDescriptor.offset }
        )
        #expect(result == TypeContextDescriptorWrapperBaseline.structTest.descriptorOffset)
    }

    @Test func asContextDescriptorWrapper() async throws {
        let wrappers = try loadStructTestWrappers()
        // `asContextDescriptorWrapper` lifts to the broader sum type
        // `ContextDescriptorWrapper`. Verify the descriptor offset round-trips.
        let result = try acrossAllReaders(
            file: { wrappers.file.asContextDescriptorWrapper.contextDescriptor.offset },
            image: { wrappers.image.asContextDescriptorWrapper.contextDescriptor.offset }
        )
        #expect(result == TypeContextDescriptorWrapperBaseline.structTest.descriptorOffset)
    }

    /// `asPointerWrapper(in:)` is `MachOImage`-only. Smoke-test that the
    /// returned wrapper has the same descriptor kind (`.struct`) as the input.
    @Test func asPointerWrapper() async throws {
        let (_, imageWrapper) = try loadStructTestWrappers()
        let pointerWrapper = imageWrapper.asPointerWrapper(in: machOImage)
        #expect(pointerWrapper.isStruct == true)
    }

    // MARK: - Methods

    @Test func parent() async throws {
        let wrappers = try loadStructTestWrappers()
        let presence = try acrossAllReaders(
            file: { (try wrappers.file.parent(in: machOFile)) != nil },
            image: { (try wrappers.image.parent(in: machOImage)) != nil }
        )
        #expect(presence == TypeContextDescriptorWrapperBaseline.structTest.hasParent)

        // ReadingContext-based overload also exercised.
        let imageCtxPresence = (try wrappers.image.parent(in: imageContext)) != nil
        #expect(imageCtxPresence == TypeContextDescriptorWrapperBaseline.structTest.hasParent)
    }

    @Test func genericContext() async throws {
        let wrappers = try loadStructTestWrappers()
        let presence = try acrossAllReaders(
            file: { (try wrappers.file.genericContext(in: machOFile)) != nil },
            image: { (try wrappers.image.genericContext(in: machOImage)) != nil }
        )
        #expect(presence == TypeContextDescriptorWrapperBaseline.structTest.hasGenericContext)

        // ReadingContext-based overload also exercised.
        let imageCtxPresence = (try wrappers.image.genericContext(in: imageContext)) != nil
        #expect(imageCtxPresence == TypeContextDescriptorWrapperBaseline.structTest.hasGenericContext)
    }

    @Test func typeGenericContext() async throws {
        let wrappers = try loadStructTestWrappers()
        let presence = try acrossAllReaders(
            file: { (try wrappers.file.typeGenericContext(in: machOFile)) != nil },
            image: { (try wrappers.image.typeGenericContext(in: machOImage)) != nil }
        )
        #expect(presence == TypeContextDescriptorWrapperBaseline.structTest.hasTypeGenericContext)

        // ReadingContext-based overload also exercised.
        let imageCtxPresence = (try wrappers.image.typeGenericContext(in: imageContext)) != nil
        #expect(imageCtxPresence == TypeContextDescriptorWrapperBaseline.structTest.hasTypeGenericContext)
    }

    @Test func resolve() async throws {
        // Static `resolve(...)` overloads collapse to one MethodKey under
        // PublicMemberScanner. Exercise the MachO-based overload that
        // returns `Self`.
        let fileDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOImage)

        let fileWrapper: TypeContextDescriptorWrapper = try TypeContextDescriptorWrapper.resolve(from: fileDescriptor.offset, in: machOFile)
        let imageWrapper: TypeContextDescriptorWrapper = try TypeContextDescriptorWrapper.resolve(from: imageDescriptor.offset, in: machOImage)

        #expect(fileWrapper.isStruct == true)
        #expect(imageWrapper.isStruct == true)
        #expect(fileWrapper.contextDescriptor.offset == TypeContextDescriptorWrapperBaseline.structTest.descriptorOffset)
        #expect(imageWrapper.contextDescriptor.offset == TypeContextDescriptorWrapperBaseline.structTest.descriptorOffset)
    }
}
