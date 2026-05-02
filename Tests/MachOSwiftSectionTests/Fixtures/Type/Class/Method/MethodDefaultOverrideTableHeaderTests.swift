import Foundation
import Testing
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `MethodDefaultOverrideTableHeader`.
///
/// The `SymbolTestsCore` fixture does not declare any class with a
/// default-override table, so a live header cannot be sourced. The Suite
/// documents the missing runtime coverage.
@Suite
final class MethodDefaultOverrideTableHeaderTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "MethodDefaultOverrideTableHeader"
    static var registeredTestMethodNames: Set<String> {
        MethodDefaultOverrideTableHeaderBaseline.registeredTestMethodNames
    }

    @Test func registrationOnly() async throws {
        // No live instance available in SymbolTestsCore; the Suite registers
        // the public surface (offset, layout) for the Coverage Invariant
        // test.
        #expect(MethodDefaultOverrideTableHeaderBaseline.registeredTestMethodNames.contains("layout"))
        #expect(MethodDefaultOverrideTableHeaderBaseline.registeredTestMethodNames.contains("offset"))
    }
}
