import Foundation

public struct CanonicalSpecializedMetadatasListEntry: LocatableLayoutWrapper {
    public struct Layout {
        let metadata: RelativeDirectPointer<MetadataWrapper>
    }
    
    public var layout: Layout
    
    public let offset: Int
    
    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}
