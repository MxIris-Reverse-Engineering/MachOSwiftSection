import Foundation

// https://github.com/apple/swift/blob/main/include/swift/ABI/MetadataValues.h#L1183
public enum ContextDescriptorKind: UInt8, CustomStringConvertible {
    /// This context descriptor represents a module.
    case module = 0

    /// This context descriptor represents an extension.
    case `extension` = 1

    /// This context descriptor represents an anonymous possibly-generic context
    /// such as a function body.
    case anonymous = 2

    /// This context descriptor represents a protocol context.
    case `protocol` = 3

    /// This context descriptor represents an opaque type alias.
    case opaqueType = 4

    /// First kind that represents a type of any sort.
    // case Type_First = 16

    /// This context descriptor represents a class.
    case `class` = 16 // Type_First

    /// This context descriptor represents a struct.
    case `struct` = 17 // Type_First + 1

    /// This context descriptor represents an enum.
    case `enum` = 18 // Type_First + 2

    /// Last kind that represents a type of any sort.
    case typeLast = 31

    /// It's not in swift source, this value only used for dump
    case unknown = 0xFF

    public var description: String {
        switch self {
        case .module: return "module"
        case .extension: return "extension"
        case .anonymous: return "anonymous"
        case .protocol: return "protocol"
        case .opaqueType: return "OpaqueType"
        case .class: return "class"
        case .struct: return "struct"
        case .enum: return "enum"
        case .typeLast: return "typeLast"
        case .unknown: return "unknown"
        }
    }

    public var mangledType: String {
        switch self {
        case .module:
            ""
        case .extension:
            ""
        case .anonymous:
            ""
        case .protocol:
            "P"
        case .opaqueType:
            ""
        case .class:
            "C"
        case .struct:
            "V"
        case .enum:
            "O"
        case .typeLast:
            ""
        case .unknown:
            "XY"
        }
    }
}
