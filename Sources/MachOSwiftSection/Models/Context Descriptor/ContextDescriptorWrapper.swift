//
//  ContextDescriptorWrapper.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/5.
//

import MachOKit

public enum ContextDescriptorWrapper {
    case type(TypeContextDescriptorWrapper)
    case `protocol`(ProtocolDescriptor)
    case anonymous(AnonymousContextDescriptor)
    case `extension`(ExtensionContextDescriptor)
    case module(ModuleContextDescriptor)
    case opaqueType(OpaqueTypeDescriptor)
    
    func name(in machOFile: MachOFile) throws -> String? {
        if case let .extension(extensionContextDescriptor) = self {
            return try extensionContextDescriptor.extendedContext(in: machOFile).map { try MetadataReader.demangle(for: $0, in: machOFile) }
        } else {
            return try namedContextDescriptor?.name(in: machOFile)
        }
    }
    
    var contextDescriptor: any ContextDescriptorProtocol {
        switch self {
        case .type(let typeContextDescriptor):
            return typeContextDescriptor.contextDescriptor
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
    
    var namedContextDescriptor: (any NamedContextDescriptorProtocol)? {
        switch self {
        case .type(let typeContextDescriptor):
            return typeContextDescriptor.namedContextDescriptor
        case .protocol(let protocolDescriptor):
            return protocolDescriptor
        case .module(let moduleContextDescriptor):
            return moduleContextDescriptor
        case .anonymous, .extension, .opaqueType:
            return nil
        }
    }
}


