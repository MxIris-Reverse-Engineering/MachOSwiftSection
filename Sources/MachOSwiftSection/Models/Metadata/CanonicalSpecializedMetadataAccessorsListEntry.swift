import Foundation

public struct CanonicalSpecializedMetadataAccessorsListEntry: LocatableLayoutWrapper {
    public struct Layout {
        public let accessor: RelativeDirectRawPointer
    }
    
    public var layout: Layout
    
    public let offset: Int
    
    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}
