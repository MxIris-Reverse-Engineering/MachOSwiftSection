import Foundation

/// Where a stored key path component's field offset lives.
///
/// Only `inline` keeps the offset in the header; the other three are sentinel
/// payloads meaning "the body carries a 32-bit word", and they stay distinct
/// because that word means something different in each case.
public enum KeyPathStoredFieldOffsetKind: Sendable, Hashable, CaseIterable {
    /// The offset is a compile-time constant small enough to sit in the
    /// header's own payload.
    case inline

    /// The offset is a compile-time constant that did not fit the payload.
    case outOfLine

    /// The offset is only known once the type's metadata exists: the body
    /// carries the byte offset OF the field-offset word within the metadata.
    /// This is what a generic type's stored property gets.
    case unresolvedFieldOffset

    /// The offset is reached through one more indirection: the body carries
    /// the byte offset of a word holding a pointer to the field offset. This
    /// is what a class with a resilient superclass gets.
    case unresolvedIndirectOffset
}

/// A stored key path component's field offset, with the body word read where
/// the header only had a sentinel.
public enum KeyPathStoredFieldOffset: Sendable, Hashable {
    /// The field's byte offset, taken from the header's payload.
    case inline(UInt32)

    /// The field's byte offset, taken from the body.
    case outOfLine(UInt32)

    /// The byte offset, within the type's metadata, of the word holding the
    /// field's offset.
    case unresolvedFieldOffset(offsetOfFieldOffset: UInt32)

    /// The byte offset, within the type's metadata, of the word holding a
    /// pointer to the field's offset.
    case unresolvedIndirectOffset(offsetOfFieldOffsetPointer: UInt32)
}

extension KeyPathStoredFieldOffset {
    public var kind: KeyPathStoredFieldOffsetKind {
        switch self {
        case .inline: return .inline
        case .outOfLine: return .outOfLine
        case .unresolvedFieldOffset: return .unresolvedFieldOffset
        case .unresolvedIndirectOffset: return .unresolvedIndirectOffset
        }
    }

    /// The 32-bit word this case carries, whatever it means.
    public var rawValue: UInt32 {
        switch self {
        case .inline(let value),
             .outOfLine(let value),
             .unresolvedFieldOffset(let value),
             .unresolvedIndirectOffset(let value):
            return value
        }
    }

    /// The field's byte offset when the binary states it outright, `nil` when
    /// it can only be read out of live metadata.
    public var staticFieldOffset: UInt32? {
        switch self {
        case .inline(let value), .outOfLine(let value):
            return value
        case .unresolvedFieldOffset, .unresolvedIndirectOffset:
            return nil
        }
    }
}
