import Foundation
import MachOKit
import MachOFoundation

public struct ExistentialMetatypeMetadata: MetadataProtocol {
    public struct Layout: MetadataLayout {
        public let kind: StoredPointer
        public let instanceType: ConstMetadataPointer<Metadata>
        public let flags: ExistentialTypeFlags
    }
    
    public var layout: Layout
    
    public let offset: Int
    
    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}
