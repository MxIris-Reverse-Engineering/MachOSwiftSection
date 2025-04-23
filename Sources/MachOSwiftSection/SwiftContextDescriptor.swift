
// https://github.com/apple/swift/blob/main/include/swift/ABI/MetadataValues.h#L1183
public enum SwiftContextDescriptorKind: UInt8, CustomStringConvertible {
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

    case unknown = 0xFF // It's not in swift source, this value only used for dump

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
}

// https://github.com/apple/swift/blob/main/include/swift/ABI/MetadataValues.h#L1849
public struct SwiftContextDescriptorFlags {
    public let value: UInt32

    public init(_ value: UInt32) {
        self.value = value
    }

    /// The kind of context this descriptor describes.
    public var kind: SwiftContextDescriptorKind {
        if let kind = SwiftContextDescriptorKind(rawValue: UInt8(value & 0x1F)) {
            return kind
        }
        return SwiftContextDescriptorKind.unknown
    }

    /// Whether the context being described is generic.
    public var isGeneric: Bool {
        return (value & 0x80) != 0
    }

    /// Whether this is a unique record describing the referenced context.
    public var isUnique: Bool {
        return (value & 0x40) != 0
    }

    /// Whether the context has information about invertible protocols, which
    /// will show up as a trailing field in the context descriptor.
    public var hasInvertibleProtocols: Bool {
        return (value & 0x20) != 0
    }

    /// The format version of the descriptor. Higher version numbers may have
    /// additional fields that aren't present in older versions.
    public var version: UInt8 {
        return UInt8((value >> 8) & 0xFF)
    }

    /// The most significant two bytes of the flags word, which can have
    /// kind-specific meaning.
    public var kindSpecificFlags: UInt16 {
        return UInt16((value >> 16) & 0xFFFF)
    }
}
