import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `ExtensionContextDescriptorProtocol`.
///
/// The protocol provides the `extendedContext(in:)` family of overloads
/// (MachO, InProcess, ReadingContext). The MangledName payload is a deep
/// ABI tree we don't embed as a literal; instead we verify cross-reader-
/// consistent results at runtime against the presence flag in the
/// baseline.
@Suite
final class ExtensionContextDescriptorProtocolTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "ExtensionContextDescriptorProtocol"
    static var registeredTestMethodNames: Set<String> {
        ExtensionContextDescriptorProtocolBaseline.registeredTestMethodNames
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
        #expect(presence == ExtensionContextDescriptorProtocolBaseline.firstExtension.hasExtendedContext)

        // Also exercise the ReadingContext-based overload to ensure the
        // third reader axis agrees.
        let imageCtxPresence = (try imageSubject.extendedContext(in: imageContext)) != nil
        #expect(imageCtxPresence == ExtensionContextDescriptorProtocolBaseline.firstExtension.hasExtendedContext)
    }
}
