import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftSectionTestingSupport
import SwiftSectionFixtureSupport

/// Fixture-based Suite for `ProtocolRequirementFlags`.
///
/// `ProtocolRequirementFlags` is a 32-bit `OptionSet` packing the
/// requirement kind in its low nibble plus an `isInstance` and
/// `maybeAsync` bit. The Suite uses a live witness-table requirement
/// for the `kind = .method` branch and synthetic raw values for the
/// remaining branches.
@Suite
@FixtureSuite
final class ProtocolRequirementFlagsTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
    private func loadFirstRequirementFlags() throws -> (file: ProtocolRequirementFlags, image: ProtocolRequirementFlags) {
        let fileDescriptor = try BaselineFixturePicker.protocol_ProtocolWitnessTableTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.protocol_ProtocolWitnessTableTest(in: machOImage)
        let fileProtocol = try MachOSwiftSection.`Protocol`(descriptor: fileDescriptor, in: fileContext)
        let imageProtocol = try MachOSwiftSection.`Protocol`(descriptor: imageDescriptor, in: imageContext)
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
        let result = try acrossAllReaders(file, image) { $0.rawValue }
        #expect(result == ProtocolRequirementFlagsBaseline.witnessTableMethod.rawValue)
    }

    @Test func kind() async throws {
        let (file, image) = try loadFirstRequirementFlags()
        let result = try acrossAllReaders(file, image) { $0.kind?.rawValue }
        #expect(result == ProtocolRequirementFlagsBaseline.witnessTableMethod.kindRawValue)
    }

    @Test func isCoroutine() async throws {
        let (file, image) = try loadFirstRequirementFlags()
        let result = try acrossAllReaders(file, image) { $0.isCoroutine }
        #expect(result == ProtocolRequirementFlagsBaseline.witnessTableMethod.isCoroutine)

        // Synthetic: read coroutine kind sets isCoroutine.
        let coroutineFlags = ProtocolRequirementFlags(rawValue: ProtocolRequirementFlagsBaseline.readCoroutine.rawValue)
        #expect(coroutineFlags.isCoroutine == ProtocolRequirementFlagsBaseline.readCoroutine.isCoroutine)
    }

    @Test func isAsync() async throws {
        let (file, image) = try loadFirstRequirementFlags()
        let result = try acrossAllReaders(file, image) { $0.isAsync }
        #expect(result == ProtocolRequirementFlagsBaseline.witnessTableMethod.isAsync)

        // Synthetic: method + maybeAsync sets isAsync.
        let asyncFlags = ProtocolRequirementFlags(rawValue: ProtocolRequirementFlagsBaseline.methodAsync.rawValue)
        #expect(asyncFlags.isAsync == ProtocolRequirementFlagsBaseline.methodAsync.isAsync)
    }

    @Test func isInstance() async throws {
        let (file, image) = try loadFirstRequirementFlags()
        let result = try acrossAllReaders(file, image) { $0.isInstance }
        #expect(result == ProtocolRequirementFlagsBaseline.witnessTableMethod.isInstance)
    }

    /// `.maybeAsync` is a static OptionSet member; assert its raw value
    /// matches the documented bit pattern (0x20).
    @Test func maybeAsync() async throws {
        #expect(ProtocolRequirementFlags.maybeAsync.rawValue == 0x20)
    }
}
