import Foundation
import MachOFoundation
import MachOMacro

@Layout
public protocol FixedArrayTypeMetadataLayout: MetadataLayout {
    var count: StoredPointerDifference { get }
    var element: ConstMetadataPointer<Metadata> { get }
}
