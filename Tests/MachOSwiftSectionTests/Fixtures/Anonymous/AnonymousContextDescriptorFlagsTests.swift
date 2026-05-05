import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `AnonymousContextDescriptorFlags`.
///
/// The flags type is a small `FlagSet` value-type whose instances are
/// stored inside a descriptor's `layout.flags.kindSpecificFlags`. We
/// extract the live instance from the fixture's first anonymous
/// descriptor and assert the `rawValue` and the derived `hasMangledName`
/// match the baseline; we also verify the `init(rawValue:)` round-trip.
@Suite
final class AnonymousContextDescriptorFlagsTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "AnonymousContextDescriptorFlags"
    static var registeredTestMethodNames: Set<String> {
        AnonymousContextDescriptorFlagsBaseline.registeredTestMethodNames
    }

    /// Helper: extract the `AnonymousContextDescriptorFlags` from the
    /// fixture's first anonymous descriptor against both readers.
    private func loadFirstFlags() throws -> (file: AnonymousContextDescriptorFlags, image: AnonymousContextDescriptorFlags) {
        let fileDescriptor = try BaselineFixturePicker.anonymous_first(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.anonymous_first(in: machOImage)
        let fileFlags = try required(fileDescriptor.layout.flags.kindSpecificFlags?.anonymousFlags)
        let imageFlags = try required(imageDescriptor.layout.flags.kindSpecificFlags?.anonymousFlags)
        return (file: fileFlags, image: imageFlags)
    }

    @Test func rawValue() async throws {
        let flags = try loadFirstFlags()
        let result = try acrossAllReaders(
            file: { flags.file.rawValue },
            image: { flags.image.rawValue }
        )
        #expect(result == AnonymousContextDescriptorFlagsBaseline.firstAnonymous.rawValue)
    }

    @Test("init(rawValue:)") func initializerWithRawValue() async throws {
        // Round-trip construction: `init(rawValue:)` must reproduce the
        // baseline's stored rawValue verbatim, and the derived
        // `hasMangledName` must match the live extraction.
        let constructed = AnonymousContextDescriptorFlags(
            rawValue: AnonymousContextDescriptorFlagsBaseline.firstAnonymous.rawValue
        )
        #expect(constructed.rawValue == AnonymousContextDescriptorFlagsBaseline.firstAnonymous.rawValue)
        #expect(constructed.hasMangledName == AnonymousContextDescriptorFlagsBaseline.firstAnonymous.hasMangledName)
    }

    @Test func hasMangledName() async throws {
        let flags = try loadFirstFlags()
        let result = try acrossAllReaders(
            file: { flags.file.hasMangledName },
            image: { flags.image.hasMangledName }
        )
        #expect(result == AnonymousContextDescriptorFlagsBaseline.firstAnonymous.hasMangledName)
    }
}
