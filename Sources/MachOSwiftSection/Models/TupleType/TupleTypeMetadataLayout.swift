import Foundation
import MachOFoundation

@Layout
public protocol TupleTypeMetadataLayout: MetadataLayout {
    var numberOfElements: StoredSize { get }
    var labels: Pointer<String> { get }
}
