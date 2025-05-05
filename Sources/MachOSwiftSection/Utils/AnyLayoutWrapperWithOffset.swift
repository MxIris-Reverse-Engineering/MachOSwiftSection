import Foundation

public struct AnyLayoutWrapper<Layout>: LayoutWrapperWithOffset {
    public let offset: Int
    public var layout: Layout

    public init(offset: Int, layout: Layout) {
        self.offset = offset
        self.layout = layout
    }
}
