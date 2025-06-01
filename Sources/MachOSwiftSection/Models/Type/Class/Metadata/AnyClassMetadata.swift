import Foundation
import MachOFoundation

public struct AnyClassMetadata: MetadataProtocol {
    public struct Layout: AnyClassMetadataLayout {
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

public struct AnyClassMetadataObjCInterop: MetadataProtocol {
    public struct Layout: AnyClassMetadataObjCInteropLayout {
        public let kind: StoredPointer
        public let superclass: StoredPointer
        public let cache: RawPointer
        public let vtable: RawPointer
        public let data: StoredSize
    }
    
    public var layout: Layout
    
    public let offset: Int
    
    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}



