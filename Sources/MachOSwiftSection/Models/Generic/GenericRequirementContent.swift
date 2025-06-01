public enum GenericRequirementContent {
    public struct InvertedProtocols {
        public let genericParamIndex: UInt16
        public let protocols: InvertibleProtocolSet
    }

    case type(RelativeDirectPointer<MangledName>)
    case `protocol`(RelativeProtocolDescriptorPointer)
    case layout(GenericRequirementLayoutKind)
    case conformance(RelativeIndirectablePointer<ProtocolConformanceDescriptor, Pointer<ProtocolConformanceDescriptor>>)
    case invertedProtocols(GenericRequirementContent.InvertedProtocols)
}

public enum ResolvedGenericRequirementContent {
    case type(MangledName)
    case `protocol`(ResolvableElement<ProtocolDescriptorWithObjCInterop>)
    case layout(GenericRequirementLayoutKind)
    case conformance(ProtocolConformanceDescriptor)
    case invertedProtocols(GenericRequirementContent.InvertedProtocols)
}
