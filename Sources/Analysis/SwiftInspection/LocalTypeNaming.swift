@_spi(Internals) import Demangling

/// How the name of a type declared in a function or closure body says so
/// (evolution proposal `local-type-context-names`).
///
/// `SymbolicDemangler` gives such a type the compiler's own name when the
/// image keeps a source of it, and a position-based one when it keeps none.
/// A printer reads this to print the type's declared name alone where a type
/// is referenced, since nothing outside the body can spell it; a host reads it
/// to tell a local type from a private one, whose name has the same shape as
/// a position-based one.
public enum LocalTypeNaming: Sendable, Equatable {
    /// The compiler's name, `Visitor #1 in Holder.countValues()`: a
    /// `localDeclName` under the function or closure that declares the type.
    case compilerSpelled

    /// No source the image keeps names the function or closure, so the type
    /// is called after the address of the anonymous context wrapping it,
    /// under the nearest context the descriptors name:
    /// `Holder.(Visitor in $1a2b3c)`. The name has a `privateDeclName`'s
    /// shape, but the type is not private and `$1a2b3c` is no discriminator —
    /// a compiler-written discriminator never starts with `$`.
    case positionBased
}

extension Node {
    /// How this nominal's name marks a local type, or `nil` when it does not
    /// name one. A type nested in a local type is not one itself: its own
    /// name is a plain identifier under the local type.
    public var localTypeNaming: LocalTypeNaming? {
        var nominal = self
        while wrapsANominal(nominal.kind), let wrapped = nominal.children.first {
            nominal = wrapped
        }
        guard nominal.kind.isAnyGeneric, let declarationName = nominal.children.at(1) else { return nil }
        switch declarationName.kind {
        case .localDeclName:
            return .compilerSpelled
        case .privateDeclName:
            return declarationName.children.first?.text?.hasPrefix("$") == true ? .positionBased : nil
        default:
            return nil
        }
    }
}

extension NodeReference {
    /// ``Node/localTypeNaming``, read from the store without materializing
    /// the tree.
    public var localTypeNaming: LocalTypeNaming? {
        var nominal = self
        while wrapsANominal(nominal.kind), let wrapped = nominal.children.first {
            nominal = wrapped
        }
        guard nominal.kind.isAnyGeneric, nominal.children.count >= 2 else { return nil }
        let declarationName = nominal.children[1]
        switch declarationName.kind {
        case .localDeclName:
            return .compilerSpelled
        case .privateDeclName:
            return declarationName.children.first?.text?.hasPrefix("$") == true ? .positionBased : nil
        default:
            return nil
        }
    }
}

/// The kinds a nominal's name sits under: the demangling's root, a type, and
/// a bound generic type, whose first child is the unbound one.
private func wrapsANominal(_ kind: Node.Kind) -> Bool {
    switch kind {
    case .global, .type, .boundGenericStructure, .boundGenericClass, .boundGenericEnum, .boundGenericOtherNominalType:
        return true
    default:
        return false
    }
}
