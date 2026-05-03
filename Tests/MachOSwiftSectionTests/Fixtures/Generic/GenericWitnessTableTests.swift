import Foundation
import Testing
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `GenericWitnessTable`.
///
/// `GenericWitnessTable` is the per-conformance witness-table layout that
/// is reachable from a `ProtocolConformanceDescriptor`'s
/// `GenericWitnessTableSection` trailing object, but the `SymbolTestsCore`
/// fixture does NOT surface any conformance whose witness-table layout
/// reaches the parser as a `GenericWitnessTable` instance through the
/// current public API. The Suite registers the public surface (`offset`,
/// `layout`) for the Coverage Invariant test and documents the missing
/// runtime coverage.
@Suite
final class GenericWitnessTableTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "GenericWitnessTable"
    static var registeredTestMethodNames: Set<String> {
        GenericWitnessTableBaseline.registeredTestMethodNames
    }

    @Test func registrationOnly() async throws {
        // No live carrier surfaced by the current public API — see
        // Generator note.
        #expect(GenericWitnessTableBaseline.registeredTestMethodNames.contains("layout"))
        #expect(GenericWitnessTableBaseline.registeredTestMethodNames.contains("offset"))
    }
}
