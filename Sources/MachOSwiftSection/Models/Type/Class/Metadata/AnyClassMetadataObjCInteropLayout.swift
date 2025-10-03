import MachOKit
import MachOFoundation


@Layout
public protocol AnyClassMetadataObjCInteropLayout: AnyClassMetadataLayout {
    var cache: RawPointer { get }
    var vtable: RawPointer { get }
    var data: StoredSize { get }
}
