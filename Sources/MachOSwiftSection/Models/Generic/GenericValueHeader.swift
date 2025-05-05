import Foundation

public struct GenericValueHeader: LayoutWrapperWithOffset {
    public struct Layout {
        public let numValues: UInt32
    }

    public let offset: Int

    public var layout: Layout

    public init(offset: Int, layout: Layout) {
        self.offset = offset
        self.layout = layout
    }
}
