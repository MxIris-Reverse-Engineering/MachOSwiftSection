import Foundation

// https://github.com/apple/swift/blob/main/include/swift/ABI/MetadataValues.h#L1849
public struct ContextDescriptorFlags: OptionSet {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    /// The kind of context this descriptor describes.
    public var kind: ContextDescriptorKind {
        if let kind = ContextDescriptorKind(rawValue: UInt8(rawValue & 0x1F)) {
            return kind
        }
        return ContextDescriptorKind.unknown
    }

    /// Whether the context has information about invertible protocols, which
    /// will show up as a trailing field in the context descriptor.
    public static let hasInvertibleProtocols = ContextDescriptorFlags(rawValue: 0x20)

    /// Whether this is a unique record describing the referenced context.
    public static let isUnique = ContextDescriptorFlags(rawValue: 0x40)

    /// Whether the context being described is generic.
    public static let isGeneric = ContextDescriptorFlags(rawValue: 0x80)

    /// The format version of the descriptor. Higher version numbers may have
    /// additional fields that aren't present in older versions.
    public var version: UInt8 {
        return UInt8((rawValue >> 8) & 0xFF)
    }

    public var kindSpecificFlagsRawValue: UInt16 {
        return UInt16((rawValue >> 16) & 0xFFFF)
    }

    /// The most significant two bytes of the flags word, which can have
    /// kind-specific meaning.
    public var kindSpecificFlags: ContextDescriptorKindSpecificFlags? {
        let rawValue = kindSpecificFlagsRawValue
        switch kind {
        case .anonymous:
            return .anonymous(.init(rawValue: rawValue))
        case .protocol:
            return .protocol(.init(rawValue: rawValue))
        case .class,
             .struct,
             .enum:
            return .type(.init(rawValue: rawValue))
        default:
            return nil
        }
    }
    
    public var hasInvertibleProtocols: Bool {
        contains(.hasInvertibleProtocols)
    }
    
    public var isUnique: Bool {
        contains(.isUnique)
    }
    
    public var isGeneric: Bool {
        contains(.isGeneric)
    }
}
