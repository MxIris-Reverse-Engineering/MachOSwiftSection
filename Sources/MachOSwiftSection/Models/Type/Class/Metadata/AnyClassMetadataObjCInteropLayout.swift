import MachOKit
import MachOFoundation

@Layout
public protocol AnyClassMetadataObjCInteropLayout: HeapMetadataLayout {
    var superclass: Pointer<ClassMetadataObjCInterop?> { get }
    var cache: RawPointer { get }
    var vtable: RawPointer { get }
    var data: StoredSize { get }
}
