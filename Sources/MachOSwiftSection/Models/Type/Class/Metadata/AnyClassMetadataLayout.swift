import MachOKit
import MachOFoundation
import MachOMacro

@Layout
public protocol AnyClassMetadataLayout: HeapMetadataLayout {
    var superclass: StoredPointer { get }
}
