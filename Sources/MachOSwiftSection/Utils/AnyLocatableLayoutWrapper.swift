import Foundation

public struct AnyLocatableLayoutWrapper<Layout>: ResolvableLocatableLayoutWrapper {
    public var layout: Layout
    public let offset: Int
    
    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
}
