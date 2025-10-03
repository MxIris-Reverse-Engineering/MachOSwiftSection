import Foundation
import MachOKit
import MachOFoundation

public struct DispatchClassMetadata: HeapMetadataProtocol {
    public struct Layout: HeapMetadataLayout {
        public let kind: StoredPointer
        public let opaque: RawPointer
        public let opaqueObjC1: RawPointer
        public let opaqueObjC2: RawPointer
        public let opaqueObjC3: RawPointer
        public let vTableType: UInt64
        public let vTableInvoke: RawPointer
    }
    
    public var layout: Layout
    
    public let offset: Int
    
    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}
