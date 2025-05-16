public struct GenericPackShapeHeader: LocatableLayoutWrapper {
    public struct Layout {
        public let numPacks: UInt16
        public let numShapeClasses: UInt16
    }

    public let offset: Int
    public var layout: Layout
    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
}
