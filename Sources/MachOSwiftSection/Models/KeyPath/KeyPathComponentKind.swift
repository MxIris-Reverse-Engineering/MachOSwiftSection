import Foundation

/// The discriminator of a key path component header.
///
/// The same 4-byte encoding is used both by the components of a key path
/// pattern and by a property descriptor, so this covers every kind the
/// runtime knows. A property descriptor only ever carries `struct`, `class`
/// or `computed` (or is trivial, in which case the whole header word is
/// zero); `external` and `optional` appear exclusively inside patterns.
///
/// Mirrors `_SwiftKeyPathComponentHeader_*Tag` in `swift/shims/KeyPath.h`.
public enum KeyPathComponentKind: UInt32, Sendable, Hashable, CaseIterable {
    /// A reference to another module's property descriptor, followed by the
    /// substitution arguments. Only ever emitted into a key path pattern.
    case external = 0

    /// A stored property of a struct. The field offset is either inline in
    /// the header's payload or in the component's body.
    case `struct` = 1

    /// A computed property: an identifier plus a getter, and a setter when
    /// the component is settable.
    case computed = 2

    /// A stored property of a class. Same payload rules as `struct`.
    case `class` = 3

    /// Optional chaining, wrapping or forcing. Only ever emitted into a key
    /// path pattern.
    case optional = 4
}

/// Which optional operation an `optional` key path component performs.
///
/// Mirrors `_SwiftKeyPathComponentHeader_Optional*Payload` in
/// `swift/shims/KeyPath.h`.
public enum KeyPathOptionalComponentKind: UInt32, Sendable, Hashable, CaseIterable {
    /// `?` — the rest of the key path is skipped when the value is `nil`.
    case chain = 0

    /// The value is wrapped back into an `Optional` at the end of a chain.
    case wrap = 1

    /// `!` — the value is force-unwrapped.
    case force = 2
}
