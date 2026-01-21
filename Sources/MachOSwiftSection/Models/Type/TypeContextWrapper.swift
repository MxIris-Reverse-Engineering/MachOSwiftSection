import Foundation
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
            .enum(`enum`.descriptor)
        case .struct(let `struct`):
            .struct(`struct`.descriptor)
        case .class(let `class`):
            .class(`class`.descriptor)
        }
    }

    public static func forTypeContextDescriptorWrapper(_ typeContextDescriptorWrapper: TypeContextDescriptorWrapper) throws -> Self {
        switch typeContextDescriptorWrapper {
        case .enum(let enumDescriptor):
            try .enum(.init(descriptor: enumDescriptor))
        case .struct(let structDescriptor):
            try .struct(.init(descriptor: structDescriptor))
        case .class(let classDescriptor):
            try .class(.init(descriptor: classDescriptor))
        }
    }

    public static func forTypeContextDescriptorWrapper(_ typeContextDescriptorWrapper: TypeContextDescriptorWrapper, in machO: some MachOSwiftSectionRepresentableWithCache) throws -> Self {
        switch typeContextDescriptorWrapper {
        case .enum(let enumDescriptor):
            try .enum(.init(descriptor: enumDescriptor, in: machO))
        case .struct(let structDescriptor):
            try .struct(.init(descriptor: structDescriptor, in: machO))
        case .class(let classDescriptor):
            try .class(.init(descriptor: classDescriptor, in: machO))
        }
    }
}
