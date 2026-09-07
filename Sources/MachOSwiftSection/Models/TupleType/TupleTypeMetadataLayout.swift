import Foundation
import MachOBase

@Layout
public protocol TupleTypeMetadataLayout: MetadataLayout {
    var numberOfElements: StoredSize { get }
    var labels: Pointer<String> { get }
}
