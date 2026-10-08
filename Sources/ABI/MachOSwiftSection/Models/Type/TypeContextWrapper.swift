import Foundation
import MachOKit
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
            return try .enum(.init(descriptor: `enum`.descriptor.asPointerWrapper(in: machO), in: InProcessContext.shared))
        case .struct(let `struct`):
            return try .struct(.init(descriptor: `struct`.descriptor.asPointerWrapper(in: machO), in: InProcessContext.shared))
        case .class(let `class`):
            return try .class(.init(descriptor: `class`.descriptor.asPointerWrapper(in: machO), in: InProcessContext.shared))
        }
    }
}

// MARK: - ReadingContext Support

extension TypeContextWrapper {
    public static func forTypeContextDescriptorWrapper(_ typeContextDescriptorWrapper: TypeContextDescriptorWrapper, in context: some ReadingContext) throws -> Self {
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

// MARK: - Deprecated Mach-O and pointer forms

extension TypeContextWrapper {
    @available(*, deprecated, message: "Pass a ReadingContext: forTypeContextDescriptorWrapper(_:in: .inProcess).")
    public static func forTypeContextDescriptorWrapper(_ typeContextDescriptorWrapper: TypeContextDescriptorWrapper) throws -> Self {
        try forTypeContextDescriptorWrapper(typeContextDescriptorWrapper, in: InProcessContext.shared)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: forTypeContextDescriptorWrapper(_:in: machO.context).")
    public static func forTypeContextDescriptorWrapper(_ typeContextDescriptorWrapper: TypeContextDescriptorWrapper, in machO: some MachOSwiftSectionRepresentableWithCache) throws -> Self {
        try forTypeContextDescriptorWrapper(typeContextDescriptorWrapper, in: machO.context)
    }
}
