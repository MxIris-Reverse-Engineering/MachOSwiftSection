import Foundation

public struct Metadata: LocatableLayoutWrapper {
    public struct Layout {
        public let kind: MetadataKind
    }

    public let offset: Int
    public var layout: Layout

    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
}
