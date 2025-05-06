import Foundation

public struct ForeignMetadataInitialization: LocatableLayoutWrapper {
    public struct Layout {
        public let completionFunction: RelativeOffset
    }

    public let offset: Int
    public var layout: Layout

    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
}
