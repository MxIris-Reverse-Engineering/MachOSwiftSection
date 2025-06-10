import Foundation
import MachOFoundation

public struct CanonicalSpecializedMetadataAccessorsListEntry: ResolvableLocatableLayoutWrapper {
    public struct Layout: Sendable {
        public let accessor: RelativeDirectRawPointer
    }
    
    public var layout: Layout
    
    public let offset: Int
    
    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}
