import MachOKit
import MachOBase

@LocatableLayoutWrapping
public struct ClassMetadataObjCInterop: ClassMetadataObjCInteropProtocol {
    public struct Layout: ClassMetadataObjCInteropLayout, FinalClassMetadataLayout {
        public let kind: StoredPointer
        public let superclass: Pointer<AnyClassMetadataObjCInterop?>
        public let cache: RawPointer
        public let vtable: RawPointer
        public let data: StoredSize
        public let flags: UInt32
        public let instanceAddressPoint: UInt32
        public let instanceSize: UInt32
        public let instanceAlignmentMask: UInt16
        public let reserved: UInt16
        public let classSize: UInt32
        public let classAddressPoint: UInt32
        public let descriptor: Pointer<ClassDescriptor?>
        public let iVarDestroyer: RawPointer
    }

    public static var descriptorOffset: Int { Layout.offset(of: .descriptor) }
}
