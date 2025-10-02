import Foundation
import MachOFoundation
import MachOMacro

@Layout
public protocol TupleTypeMetadataLayout: MetadataLayout {
    var numberOfElements: StoredSize { get }
    var labels: Pointer<String> { get }
}
