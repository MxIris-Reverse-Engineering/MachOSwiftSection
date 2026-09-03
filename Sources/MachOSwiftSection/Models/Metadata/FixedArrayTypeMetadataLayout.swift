import Foundation
import MachOBase

@Layout
public protocol FixedArrayTypeMetadataLayout: MetadataLayout {
    var count: StoredPointerDifference { get }
    var element: ConstMetadataPointer<Metadata> { get }
}
