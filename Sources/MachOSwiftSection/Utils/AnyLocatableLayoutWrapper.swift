import Foundation

public struct AnyLocatableLayoutWrapper<Layout>: LocatableLayoutWrapper {
    public var layout: Layout
    public let offset: Int
    
    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
}
