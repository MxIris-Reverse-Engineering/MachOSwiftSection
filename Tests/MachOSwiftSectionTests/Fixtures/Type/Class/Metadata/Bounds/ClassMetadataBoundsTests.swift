import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `ClassMetadataBounds`.
///
/// `ClassMetadataBounds` is a derived value type usually built through
/// the static factories on `ClassMetadataBoundsProtocol`. We construct
/// instances with known scalars and verify the layout fields round-trip.
@Suite
final class ClassMetadataBoundsTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "ClassMetadataBounds"
    static var registeredTestMethodNames: Set<String> {
        ClassMetadataBoundsBaseline.registeredTestMethodNames
    }

    @Test func offset() async throws {
        // Construct a deterministic instance and verify the `offset` ivar
        // is set as supplied. (Default-init through the public layout
        // initializer.)
        let bounds = ClassMetadataBounds(
            layout: ClassMetadataBounds.Layout(negativeSizeInWords: 0, positiveSizeInWords: 0),
            offset: 0x1234
        )
        #expect(bounds.offset == 0x1234)
    }

    @Test func layout() async throws {
        let bounds = ClassMetadataBounds(
            layout: ClassMetadataBounds.Layout(negativeSizeInWords: 2, positiveSizeInWords: 7),
            offset: 0
        )
        #expect(bounds.layout.negativeSizeInWords == 2)
        #expect(bounds.layout.positiveSizeInWords == 7)
        // Default constructor zeroes the immediateMembersOffset.
        #expect(bounds.layout.immediateMembersOffset == 0)
    }
}
