import Foundation

/// What the identifier word of a `computed` key path component means.
///
/// The identifier is what makes two key paths to the same property compare
/// equal, so its encoding depends on how the property is dispatched.
///
/// Mirrors the `_SwiftKeyPathComponentHeader_ComputedIDBy*Flag` pair in
/// `swift/shims/KeyPath.h`.
public enum KeyPathComputedIdentifierKind: Sendable, Hashable, CaseIterable {
    /// The identifier is a relative pointer to whatever the compiler chose to
    /// identify the property with — a method descriptor for a class member, a
    /// getter's address for a static or final one, a selector reference for
    /// an `@objc dynamic` one. `KeyPathComputedIdentifierResolution` says how
    /// to get from that pointer to the identity value.
    case pointer

    /// The identifier is a stored property's field offset, not a pointer.
    case storedPropertyOffset

    /// The identifier is a vtable offset, not a pointer.
    case vtableOffset
}

/// How to turn a pointer-kind identifier into the value that actually
/// identifies the property.
///
/// Mirrors `_SwiftKeyPathComponentHeader_ComputedIDResolution*` in
/// `swift/shims/KeyPath.h`.
public enum KeyPathComputedIdentifierResolution: UInt32, Sendable, Hashable, CaseIterable {
    /// The pointer already is the identity value.
    case resolved = 0

    /// The pointer references a function that must be called to produce the
    /// identity value. This is the `@objc` case: the referenced thunk hands
    /// back the property's selector.
    case unresolvedFunctionCall = 1

    /// The pointer references a word holding the identity value, which has to
    /// be loaded.
    case unresolvedIndirectPointer = 2

    /// The pointer is an absolute address that already is the identity value.
    case resolvedAbsolute = 3
}
