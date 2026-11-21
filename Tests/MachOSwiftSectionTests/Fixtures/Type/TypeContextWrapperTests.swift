import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftSectionTestingSupport
import SwiftSectionFixtureSupport

/// Fixture-based Suite for `TypeContextWrapper`.
///
/// `TypeContextWrapper` is the high-level sum type covering the
/// `enum`/`struct`/`class` type contexts (analogous to
/// `TypeContextDescriptorWrapper` but at the `*Context` level — wrapping
/// the high-level `Enum`/`Struct`/`Class` types, not their descriptors).
///
/// Picker: route `Structs.StructTest`'s descriptor through
/// `TypeContextWrapper.forTypeContextDescriptorWrapper` to materialize a
/// `.struct(...)` wrapper.
@Suite
@FixtureSuite
final class TypeContextWrapperTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
    private func loadStructTestWrappers() throws -> (file: TypeContextWrapper, image: TypeContextWrapper) {
        let fileDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOImage)
        let fileWrapperDescriptor = TypeContextDescriptorWrapper.struct(fileDescriptor)
        let imageWrapperDescriptor = TypeContextDescriptorWrapper.struct(imageDescriptor)
        let file = try TypeContextWrapper.forTypeContextDescriptorWrapper(fileWrapperDescriptor, in: fileContext)
        let image = try TypeContextWrapper.forTypeContextDescriptorWrapper(imageWrapperDescriptor, in: imageContext)
        return (file: file, image: image)
    }

    @Test func contextDescriptorWrapper() async throws {
        let wrappers = try loadStructTestWrappers()
        let result = try acrossAllReaders(wrappers.file, wrappers.image) { $0.contextDescriptorWrapper.contextDescriptor.offset }
        #expect(result == TypeContextWrapperBaseline.structTest.descriptorOffset)
    }

    @Test func typeContextDescriptorWrapper() async throws {
        let wrappers = try loadStructTestWrappers()
        let result = try acrossAllReaders(wrappers.file, wrappers.image) { wrapper in
            wrapper.typeContextDescriptorWrapper.contextDescriptor.offset
        }
        #expect(result == TypeContextWrapperBaseline.structTest.descriptorOffset)
    }

    /// `asPointerWrapper(in:)` is `MachOImage`-only. Smoke-test that the
    /// returned wrapper preserves the kind (`.struct`).
    @Test func asPointerWrapper() async throws {
        let (_, imageWrapper) = try loadStructTestWrappers()
        let pointerWrapper = try imageWrapper.asPointerWrapper(in: machOImage)
        #expect(pointerWrapper.isStruct == true)
    }

    /// `forTypeContextDescriptorWrapper(_:in:)` overloads (MachO + InProcess
    /// + ReadingContext) collapse to one MethodKey. The helper above
    /// exercises the ReadingContext overload over the file and image
    /// contexts; the image-context variant is exercised here as well.
    @Test func forTypeContextDescriptorWrapper() async throws {
        let imageDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOImage)
        let imageWrapperDescriptor = TypeContextDescriptorWrapper.struct(imageDescriptor)
        let imageCtxWrapper = try TypeContextWrapper.forTypeContextDescriptorWrapper(imageWrapperDescriptor, in: imageContext)
        #expect(imageCtxWrapper.isStruct == true)
        #expect(imageCtxWrapper.typeContextDescriptorWrapper.contextDescriptor.offset == TypeContextWrapperBaseline.structTest.descriptorOffset)
    }
}
