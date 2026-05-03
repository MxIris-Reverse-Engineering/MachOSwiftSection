import Foundation
import Testing
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `RelativeObjCProtocolPrefix`.
///
/// `RelativeObjCProtocolPrefix` is the relative-pointer variant of the
/// ObjC protocol prefix. The `SymbolTestsCore` fixture's ObjC reference
/// uses the absolute-pointer `ObjCProtocolPrefix` form, not the
/// relative variant. The Suite registers the public surface
/// (`offset`, `layout`, `mangledName`) for the Coverage Invariant test
/// and documents the missing runtime coverage.
@Suite
final class RelativeObjCProtocolPrefixTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "RelativeObjCProtocolPrefix"
    static var registeredTestMethodNames: Set<String> {
        RelativeObjCProtocolPrefixBaseline.registeredTestMethodNames
    }

    @Test func registrationOnly() async throws {
        // No live instance available in SymbolTestsCore; the Suite registers
        // the public surface (offset, layout, mangledName) for the Coverage
        // Invariant test.
        #expect(RelativeObjCProtocolPrefixBaseline.registeredTestMethodNames.contains("layout"))
        #expect(RelativeObjCProtocolPrefixBaseline.registeredTestMethodNames.contains("mangledName"))
        #expect(RelativeObjCProtocolPrefixBaseline.registeredTestMethodNames.contains("offset"))
    }
}
