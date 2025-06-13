import MachOKit
import MachOFoundation
import MachOMacro

@Layout
public protocol AnyClassMetadataObjCInteropLayout: AnyClassMetadataLayout {
    var cache: RawPointer { get }
    var vtable: RawPointer { get }
    var data: StoredSize { get }
}
