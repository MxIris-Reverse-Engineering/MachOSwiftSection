import Foundation

public struct GenericValueDescriptor: LocatableLayoutWrapper {
    public struct Layout {
        public let type: GenericValueType
    }
    public let offset: Int
    public var layout: Layout
    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
}
