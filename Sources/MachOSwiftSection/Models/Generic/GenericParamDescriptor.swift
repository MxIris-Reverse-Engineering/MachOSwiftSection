public struct GenericParamDescriptor: ResolvableLocatableLayoutWrapper {
    public struct Layout: Sendable {
        public let rawValue: UInt8
    }

    public let offset: Int
    public var layout: Layout

    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }

    public var hasKeyArgument: Bool {
        layout.rawValue & 0x80 != 0
    }

    public var kind: GenericParamKind {
        .init(rawValue: layout.rawValue & 0x3F)!
    }
}
