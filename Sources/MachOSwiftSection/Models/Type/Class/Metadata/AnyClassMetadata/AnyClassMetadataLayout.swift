import MachOKit
import MachOBase

@Layout
public protocol AnyClassMetadataLayout: HeapMetadataLayout {
    var superclass: Pointer<AnyClassMetadata?> { get }
}
