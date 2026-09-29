import Foundation
import Utilities

@Layout
public protocol ClassMetadataBoundsLayout: MetadataBoundsLayout {
    var immediateMembersOffset: StoredPointerDifference { get }
    init(negativeSizeInWords: UInt32, positiveSizeInWords: UInt32, immediateMembersOffset: StoredPointerDifference)
}
