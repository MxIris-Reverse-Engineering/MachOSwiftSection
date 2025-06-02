import Foundation

public struct GenericValueDescriptor: ResolvableLocatableLayoutWrapper {
    public struct Layout {
        public let type: UInt32
    }

    public let offset: Int
    public var layout: Layout
    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
}
