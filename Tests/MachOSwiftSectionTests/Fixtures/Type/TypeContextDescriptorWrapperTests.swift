import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftSectionTestingSupport
import SwiftSectionFixtureSupport

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
@FixtureSuite
final class TypeContextDescriptorWrapperTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
    private func loadStructTestWrappers() throws -> (file: TypeContextDescriptorWrapper, image: TypeContextDescriptorWrapper) {
        let file = try BaselineFixturePicker.struct_StructTest(in: machOFile)
        let image = try BaselineFixturePicker.struct_StructTest(in: machOImage)
        return (file: .struct(file), image: .struct(image))
    }

    // MARK: - Alternate-projection vars

    @Test func contextDescriptor() async throws {
        let wrappers = try loadStructTestWrappers()
        let result = try acrossAllReaders(wrappers.file, wrappers.image) { $0.contextDescriptor.offset }
        #expect(result == TypeContextDescriptorWrapperBaseline.structTest.descriptorOffset)
    }

    @Test func namedContextDescriptor() async throws {
        let wrappers = try loadStructTestWrappers()
        let result = try acrossAllReaders(wrappers.file, wrappers.image) { $0.namedContextDescriptor.offset }
        #expect(result == TypeContextDescriptorWrapperBaseline.structTest.descriptorOffset)
    }

    @Test func typeContextDescriptor() async throws {
        let wrappers = try loadStructTestWrappers()
        let result = try acrossAllReaders(wrappers.file, wrappers.image) { $0.typeContextDescriptor.offset }
        #expect(result == TypeContextDescriptorWrapperBaseline.structTest.descriptorOffset)
    }

    @Test func asContextDescriptorWrapper() async throws {
        let wrappers = try loadStructTestWrappers()
        // `asContextDescriptorWrapper` lifts to the broader sum type
        // `ContextDescriptorWrapper`. Verify the descriptor offset round-trips.
        let result = try acrossAllReaders(wrappers.file, wrappers.image) { wrapper in
            wrapper.asContextDescriptorWrapper.contextDescriptor.offset
        }
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
        let presence = try acrossAllContexts(wrappers.file, wrappers.image) { wrapper, context in
            (try wrapper.parent(in: context)) != nil
        }
        #expect(presence == TypeContextDescriptorWrapperBaseline.structTest.hasParent)
    }

    @Test func genericContext() async throws {
        let wrappers = try loadStructTestWrappers()
        let presence = try acrossAllContexts(wrappers.file, wrappers.image) { wrapper, context in
            (try wrapper.genericContext(in: context)) != nil
        }
        #expect(presence == TypeContextDescriptorWrapperBaseline.structTest.hasGenericContext)
    }

    @Test func typeGenericContext() async throws {
        let wrappers = try loadStructTestWrappers()
        let presence = try acrossAllContexts(wrappers.file, wrappers.image) { wrapper, context in
            (try wrapper.typeGenericContext(in: context)) != nil
        }
        #expect(presence == TypeContextDescriptorWrapperBaseline.structTest.hasTypeGenericContext)
    }

    @Test func resolve() async throws {
        // Static `resolve(...)` overloads collapse to one MethodKey under
        // PublicMemberScanner. Exercise the ReadingContext-based overload
        // that returns `Self`.
        let fileDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOImage)

        let fileWrapper: TypeContextDescriptorWrapper = try TypeContextDescriptorWrapper.resolve(at: fileDescriptor.offset, in: fileContext)
        let imageWrapper: TypeContextDescriptorWrapper = try TypeContextDescriptorWrapper.resolve(at: imageDescriptor.offset, in: imageContext)

        #expect(fileWrapper.isStruct == true)
        #expect(imageWrapper.isStruct == true)
        #expect(fileWrapper.contextDescriptor.offset == TypeContextDescriptorWrapperBaseline.structTest.descriptorOffset)
        #expect(imageWrapper.contextDescriptor.offset == TypeContextDescriptorWrapperBaseline.structTest.descriptorOffset)
    }
}
