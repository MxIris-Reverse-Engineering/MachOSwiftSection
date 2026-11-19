import Foundation
import MachOBase
import Utilities

@Layout
public protocol TupleTypeMetadataLayout: MetadataLayout {
    var numberOfElements: StoredSize { get }
    var labels: Pointer<String> { get }
}
