import Foundation
import MachOKit

public protocol ClassMetadataBoundsProtocol: MetadataBoundsProtocol where Layout: ClassMetadataBoundsLayout {}

extension ClassMetadataBoundsProtocol {
    public func adjustForSubclass(areImmediateMembersNegative: Bool, numImmediateMembers: UInt32) -> Self {
        var negativeSizeInWords: UInt32 = layout.negativeSizeInWords
        var positiveSizeInWords: UInt32 = layout.positiveSizeInWords
        var immediateMembersOffset: StoredPointerDifference = layout.immediateMembersOffset
        if areImmediateMembersNegative {
            negativeSizeInWords += numImmediateMembers
            immediateMembersOffset = -StoredPointerDifference(layout.negativeSizeInWords) * MemoryLayout<StoredPointer>.size.cast()
        } else {
            immediateMembersOffset = layout.positiveSizeInWords.cast() * MemoryLayout<StoredPointer>.size.cast()
            positiveSizeInWords += numImmediateMembers
        }

        return .init(layout: .init(negativeSizeInWords: negativeSizeInWords, positiveSizeInWords: positiveSizeInWords, immediateMembersOffset: immediateMembersOffset), offset: offset)
    }

    public static func forAddressPointAndSize(addressPoint: StoredSize, totalSize: StoredSize, offset: Int) -> Self {
        .init(layout: .init(negativeSizeInWords: .init(addressPoint.cast() / MemoryLayout<StoredPointer>.size), positiveSizeInWords: .init((totalSize - addressPoint).cast() / MemoryLayout<StoredPointer>.size), immediateMembersOffset: .init(totalSize - addressPoint)), offset: offset)
    }

    public static func forSwiftRootClass(offset: Int) -> Self {
        return forAddressPointAndSize(
            addressPoint: ClassMetadataObjCInterop.HeaderType.layoutSize.cast(),
            totalSize: FullMetadata<ClassMetadataObjCInterop>.layoutSize.cast(),
            offset: offset
        )
    }
}
