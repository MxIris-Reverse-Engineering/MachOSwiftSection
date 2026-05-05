import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `ContextDescriptorFlags`.
///
/// The flags type is the bit-packed `OptionSet` carried in the first 4 bytes
/// of every descriptor. We sample it off `Structs.StructTest`'s descriptor.
/// The three static `let`s (`hasInvertibleProtocols`, `isUnique`, `isGeneric`)
/// collapse with their same-named instance vars under PublicMemberScanner's
/// name-only key; we register one entry per name and exercise the
/// instance-derivation path here.
@Suite
final class ContextDescriptorFlagsTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "ContextDescriptorFlags"
    static var registeredTestMethodNames: Set<String> {
        ContextDescriptorFlagsBaseline.registeredTestMethodNames
    }

    /// Helper: extract the `ContextDescriptorFlags` from
    /// `Structs.StructTest`'s descriptor against both readers.
    private func loadStructTestFlags() throws -> (file: ContextDescriptorFlags, image: ContextDescriptorFlags) {
        let fileDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOImage)
        return (file: fileDescriptor.layout.flags, image: imageDescriptor.layout.flags)
    }

    @Test func rawValue() async throws {
        let flags = try loadStructTestFlags()
        let result = try acrossAllReaders(
            file: { flags.file.rawValue },
            image: { flags.image.rawValue }
        )
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
        let result = try acrossAllReaders(
            file: { flags.file.kind.rawValue },
            image: { flags.image.kind.rawValue }
        )
        #expect(result == ContextDescriptorFlagsBaseline.structTest.kindRawValue)
    }

    @Test func version() async throws {
        let flags = try loadStructTestFlags()
        let result = try acrossAllReaders(
            file: { flags.file.version },
            image: { flags.image.version }
        )
        #expect(result == ContextDescriptorFlagsBaseline.structTest.version)
    }

    @Test func kindSpecificFlagsRawValue() async throws {
        let flags = try loadStructTestFlags()
        let result = try acrossAllReaders(
            file: { flags.file.kindSpecificFlagsRawValue },
            image: { flags.image.kindSpecificFlagsRawValue }
        )
        #expect(result == ContextDescriptorFlagsBaseline.structTest.kindSpecificFlagsRawValue)
    }

    @Test func kindSpecificFlags() async throws {
        let flags = try loadStructTestFlags()
        // `kindSpecificFlags` returns `ContextDescriptorKindSpecificFlags?`,
        // which isn't trivially Equatable. Use presence-only assertion.
        let presence = try acrossAllReaders(
            file: { flags.file.kindSpecificFlags != nil },
            image: { flags.image.kindSpecificFlags != nil }
        )
        #expect(presence == ContextDescriptorFlagsBaseline.structTest.hasKindSpecificFlags)
    }

    @Test func hasInvertibleProtocols() async throws {
        let flags = try loadStructTestFlags()
        let result = try acrossAllReaders(
            file: { flags.file.hasInvertibleProtocols },
            image: { flags.image.hasInvertibleProtocols }
        )
        #expect(result == ContextDescriptorFlagsBaseline.structTest.hasInvertibleProtocols)
    }

    @Test func isUnique() async throws {
        let flags = try loadStructTestFlags()
        let result = try acrossAllReaders(
            file: { flags.file.isUnique },
            image: { flags.image.isUnique }
        )
        #expect(result == ContextDescriptorFlagsBaseline.structTest.isUnique)
    }

    @Test func isGeneric() async throws {
        let flags = try loadStructTestFlags()
        let result = try acrossAllReaders(
            file: { flags.file.isGeneric },
            image: { flags.image.isGeneric }
        )
        #expect(result == ContextDescriptorFlagsBaseline.structTest.isGeneric)
    }
}
