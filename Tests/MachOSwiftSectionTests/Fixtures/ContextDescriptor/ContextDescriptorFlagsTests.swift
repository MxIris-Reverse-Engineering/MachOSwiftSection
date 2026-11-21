import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftSectionTestingSupport
import SwiftSectionFixtureSupport

/// Fixture-based Suite for `ContextDescriptorFlags`.
///
/// The flags type is the bit-packed `OptionSet` carried in the first 4 bytes
/// of every descriptor. We sample it off `Structs.StructTest`'s descriptor.
/// The three static `let`s (`hasInvertibleProtocols`, `isUnique`, `isGeneric`)
/// collapse with their same-named instance vars under PublicMemberScanner's
/// name-only key; we register one entry per name and exercise the
/// instance-derivation path here.
@Suite
@FixtureSuite
final class ContextDescriptorFlagsTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
    /// Helper: extract the `ContextDescriptorFlags` from
    /// `Structs.StructTest`'s descriptor against both readers.
    private func loadStructTestFlags() throws -> (file: ContextDescriptorFlags, image: ContextDescriptorFlags) {
        let fileDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOImage)
        return (file: fileDescriptor.layout.flags, image: imageDescriptor.layout.flags)
    }

    @Test func rawValue() async throws {
        let flags = try loadStructTestFlags()
        let result = try acrossAllReaders(flags.file, flags.image) { $0.rawValue }
        #expect(result == ContextDescriptorFlagsBaseline.structTest.rawValue)
    }

    @Test("init(rawValue:)") func initializerWithRawValue() async throws {
        // Round-trip construction: `init(rawValue:)` must reproduce the
        // baseline's stored rawValue verbatim, and the derived accessors
        // (`kind`, `version`, etc.) must match the live extraction.
        let constructed = ContextDescriptorFlags(
            rawValue: ContextDescriptorFlagsBaseline.structTest.rawValue
        )
        #expect(constructed.rawValue == ContextDescriptorFlagsBaseline.structTest.rawValue)
        #expect(constructed.kind.rawValue == ContextDescriptorFlagsBaseline.structTest.kindRawValue)
        #expect(constructed.version == ContextDescriptorFlagsBaseline.structTest.version)
        #expect(constructed.kindSpecificFlagsRawValue == ContextDescriptorFlagsBaseline.structTest.kindSpecificFlagsRawValue)
        #expect(constructed.hasInvertibleProtocols == ContextDescriptorFlagsBaseline.structTest.hasInvertibleProtocols)
        #expect(constructed.isUnique == ContextDescriptorFlagsBaseline.structTest.isUnique)
        #expect(constructed.isGeneric == ContextDescriptorFlagsBaseline.structTest.isGeneric)
    }

    @Test func kind() async throws {
        let flags = try loadStructTestFlags()
        let result = try acrossAllReaders(flags.file, flags.image) { $0.kind.rawValue }
        #expect(result == ContextDescriptorFlagsBaseline.structTest.kindRawValue)
    }

    @Test func version() async throws {
        let flags = try loadStructTestFlags()
        let result = try acrossAllReaders(flags.file, flags.image) { $0.version }
        #expect(result == ContextDescriptorFlagsBaseline.structTest.version)
    }

    @Test func kindSpecificFlagsRawValue() async throws {
        let flags = try loadStructTestFlags()
        let result = try acrossAllReaders(flags.file, flags.image) { $0.kindSpecificFlagsRawValue }
        #expect(result == ContextDescriptorFlagsBaseline.structTest.kindSpecificFlagsRawValue)
    }

    @Test func kindSpecificFlags() async throws {
        let flags = try loadStructTestFlags()
        // `kindSpecificFlags` returns `ContextDescriptorKindSpecificFlags?`,
        // which isn't trivially Equatable. Use presence-only assertion.
        let presence = try acrossAllReaders(flags.file, flags.image) { $0.kindSpecificFlags != nil }
        #expect(presence == ContextDescriptorFlagsBaseline.structTest.hasKindSpecificFlags)
    }

    @Test func hasInvertibleProtocols() async throws {
        let flags = try loadStructTestFlags()
        let result = try acrossAllReaders(flags.file, flags.image) { $0.hasInvertibleProtocols }
        #expect(result == ContextDescriptorFlagsBaseline.structTest.hasInvertibleProtocols)
    }

    @Test func isUnique() async throws {
        let flags = try loadStructTestFlags()
        let result = try acrossAllReaders(flags.file, flags.image) { $0.isUnique }
        #expect(result == ContextDescriptorFlagsBaseline.structTest.isUnique)
    }

    @Test func isGeneric() async throws {
        let flags = try loadStructTestFlags()
        let result = try acrossAllReaders(flags.file, flags.image) { $0.isGeneric }
        #expect(result == ContextDescriptorFlagsBaseline.structTest.isGeneric)
    }
}
