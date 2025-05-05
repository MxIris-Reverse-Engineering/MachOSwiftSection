import Foundation

public struct AnyLayoutWrapper<Layout>: LayoutWrapperWithOffset {
    public let offset: Int
    public var layout: Layout

    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
}
