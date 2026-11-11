import MachOKit
import MachOBase
import SwiftStdlibToolbox
import FoundationToolbox

@CaseCheckable(.public)
@AssociatedValue(.public)
@Loggable(.private, subsystem: "com.machoswiftsection.macho-swift-section", category: "TypeContextDescriptorWrapper")
public enum TypeContextDescriptorWrapper {
    case `enum`(EnumDescriptor)
    case `struct`(StructDescriptor)
    case `class`(ClassDescriptor)

    public var contextDescriptor: any ContextDescriptorProtocol {
        switch self {
        case .enum(let enumDescriptor):
            return enumDescriptor
        case .struct(let structDescriptor):
            return structDescriptor
        case .class(let classDescriptor):
            return classDescriptor
        }
    }

    public var namedContextDescriptor: any NamedContextDescriptorProtocol {
        switch self {
        case .enum(let enumDescriptor):
            return enumDescriptor
        case .struct(let structDescriptor):
            return structDescriptor
        case .class(let classDescriptor):
            return classDescriptor
        }
    }

    public var typeContextDescriptor: any TypeContextDescriptorProtocol {
        switch self {
        case .enum(let enumDescriptor):
            return enumDescriptor
        case .struct(let structDescriptor):
            return structDescriptor
        case .class(let classDescriptor):
            return classDescriptor
        }
    }

    // MARK: - ReadingContext Support

    public func parent(in context: some ReadingContext) throws -> SymbolOrElement<ContextDescriptorWrapper>? {
        return try contextDescriptor.parent(in: context)
    }

    public func genericContext(in context: some ReadingContext) throws -> GenericContext? {
        return try contextDescriptor.genericContext(in: context)
    }

    public func typeGenericContext(in context: some ReadingContext) throws -> TypeGenericContext? {
        return try typeContextDescriptor.typeGenericContext(in: context)
    }

    public var asContextDescriptorWrapper: ContextDescriptorWrapper {
        return .type(self)
    }
    
    public func asPointerWrapper(in machO: MachOImage) -> Self {
        switch self {
        case .enum(let enumDescriptor):
            return .enum(enumDescriptor.asPointerWrapper(in: machO))
        case .struct(let structDescriptor):
            return .struct(structDescriptor.asPointerWrapper(in: machO))
        case .class(let classDescriptor):
            return .class(classDescriptor.asPointerWrapper(in: machO))
        }
    }
}

extension TypeContextDescriptorWrapper: Resolvable {
    public enum ResolutionError: Error {
        case invalidTypeContextDescriptor
    }

    // MARK: - ReadingContext Support

    public static func resolve<Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> Self {
        let contextDescriptor: ContextDescriptor = try context.readWrapperElement(at: address)
        switch contextDescriptor.flags.kind {
        case .class:
            return try .class(context.readWrapperElement(at: address))
        case .enum:
            return try .enum(context.readWrapperElement(at: address))
        case .struct:
            return try .struct(context.readWrapperElement(at: address))
        default:
            throw ResolutionError.invalidTypeContextDescriptor
        }
    }

    public static func resolve<Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> Self? {
        do {
            return try resolve(at: address, in: context) as Self
        } catch {
            #log(.error, "type context descriptor at \(String(describing: address), privacy: .public) unresolvable, read as absent: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}

@CaseCheckable(.public)
@AssociatedValue(.public)
@Loggable(.private, subsystem: "com.machoswiftsection.macho-swift-section", category: "ValueTypeDescriptorWrapper")
public enum ValueTypeDescriptorWrapper {
    case `enum`(EnumDescriptor)
    case `struct`(StructDescriptor)

    public var contextDescriptor: any ContextDescriptorProtocol {
        switch self {
        case .enum(let enumDescriptor):
            return enumDescriptor
        case .struct(let structDescriptor):
            return structDescriptor
        }
    }

    public var namedContextDescriptor: any NamedContextDescriptorProtocol {
        switch self {
        case .enum(let enumDescriptor):
            return enumDescriptor
        case .struct(let structDescriptor):
            return structDescriptor
        }
    }

    public var typeContextDescriptor: any TypeContextDescriptorProtocol {
        switch self {
        case .enum(let enumDescriptor):
            return enumDescriptor
        case .struct(let structDescriptor):
            return structDescriptor
        }
    }

    // MARK: - ReadingContext Support

    public func parent(in context: some ReadingContext) throws -> SymbolOrElement<ContextDescriptorWrapper>? {
        return try contextDescriptor.parent(in: context)
    }

    public func genericContext(in context: some ReadingContext) throws -> GenericContext? {
        return try contextDescriptor.genericContext(in: context)
    }

    public var asTypeContextDescriptorWrapper: TypeContextDescriptorWrapper {
        switch self {
        case .enum(let enumDescriptor):
            return .enum(enumDescriptor)
        case .struct(let structDescriptor):
            return .struct(structDescriptor)
        }
    }
    
    public var asContextDescriptorWrapper: ContextDescriptorWrapper {
        return .type(asTypeContextDescriptorWrapper)
    }
}

extension ValueTypeDescriptorWrapper: Resolvable {
    public enum ResolutionError: Error {
        case invalidTypeContextDescriptor
    }

    public static func resolve<Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> Self {
        let contextDescriptor: ContextDescriptor = try context.readWrapperElement(at: address)
        switch contextDescriptor.flags.kind {
        case .enum:
            return try .enum(context.readWrapperElement(at: address))
        case .struct:
            return try .struct(context.readWrapperElement(at: address))
        default:
            throw ResolutionError.invalidTypeContextDescriptor
        }
    }

    public static func resolve<Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> Self? {
        do {
            return try resolve(at: address, in: context) as Self
        } catch {
            #log(.error, "value type descriptor at \(String(describing: address), privacy: .public) unresolvable, read as absent: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}
