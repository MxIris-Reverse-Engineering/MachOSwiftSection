import MachOFoundation

public struct GenericParamDescriptor: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
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
        // An unmodeled kind byte (the 60 reserved low-6-bits values `3...0x3E`,
        // e.g. emitted by a future toolchain) must not trap: the runtime
        // reserves `Max` (0x3F) as the guard sentinel, so fold any unknown value
        // into `.max`. Every caller tests against `.type` / `.value` /
        // `.typePack`, for which `.max` correctly reads as "none of these".
        .init(rawValue: layout.rawValue & 0x3F) ?? .max
    }
}
