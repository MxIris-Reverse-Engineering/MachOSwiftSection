import Foundation
import MachOSymbols

public enum TypeWrapper: Sendable {
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
}
