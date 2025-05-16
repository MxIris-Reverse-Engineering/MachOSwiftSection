//
//  GenericRequirementContent.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/15.
//


public enum GenericRequirementContent {
    public struct InvertedProtocols {
        let genericParamIndex: UInt16
        let protocols: InvertibleProtocolSet
    }

    case type(RelativeDirectPointer<MangledName>)
    case `protocol`(RelativeProtocolDescriptorPointer)
    case layout(GenericRequirementLayoutKind)
    case conformance(RelativeIndirectablePointer<ProtocolConformanceDescriptor, Pointer<ProtocolConformanceDescriptor>>)
    case invertedProtocols(GenericRequirementContent.InvertedProtocols)
}

public enum ResolvedGenericRequirementContent {
    case type(MangledName)
    case `protocol`(RelativeProtocolDescriptorPointer)
    case layout(GenericRequirementLayoutKind)
    case conformance(ProtocolConformanceDescriptor)
    case invertedProtocols(GenericRequirementContent.InvertedProtocols)
}