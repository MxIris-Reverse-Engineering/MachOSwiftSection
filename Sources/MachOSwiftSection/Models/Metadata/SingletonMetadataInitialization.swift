import Foundation

public struct SingletonMetadataInitialization: LayoutWrapperWithOffset {
    public struct Layout {
        public let initializationCacheOffset: RelativeDirectPointer
        public let incompleteMetadata: RelativeDirectPointer
        public let completionFunction: RelativeDirectPointer
    }

    public let offset: Int
    public var layout: Layout

    public init(offset: Int, layout: Layout) {
        self.offset = offset
        self.layout = layout
    }
    
}
