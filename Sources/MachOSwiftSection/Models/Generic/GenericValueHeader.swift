import Foundation

public struct GenericValueHeader: LocatableLayoutWrapper {
    public struct Layout {
        public let numValues: UInt32
    }

    public let offset: Int

    public var layout: Layout

    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
}
