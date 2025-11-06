import MachOKit
import MachOFoundation

@Layout
public protocol AnyClassMetadataLayout: HeapMetadataLayout {
    var superclass: Pointer<AnyClassMetadata?> { get }
}
