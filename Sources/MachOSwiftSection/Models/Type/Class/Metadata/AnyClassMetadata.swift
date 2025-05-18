import Foundation

public struct AnyClassMetadata: LocatableLayoutWrapper {
    public struct Layout {
        public let kind: StoredPointer
        public let superclass: StoredPointer
    }
    
    public var layout: Layout
    
    public let offset: Int
    
    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}

public struct AnyClassMetadataObjCInterop: LocatableLayoutWrapper {
    public struct Layout {
        public let kind: StoredPointer
        public let superclass: StoredPointer
        public let cacheData: (RawPointer, RawPointer)
        public let data: StoredSize
    }
    
    public var layout: Layout
    
    public let offset: Int
    
    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}



