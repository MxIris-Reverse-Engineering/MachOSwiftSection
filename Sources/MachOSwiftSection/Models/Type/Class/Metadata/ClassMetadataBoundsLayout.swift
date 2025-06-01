import Foundation
import MachOMacro


@Layout
public protocol ClassMetadataBoundsLayout: MetadataBoundsLayout {
    var immediateMembersOffset: StoredPointerDifference { get }
}
