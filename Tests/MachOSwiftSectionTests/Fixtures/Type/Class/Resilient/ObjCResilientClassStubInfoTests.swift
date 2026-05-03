import Foundation
import Testing
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `ObjCResilientClassStubInfo`.
///
/// The `SymbolTestsCore` fixture does not declare any class with an
/// ObjC resilient class stub, so a live instance cannot be sourced.
/// The Suite documents the missing runtime coverage and registers the
/// public surface for the Coverage Invariant test.
@Suite
final class ObjCResilientClassStubInfoTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "ObjCResilientClassStubInfo"
    static var registeredTestMethodNames: Set<String> {
        ObjCResilientClassStubInfoBaseline.registeredTestMethodNames
    }

    @Test func registrationOnly() async throws {
        // No live instance available in SymbolTestsCore; the Suite
        // registers the public surface (offset, layout) for the
        // Coverage Invariant test.
        #expect(ObjCResilientClassStubInfoBaseline.registeredTestMethodNames.contains("offset"))
        #expect(ObjCResilientClassStubInfoBaseline.registeredTestMethodNames.contains("layout"))
    }
}
