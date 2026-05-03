import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `ProtocolRequirementFlags`.
///
/// `ProtocolRequirementFlags` is a 32-bit `OptionSet` packing the
/// requirement kind in its low nibble plus an `isInstance` and
/// `maybeAsync` bit. The Suite uses a live witness-table requirement
/// for the `kind = .method` branch and synthetic raw values for the
/// remaining branches.
@Suite
final class ProtocolRequirementFlagsTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "ProtocolRequirementFlags"
    static var registeredTestMethodNames: Set<String> {
        ProtocolRequirementFlagsBaseline.registeredTestMethodNames
    }

    private func loadFirstRequirementFlags() throws -> (file: ProtocolRequirementFlags, image: ProtocolRequirementFlags) {
        let fileDescriptor = try BaselineFixturePicker.protocol_ProtocolWitnessTableTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.protocol_ProtocolWitnessTableTest(in: machOImage)
        let fileProtocol = try MachOSwiftSection.`Protocol`(descriptor: fileDescriptor, in: machOFile)
        let imageProtocol = try MachOSwiftSection.`Protocol`(descriptor: imageDescriptor, in: machOImage)
        let file = try required(fileProtocol.requirements.first?.layout.flags)
        let image = try required(imageProtocol.requirements.first?.layout.flags)
        return (file: file, image: image)
    }

    @Test("init(rawValue:)") func initializerWithRawValue() async throws {
        let flags = ProtocolRequirementFlags(rawValue: ProtocolRequirementFlagsBaseline.witnessTableMethod.rawValue)
        #expect(flags.rawValue == ProtocolRequirementFlagsBaseline.witnessTableMethod.rawValue)
    }

    @Test func rawValue() async throws {
        let (file, image) = try loadFirstRequirementFlags()
        let result = try acrossAllReaders(
            file: { file.rawValue },
            image: { image.rawValue }
        )
        #expect(result == ProtocolRequirementFlagsBaseline.witnessTableMethod.rawValue)
    }

    @Test func kind() async throws {
        let (file, image) = try loadFirstRequirementFlags()
        let result = try acrossAllReaders(
            file: { file.kind.rawValue },
            image: { image.kind.rawValue }
        )
        #expect(result == ProtocolRequirementFlagsBaseline.witnessTableMethod.kindRawValue)
    }

    @Test func isCoroutine() async throws {
        let (file, image) = try loadFirstRequirementFlags()
        let result = try acrossAllReaders(
            file: { file.isCoroutine },
            image: { image.isCoroutine }
        )
        #expect(result == ProtocolRequirementFlagsBaseline.witnessTableMethod.isCoroutine)

        // Synthetic: read coroutine kind sets isCoroutine.
        let coroutineFlags = ProtocolRequirementFlags(rawValue: ProtocolRequirementFlagsBaseline.readCoroutine.rawValue)
        #expect(coroutineFlags.isCoroutine == ProtocolRequirementFlagsBaseline.readCoroutine.isCoroutine)
    }

    @Test func isAsync() async throws {
        let (file, image) = try loadFirstRequirementFlags()
        let result = try acrossAllReaders(
            file: { file.isAsync },
            image: { image.isAsync }
        )
        #expect(result == ProtocolRequirementFlagsBaseline.witnessTableMethod.isAsync)

        // Synthetic: method + maybeAsync sets isAsync.
        let asyncFlags = ProtocolRequirementFlags(rawValue: ProtocolRequirementFlagsBaseline.methodAsync.rawValue)
        #expect(asyncFlags.isAsync == ProtocolRequirementFlagsBaseline.methodAsync.isAsync)
    }

    @Test func isInstance() async throws {
        let (file, image) = try loadFirstRequirementFlags()
        let result = try acrossAllReaders(
            file: { file.isInstance },
            image: { image.isInstance }
        )
        #expect(result == ProtocolRequirementFlagsBaseline.witnessTableMethod.isInstance)
    }

    /// `.maybeAsync` is a static OptionSet member; assert its raw value
    /// matches the documented bit pattern (0x20).
    @Test func maybeAsync() async throws {
        #expect(ProtocolRequirementFlags.maybeAsync.rawValue == 0x20)
    }
}
