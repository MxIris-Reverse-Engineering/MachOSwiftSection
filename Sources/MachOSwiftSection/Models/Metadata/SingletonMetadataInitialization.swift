import Foundation

public struct SingletonMetadataInitialization: LayoutWrapperWithOffset {
    public struct Layout {
        public let initializationCacheOffset: RelativeOffset
        public let incompleteMetadata: RelativeOffset
        public let completionFunction: RelativeOffset
    }

    public let offset: Int
    public var layout: Layout

    public init(offset: Int, layout: Layout) {
        self.offset = offset
        self.layout = layout
    }
    
}
