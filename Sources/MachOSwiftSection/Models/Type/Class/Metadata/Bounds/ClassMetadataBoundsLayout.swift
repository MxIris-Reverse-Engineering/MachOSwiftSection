import Foundation

@Layout
public protocol ClassMetadataBoundsLayout: MetadataBoundsLayout {
    var immediateMembersOffset: StoredPointerDifference { get }
}
