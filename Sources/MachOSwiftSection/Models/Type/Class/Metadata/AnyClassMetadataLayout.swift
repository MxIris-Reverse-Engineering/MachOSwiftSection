import MachOKit
import MachOFoundation
import MachOMacro

@Layout
public protocol AnyClassMetadataLayout: MetadataLayout {
    var superclass: StoredPointer { get }
}
