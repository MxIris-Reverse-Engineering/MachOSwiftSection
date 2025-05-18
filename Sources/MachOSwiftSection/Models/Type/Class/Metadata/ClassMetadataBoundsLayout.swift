import Foundation
import MachOSwiftSectionMacro


@Layout
public protocol ClassMetadataBoundsLayout: MetadataBoundsLayout {
    var immediateMembersOffset: StoredPointerDifference { get }
}
