import Foundation
import MachOFoundation
import MachOMacro

@Layout
public protocol TupleTypeMetadataElementLayout: LayoutProtocol {
    var type: ConstMetadataPointer<Metadata> { get }
    var offset: StoredSize { get }
}
