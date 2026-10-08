import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `ResilientWitness`.
///
/// Picker: the first `ProtocolConformance` from the fixture with a
/// non-empty `resilientWitnesses` array. We pick its first witness and
/// exercise the `requirement(in:)` resolution path over both readers'
/// contexts, the `implementationOffset` derived var (pinned as a literal),
/// and the implementation address in both forms: the ReadingContext
/// address from `implementationAddress(in:)` must equal the offset, and the
/// MachO-only debug formatter `implementationAddressString(in:)` must
/// produce a non-empty hex string.
@Suite
final class ResilientWitnessTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "ResilientWitness"
    static var registeredTestMethodNames: Set<String> {
        ResilientWitnessBaseline.registeredTestMethodNames
    }

    private func loadFirstWitnesses() throws -> (file: ResilientWitness, image: ResilientWitness) {
        let fileConformance = try BaselineFixturePicker.protocolConformance_resilientWitnessFirst(in: machOFile)
        let imageConformance = try BaselineFixturePicker.protocolConformance_resilientWitnessFirst(in: machOImage)
        let file = try required(fileConformance.resilientWitnesses.first)
        let image = try required(imageConformance.resilientWitnesses.first)
        return (file: file, image: image)
    }

    @Test func offset() async throws {
        let (file, image) = try loadFirstWitnesses()
        let result = try acrossAllReaders(
            file: { file.offset },
            image: { image.offset }
        )
        #expect(result == ResilientWitnessBaseline.firstWitness.offset)
    }

    @Test func layout() async throws {
        let (file, _) = try loadFirstWitnesses()
        // The layout carries `requirement` (relative-pointer pair) and
        // `implementation` (relative-direct pointer); we exercise their
        // accessibility — the resolution paths are exercised below.
        _ = file.layout.requirement
        _ = file.layout.implementation
    }

    @Test func requirement() async throws {
        let (file, image) = try loadFirstWitnesses()
        let result = try acrossAllContexts(
            file: { (try file.requirement(in: fileContext)) != nil },
            image: { (try image.requirement(in: imageContext)) != nil }
        )
        #expect(result == ResilientWitnessBaseline.firstWitness.hasRequirement)
    }

    @Test func implementationOffset() async throws {
        let (file, image) = try loadFirstWitnesses()
        let result = try acrossAllReaders(
            file: { file.implementationOffset },
            image: { image.implementationOffset }
        )
        #expect(result == ResilientWitnessBaseline.firstWitness.implementationOffset)
    }

    /// The ReadingContext form answers the typed location of the
    /// implementation, which for a Mach-O context is its offset.
    @Test func implementationAddress() async throws {
        let (file, image) = try loadFirstWitnesses()
        let fileContextAddress = try file.implementationAddress(in: fileContext)
        let imageContextAddress = try image.implementationAddress(in: imageContext)
        #expect(fileContextAddress == file.implementationOffset)
        #expect(imageContextAddress == image.implementationOffset)
        #expect(imageContextAddress == ResilientWitnessBaseline.firstWitness.implementationOffset)
    }

    /// `implementationAddressString(in:)` is a Mach-O display helper — we
    /// don't pin the address string (it differs between MachOFile vs
    /// MachOImage by file vs in-memory base), but we verify it produces
    /// non-empty hex from both readers.
    @Test func implementationAddressString() async throws {
        let (file, image) = try loadFirstWitnesses()
        let fileAddress = file.implementationAddressString(in: machOFile)
        let imageAddress = image.implementationAddressString(in: machOImage)
        #expect(fileAddress?.isEmpty == false)
        #expect(imageAddress?.isEmpty == false)
    }
}
