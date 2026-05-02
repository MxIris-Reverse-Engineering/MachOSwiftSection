import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `ContextWrapper`.
///
/// `ContextWrapper` is the high-level sum type covering all context wrappers
/// (analogous to `ContextDescriptorWrapper`). Members include `context`
/// (the unified projection), the static `forContextDescriptorWrapper(_:in:)`
/// constructor family, and `parent(in:)`.
///
/// Picker: route `Structs.StructTest`'s descriptor through
/// `ContextWrapper.forContextDescriptorWrapper` to produce a
/// `.type(.struct(...))` wrapper.
@Suite
final class ContextWrapperTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "ContextWrapper"
    static var registeredTestMethodNames: Set<String> {
        ContextWrapperBaseline.registeredTestMethodNames
    }

    /// Helper: build a `ContextWrapper` of the `Structs.StructTest`
    /// descriptor against both readers via
    /// `forContextDescriptorWrapper(_:in:)`.
    private func loadStructTestWrappers() throws -> (file: ContextWrapper, image: ContextWrapper) {
        let fileDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOImage)
        let fileWrapper = try ContextWrapper.forContextDescriptorWrapper(.type(.struct(fileDescriptor)), in: machOFile)
        let imageWrapper = try ContextWrapper.forContextDescriptorWrapper(.type(.struct(imageDescriptor)), in: machOImage)
        return (file: fileWrapper, image: imageWrapper)
    }

    @Test func context() async throws {
        let wrappers = try loadStructTestWrappers()
        // `context` projects to `any ContextProtocol`; the descriptor's
        // `offset` is the cross-reader-stable scalar.
        let result = try acrossAllReaders(
            file: { wrappers.file.context.descriptor.offset },
            image: { wrappers.image.context.descriptor.offset }
        )
        #expect(result == ContextWrapperBaseline.structTest.descriptorOffset)
    }

    @Test func forContextDescriptorWrapper() async throws {
        let fileDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOImage)

        // All three overloads (MachO, ReadingContext, InProcess) collapse to
        // a single MethodKey. Exercise each path and assert the resulting
        // wrapper's descriptor offset matches the baseline.
        let fileWrapper = try ContextWrapper.forContextDescriptorWrapper(.type(.struct(fileDescriptor)), in: machOFile)
        let imageWrapper = try ContextWrapper.forContextDescriptorWrapper(.type(.struct(imageDescriptor)), in: machOImage)
        let imageCtxWrapper = try ContextWrapper.forContextDescriptorWrapper(.type(.struct(imageDescriptor)), in: imageContext)

        #expect(fileWrapper.context.descriptor.offset == ContextWrapperBaseline.structTest.descriptorOffset)
        #expect(imageWrapper.context.descriptor.offset == ContextWrapperBaseline.structTest.descriptorOffset)
        #expect(imageCtxWrapper.context.descriptor.offset == ContextWrapperBaseline.structTest.descriptorOffset)
    }

    @Test func parent() async throws {
        let wrappers = try loadStructTestWrappers()
        let presence = try acrossAllReaders(
            file: { (try wrappers.file.parent(in: machOFile)) != nil },
            image: { (try wrappers.image.parent(in: machOImage)) != nil }
        )
        #expect(presence == ContextWrapperBaseline.structTest.hasParent)

        // ReadingContext-based overload also exercised.
        let imageCtxPresence = (try wrappers.image.parent(in: imageContext)) != nil
        #expect(imageCtxPresence == ContextWrapperBaseline.structTest.hasParent)
    }
}
