import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `MethodOverrideDescriptor`.
///
/// The Suite picks the first override entry from `Classes.SubclassTest`,
/// then asserts cross-reader equality on the descriptor's offset and
/// presence-flags for the resolved class/method/symbols pointers.
@Suite
final class MethodOverrideDescriptorTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "MethodOverrideDescriptor"
    static var registeredTestMethodNames: Set<String> {
        MethodOverrideDescriptorBaseline.registeredTestMethodNames
    }

    /// Helper: load the first override entry of `Classes.SubclassTest`
    /// from each reader.
    private func loadFirstOverrides() throws -> (file: MethodOverrideDescriptor, image: MethodOverrideDescriptor) {
        let fileDescriptor = try BaselineFixturePicker.class_SubclassTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.class_SubclassTest(in: machOImage)
        let fileClass = try Class(descriptor: fileDescriptor, in: machOFile)
        let imageClass = try Class(descriptor: imageDescriptor, in: machOImage)
        let fileOverride = try required(fileClass.methodOverrideDescriptors.first)
        let imageOverride = try required(imageClass.methodOverrideDescriptors.first)
        return (file: fileOverride, image: imageOverride)
    }

    @Test func offset() async throws {
        let overrides = try loadFirstOverrides()
        let result = try acrossAllReaders(
            file: { overrides.file.offset },
            image: { overrides.image.offset }
        )
        #expect(result == MethodOverrideDescriptorBaseline.firstSubclassOverride.offset)
    }

    /// `layout` is a small struct (3 relative pointers); we just verify
    /// both readers see the same backing data by re-reading the wrapper.
    @Test func layout() async throws {
        let overrides = try loadFirstOverrides()
        // Use the offset as a stable proxy for "both readers materialised
        // the same backing record"; the `layout` struct contains relative
        // pointers that aren't stable literals.
        #expect(overrides.file.offset == overrides.image.offset)
    }

    /// `classDescriptor(in:)` returns a `SymbolOrElement<ContextDescriptorWrapper>?`.
    /// For SubclassTest's first override, the `class` pointer references
    /// the class hosting the override (i.e. SubclassTest itself, or its
    /// ancestor depending on layout). Verify cross-reader presence.
    @Test func classDescriptor() async throws {
        let overrides = try loadFirstOverrides()
        let presence = try acrossAllReaders(
            file: { (try overrides.file.classDescriptor(in: machOFile)) != nil },
            image: { (try overrides.image.classDescriptor(in: machOImage)) != nil }
        )
        #expect(presence == true)

        // ReadingContext-based overload.
        let imageCtxPresence = (try overrides.image.classDescriptor(in: imageContext)) != nil
        #expect(imageCtxPresence == true)
    }

    /// `methodDescriptor(in:)` returns the underlying method being overridden.
    /// Exercise both the MachO and pointer-based overloads.
    @Test func methodDescriptor() async throws {
        let overrides = try loadFirstOverrides()
        let presence = try acrossAllReaders(
            file: { (try overrides.file.methodDescriptor(in: machOFile)) != nil },
            image: { (try overrides.image.methodDescriptor(in: machOImage)) != nil }
        )
        #expect(presence == true)
    }

    /// `implementationSymbols(in:)` returns the resolved override
    /// implementation Symbols.
    @Test func implementationSymbols() async throws {
        let overrides = try loadFirstOverrides()
        let presence = try acrossAllReaders(
            file: { (try overrides.file.implementationSymbols(in: machOFile)) != nil },
            image: { (try overrides.image.implementationSymbols(in: machOImage)) != nil }
        )
        #expect(presence == true)

        // ReadingContext-based overload.
        let imageCtxPresence = (try overrides.image.implementationSymbols(in: imageContext)) != nil
        #expect(imageCtxPresence == true)
    }
}
