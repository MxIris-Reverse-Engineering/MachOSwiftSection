import MachOKit
import MachOFoundation
import MachOMacro

@dynamicMemberLookup
public enum ContextDescriptorWrapper {
    case type(TypeContextDescriptorWrapper)
    case `protocol`(ProtocolDescriptor)
    case anonymous(AnonymousContextDescriptor)
    case `extension`(ExtensionContextDescriptor)
    case module(ModuleContextDescriptor)
    case opaqueType(OpaqueTypeDescriptor)

    public var protocolDescriptor: ProtocolDescriptor? {
        if case let .protocol(descriptor) = self {
            return descriptor
        } else {
            return nil
        }
    }

    public var extensionContextDescriptor: ExtensionContextDescriptor? {
        if case let .extension(descriptor) = self {
            return descriptor
        } else {
            return nil
        }
    }

    public var opaqueTypeDescriptor: OpaqueTypeDescriptor? {
        if case let .opaqueType(descriptor) = self {
            return descriptor
        } else {
            return nil
        }
    }

    public var moduleContextDescriptor: ModuleContextDescriptor? {
        if case let .module(descriptor) = self {
            return descriptor
        } else {
            return nil
        }
    }

    public var anonymousContextDescriptor: AnonymousContextDescriptor? {
        if case let .anonymous(descriptor) = self {
            return descriptor
        } else {
            return nil
        }
    }

    public var isType: Bool {
        switch self {
        case .type:
            return true
        default:
            return false
        }
    }

    public var isProtocol: Bool {
        switch self {
        case .protocol:
            return true
        default:
            return false
        }
    }

    public func parent<MachO: MachORepresentableWithCache & MachOReadable>(in machO: MachO) throws -> SymbolOrElement<ContextDescriptorWrapper>? {
        return try contextDescriptor.parent(in: machO)
    }

    public var contextDescriptor: any ContextDescriptorProtocol {
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

    public var namedContextDescriptor: (any NamedContextDescriptorProtocol)? {
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

    public var typeContextDescriptor: (any TypeContextDescriptorProtocol)? {
        if case let .type(typeContextDescriptor) = self {
            switch typeContextDescriptor {
            case let .enum(enumDescriptor):
                return enumDescriptor
            case let .struct(structDescriptor):
                return structDescriptor
            case let .class(classDescriptor):
                return classDescriptor
            }
        } else {
            return nil
        }
    }

    public subscript<Property>(dynamicMember keyPath: KeyPath<any ContextDescriptorProtocol, Property>) -> Property {
        return contextDescriptor[keyPath: keyPath]
    }
}

extension ContextDescriptorWrapper: Resolvable {
    public enum ResolutionError: Error {
        case invalidContextDescriptor
    }

    public static func resolve<MachO: MachORepresentableWithCache & MachOReadable>(from offset: Int, in machO: MachO) throws -> Self {
        let contextDescriptor: ContextDescriptor = try machO.readWrapperElement(offset: offset)
        switch contextDescriptor.flags.kind {
        case .class:
            return try .type(.class(machO.readWrapperElement(offset: offset)))
        case .enum:
            return try .type(.enum(machO.readWrapperElement(offset: offset)))
        case .struct:
            return try .type(.struct(machO.readWrapperElement(offset: offset)))
        case .protocol:
            return try .protocol(machO.readWrapperElement(offset: offset))
        case .anonymous:
            return try .anonymous(machO.readWrapperElement(offset: offset))
        case .extension:
            return try .extension(machO.readWrapperElement(offset: offset))
        case .module:
            return try .module(machO.readWrapperElement(offset: offset))
        case .opaqueType:
            return try .opaqueType(machO.readWrapperElement(offset: offset))
        default:
            throw ResolutionError.invalidContextDescriptor
        }
    }

    public static func resolve<MachO: MachORepresentableWithCache & MachOReadable>(from offset: Int, in machO: MachO) throws -> Self? {
        do {
            return try resolve(from: offset, in: machO) as Self
        } catch {
            print("Error resolving ContextDescriptorWrapper: \(error)")
            return nil
        }
    }
}
