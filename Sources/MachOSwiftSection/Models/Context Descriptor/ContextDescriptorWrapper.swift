//
//  ContextDescriptorWrapper.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/5.
//

import MachOKit

public enum ContextDescriptorWrapper {
    case type(TypeContextDescriptor)
    case `protocol`(ProtocolDescriptor)
    case anonymous(AnonymousContextDescriptor)
    case `extension`(ExtensionContextDescriptor)
    case module(ModuleContextDescriptor)
    case opaqueType(OpaqueTypeDescriptor)
    
    func name(in machO: MachOFile) throws -> String? {
        switch self {
        case .type(let typeContextDescriptor):
            return try typeContextDescriptor.name(in: machO)
        case .protocol(let protocolDescriptor):
            return try protocolDescriptor.name(in: machO)
        case .anonymous(let anonymousContextDescriptor):
            return nil
        case .extension(let extensionContextDescriptor):
            return nil
        case .module(let moduleContextDescriptor):
            return try moduleContextDescriptor.name(in: machO)
        case .opaqueType(let opaqueTypeDescriptor):
            return nil
        }
    }
    
    var contextDescriptor: any ContextDescriptorProtocol {
        switch self {
        case .type(let typeContextDescriptor):
            return typeContextDescriptor
        case .protocol(let protocolDescriptor):
            return protocolDescriptor
        case .anonymous(let anonymousContextDescriptor):
            return anonymousContextDescriptor
        case .extension(let extensionContextDescriptor):
            return extensionContextDescriptor
        case .module(let moduleContextDescriptor):
            return moduleContextDescriptor
        case .opaqueType(let opaqueTypeDescriptor):
            return opaqueTypeDescriptor
        }
    }
}
