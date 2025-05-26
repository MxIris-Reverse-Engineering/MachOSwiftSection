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
        if case .protocol(let descriptor) = self {
            return descriptor
        } else {
            return nil
        }
    }

    var extensionContextDescriptor: ExtensionContextDescriptor? {
        if case .extension(let descriptor) = self {
            return descriptor
        } else {
            return nil
        }
    }

    var opaqueTypeDescriptor: OpaqueTypeDescriptor? {
        if case .opaqueType(let descriptor) = self {
            return descriptor
        } else {
            return nil
        }
    }

    var moduleContextDescriptor: ModuleContextDescriptor? {
        if case .module(let descriptor) = self {
            return descriptor
        } else {
            return nil
        }
    }

    var anonymousContextDescriptor: AnonymousContextDescriptor? {
        if case .anonymous(let descriptor) = self {
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

    func parent(in machOFile: MachOFile) throws -> ResolvableElement<ContextDescriptorWrapper>? {
        return try contextDescriptor.parent(in: machOFile)
    }

    func name(in machOFile: MachOFile) throws -> String? {
        if case .extension(let extensionContextDescriptor) = self {
            return try extensionContextDescriptor.extendedContext(in: machOFile).map { try MetadataReader.demangleType(for: $0, in: machOFile) }
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

extension ContextDescriptorWrapper: Resolvable {
    
    public enum ResolutionError: Error {
        case invalidContextDescriptor
    }
    
    public static func resolve(from offset: Int, in machOFile: MachOFile) throws -> Self {
        let contextDescriptor: ContextDescriptor = try machOFile.readElement(offset: offset)
        switch contextDescriptor.flags.kind {
        case .class:
            return try .type(.class(machOFile.readElement(offset: offset)))
        case .enum:
            return try .type(.enum(machOFile.readElement(offset: offset)))
        case .struct:
            return try .type(.struct(machOFile.readElement(offset: offset)))
        case .protocol:
            return try .protocol(machOFile.readElement(offset: offset))
        case .anonymous:
            return try .anonymous(machOFile.readElement(offset: offset))
        case .extension:
            return try .extension(machOFile.readElement(offset: offset))
        case .module:
            return try .module(machOFile.readElement(offset: offset))
        case .opaqueType:
            return try .opaqueType(machOFile.readElement(offset: offset))
        default:
            throw ResolutionError.invalidContextDescriptor
        }
    }
    
    public static func resolve(from offset: Int, in machOFile: MachOFile) throws -> Self? {
        do {
            return try resolve(from: offset, in: machOFile) as Self
        } catch {
            print("Error resolving ContextDescriptorWrapper: \(error)")
            return nil
        }
    }
}
