import Foundation
import Testing
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `CanonicalSpecializedMetadatasListCount`.
///
/// `RawRepresentable` wrapper around a `UInt32` count read from descriptors
/// with the `hasCanonicalMetadataPrespecializations` bit. The
/// `SymbolTestsCore` fixture declares no prespecializations, so the type is
/// exercised via constant round-trip through `init(rawValue:)` / `rawValue`.
@Suite
final class CanonicalSpecializedMetadatasListCountTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "CanonicalSpecializedMetadatasListCount"
    static var registeredTestMethodNames: Set<String> {
        CanonicalSpecializedMetadatasListCountBaseline.registeredTestMethodNames
    }

    /// `init(rawValue:)` constructs the wrapper from a raw `UInt32`.
    @Test("init(rawValue:)") func initializerWithRawValue() async throws {
        let count = CanonicalSpecializedMetadatasListCount(
            rawValue: CanonicalSpecializedMetadatasListCountBaseline.sampleRawValue
        )
        #expect(count.rawValue == CanonicalSpecializedMetadatasListCountBaseline.sampleRawValue)
    }

    /// `rawValue` projects the stored count.
    @Test func rawValue() async throws {
        let count = CanonicalSpecializedMetadatasListCount(rawValue: 0)
        #expect(count.rawValue == 0)
    }
}
