import MachOKit
import MachOFoundation
import MachOMacro

@Layout
public protocol ClassMetadataLayout: AnyClassMetadataLayout {
    var flags: UInt32 { get }
    var instanceAddressPoint: UInt32 { get }
    var instanceSize: UInt32 { get }
    var instanceAlignmentMask: UInt16 { get }
    var reserved: UInt16 { get }
    var classSize: UInt32 { get }
    var classAddressPoint: UInt32 { get }
    var descriptor: Pointer<ClassDescriptor> { get }
    var iVarDestroyer: RawPointer { get }
}
