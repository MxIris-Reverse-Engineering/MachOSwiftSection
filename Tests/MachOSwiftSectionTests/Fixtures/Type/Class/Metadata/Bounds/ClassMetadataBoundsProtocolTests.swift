import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `ClassMetadataBoundsProtocol`.
///
/// The protocol declares one instance method (`adjustForSubclass`) and
/// two static factories (`forAddressPointAndSize`, `forSwiftRootClass`).
/// We exercise them on `ClassMetadataBounds` with known inputs.
@Suite
final class ClassMetadataBoundsProtocolTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "ClassMetadataBoundsProtocol"
    static var registeredTestMethodNames: Set<String> {
        ClassMetadataBoundsProtocolBaseline.registeredTestMethodNames
    }

    /// `forAddressPointAndSize(addressPoint:totalSize:offset:)` derives
    /// negative/positive sizes from a (pointer-aligned) address point and
    /// total size. Use known multiples of pointer size to verify the
    /// arithmetic.
    @Test func forAddressPointAndSize() async throws {
        let pointerSize = MemoryLayout<UnsafeRawPointer>.size
        let addressPoint = StoredSize(2 * pointerSize)
        let totalSize = StoredSize(8 * pointerSize)

        let bounds = ClassMetadataBounds.forAddressPointAndSize(
            addressPoint: addressPoint,
            totalSize: totalSize,
            offset: 0
        )

        #expect(bounds.layout.negativeSizeInWords == 2)
        #expect(bounds.layout.positiveSizeInWords == 6)
        #expect(bounds.layout.immediateMembersOffset == StoredPointerDifference(totalSize - addressPoint))
    }

    /// `forSwiftRootClass(offset:)` returns the structural bounds for the
    /// implicit Swift root class metadata.
    @Test func forSwiftRootClass() async throws {
        let bounds = ClassMetadataBounds.forSwiftRootClass(offset: 0x42)
        #expect(bounds.offset == 0x42)
        // The bounds must have non-zero sizes (otherwise the root class
        // root metadata couldn't house anything).
        #expect(bounds.layout.negativeSizeInWords > 0 || bounds.layout.positiveSizeInWords > 0)
    }

    /// `adjustForSubclass(areImmediateMembersNegative:numImmediateMembers:)`
    /// produces a new bounds with the subclass's immediate members
    /// folded in. Verify the size delta in both directions.
    @Test func adjustForSubclass() async throws {
        let initial = ClassMetadataBounds(
            layout: ClassMetadataBounds.Layout(negativeSizeInWords: 4, positiveSizeInWords: 4),
            offset: 0
        )

        // Negative immediate members increase the negative size.
        let negativeAdjusted = initial.adjustForSubclass(areImmediateMembersNegative: true, numImmediateMembers: 3)
        #expect(negativeAdjusted.layout.negativeSizeInWords == 7)
        #expect(negativeAdjusted.layout.positiveSizeInWords == 4)

        // Positive immediate members increase the positive size.
        let positiveAdjusted = initial.adjustForSubclass(areImmediateMembersNegative: false, numImmediateMembers: 5)
        #expect(positiveAdjusted.layout.negativeSizeInWords == 4)
        #expect(positiveAdjusted.layout.positiveSizeInWords == 9)
    }
}
