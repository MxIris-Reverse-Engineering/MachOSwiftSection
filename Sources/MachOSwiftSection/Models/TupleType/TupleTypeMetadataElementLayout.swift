import Foundation
import MachOFoundation

@Layout
public protocol TupleTypeMetadataElementLayout: LayoutProtocol {
    var type: ConstMetadataPointer<Metadata> { get }
    var offset: StoredSize { get }
}
