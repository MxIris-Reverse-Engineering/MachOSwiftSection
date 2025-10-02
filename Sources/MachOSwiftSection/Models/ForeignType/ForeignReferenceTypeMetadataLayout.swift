import Foundation
import MachOFoundation
import MachOMacro

@Layout
public protocol ForeignReferenceTypeMetadataLayout: MetadataLayout {
    var descriptor: Pointer<ClassDescriptor> { get }
    var reserved: StoredPointer { get }
}
