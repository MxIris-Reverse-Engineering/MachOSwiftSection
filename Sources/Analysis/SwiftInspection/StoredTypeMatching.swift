@_spi(Internals) import Demangling

/// How a property's declared type, read off one of its symbols, compares
/// with the type a field record stores. Three recoveries compare the two:
/// rule 1 of the `@Observable` expansion recovery (evolution proposal
/// `observable-macro-folding`), the wrapped-property attribute spelling, and
/// the init accessor inference (`init-accessor-recovery`), which the dump
/// runs too, below the declaration model.
package enum StoredTypeMatching {
    /// The type a stored property's accessors traffic in: its field type
    /// without the `weak` / `unowned` / `unowned(unsafe)` storage around it,
    /// with the `type` node around it — the shape a member variable's
    /// declared type has.
    package static func referencedTypeNode(ofStoredType storedTypeNode: Node) -> Node {
        var node = storedTypeNode
        while node.kind == .type, let referenceStorage = node.firstChild,
              referenceStorage.kind == .weak || referenceStorage.kind == .unowned || referenceStorage.kind == .unmanaged,
              let referencedTypeNode = referenceStorage.firstChild {
            node = referencedTypeNode
        }
        return node
    }

    /// Whether a member variable's declared type — read off one of its
    /// symbols: the getter's, or the init accessor's — is the type a field
    /// record stores, `sending` set aside. The mangler leaves `sending` out
    /// of a declaration's own function type, on its result and its
    /// parameters (`ASTMangler::appendDeclType`: adding it must not change a
    /// symbol), while a field record's type keeps it: the accessors of
    /// `var make: () -> sending T` read `() -> T`, its storage
    /// `() -> sending T` (SwiftUI's `makeFileCoordinator`). A function type
    /// nested deeper carries it on both sides.
    package static func declaredType(_ declaredTypeNode: Node, matchesStoredType storedTypeNode: Node) -> Bool {
        var pendingPairs: [(declared: Node, stored: Node)] = [(declaredTypeNode, storedTypeNode)]
        while let pair = pendingPairs.popLast() {
            let declared = withoutSendingParameterMarker(pair.declared)
            let stored = withoutSendingParameterMarker(pair.stored)
            if declared === stored { continue }
            guard declared.kind == stored.kind, declared.contents == stored.contents else { return false }
            let declaredChildren = declared.children.filter { $0.kind != .sendingResultFunctionType }
            let storedChildren = stored.children.filter { $0.kind != .sendingResultFunctionType }
            guard declaredChildren.count == storedChildren.count else { return false }
            pendingPairs.append(contentsOf: zip(declaredChildren, storedChildren).map { (declared: $0, stored: $1) })
        }
        return true
    }

    /// A parameter's type with the `sending` the demangler wraps around it
    /// (`type(sending(X))`) taken off, the shape it has without one.
    private static func withoutSendingParameterMarker(_ node: Node) -> Node {
        var node = node
        while node.kind == .sending, let child = node.firstChild {
            node = child
        }
        return node
    }
}
