import Foundation

public struct ForeignMetadataInitialization: LayoutWrapperWithOffset {
    public struct Layout {
        public let completionFunction: RelativeOffset
    }

    public let offset: Int
    public var layout: Layout

    public init(offset: Int, layout: Layout) {
        self.offset = offset
        self.layout = layout
    }
}
