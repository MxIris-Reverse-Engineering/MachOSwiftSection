import Foundation
import MachOKit
import MachOFoundation

public struct ExtendedExistentialTypeMetadata: MetadataProtocol {
    public struct Layout: MetadataLayout {
        public let kind: StoredPointer
        public let shape: Pointer<ExtendedExistentialTypeShape>
    }
    
    public var layout: Layout
    
    public let offset: Int
    
    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}
