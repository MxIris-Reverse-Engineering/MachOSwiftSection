import Demangling

extension DemanglingNode {
    /// The part of a member symbol's tree the member builders read the member
    /// from: a protocol witness's requirement, without the conformance the
    /// witness is filed under; the whole tree for any other symbol.
    ///
    /// A witness names its conformance first (`protocol witness for
    /// Swift.Hashable.hash(into:) in conformance Key #1 in
    /// Holder.keyFromGetter.getter : Any`), so a kind-scoped search of the
    /// whole tree — `contains(_:)`, `first(of:)` — reaches the conforming
    /// type before the requirement. A local type's name carries its enclosing
    /// declaration: a getter's variable, a method's `static`, the function
    /// itself. Searched whole, every witness of a type declared in a getter
    /// read as a property named after the getter, a type declared in a
    /// `static` method lent its witnesses `static`, and the method witnesses
    /// of one conformance all keyed as the enclosing function, which kept one
    /// of them (evolution proposal `local-type-context-names`).
    package var memberSubtree: Self {
        guard let protocolWitness, let requirement = protocolWitness.children.at(1) else { return self }
        return requirement
    }

    /// The protocol witness this tree is, or the one under its `global` root.
    private var protocolWitness: Self? {
        if kind == .protocolWitness {
            return self
        }
        guard kind == .global else { return nil }
        return children.first { $0.kind == .protocolWitness }
    }
}
