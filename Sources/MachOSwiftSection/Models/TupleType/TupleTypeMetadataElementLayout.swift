import Foundation
import MachOBase

@Layout
public protocol TupleTypeMetadataElementLayout: LayoutProtocol {
    var type: ConstMetadataPointer<Metadata> { get }
    var offset: StoredSize { get }
}
