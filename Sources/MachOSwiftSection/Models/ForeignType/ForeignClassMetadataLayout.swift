import Foundation
import MachOFoundation
import MachOMacro

@Layout
public protocol ForeignClassMetadataLayout: MetadataLayout {
    var descriptor: Pointer<ClassDescriptor> { get }
    var superclass: ConstMetadataPointer<ForeignClassMetadata> { get }
    var reserved: StoredPointer { get }
}



