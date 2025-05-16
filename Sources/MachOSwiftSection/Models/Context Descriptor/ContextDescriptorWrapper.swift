//
//  ContextDescriptorWrapper.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/5.
//

import MachOKit

@dynamicMemberLookup
public enum ContextDescriptorWrapper {
    case type(TypeContextDescriptorWrapper)
    case `protocol`(ProtocolDescriptor)
    case anonymous(AnonymousContextDescriptor)
    case `extension`(ExtensionContextDescriptor)
    case module(ModuleContextDescriptor)
    case opaqueType(OpaqueTypeDescriptor)


    var protocolDescriptor: ProtocolDescriptor? {
        if case let .protocol(descriptor) = self {
            return descriptor
        } else {
            return nil
        }
    }
    
    var extensionContextDescriptor: ExtensionContextDescriptor? {
        if case let .extension(descriptor) = self {
            return descriptor
        } else {
            return nil
        }
    }
    
    var opaqueTypeDescriptor: OpaqueTypeDescriptor? {
        if case let .opaqueType(descriptor) = self {
            return descriptor
        } else {
            return nil
        }
    }
    
    var moduleContextDescriptor: ModuleContextDescriptor? {
        if case let .module(descriptor) = self {
            return descriptor
        } else {
            return nil
        }
    }
    
    var anonymousContextDescriptor: AnonymousContextDescriptor? {
        if case let .anonymous(descriptor) = self {
            return descriptor
        } else {
            return nil
        }
    }
    
    var isType: Bool {
        switch self {
        case .type:
            return true
        default:
            return false
        }
    }
    
    var isProtocol: Bool {
        switch self {
        case .protocol:
            return true
        default:
            return false
        }
    }
    
    func parent(in machOFile: MachOFile) throws -> ContextDescriptorWrapper? {
        return try contextDescriptor.parent(in: machOFile)
    }

    func name(in machOFile: MachOFile) throws -> String? {
        if case let .extension(extensionContextDescriptor) = self {
            return try extensionContextDescriptor.extendedContext(in: machOFile).map { try MetadataReader.demangle(for: $0, in: machOFile) }
        } else {
            return try namedContextDescriptor?.name(in: machOFile)
        }
    }

    var contextDescriptor: any ContextDescriptorProtocol {
        switch self {
        case let .type(typeContextDescriptor):
            return typeContextDescriptor.contextDescriptor
        case let .protocol(protocolDescriptor):
            return protocolDescriptor
        case let .anonymous(anonymousContextDescriptor):
            return anonymousContextDescriptor
        case let .extension(extensionContextDescriptor):
            return extensionContextDescriptor
        case let .module(moduleContextDescriptor):
            return moduleContextDescriptor
        case let .opaqueType(opaqueTypeDescriptor):
            return opaqueTypeDescriptor
        }
    }

    var namedContextDescriptor: (any NamedContextDescriptorProtocol)? {
        switch self {
        case let .type(typeContextDescriptor):
            return typeContextDescriptor.namedContextDescriptor
        case let .protocol(protocolDescriptor):
            return protocolDescriptor
        case let .module(moduleContextDescriptor):
            return moduleContextDescriptor
        case .anonymous,
             .extension,
             .opaqueType:
            return nil
        }
    }
    
    subscript<Property>(dynamicMember keyPath: KeyPath<any ContextDescriptorProtocol, Property>) -> Property {
        return contextDescriptor[keyPath: keyPath]
    }
    
}
