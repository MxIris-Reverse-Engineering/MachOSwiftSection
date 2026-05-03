import Foundation
import Testing
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `MetadataBounds`.
///
/// `MetadataBounds` carries a `(negativeSizeInWords, positiveSizeInWords)`
/// pair describing the prefix/suffix bounds of a class metadata. It is
/// reachable through `ClassMetadataBounds.layout.bounds` for any non-resilient
/// Swift class. Rather than materialise a class metadata (a MachOImage-only
/// path), the Suite drives a constant round-trip through the memberwise
/// initialiser to assert the structural members are preserved.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized; the
/// derived sizes (`totalSizeInBytes`, `addressPointInBytes`) are inherited
/// from `MetadataBoundsProtocol` and covered by that Suite.
@Suite
final class MetadataBoundsTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "MetadataBounds"
    static var registeredTestMethodNames: Set<String> {
        MetadataBoundsBaseline.registeredTestMethodNames
    }

    @Test func offset() async throws {
        let bounds = MetadataBounds(
            layout: .init(
                negativeSizeInWords: MetadataBoundsBaseline.sampleNegativeSizeInWords,
                positiveSizeInWords: MetadataBoundsBaseline.samplePositiveSizeInWords
            ),
            offset: MetadataBoundsBaseline.sampleOffset
        )
        #expect(bounds.offset == MetadataBoundsBaseline.sampleOffset)
    }

    @Test func layout() async throws {
        let bounds = MetadataBounds(
            layout: .init(
                negativeSizeInWords: MetadataBoundsBaseline.sampleNegativeSizeInWords,
                positiveSizeInWords: MetadataBoundsBaseline.samplePositiveSizeInWords
            ),
            offset: 0
        )
        #expect(bounds.layout.negativeSizeInWords == MetadataBoundsBaseline.sampleNegativeSizeInWords)
        #expect(bounds.layout.positiveSizeInWords == MetadataBoundsBaseline.samplePositiveSizeInWords)
    }
}
