//
//  ContextDescriptorKindSpecificFlags.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/3.
//


public enum ContextDescriptorKindSpecificFlags {
    case `protocol`(ProtocolContextDescriptorFlags)
    case type(TypeContextDescriptorFlags)
    case anonymous(AnonymousContextDescriptorFlags)
}