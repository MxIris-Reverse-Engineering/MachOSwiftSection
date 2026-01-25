import MachOKit
import MachOFoundation
import SwiftStdlibToolbox

@CaseCheckable(.public)
@AssociatedValue(.public)
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

    public func parent<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> SymbolOrElement<ContextDescriptorWrapper>? {
        return try contextDescriptor.parent(in: machO)
    }

    public func genericContext<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> GenericContext? {
        return try contextDescriptor.genericContext(in: machO)
    }

    public func typeGenericContext<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> TypeGenericContext? {
        return try typeContextDescriptor.typeGenericContext(in: machO)
    }
    
    public func parent() throws -> SymbolOrElement<ContextDescriptorWrapper>? {
        return try contextDescriptor.parent()
    }

    public func genericContext() throws -> GenericContext? {
        return try contextDescriptor.genericContext()
    }
    
    public func typeGenericContext() throws -> TypeGenericContext? {
        return try typeContextDescriptor.typeGenericContext()
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

    public static func resolve<MachO: MachORepresentableWithCache & Readable>(from offset: Int, in machO: MachO) throws -> Self {
        let contextDescriptor: ContextDescriptor = try machO.readWrapperElement(offset: offset)
        switch contextDescriptor.flags.kind {
        case .class:
            return try .class(machO.readWrapperElement(offset: offset))
        case .enum:
            return try .enum(machO.readWrapperElement(offset: offset))
        case .struct:
            return try .struct(machO.readWrapperElement(offset: offset))
        default:
            throw ResolutionError.invalidTypeContextDescriptor
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

    public static func resolve(from ptr: UnsafeRawPointer) throws -> Self {
        let contextDescriptor = try ContextDescriptor.resolve(from: ptr)
        switch contextDescriptor.flags.kind {
        case .class:
            return try .class(.resolve(from: ptr))
        case .enum:
            return try .enum(.resolve(from: ptr))
        case .struct:
            return try .struct(.resolve(from: ptr))
        default:
            throw ResolutionError.invalidTypeContextDescriptor
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

    public static func resolve<Context: ReadingContext>(
        at address: Context.Address,
        in context: Context
    ) throws -> Self? {
        do {
            return try resolve(at: address, in: context) as Self
        } catch {
            print("Error resolving TypeContextDescriptorWrapper: \(error)")
            return nil
        }
    }
}

@CaseCheckable(.public)
@AssociatedValue(.public)
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

    public static func resolve<MachO: MachORepresentableWithCache & Readable>(from offset: Int, in machO: MachO) throws -> Self {
        let contextDescriptor: ContextDescriptor = try machO.readWrapperElement(offset: offset)
        switch contextDescriptor.flags.kind {
        case .enum:
            return try .enum(machO.readWrapperElement(offset: offset))
        case .struct:
            return try .struct(machO.readWrapperElement(offset: offset))
        default:
            throw ResolutionError.invalidTypeContextDescriptor
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

    public static func resolve(from ptr: UnsafeRawPointer) throws -> Self {
        let contextDescriptor = try ContextDescriptor.resolve(from: ptr)
        switch contextDescriptor.flags.kind {
        case .enum:
            return try .enum(.resolve(from: ptr))
        case .struct:
            return try .struct(.resolve(from: ptr))
        default:
            throw ResolutionError.invalidTypeContextDescriptor
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
}
