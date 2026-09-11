import MachOBase

@LocatableLayoutWrapping
public struct GenericPackShapeDescriptor: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let kind: UInt16
        public let index: UInt16
        public let shapeClass: UInt16
        public let unused: UInt16
    }
}

extension GenericPackShapeDescriptor {
    public var kind: GenericPackKind {
        .init(rawValue: layout.kind)!
    }
}
