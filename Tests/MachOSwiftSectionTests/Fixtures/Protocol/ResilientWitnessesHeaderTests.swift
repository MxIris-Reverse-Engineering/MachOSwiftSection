import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftSectionTestingSupport
import SwiftSectionFixtureSupport

/// Fixture-based Suite for `ResilientWitnessesHeader`.
///
/// Picker: the first `ProtocolConformance` from the fixture with a
/// non-empty `resilientWitnesses` array (so the header materializes).
@Suite
@FixtureSuite
final class ResilientWitnessesHeaderTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
    private func loadFirstHeaders() throws -> (file: ResilientWitnessesHeader, image: ResilientWitnessesHeader) {
        let fileConformance = try BaselineFixturePicker.protocolConformance_resilientWitnessFirst(in: machOFile)
        let imageConformance = try BaselineFixturePicker.protocolConformance_resilientWitnessFirst(in: machOImage)
        let file = try required(fileConformance.resilientWitnessesHeader)
        let image = try required(imageConformance.resilientWitnessesHeader)
        return (file: file, image: image)
    }

    @Test func offset() async throws {
        let (file, image) = try loadFirstHeaders()
        let result = try acrossAllReaders(file, image) { $0.offset }
        #expect(result == ResilientWitnessesHeaderBaseline.firstHeader.offset)
    }

    @Test func layout() async throws {
        let (file, image) = try loadFirstHeaders()
        let result = try acrossAllReaders(file, image) { $0.layout.numWitnesses }
        #expect(result == ResilientWitnessesHeaderBaseline.firstHeader.layoutNumWitnesses)
    }
}
