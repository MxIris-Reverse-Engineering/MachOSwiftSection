import MachOKit
import MachOBase
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
            print("Error resolving ContextDescriptorWrapper: \(error)")
            return nil
        }
    }
}

// MARK: - Deprecated Mach-O and pointer forms

extension TypeContextDescriptorWrapper {
    @available(*, deprecated, message: "Pass a ReadingContext: parent(in: machO.context).")
    public func parent(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> SymbolOrElement<ContextDescriptorWrapper>? {
        try parent(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: genericContext(in: machO.context).")
    public func genericContext(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> GenericContext? {
        try genericContext(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: typeGenericContext(in: machO.context).")
    public func typeGenericContext(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> TypeGenericContext? {
        try typeGenericContext(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: parent(in: .inProcess).")
    public func parent() throws -> SymbolOrElement<ContextDescriptorWrapper>? {
        try parent(in: InProcessContext.shared)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: genericContext(in: .inProcess).")
    public func genericContext() throws -> GenericContext? {
        try genericContext(in: InProcessContext.shared)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: typeGenericContext(in: .inProcess).")
    public func typeGenericContext() throws -> TypeGenericContext? {
        try typeGenericContext(in: InProcessContext.shared)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: resolve(at: offset, in: machO.context).")
    public static func resolve(from offset: Int, in machO: some MachORepresentableWithCache & Readable) throws -> Self {
        try resolve(at: offset, in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: resolve(at: offset, in: machO.context).")
    public static func resolve(from offset: Int, in machO: some MachORepresentableWithCache & Readable) throws -> Self? {
        try resolve(at: offset, in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: resolve(at: pointer, in: .inProcess).")
    public static func resolve(from ptr: UnsafeRawPointer) throws -> Self {
        try resolve(at: ptr, in: InProcessContext.shared)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: resolve(at: pointer, in: .inProcess).")
    public static func resolve(from ptr: UnsafeRawPointer) throws -> Self? {
        try resolve(at: ptr, in: InProcessContext.shared)
    }
}

extension ValueTypeDescriptorWrapper {
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

    @available(*, deprecated, message: "Pass a ReadingContext: resolve(at: offset, in: machO.context).")
    public static func resolve(from offset: Int, in machO: some MachORepresentableWithCache & Readable) throws -> Self? {
        try resolve(at: offset, in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: resolve(at: pointer, in: .inProcess).")
    public static func resolve(from ptr: UnsafeRawPointer) throws -> Self {
        try resolve(at: ptr, in: InProcessContext.shared)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: resolve(at: pointer, in: .inProcess).")
    public static func resolve(from ptr: UnsafeRawPointer) throws -> Self? {
        try resolve(at: ptr, in: InProcessContext.shared)
    }
}
