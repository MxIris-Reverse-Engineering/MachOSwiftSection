import Foundation

public struct ClassMetadata: LocatableLayoutWrapper {
    public struct Layout {
        public let kind: StoredPointer
        public let superclass: StoredPointer
        public let flags: ClassFlags
        public let instanceAddressPoint: UInt32
        public let instanceSize: UInt32
        public let instanceAlignmentMask: UInt16
        public let reserved: UInt16
        public let classSize: UInt32
        public let classAddressPoint: UInt32
        public let description: SignedPointer<ClassDescriptor>
    }
    
    public var layout: Layout
    
    public let offset: Int
    
    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}

public struct ClassMetadataObjCInterop: LocatableLayoutWrapper {
    public struct Layout {
        public let kind: StoredPointer
        public let superclass: StoredPointer
        public let cacheData: (RawPointer, RawPointer)
        public let data: StoredSize
        public let flags: ClassFlags
        public let instanceAddressPoint: UInt32
        public let instanceSize: UInt32
        public let instanceAlignmentMask: UInt16
        public let reserved: UInt16
        public let classSize: UInt32
        public let classAddressPoint: UInt32
        public let description: SignedPointer<ClassDescriptor>
    }
    
    public var layout: Layout
    
    public let offset: Int
    
    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}
