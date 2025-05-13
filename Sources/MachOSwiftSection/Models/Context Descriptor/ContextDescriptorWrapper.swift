//
//  ContextDescriptorWrapper.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/5.
//

import MachOKit

public enum ContextDescriptorWrapper: ResolvableElement {
    case type(TypeContextDescriptorWrapper)
    case `protocol`(ProtocolDescriptor)
    case anonymous(AnonymousContextDescriptor)
    case `extension`(ExtensionContextDescriptor)
    case module(ModuleContextDescriptor)
    case opaqueType(OpaqueTypeDescriptor)
    
    func name(in machO: MachOFile) throws -> String? {
        if case let .extension(extensionContextDescriptor) = self {
            return try extensionContextDescriptor.extendedContext(in: machO).map { try MetadataReader.demangle(for: $0, in: machO) }
        } else {
            return try namedContextDescriptor?.name(in: machO)
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

extension ContextDescriptorWrapper {
    public static func resolve(from fileOffset: Int, in machO: MachOFile) throws -> Self? {
        guard let contextDescriptor = try machO.swift._readContextDescriptor(from: fileOffset) else { return nil }
        return contextDescriptor
    }
}
