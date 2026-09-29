/// Flags describing the layout of a generic metadata instantiation pattern.
///
/// Mirrors `swift::GenericMetadataPatternFlags`
/// (`swift/ABI/MetadataValues.h`). Two bits are general and the rest are
/// kind-specific, which is why bit 31 means two different things: for a class
/// pattern it is `Class_HasImmediateMembersPattern`, for a value pattern it is
/// the top bit of the metadata kind field. Read only the accessors that match
/// the pattern you have.
public struct GenericMetadataPatternFlags: RawRepresentable, Hashable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    private enum Constants {
        /// General flags build up from bit 0.
        static let hasExtraDataPatternBit: UInt32 = 0
        static let hasTrailingFlagsBit: UInt32 = 1
        /// Kind-specific flags build down from bit 31.
        static let classHasImmediateMembersPatternBit: UInt32 = 31
        /// Value-specific: the metadata kind to instantiate.
        static let valueMetadataKindShift: UInt32 = 21
        static let valueMetadataKindWidth: UInt32 = 11
    }

    private func bit(_ index: UInt32) -> Bool {
        rawValue & (1 << index) != 0
    }

    /// Whether a ``GenericMetadataPartialPattern`` trails the pattern
    /// describing extra data to be copied into the instantiated metadata.
    public var hasExtraDataPattern: Bool {
        bit(Constants.hasExtraDataPatternBit)
    }

    /// Whether instances of this pattern carry a trailing flag word after the
    /// metadata (and after the extra data, if any).
    public var hasTrailingFlags: Bool {
        bit(Constants.hasTrailingFlagsBit)
    }

    /// Class patterns only: whether a second ``GenericMetadataPartialPattern``
    /// trails, describing the class's immediate members.
    ///
    /// Meaningless on a value pattern, where this bit is part of
    /// ``valueMetadataKindRawValue``.
    public var classHasImmediateMembersPattern: Bool {
        bit(Constants.classHasImmediateMembersPatternBit)
    }

    /// Value patterns only: the raw metadata kind the instantiation produces.
    ///
    /// Meaningless on a class pattern, whose top bit is
    /// ``classHasImmediateMembersPattern``.
    public var valueMetadataKindRawValue: UInt32 {
        (rawValue >> Constants.valueMetadataKindShift) & ((1 << Constants.valueMetadataKindWidth) - 1)
    }

    /// Value patterns only: the metadata kind the instantiation produces, or
    /// `nil` when the field holds a value this library does not recognize.
    public var valueMetadataKind: MetadataKind? {
        MetadataKind(rawValue: valueMetadataKindRawValue)
    }
}
