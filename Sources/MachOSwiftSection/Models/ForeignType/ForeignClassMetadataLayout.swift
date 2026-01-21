import Foundation
import MachOFoundation

@Layout
public protocol ForeignClassMetadataLayout: MetadataLayout {
    var descriptor: Pointer<ClassDescriptor> { get }
    var superclass: ConstMetadataPointer<ForeignClassMetadata> { get }
    var reserved: StoredPointer { get }
}
