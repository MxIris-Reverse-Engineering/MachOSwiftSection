import MachOKit
import MachOFoundation
import MachOMacro

public enum ContextDescriptorWrapper {
    case type(TypeContextDescriptorWrapper)
    case `protocol`(ProtocolDescriptor)
    case anonymous(AnonymousContextDescriptor)
    case `extension`(ExtensionContextDescriptor)
    case module(ModuleContextDescriptor)
    case opaqueType(OpaqueTypeDescriptor)

    public var protocolDescriptor: ProtocolDescriptor? {
        if case .protocol(let descriptor) = self {
            return descriptor
        } else {
            return nil
        }
    }

    public var extensionContextDescriptor: ExtensionContextDescriptor? {
        if case .extension(let descriptor) = self {
            return descriptor
        } else {
            return nil
        }
    }

    public var opaqueTypeDescriptor: OpaqueTypeDescriptor? {
        if case .opaqueType(let descriptor) = self {
            return descriptor
        } else {
            return nil
        }
    }

    public var moduleContextDescriptor: ModuleContextDescriptor? {
        if case .module(let descriptor) = self {
            return descriptor
        } else {
            return nil
        }
    }

    public var anonymousContextDescriptor: AnonymousContextDescriptor? {
        if case .anonymous(let descriptor) = self {
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
    
    public var isEnum: Bool {
        if case .type(.enum) = self {
            return true
        } else {
            return false
        }
    }
    
    public var isStruct: Bool {
        if case .type(.struct) = self {
            return true
        } else {
            return false
        }
    }
    
    public var isClass: Bool {
        if case .type(.class) = self {
            return true
        } else {
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

    public var isAnonymous: Bool {
        switch self {
        case .anonymous:
            return true
        default:
            return false
        }
    }

    public var isExtension: Bool {
        switch self {
        case .extension:
            return true
        default:
            return false
        }
    }

    public var isModule: Bool {
        switch self {
        case .module:
            return true
        default:
            return false
        }
    }

    public var isOpaqueType: Bool {
        switch self {
        case .opaqueType:
            return true
        default:
            return false
        }
    }

    public func parent<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> SymbolOrElement<ContextDescriptorWrapper>? {
        return try contextDescriptor.parent(in: machO)
    }

    public func genericContext<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> GenericContext? {
        return try contextDescriptor.genericContext(in: machO)
    }
    
    public var contextDescriptor: any ContextDescriptorProtocol {
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

    public var namedContextDescriptor: (any NamedContextDescriptorProtocol)? {
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

    public var typeContextDescriptor: (any TypeContextDescriptorProtocol)? {
        if case .type(let typeContextDescriptor) = self {
            switch typeContextDescriptor {
            case .enum(let enumDescriptor):
                return enumDescriptor
            case .struct(let structDescriptor):
                return structDescriptor
            case .class(let classDescriptor):
                return classDescriptor
            }
        } else {
            return nil
        }
    }

    public var typeContextDescriptorWrapper: TypeContextDescriptorWrapper? {
        if case .type(let typeContextDescriptor) = self {
            return typeContextDescriptor
        } else {
            return nil
        }
    }
}

extension ContextDescriptorWrapper: Resolvable {
    public enum ResolutionError: Error {
        case invalidContextDescriptor
    }

    public static func resolve<MachO: MachORepresentableWithCache & MachOReadable>(from offset: Int, in machO: MachO) throws -> Self {
        let contextDescriptor: ContextDescriptor = try machO.readWrapperElement(offset: offset)
        switch contextDescriptor.flags.kind {
        case .class, .struct, .enum:
            return try .type(.resolve(from: offset, in: machO))
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
