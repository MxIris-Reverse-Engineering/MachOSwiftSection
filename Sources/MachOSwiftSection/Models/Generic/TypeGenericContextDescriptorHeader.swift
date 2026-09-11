import MachOBase

public struct TypeGenericContextDescriptorHeader: GenericContextDescriptorHeaderProtocol {
    public struct Layout: GenericContextDescriptorHeaderLayout {
        /// The runtime's metadata instantiation cache for this type. The
        /// cache is mutable runtime state and reads as zero in the file; only
        /// its location is a static fact.
        public let instantiationCache: RelativeDirectRawPointer
        /// The type's default metadata instantiation pattern. Which pattern
        /// type lives there follows the descriptor's kind:
        /// ``GenericClassMetadataPattern`` for a class,
        /// ``GenericValueMetadataPattern`` for a struct or an enum — this
        /// layer records the location, not the kind.
        public let defaultInstantiationPattern: RelativeDirectRawPointer
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
