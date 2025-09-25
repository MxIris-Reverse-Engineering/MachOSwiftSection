import MachOFoundation

public enum GenericRequirementContent: Sendable, Equatable {
    public struct InvertedProtocols: Sendable, Equatable {
        public let genericParamIndex: UInt16
        public let protocols: InvertibleProtocolSet
    }

    case type(RelativeDirectPointer<MangledName>)
    case `protocol`(RelativeProtocolDescriptorPointer)
    case layout(GenericRequirementLayoutKind)
    case conformance(RelativeIndirectablePointer<ProtocolConformanceDescriptor, Pointer<ProtocolConformanceDescriptor>>)
    case invertedProtocols(GenericRequirementContent.InvertedProtocols)
}

public enum ResolvedGenericRequirementContent: Sendable, Equatable {
    case type(MangledName)
    case `protocol`(SymbolOrElement<ProtocolDescriptorWithObjCInterop>)
    case layout(GenericRequirementLayoutKind)
    case conformance(ProtocolConformanceDescriptor)
    case invertedProtocols(GenericRequirementContent.InvertedProtocols)
}
