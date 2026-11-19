import Foundation
import MachOBase
import Utilities

@Layout
public protocol FixedArrayTypeMetadataLayout: MetadataLayout {
    var count: StoredPointerDifference { get }
    var element: ConstMetadataPointer<Metadata> { get }
}
