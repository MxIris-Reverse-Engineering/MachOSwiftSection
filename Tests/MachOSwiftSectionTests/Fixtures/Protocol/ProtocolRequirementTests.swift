import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `ProtocolRequirement`.
///
/// Picker: `Protocols.ProtocolWitnessTableTest` — its 5 method
/// requirements (`a`/`b`/`c`/`d`/`e`) flesh out the trailing array; we
/// pick the first requirement and exercise its accessors.
///
/// `ProtocolBaseRequirement` (the second struct in the same file) gets
/// its own Suite (`ProtocolBaseRequirementTests`).
@Suite
final class ProtocolRequirementTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "ProtocolRequirement"
    static var registeredTestMethodNames: Set<String> {
        ProtocolRequirementBaseline.registeredTestMethodNames
    }

    private func loadFirstRequirements() throws -> (file: ProtocolRequirement, image: ProtocolRequirement) {
        let fileDescriptor = try BaselineFixturePicker.protocol_ProtocolWitnessTableTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.protocol_ProtocolWitnessTableTest(in: machOImage)
        let fileProtocol = try MachOSwiftSection.`Protocol`(descriptor: fileDescriptor, in: machOFile)
        let imageProtocol = try MachOSwiftSection.`Protocol`(descriptor: imageDescriptor, in: machOImage)
        let file = try required(fileProtocol.requirements.first)
        let image = try required(imageProtocol.requirements.first)
        return (file: file, image: image)
    }

    @Test func offset() async throws {
        let (file, image) = try loadFirstRequirements()
        let result = try acrossAllReaders(
            file: { file.offset },
            image: { image.offset }
        )
        #expect(result == ProtocolRequirementBaseline.firstRequirement.offset)
    }

    @Test func layout() async throws {
        let (file, image) = try loadFirstRequirements()
        let result = try acrossAllReaders(
            file: { file.layout.flags.rawValue },
            image: { image.layout.flags.rawValue }
        )
        #expect(result == ProtocolRequirementBaseline.firstRequirement.layoutFlagsRawValue)
    }

    @Test func defaultImplementationSymbols() async throws {
        let (file, image) = try loadFirstRequirements()
        let result = try acrossAllReaders(
            file: { (try file.defaultImplementationSymbols(in: machOFile)) != nil },
            image: { (try image.defaultImplementationSymbols(in: machOImage)) != nil }
        )
        #expect(result == ProtocolRequirementBaseline.firstRequirement.hasDefaultImplementation)

        // ReadingContext overload also exercised.
        let imageContextResult = (try image.defaultImplementationSymbols(in: imageContext)) != nil
        #expect(imageContextResult == ProtocolRequirementBaseline.firstRequirement.hasDefaultImplementation)
    }
}
