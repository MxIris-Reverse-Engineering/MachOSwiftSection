import Foundation
import MachOKit
import MachOFoundation

public struct ExistentialTypeMetadata: MetadataProtocol {
    public struct Layout: ExistentialTypeMetadataLayout {
        public let kind: StoredPointer
        public let flags: ExistentialTypeFlags
        public let numberOfProtocols: UInt32
    }
    
    public var layout: Layout
    
    public let offset: Int
    
    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}
