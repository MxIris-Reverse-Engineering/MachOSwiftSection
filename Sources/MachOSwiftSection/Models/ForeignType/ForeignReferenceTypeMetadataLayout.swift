import Foundation
import MachOFoundation


@Layout
public protocol ForeignReferenceTypeMetadataLayout: MetadataLayout {
    var descriptor: Pointer<ClassDescriptor> { get }
    var reserved: StoredPointer { get }
}
