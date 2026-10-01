import MachOKit
import MachOBase
import SwiftStdlibToolbox
import FoundationToolbox

@Loggable(.private, subsystem: "com.machoswiftsection.macho-swift-section", category: "ContextDescriptorWrapper")
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

    // MARK: - ReadingContext Support

    public func parent(in context: some ReadingContext) throws -> SymbolOrElement<ContextDescriptorWrapper>? {
        return try contextDescriptor.parent(in: context)
    }

    public func genericContext(in context: some ReadingContext) throws -> GenericContext? {
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

    public static func resolve<Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> Self {
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

    public static func resolve<Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> Self? {
        do {
            return try resolve(at: address, in: context) as Self
        } catch {
            #log(.error, "context descriptor at \(String(describing: address), privacy: .public) unresolvable, read as absent: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}

// MARK: - Deprecated Mach-O and pointer forms

extension ContextDescriptorWrapper {
    @available(*, deprecated, message: "Pass a ReadingContext: parent(in: machO.context).")
    public func parent(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> SymbolOrElement<ContextDescriptorWrapper>? {
        try parent(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: genericContext(in: machO.context).")
    public func genericContext(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> GenericContext? {
        try genericContext(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: parent(in: .inProcess).")
    public func parent() throws -> SymbolOrElement<ContextDescriptorWrapper>? {
        try parent(in: InProcessContext.shared)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: genericContext(in: .inProcess).")
    public func genericContext() throws -> GenericContext? {
        try genericContext(in: InProcessContext.shared)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: resolve(at: offset, in: machO.context).")
    public static func resolve(from offset: Int, in machO: some MachORepresentableWithCache & Readable) throws -> Self {
        try resolve(at: offset, in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: resolve(at: pointer, in: .inProcess).")
    public static func resolve(from ptr: UnsafeRawPointer) throws -> Self {
        try resolve(at: ptr, in: InProcessContext.shared)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: resolve(at: offset, in: machO.context).")
    public static func resolve(from offset: Int, in machO: some MachORepresentableWithCache & Readable) throws -> Self? {
        try resolve(at: offset, in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: resolve(at: pointer, in: .inProcess).")
    public static func resolve(from ptr: UnsafeRawPointer) throws -> Self? {
        try resolve(at: ptr, in: InProcessContext.shared)
    }
}
