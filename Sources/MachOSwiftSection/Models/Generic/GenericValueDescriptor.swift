import Foundation

public struct GenericValueDescriptor: LayoutWrapperWithOffset {
    public struct Layout {
        public let type: GenericValueType
    }
    public let offset: Int
    public var layout: Layout
    public init(offset: Int, layout: Layout) {
        self.offset = offset
        self.layout = layout
    }
}
