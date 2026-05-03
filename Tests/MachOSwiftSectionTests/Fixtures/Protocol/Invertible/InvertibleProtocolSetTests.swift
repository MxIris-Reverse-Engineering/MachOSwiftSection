import Foundation
import Testing
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `InvertibleProtocolSet`.
///
/// `InvertibleProtocolSet` is a 16-bit `OptionSet` over the invertible
/// protocol kinds (`copyable`, `escapable`). The fixture has no live
/// carrier (the bits are encoded inline on each type's
/// `RequirementInSignature`), so the Suite exercises the accessors
/// against the synthetic raw values embedded in the baseline.
@Suite
final class InvertibleProtocolSetTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "InvertibleProtocolSet"
    static var registeredTestMethodNames: Set<String> {
        InvertibleProtocolSetBaseline.registeredTestMethodNames
    }

    @Test("init(rawValue:)") func initializerWithRawValue() async throws {
        let set = InvertibleProtocolSet(rawValue: InvertibleProtocolSetBaseline.both.rawValue)
        #expect(set.rawValue == InvertibleProtocolSetBaseline.both.rawValue)
    }

    @Test func rawValue() async throws {
        let set = InvertibleProtocolSet(rawValue: InvertibleProtocolSetBaseline.copyableOnly.rawValue)
        #expect(set.rawValue == InvertibleProtocolSetBaseline.copyableOnly.rawValue)
    }

    @Test func copyable() async throws {
        // Static OptionSet members carry their canonical bit pattern.
        #expect(InvertibleProtocolSet.copyable.rawValue == InvertibleProtocolSetBaseline.copyableOnly.rawValue)
    }

    @Test func escapable() async throws {
        #expect(InvertibleProtocolSet.escapable.rawValue == InvertibleProtocolSetBaseline.escapableOnly.rawValue)
    }

    @Test func hasCopyable() async throws {
        let none = InvertibleProtocolSet(rawValue: InvertibleProtocolSetBaseline.none.rawValue)
        #expect(none.hasCopyable == InvertibleProtocolSetBaseline.none.hasCopyable)

        let copyableOnly = InvertibleProtocolSet(rawValue: InvertibleProtocolSetBaseline.copyableOnly.rawValue)
        #expect(copyableOnly.hasCopyable == InvertibleProtocolSetBaseline.copyableOnly.hasCopyable)

        let both = InvertibleProtocolSet(rawValue: InvertibleProtocolSetBaseline.both.rawValue)
        #expect(both.hasCopyable == InvertibleProtocolSetBaseline.both.hasCopyable)
    }

    @Test func hasEscapable() async throws {
        let none = InvertibleProtocolSet(rawValue: InvertibleProtocolSetBaseline.none.rawValue)
        #expect(none.hasEscapable == InvertibleProtocolSetBaseline.none.hasEscapable)

        let escapableOnly = InvertibleProtocolSet(rawValue: InvertibleProtocolSetBaseline.escapableOnly.rawValue)
        #expect(escapableOnly.hasEscapable == InvertibleProtocolSetBaseline.escapableOnly.hasEscapable)

        let both = InvertibleProtocolSet(rawValue: InvertibleProtocolSetBaseline.both.rawValue)
        #expect(both.hasEscapable == InvertibleProtocolSetBaseline.both.hasEscapable)
    }
}
