import MachOKit
import MachOFoundation

public struct ClassMetadata: ClassMetadataProtocol {
    public struct Layout: ClassMetadataLayout, ClassMetadataLayoutWithDescriptor {
        public let kind: StoredPointer
        public let superclass: Pointer<ClassMetadata?>
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

    public var layout: Layout

    public let offset: Int

    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }

    public static var descriptorOffset: Int { Layout.offset(of: .descriptor) }
}
