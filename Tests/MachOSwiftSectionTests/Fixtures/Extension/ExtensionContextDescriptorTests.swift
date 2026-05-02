import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `ExtensionContextDescriptor`.
///
/// `ExtensionContextDescriptor` declares `offset`, `layout`, and the
/// `extendedContext(in:)` family of overloads as protocol-extension
/// methods on `ExtensionContextDescriptorProtocol` (declared in this
/// file). The `init(layout:offset:)` is filtered as memberwise-synthesized.
@Suite
final class ExtensionContextDescriptorTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "ExtensionContextDescriptor"
    static var registeredTestMethodNames: Set<String> {
        ExtensionContextDescriptorBaseline.registeredTestMethodNames
    }

    @Test func offset() async throws {
        let fileSubject = try BaselineFixturePicker.extension_first(in: machOFile)
        let imageSubject = try BaselineFixturePicker.extension_first(in: machOImage)

        let result = try acrossAllReaders(
            file: { fileSubject.offset },
            image: { imageSubject.offset }
        )
        #expect(result == ExtensionContextDescriptorBaseline.firstExtension.offset)
    }

    @Test func layout() async throws {
        let fileSubject = try BaselineFixturePicker.extension_first(in: machOFile)
        let imageSubject = try BaselineFixturePicker.extension_first(in: machOImage)

        let flagsRaw = try acrossAllReaders(
            file: { fileSubject.layout.flags.rawValue },
            image: { imageSubject.layout.flags.rawValue }
        )
        #expect(flagsRaw == ExtensionContextDescriptorBaseline.firstExtension.layoutFlagsRawValue)
    }

    @Test func extendedContext() async throws {
        let fileSubject = try BaselineFixturePicker.extension_first(in: machOFile)
        let imageSubject = try BaselineFixturePicker.extension_first(in: machOImage)

        // Cross-reader equality on the *presence* of the extended-context
        // mangled name. The MangledName tree itself is Hashable but we
        // record presence-only in the baseline for parity with the
        // wrapper Suite.
        let presence = try acrossAllReaders(
            file: { (try fileSubject.extendedContext(in: machOFile)) != nil },
            image: { (try imageSubject.extendedContext(in: machOImage)) != nil }
        )
        #expect(presence == ExtensionContextDescriptorBaseline.firstExtension.hasExtendedContext)

        // Also exercise the ReadingContext-based overload to ensure the
        // third reader axis agrees.
        let imageCtxPresence = (try imageSubject.extendedContext(in: imageContext)) != nil
        #expect(imageCtxPresence == ExtensionContextDescriptorBaseline.firstExtension.hasExtendedContext)
    }
}
