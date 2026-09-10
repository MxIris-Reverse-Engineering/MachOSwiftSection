import Foundation
import MachOBase

/// The body of a `computed` key path component: an identifier, a getter, and
/// a setter when the component is settable.
///
/// A property descriptor's computed body stops there — subscript arguments
/// are the client pattern's business, never the descriptor's.
public struct KeyPathComputedPropertyBody: Sendable, Equatable {
    /// The header the body was read under; it is what gives the identifier
    /// word its meaning.
    public let header: KeyPathComponentHeader

    /// Location of the body's first word, in the same coordinate space as the
    /// descriptor's own `offset`: a file offset for `MachOFile`, a pointer's
    /// bit pattern in process.
    public let offset: Int

    /// The identifier word, exactly as stored. Interpret it through
    /// `header.computedIdentifierKind`: a relative pointer, a stored
    /// property's field offset, or a vtable offset.
    public let rawIdentifier: RelativeOffset

    /// Relative pointer to the getter.
    public let getter: RelativeDirectRawPointer

    /// Relative pointer to the setter, `nil` when the component is not
    /// settable (in which case the word is not present at all).
    public let setter: RelativeDirectRawPointer?

    /// Deliberately not `public`: a body is a parsed projection, only ever
    /// produced by `PropertyDescriptor`, never assembled by a caller.
    package init(
        header: KeyPathComponentHeader,
        offset: Int,
        rawIdentifier: RelativeOffset,
        getter: RelativeDirectRawPointer,
        setter: RelativeDirectRawPointer?
    ) {
        self.header = header
        self.offset = offset
        self.rawIdentifier = rawIdentifier
        self.getter = getter
        self.setter = setter
    }
}

extension KeyPathComputedPropertyBody {
    /// Location of the identifier word itself.
    public var identifierFieldOffset: Int { offset }

    /// Location of the getter word itself.
    public var getterFieldOffset: Int { offset + MemoryLayout<RelativeOffset>.size }

    /// Location of the setter word itself, `nil` when there is no setter.
    public var setterFieldOffset: Int? {
        guard setter != nil else { return nil }
        return offset + MemoryLayout<RelativeOffset>.size * 2
    }

    /// Where the identifier's relative pointer lands, or `nil` when the
    /// identifier is not a pointer at all (a stored-property or vtable
    /// offset) or the pointer is null.
    ///
    /// Note this is only the location the pointer names; whether the identity
    /// value IS that location, or has to be loaded from it or produced by
    /// calling it, is `header.computedIdentifierResolution`.
    public var identifierOffset: Int? {
        guard header.computedIdentifierKind == .pointer, rawIdentifier != 0 else { return nil }
        return identifierFieldOffset + Int(rawIdentifier)
    }

    /// Where the getter's implementation lives, `nil` for a null pointer.
    /// Pure relative-pointer arithmetic, like
    /// `MethodDescriptor.implementationOffset`.
    public var getterOffset: Int? {
        guard getter.isValid else { return nil }
        return getter.resolveDirectOffset(from: getterFieldOffset)
    }

    /// Where the setter's implementation lives, `nil` when the component is
    /// not settable or the pointer is null.
    public var setterOffset: Int? {
        guard let setter, setter.isValid, let setterFieldOffset else { return nil }
        return setter.resolveDirectOffset(from: setterFieldOffset)
    }
}
