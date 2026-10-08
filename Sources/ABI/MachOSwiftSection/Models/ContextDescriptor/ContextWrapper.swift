import Foundation
import MachOKit
import FoundationToolbox
import MachOBase

@CaseCheckable(.public)
@AssociatedValue(.public)
public enum ContextWrapper: Resolvable {
    case type(TypeContextWrapper)
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
}

// MARK: - ReadingContext Support

extension ContextWrapper {
    public static func forContextDescriptorWrapper(_ contextDescriptorWrapper: ContextDescriptorWrapper, in context: some ReadingContext) throws -> Self {
        switch contextDescriptorWrapper {
        case .type(let typeContextDescriptorWrapper):
            switch typeContextDescriptorWrapper {
            case .enum(let enumDescriptor):
                return try .type(.enum(.init(descriptor: enumDescriptor, in: context)))
            case .struct(let structDescriptor):
                return try .type(.struct(.init(descriptor: structDescriptor, in: context)))
            case .class(let classDescriptor):
                return try .type(.class(.init(descriptor: classDescriptor, in: context)))
            }
        case .protocol(let protocolDescriptor):
            return try .protocol(.init(descriptor: protocolDescriptor, in: context))
        case .anonymous(let anonymousContextDescriptor):
            return try .anonymous(.init(descriptor: anonymousContextDescriptor, in: context))
        case .extension(let extensionContextDescriptor):
            return try .extension(.init(descriptor: extensionContextDescriptor, in: context))
        case .module(let moduleContextDescriptor):
            return try .module(.init(descriptor: moduleContextDescriptor, in: context))
        case .opaqueType(let opaqueTypeDescriptor):
            return try .opaqueType(.init(descriptor: opaqueTypeDescriptor, in: context))
        }
    }

    public func parent(in context: some ReadingContext) throws -> SymbolOrElement<ContextWrapper>? {
        switch self {
        case .type(let typeWrapper):
            switch typeWrapper {
            case .enum(let `enum`):
                return try `enum`.descriptor.parent(in: context)?.map { try ContextWrapper.forContextDescriptorWrapper($0, in: context) }
            case .struct(let `struct`):
                return try `struct`.descriptor.parent(in: context)?.map { try ContextWrapper.forContextDescriptorWrapper($0, in: context) }
            case .class(let `class`):
                return try `class`.descriptor.parent(in: context)?.map { try ContextWrapper.forContextDescriptorWrapper($0, in: context) }
            }
        case .protocol(let `protocol`):
            return try `protocol`.descriptor.parent(in: context)?.map { try ContextWrapper.forContextDescriptorWrapper($0, in: context) }
        case .anonymous(let anonymousContext):
            return try anonymousContext.descriptor.parent(in: context)?.map { try ContextWrapper.forContextDescriptorWrapper($0, in: context) }
        case .extension(let extensionContext):
            return try extensionContext.descriptor.parent(in: context)?.map { try ContextWrapper.forContextDescriptorWrapper($0, in: context) }
        case .module(let moduleContext):
            return try moduleContext.descriptor.parent(in: context)?.map { try ContextWrapper.forContextDescriptorWrapper($0, in: context) }
        case .opaqueType(let opaqueType):
            return try opaqueType.descriptor.parent(in: context)?.map { try ContextWrapper.forContextDescriptorWrapper($0, in: context) }
        }
    }
}

// MARK: - Deprecated Mach-O and pointer forms

extension ContextWrapper {
    @available(*, deprecated, message: "Pass a ReadingContext: forContextDescriptorWrapper(_:in: machO.context).")
    public static func forContextDescriptorWrapper(_ contextDescriptorWrapper: ContextDescriptorWrapper, in machO: some MachOSwiftSectionRepresentableWithCache) throws -> Self {
        try forContextDescriptorWrapper(contextDescriptorWrapper, in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: parent(in: machO.context).")
    public func parent(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> SymbolOrElement<ContextWrapper>? {
        try parent(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: forContextDescriptorWrapper(_:in: .inProcess).")
    public static func forContextDescriptorWrapper(_ contextDescriptorWrapper: ContextDescriptorWrapper) throws -> Self {
        try forContextDescriptorWrapper(contextDescriptorWrapper, in: InProcessContext.shared)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: parent(in: .inProcess).")
    public func parent() throws -> SymbolOrElement<ContextWrapper>? {
        try parent(in: InProcessContext.shared)
    }
}
