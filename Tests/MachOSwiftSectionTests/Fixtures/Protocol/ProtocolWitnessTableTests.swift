import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `ProtocolWitnessTable`.
///
/// `ProtocolWitnessTable` is a thin trailing-object wrapper exposing a
/// pointer to the `ProtocolConformanceDescriptor` that owns the table.
/// We pick a live witness-table pattern from the first
/// `ProtocolConformance` in the fixture that surfaces one and verify
/// the offset equals the baseline.
@Suite
final class ProtocolWitnessTableTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "ProtocolWitnessTable"
    static var registeredTestMethodNames: Set<String> {
        ProtocolWitnessTableBaseline.registeredTestMethodNames
    }

    private func loadFirstWitnessTables() throws -> (file: ProtocolWitnessTable, image: ProtocolWitnessTable) {
        let fileConformance = try required(
            try machOFile.swift.protocolConformances.first(where: { $0.witnessTablePattern != nil })
        )
        let imageConformance = try required(
            try machOImage.swift.protocolConformances.first(where: { $0.witnessTablePattern != nil })
        )
        let file = try required(fileConformance.witnessTablePattern)
        let image = try required(imageConformance.witnessTablePattern)
        return (file: file, image: image)
    }

    @Test func offset() async throws {
        let (file, image) = try loadFirstWitnessTables()
        let result = try acrossAllReaders(
            file: { file.offset },
            image: { image.offset }
        )
        #expect(result == ProtocolWitnessTableBaseline.firstWitnessTable.offset)
    }

    @Test func layout() async throws {
        let (file, _) = try loadFirstWitnessTables()
        // The layout's `descriptor` is a raw pointer; verify the property
        // is accessible (compile-time check — the pointer's payload is
        // exercised at the conformance-descriptor level in Task 11).
        _ = file.layout.descriptor
    }
}
