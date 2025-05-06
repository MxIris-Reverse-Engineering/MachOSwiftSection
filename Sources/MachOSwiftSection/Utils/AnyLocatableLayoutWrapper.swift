import Foundation

public struct AnyLocatableLayoutWrapper<Layout>: LocatableLayoutWrapper {
    public let offset: Int
    public var layout: Layout

    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
}
