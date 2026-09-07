import MachOKit
import MachOBase

@Layout
public protocol AnyClassMetadataObjCInteropLayout: HeapMetadataLayout {
    var superclass: Pointer<AnyClassMetadataObjCInterop?> { get }
    var cache: RawPointer { get }
    var vtable: RawPointer { get }
    var data: StoredSize { get }
}
