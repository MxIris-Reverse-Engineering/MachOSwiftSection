import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `ProtocolBaseRequirement`.
///
/// `ProtocolBaseRequirement` is the empty-layout marker companion to
/// `ProtocolRequirement` (both declared in `ProtocolRequirement.swift`).
/// We pick a live instance via `Protocols.ProtocolWitnessTableTest`'s
/// `baseRequirement` slot.
@Suite
final class ProtocolBaseRequirementTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "ProtocolBaseRequirement"
    static var registeredTestMethodNames: Set<String> {
        ProtocolBaseRequirementBaseline.registeredTestMethodNames
    }

    private func loadBaseRequirements() throws -> (file: ProtocolBaseRequirement, image: ProtocolBaseRequirement) {
        let fileDescriptor = try BaselineFixturePicker.protocol_ProtocolWitnessTableTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.protocol_ProtocolWitnessTableTest(in: machOImage)
        let fileProtocol = try MachOSwiftSection.`Protocol`(descriptor: fileDescriptor, in: machOFile)
        let imageProtocol = try MachOSwiftSection.`Protocol`(descriptor: imageDescriptor, in: machOImage)
        let file = try required(fileProtocol.baseRequirement)
        let image = try required(imageProtocol.baseRequirement)
        return (file: file, image: image)
    }

    @Test func offset() async throws {
        let (file, image) = try loadBaseRequirements()
        let result = try acrossAllReaders(
            file: { file.offset },
            image: { image.offset }
        )
        #expect(result == ProtocolBaseRequirementBaseline.witnessTableTest.offset)
    }

    @Test func layout() async throws {
        let (file, _) = try loadBaseRequirements()
        // The `Layout` is empty; verify the property is accessible (compile-
        // time check, since the type carries no scalar fields).
        _ = file.layout
    }
}
