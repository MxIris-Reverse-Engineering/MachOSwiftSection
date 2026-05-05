import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `MethodDescriptor`.
///
/// The Suite picks the first vtable entry from `Classes.ClassTest`, then
/// asserts cross-reader equality on the descriptor's offset and the
/// `flags.rawValue`. The `implementationSymbols` accessor is exercised
/// via cross-reader presence.
@Suite
final class MethodDescriptorTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "MethodDescriptor"
    static var registeredTestMethodNames: Set<String> {
        MethodDescriptorBaseline.registeredTestMethodNames
    }

    /// Helper: load the first vtable entry of `Classes.ClassTest` from
    /// each reader.
    private func loadFirstMethods() throws -> (file: MethodDescriptor, image: MethodDescriptor) {
        let fileDescriptor = try BaselineFixturePicker.class_ClassTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.class_ClassTest(in: machOImage)
        let fileClass = try Class(descriptor: fileDescriptor, in: machOFile)
        let imageClass = try Class(descriptor: imageDescriptor, in: machOImage)
        let fileMethod = try required(fileClass.methodDescriptors.first)
        let imageMethod = try required(imageClass.methodDescriptors.first)
        return (file: fileMethod, image: imageMethod)
    }

    @Test func offset() async throws {
        let methods = try loadFirstMethods()
        let result = try acrossAllReaders(
            file: { methods.file.offset },
            image: { methods.image.offset }
        )
        #expect(result == MethodDescriptorBaseline.firstClassTestMethod.offset)
    }

    @Test func layout() async throws {
        let methods = try loadFirstMethods()
        let flagsRaw = try acrossAllReaders(
            file: { methods.file.layout.flags.rawValue },
            image: { methods.image.layout.flags.rawValue }
        )
        #expect(flagsRaw == MethodDescriptorBaseline.firstClassTestMethod.layoutFlagsRawValue)
    }

    /// `implementationSymbols(in:)` returns the resolved Symbols (or nil).
    /// Exercise cross-reader presence; the underlying Symbols object is
    /// not cheaply Equatable so we don't compare values directly.
    @Test func implementationSymbols() async throws {
        let methods = try loadFirstMethods()
        let presence = try acrossAllReaders(
            file: { (try methods.file.implementationSymbols(in: machOFile)) != nil },
            image: { (try methods.image.implementationSymbols(in: machOImage)) != nil }
        )
        // The first vtable entry of ClassTest resolves to a real symbol.
        #expect(presence == true)

        // ReadingContext-based overload.
        let imageCtxPresence = (try methods.image.implementationSymbols(in: imageContext)) != nil
        #expect(imageCtxPresence == true)
    }
}
