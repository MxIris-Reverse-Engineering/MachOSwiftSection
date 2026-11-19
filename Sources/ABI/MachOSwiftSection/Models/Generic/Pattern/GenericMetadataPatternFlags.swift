import SwiftStdlibToolbox

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

    /// Whether a ``GenericMetadataPartialPattern`` trails the pattern
    /// describing extra data to be copied into the instantiated metadata.
    @BitField(bits: 0)
    public var hasExtraDataPattern: Bool

    /// Whether instances of this pattern carry a trailing flag word after the
    /// metadata (and after the extra data, if any).
    @BitField(bits: 1)
    public var hasTrailingFlags: Bool

    /// Class patterns only: whether a second ``GenericMetadataPartialPattern``
    /// trails, describing the class's immediate members.
    ///
    /// Meaningless on a value pattern, where this bit is part of
    /// ``valueMetadataKindRawValue``.
    @BitField(bits: 31)
    public var classHasImmediateMembersPattern: Bool

    /// Value patterns only: the raw metadata kind the instantiation produces.
    ///
    /// Meaningless on a class pattern, whose top bit is
    /// ``classHasImmediateMembersPattern``.
    @BitField(bits: 21..<32)
    public var valueMetadataKindRawValue: UInt32

    /// Value patterns only: the metadata kind the instantiation produces, or
    /// `nil` when the field holds a value this library does not recognize.
    @BitField(bits: 21..<32)
    public var valueMetadataKind: MetadataKind?
}
