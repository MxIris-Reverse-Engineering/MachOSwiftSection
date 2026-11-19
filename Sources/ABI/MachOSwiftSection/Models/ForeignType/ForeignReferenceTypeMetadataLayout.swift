import Foundation
import MachOBase
import Utilities

@Layout
public protocol ForeignReferenceTypeMetadataLayout: MetadataLayout {
    var descriptor: Pointer<ClassDescriptor> { get }
    var reserved: StoredPointer { get }
}
