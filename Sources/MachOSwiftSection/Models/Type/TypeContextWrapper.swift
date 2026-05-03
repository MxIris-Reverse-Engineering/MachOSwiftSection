import Foundation
import MachOKit
import MachOSymbols
import SwiftStdlibToolbox

@AssociatedValue(.public)
@CaseCheckable(.public)
public enum TypeContextWrapper: Sendable {
    case `enum`(Enum)
    case `struct`(Struct)
    case `class`(Class)

    public var contextDescriptorWrapper: ContextDescriptorWrapper {
        return .type(typeContextDescriptorWrapper)
    }

    public var typeContextDescriptorWrapper: TypeContextDescriptorWrapper {
        switch self {
        case .enum(let `enum`):
            return .enum(`enum`.descriptor)
        case .struct(let `struct`):
            return .struct(`struct`.descriptor)
        case .class(let `class`):
            return .class(`class`.descriptor)
        }
    }
    
    public func asPointerWrapper(in machO: MachOImage) throws -> Self {
        switch self {
        case .enum(let `enum`):
            return try .enum(.init(descriptor: `enum`.descriptor.asPointerWrapper(in: machO)))
        case .struct(let `struct`):
            return try .struct(.init(descriptor: `struct`.descriptor.asPointerWrapper(in: machO)))
        case .class(let `class`):
            return try .class(.init(descriptor: `class`.descriptor.asPointerWrapper(in: machO)))
        }
    }

    public static func forTypeContextDescriptorWrapper(_ typeContextDescriptorWrapper: TypeContextDescriptorWrapper) throws -> Self {
        switch typeContextDescriptorWrapper {
        case .enum(let enumDescriptor):
            return try .enum(.init(descriptor: enumDescriptor))
        case .struct(let structDescriptor):
            return try .struct(.init(descriptor: structDescriptor))
        case .class(let classDescriptor):
            return try .class(.init(descriptor: classDescriptor))
        }
    }

    public static func forTypeContextDescriptorWrapper(_ typeContextDescriptorWrapper: TypeContextDescriptorWrapper, in machO: some MachOSwiftSectionRepresentableWithCache) throws -> Self {
        switch typeContextDescriptorWrapper {
        case .enum(let enumDescriptor):
            return try .enum(.init(descriptor: enumDescriptor, in: machO))
        case .struct(let structDescriptor):
            return try .struct(.init(descriptor: structDescriptor, in: machO))
        case .class(let classDescriptor):
            return try .class(.init(descriptor: classDescriptor, in: machO))
        }
    }
}

// MARK: - ReadingContext Support

extension TypeContextWrapper {
    public static func forTypeContextDescriptorWrapper<Context: ReadingContext>(_ typeContextDescriptorWrapper: TypeContextDescriptorWrapper, in context: Context) throws -> Self {
        switch typeContextDescriptorWrapper {
        case .enum(let enumDescriptor):
            return try .enum(.init(descriptor: enumDescriptor, in: context))
        case .struct(let structDescriptor):
            return try .struct(.init(descriptor: structDescriptor, in: context))
        case .class(let classDescriptor):
            return try .class(.init(descriptor: classDescriptor, in: context))
        }
    }
}
