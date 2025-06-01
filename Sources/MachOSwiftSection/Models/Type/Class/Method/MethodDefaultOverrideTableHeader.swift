import Foundation

public struct MethodDefaultOverrideTableHeader: ResolvableLocatableLayoutWrapper {
    public struct Layout {
        public let numEntries: UInt32
    }

    public var layout: Layout

    public let offset: Int

    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}
