import MachOKit
import MachOFoundation
import SwiftStdlibToolbox

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

    public func parent() throws -> SymbolOrElement<ContextDescriptorWrapper>? {
        return try contextDescriptor.parent()
    }

    public func genericContext() throws -> GenericContext? {
        return try contextDescriptor.genericContext()
    }

    // MARK: - ReadingContext Support

    public func parent<Context: ReadingContext>(in context: Context) throws -> SymbolOrElement<ContextDescriptorWrapper>? {
        return try contextDescriptor.parent(in: context)
    }

    public func genericContext<Context: ReadingContext>(in context: Context) throws -> GenericContext? {
        return try contextDescriptor.genericContext(in: context)
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

    public static func resolve<MachO: MachORepresentableWithCache & Readable>(from offset: Int, in machO: MachO) throws -> Self {
        let contextDescriptor: ContextDescriptor = try machO.readWrapperElement(offset: offset)
        switch contextDescriptor.flags.kind {
        case .class,
             .struct,
             .enum:
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

    public static func resolve(from ptr: UnsafeRawPointer) throws -> Self {
        let contextDescriptor: ContextDescriptor = try .resolve(from: ptr)
        switch contextDescriptor.flags.kind {
        case .class,
             .struct,
             .enum:
            return try .type(.resolve(from: ptr))
        case .protocol:
            return try .protocol(.resolve(from: ptr))
        case .anonymous:
            return try .anonymous(.resolve(from: ptr))
        case .extension:
            return try .extension(.resolve(from: ptr))
        case .module:
            return try .module(.resolve(from: ptr))
        case .opaqueType:
            return try .opaqueType(.resolve(from: ptr))
        default:
            throw ResolutionError.invalidContextDescriptor
        }
    }

    public static func resolve<MachO: MachORepresentableWithCache & Readable>(from offset: Int, in machO: MachO) throws -> Self? {
        do {
            return try resolve(from: offset, in: machO) as Self
        } catch {
            print("Error resolving ContextDescriptorWrapper: \(error)")
            return nil
        }
    }

    public static func resolve(from ptr: UnsafeRawPointer) throws -> Self? {
        do {
            return try resolve(from: ptr) as Self
        } catch {
            print("Error resolving ContextDescriptorWrapper: \(error)")
            return nil
        }
    }

    // MARK: - ReadingContext Support

    public static func resolve<Context: ReadingContext>(
        at address: Context.Address,
        in context: Context
    ) throws -> Self {
        let contextDescriptor: ContextDescriptor = try context.readWrapperElement(at: address)
        switch contextDescriptor.flags.kind {
        case .class,
             .struct,
             .enum:
            return try .type(.resolve(at: address, in: context))
        case .protocol:
            return try .protocol(context.readWrapperElement(at: address))
        case .anonymous:
            return try .anonymous(context.readWrapperElement(at: address))
        case .extension:
            return try .extension(context.readWrapperElement(at: address))
        case .module:
            return try .module(context.readWrapperElement(at: address))
        case .opaqueType:
            return try .opaqueType(context.readWrapperElement(at: address))
        default:
            throw ResolutionError.invalidContextDescriptor
        }
    }

    public static func resolve<Context: ReadingContext>(
        at address: Context.Address,
        in context: Context
    ) throws -> Self? {
        do {
            return try resolve(at: address, in: context) as Self
        } catch {
            print("Error resolving ContextDescriptorWrapper: \(error)")
            return nil
        }
    }
}
