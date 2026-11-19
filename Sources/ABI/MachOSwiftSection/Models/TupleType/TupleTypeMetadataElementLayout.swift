import Foundation
import MachOBase
import Utilities

@Layout
public protocol TupleTypeMetadataElementLayout: LayoutProtocol {
    var type: ConstMetadataPointer<Metadata> { get }
    var offset: StoredSize { get }
}
