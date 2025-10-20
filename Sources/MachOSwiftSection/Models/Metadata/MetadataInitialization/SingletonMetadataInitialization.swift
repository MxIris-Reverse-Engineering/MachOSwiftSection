import Foundation
import MachOFoundation

public struct SingletonMetadataInitialization: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let initializationCacheOffset: RelativeOffset
        public let incompleteMetadata: RelativeOffset
        public let completionFunction: RelativeOffset
    }

    public let offset: Int
    public var layout: Layout

    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
    
}
