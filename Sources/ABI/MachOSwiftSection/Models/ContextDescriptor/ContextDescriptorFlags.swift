import Foundation
import SwiftStdlibToolbox

/// https://github.com/apple/swift/blob/main/include/swift/ABI/MetadataValues.h#L1849
public struct ContextDescriptorFlags: OptionSet, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    /// The kind of context this descriptor describes, or `.unknown` for a
    /// kind this reader does not know.
    @BitField(bits: 0..<5, default: ContextDescriptorKind.unknown)
    public var kind: ContextDescriptorKind

    /// Whether the context has information about invertible protocols, which
    /// will show up as a trailing field in the context descriptor.
    public static let hasInvertibleProtocols = ContextDescriptorFlags(rawValue: 0x20)

    /// Whether this is a unique record describing the referenced context.
    public static let isUnique = ContextDescriptorFlags(rawValue: 0x40)

    /// Whether the context being described is generic.
    public static let isGeneric = ContextDescriptorFlags(rawValue: 0x80)

    /// The format version of the descriptor. Higher version numbers may have
    /// additional fields that aren't present in older versions.
    @BitField(bits: 8..<16)
    public var version: UInt8

    @BitField(bits: 16..<32)
    public var kindSpecificFlagsRawValue: UInt16

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

    @BitField(bits: 5)
    public var hasInvertibleProtocols: Bool

    @BitField(bits: 6)
    public var isUnique: Bool

    @BitField(bits: 7)
    public var isGeneric: Bool
}
