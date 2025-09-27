import MachOFoundation

public struct GenericPackShapeDescriptor: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let kind: UInt16
        public let index: UInt16
        public let shapeClass: UInt16
        public let unused: UInt16
    }

    public let offset: Int
    public var layout: Layout
    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
}

extension GenericPackShapeDescriptor {
    public var kind: GenericPackKind {
        .init(rawValue: layout.kind)!
    }
}
