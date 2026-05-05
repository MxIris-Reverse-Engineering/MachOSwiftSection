import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `ExtensionContextDescriptor`.
///
/// `ExtensionContextDescriptor` declares only `offset` and `layout`
/// directly (the `init(layout:offset:)` is filtered as memberwise-
/// synthesized). The protocol-extension `extendedContext(in:)` family of
/// overloads is attributed to `ExtensionContextDescriptorProtocol` by
/// `PublicMemberScanner` and is covered by
/// `ExtensionContextDescriptorProtocolTests`.
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
}
