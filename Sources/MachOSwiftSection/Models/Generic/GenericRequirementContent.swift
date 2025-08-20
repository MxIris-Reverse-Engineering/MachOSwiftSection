import MachOFoundation

public enum GenericRequirementContent: Sendable {
    public struct InvertedProtocols: Sendable {
        public let genericParamIndex: UInt16
        public let protocols: InvertibleProtocolSet
    }

    case type(RelativeDirectPointer<MangledName>)
    case `protocol`(RelativeProtocolDescriptorPointer)
    case layout(GenericRequirementLayoutKind)
    case conformance(RelativeIndirectablePointer<ProtocolConformanceDescriptor, Pointer<ProtocolConformanceDescriptor>>)
    case invertedProtocols(GenericRequirementContent.InvertedProtocols)
}

public enum ResolvedGenericRequirementContent: Sendable {
    case type(MangledName)
    case `protocol`(SymbolOrElement<ProtocolDescriptorWithObjCInterop>)
    case layout(GenericRequirementLayoutKind)
    case conformance(ProtocolConformanceDescriptor)
    case invertedProtocols(GenericRequirementContent.InvertedProtocols)
}
