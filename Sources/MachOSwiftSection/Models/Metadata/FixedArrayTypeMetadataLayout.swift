import Foundation
import MachOFoundation

@Layout
public protocol FixedArrayTypeMetadataLayout: MetadataLayout {
    var count: StoredPointerDifference { get }
    var element: ConstMetadataPointer<Metadata> { get }
}
