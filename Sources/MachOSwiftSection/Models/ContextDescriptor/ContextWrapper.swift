import Foundation
import MachOKit
import MachOMacro
import MachOFoundation

@CaseCheckable(.public)
@AssociatedValue(.public)
public enum ContextWrapper: Resolvable {
    case type(TypeWrapper)
    case `protocol`(`Protocol`)
    case anonymous(AnonymousContext)
    case `extension`(ExtensionContext)
    case module(ModuleContext)
    case opaqueType(OpaqueType)
    
    
    public var context: any ContextProtocol {
        switch self {
        case .type(let typeWrapper):
            switch typeWrapper {
            case .enum(let `enum`):
                return `enum`
            case .struct(let `struct`):
                return `struct`
            case .class(let `class`):
                return `class`
            }
        case .protocol(let protocolWrapper):
            return protocolWrapper
        case .anonymous(let anonymousContext):
            return anonymousContext
        case .extension(let extensionContext):
            return extensionContext
        case .module(let moduleContext):
            return moduleContext
        case .opaqueType(let opaqueType):
            return opaqueType
        }
    }
    
    
    public static func forContextDescriptorWrapper(_ contextDescriptorWrapper: ContextDescriptorWrapper, in machO: some MachORepresentableWithCache & MachOReadable) throws -> Self {
        switch contextDescriptorWrapper {
        case .type(let typeContextDescriptorWrapper):
            switch typeContextDescriptorWrapper {
            case .enum(let enumDescriptor):
                return try .type(.enum(.init(descriptor: enumDescriptor, in: machO)))
            case .struct(let structDescriptor):
                return try .type(.struct(.init(descriptor: structDescriptor, in: machO)))
            case .class(let classDescriptor):
                return try .type(.class(.init(descriptor: classDescriptor, in: machO)))
            }
        case .protocol(let protocolDescriptor):
            return try .protocol(.init(descriptor: protocolDescriptor, in: machO))
        case .anonymous(let anonymousContextDescriptor):
            return try .anonymous(.init(descriptor: anonymousContextDescriptor, in: machO))
        case .extension(let extensionContextDescriptor):
            return try .extension(.init(descriptor: extensionContextDescriptor, in: machO))
        case .module(let moduleContextDescriptor):
            return try .module(.init(descriptor: moduleContextDescriptor, in: machO))
        case .opaqueType(let opaqueTypeDescriptor):
            return try .opaqueType(.init(descriptor: opaqueTypeDescriptor, in: machO))
        }
    }

    public func parent(in machO: some MachORepresentableWithCache & MachOReadable) throws -> SymbolOrElement<ContextWrapper>? {
        switch self {
        case .type(let typeWrapper):
            switch typeWrapper {
            case .enum(let `enum`):
                return try `enum`.descriptor.parent(in: machO)?.map { try ContextWrapper.forContextDescriptorWrapper($0, in: machO) }
            case .struct(let `struct`):
                return try `struct`.descriptor.parent(in: machO)?.map { try ContextWrapper.forContextDescriptorWrapper($0, in: machO) }
            case .class(let `class`):
                return try `class`.descriptor.parent(in: machO)?.map { try ContextWrapper.forContextDescriptorWrapper($0, in: machO) }
            }
        case .protocol(let `protocol`):
            return try `protocol`.descriptor.parent(in: machO)?.map { try ContextWrapper.forContextDescriptorWrapper($0, in: machO) }
        case .anonymous(let anonymousContext):
            return try anonymousContext.descriptor.parent(in: machO)?.map { try ContextWrapper.forContextDescriptorWrapper($0, in: machO) }
        case .extension(let extensionContext):
            return try extensionContext.descriptor.parent(in: machO)?.map { try ContextWrapper.forContextDescriptorWrapper($0, in: machO) }
        case .module(let moduleContext):
            return try moduleContext.descriptor.parent(in: machO)?.map { try ContextWrapper.forContextDescriptorWrapper($0, in: machO) }
        case .opaqueType(let opaqueType):
            return try opaqueType.descriptor.parent(in: machO)?.map { try ContextWrapper.forContextDescriptorWrapper($0, in: machO) }
        }
    }
}
