import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `AnonymousContextDescriptor`.
///
/// `AnonymousContextDescriptor` declares only `offset` and `layout`
/// directly (the `init(layout:offset:)` is filtered as a memberwise
/// synthesized initializer). Protocol-extension members (`mangledName(in:)`,
/// `hasMangledName`) live on `AnonymousContextDescriptorProtocol` and are
/// covered by `AnonymousContextDescriptorProtocolTests`.
@Suite
final class AnonymousContextDescriptorTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "AnonymousContextDescriptor"
    static var registeredTestMethodNames: Set<String> {
        AnonymousContextDescriptorBaseline.registeredTestMethodNames
    }

    @Test func offset() async throws {
        let fileSubject = try BaselineFixturePicker.anonymous_first(in: machOFile)
        let imageSubject = try BaselineFixturePicker.anonymous_first(in: machOImage)

        let result = try acrossAllReaders(
            file: { fileSubject.offset },
            image: { imageSubject.offset }
        )
        #expect(result == AnonymousContextDescriptorBaseline.firstAnonymous.offset)
    }

    @Test func layout() async throws {
        let fileSubject = try BaselineFixturePicker.anonymous_first(in: machOFile)
        let imageSubject = try BaselineFixturePicker.anonymous_first(in: machOImage)

        // Cross-reader equality on the only stable scalar field
        // (`flags.rawValue`); `parent` is a relative pointer whose value
        // varies by reader.
        let flagsRaw = try acrossAllReaders(
            file: { fileSubject.layout.flags.rawValue },
            image: { imageSubject.layout.flags.rawValue }
        )
        #expect(flagsRaw == AnonymousContextDescriptorBaseline.firstAnonymous.layoutFlagsRawValue)
    }
}
