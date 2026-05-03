import Foundation
import Testing
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `GenericValueHeader`.
///
/// The `SymbolTestsCore` fixture does not declare any integer-value
/// generic type, so a live header cannot be sourced. The Suite registers
/// the public surface (`offset`, `layout`) for the Coverage Invariant
/// test and documents the missing runtime coverage.
@Suite
final class GenericValueHeaderTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "GenericValueHeader"
    static var registeredTestMethodNames: Set<String> {
        GenericValueHeaderBaseline.registeredTestMethodNames
    }

    @Test func registrationOnly() async throws {
        // No live carrier in SymbolTestsCore — see Generator note.
        #expect(GenericValueHeaderBaseline.registeredTestMethodNames.contains("layout"))
        #expect(GenericValueHeaderBaseline.registeredTestMethodNames.contains("offset"))
    }
}
