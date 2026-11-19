@_spi(Internals) import Demangling
@_spi(Internals) import SwiftInspection

extension DefinitionName {
    /// The name a reader is shown of a type declared in a function or
    /// closure body, or of a type nested in one; `nil` for any other type
    /// (evolution proposal `private-declarations`).
    ///
    /// The compiler's name of such a type carries the declaring function's
    /// whole signature, `Visitor #1 in M.Holder.countValues() -> Any`. Shown
    /// to a reader it leaves the modules and the parameter and result types
    /// out and keeps the ordinal: `Visitor #1 in Holder.countValues()` —
    /// short enough to list, and still telling apart the `Visitor`s two
    /// methods of one type declare. A type nested in one reads
    /// `Element in Generator #1 in Holder.nested()`.
    ///
    /// A position-based local type (`LocalTypeNaming.positionBased`) has no
    /// function to name, and keeps the address of the anonymous context
    /// wrapping it, `Holder.(Visitor in $1a2b3c)`: it is the one thing that
    /// tells the unnamed `Visitor`s of `Holder` apart. Real private
    /// discriminators are left out either way.
    public var localTypeDisplayName: String? {
        switch node.nearestLocalTypeNaming {
        case .compilerSpelled?:
            return node.print(using: .localTypeDisplayName)
        case .positionBased?:
            let readableNode = PrivateDiscriminatorRemover().rewrite(node.materialize())
            return readableNode.print(using: DemangleOptions.localTypeDisplayName.union(.showPrivateDiscriminators))
        case nil:
            return nil
        }
    }
}

extension DemangleOptions {
    /// A local type's compiler-spelled name the way a reader says it: no
    /// modules, no parameter or result types, the `#1` ordinal kept.
    fileprivate static let localTypeDisplayName = DemangleOptions.simplified.union(.displayLocalNameContexts)
}

extension NodeReference {
    /// How the nearest local type this name runs through is named — the
    /// type itself, or a type it is nested in — or `nil` when it runs
    /// through none.
    fileprivate var nearestLocalTypeNaming: LocalTypeNaming? {
        var current = self
        while true {
            if let localTypeNaming = current.localTypeNaming {
                return localTypeNaming
            }
            while current.kind.wrapsANominal, let wrapped = current.children.first {
                current = wrapped
            }
            guard current.kind.isAnyGeneric, let context = current.children.first else {
                return nil
            }
            current = context
        }
    }
}

extension Node.Kind {
    /// The kinds a nominal's name sits under: the demangling's root, a type,
    /// and a bound generic type, whose first child is the unbound one.
    fileprivate var wrapsANominal: Bool {
        switch self {
        case .global, .type, .boundGenericStructure, .boundGenericClass, .boundGenericEnum, .boundGenericOtherNominalType:
            return true
        default:
            return false
        }
    }
}

/// Replaces every compiler-written `privateDeclName` with the name it
/// declares, keeping position-based ones, so that a tree printed with
/// `showPrivateDiscriminators` shows the `$` addresses alone.
private final class PrivateDiscriminatorRemover: Node.Rewriter {
    override func visit(_ node: Node) -> Node {
        guard node.kind == .privateDeclName, !node.isPositionBasedPrivateName, let name = node.children.at(1) else {
            return node
        }
        return name
    }
}
