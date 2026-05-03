import Foundation
import Testing
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `MetadataBoundsProtocol`.
///
/// Per the protocol-extension attribution rule (see `BaselineGenerator.swift`),
/// `totalSizeInBytes` and `addressPointInBytes` are declared in
/// `extension MetadataBoundsProtocol { ... }` and attribute to the
/// protocol, not to concrete bounds carriers like `MetadataBounds`.
///
/// The Suite drives a constant `MetadataBounds` and asserts the derived
/// sizes match the closed-form formulas:
///   `totalSizeInBytes    = (neg + pos) * sizeof(UnsafeRawPointer)`
///   `addressPointInBytes =  neg        * sizeof(UnsafeRawPointer)`
@Suite
final class MetadataBoundsProtocolTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "MetadataBoundsProtocol"
    static var registeredTestMethodNames: Set<String> {
        MetadataBoundsProtocolBaseline.registeredTestMethodNames
    }

    private func makeBounds() -> MetadataBounds {
        MetadataBounds(
            layout: .init(
                negativeSizeInWords: MetadataBoundsProtocolBaseline.sampleNegativeSizeInWords,
                positiveSizeInWords: MetadataBoundsProtocolBaseline.samplePositiveSizeInWords
            ),
            offset: 0
        )
    }

    @Test func totalSizeInBytes() async throws {
        let bounds = makeBounds()
        let pointerSize = UInt64(MemoryLayout<UnsafeRawPointer>.size)
        let expected = (UInt64(MetadataBoundsProtocolBaseline.sampleNegativeSizeInWords)
            + UInt64(MetadataBoundsProtocolBaseline.samplePositiveSizeInWords)) * pointerSize
        #expect(UInt64(bounds.totalSizeInBytes) == expected)
    }

    @Test func addressPointInBytes() async throws {
        let bounds = makeBounds()
        let pointerSize = UInt64(MemoryLayout<UnsafeRawPointer>.size)
        let expected = UInt64(MetadataBoundsProtocolBaseline.sampleNegativeSizeInWords) * pointerSize
        #expect(UInt64(bounds.addressPointInBytes) == expected)
    }
}
