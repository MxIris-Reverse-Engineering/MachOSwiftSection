import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `ProtocolContextDescriptorFlags`.
///
/// `ProtocolContextDescriptorFlags` is the kind-specific 16-bit `FlagSet`
/// reachable via `ContextDescriptorFlags.kindSpecificFlags?.protocolFlags`.
/// We exercise it against `Protocols.ProtocolTest` whose kind-specific
/// flags slot resolves to a real value.
@Suite
final class ProtocolContextDescriptorFlagsTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "ProtocolContextDescriptorFlags"
    static var registeredTestMethodNames: Set<String> {
        ProtocolContextDescriptorFlagsBaseline.registeredTestMethodNames
    }

    private func loadProtocolTestFlags() throws -> (file: ProtocolContextDescriptorFlags, image: ProtocolContextDescriptorFlags) {
        let fileDescriptor = try BaselineFixturePicker.protocol_ProtocolTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.protocol_ProtocolTest(in: machOImage)
        let file = try required(fileDescriptor.layout.flags.kindSpecificFlags?.protocolFlags)
        let image = try required(imageDescriptor.layout.flags.kindSpecificFlags?.protocolFlags)
        return (file: file, image: image)
    }

    @Test func rawValue() async throws {
        let flags = try loadProtocolTestFlags()
        let result = try acrossAllReaders(
            file: { flags.file.rawValue },
            image: { flags.image.rawValue }
        )
        #expect(result == ProtocolContextDescriptorFlagsBaseline.protocolTest.rawValue)
    }

    @Test("init(rawValue:)") func initializerWithRawValue() async throws {
        // Round-trip: re-construct the flags from the baseline rawValue and
        // verify the derived accessors agree.
        let constructed = ProtocolContextDescriptorFlags(
            rawValue: ProtocolContextDescriptorFlagsBaseline.protocolTest.rawValue
        )
        #expect(constructed.rawValue == ProtocolContextDescriptorFlagsBaseline.protocolTest.rawValue)
        #expect(constructed.isResilient == ProtocolContextDescriptorFlagsBaseline.protocolTest.isResilient)
        #expect(constructed.classConstraint.rawValue == ProtocolContextDescriptorFlagsBaseline.protocolTest.classConstraintRawValue)
        #expect(constructed.specialProtocolKind.rawValue == ProtocolContextDescriptorFlagsBaseline.protocolTest.specialProtocolKindRawValue)
    }

    @Test func isResilient() async throws {
        let flags = try loadProtocolTestFlags()
        let result = try acrossAllReaders(
            file: { flags.file.isResilient },
            image: { flags.image.isResilient }
        )
        #expect(result == ProtocolContextDescriptorFlagsBaseline.protocolTest.isResilient)
    }

    @Test func classConstraint() async throws {
        let flags = try loadProtocolTestFlags()
        let result = try acrossAllReaders(
            file: { flags.file.classConstraint.rawValue },
            image: { flags.image.classConstraint.rawValue }
        )
        #expect(result == ProtocolContextDescriptorFlagsBaseline.protocolTest.classConstraintRawValue)
    }

    @Test func specialProtocolKind() async throws {
        let flags = try loadProtocolTestFlags()
        let result = try acrossAllReaders(
            file: { flags.file.specialProtocolKind.rawValue },
            image: { flags.image.specialProtocolKind.rawValue }
        )
        #expect(result == ProtocolContextDescriptorFlagsBaseline.protocolTest.specialProtocolKindRawValue)
    }
}
