import MachOBase

public struct TypeGenericContextDescriptorHeader: GenericContextDescriptorHeaderProtocol {
    public struct Layout: GenericContextDescriptorHeaderLayout {
        public let instantiationCache: RelativeOffset
        public let defaultInstantiationPattern: RelativeOffset
        public let base: GenericContextDescriptorHeader.Layout

        public var numParams: UInt16 { base.numParams }
        public var numRequirements: UInt16 { base.numRequirements }
        public var numKeyArguments: UInt16 { base.numKeyArguments }
        public var flags: GenericContextDescriptorFlags { base.flags }
    }

    public let offset: Int
    public var layout: Layout

    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
}

extension TypeGenericContextDescriptorHeader {
    /// File offset of the runtime's metadata instantiation cache for this
    /// type, or `nil` for a null pointer. The cache is mutable runtime state
    /// and is zero-filled in the file; only its location is a static fact.
    public var instantiationCacheOffset: Int? {
        guard layout.instantiationCache != 0 else { return nil }
        return offset(of: \.instantiationCache) + Int(layout.instantiationCache)
    }

    /// File offset of the type's default metadata instantiation pattern, or
    /// `nil` for a null pointer.
    ///
    /// Which pattern type lives there follows the descriptor's kind:
    /// ``GenericClassMetadataPattern`` for a class, and
    /// ``GenericValueMetadataPattern`` for a struct or an enum. Resolve it
    /// with the matching type — this layer knows the location, not the kind.
    public var defaultInstantiationPatternOffset: Int? {
        guard layout.defaultInstantiationPattern != 0 else { return nil }
        return offset(of: \.defaultInstantiationPattern) + Int(layout.defaultInstantiationPattern)
    }
}
