import MachOKit
import MachOBase
import Utilities

@Layout
public protocol AnyClassMetadataLayout: HeapMetadataLayout {
    var superclass: Pointer<AnyClassMetadata?> { get }
}
