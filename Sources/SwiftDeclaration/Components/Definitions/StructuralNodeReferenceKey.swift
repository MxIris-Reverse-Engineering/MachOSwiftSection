import Demangling

/// A dictionary key that compares `NodeReference`s by **structure**, not by
/// store identity.
///
/// `NodeReference`'s intrinsic `Hashable` keys on `(store, index)`, so two
/// structurally-equal nodes minted into different stores hash and compare as
/// distinct. That is correct for grouping symbols that all come from one
/// image store (equal structure ⇒ equal index there, via hash-consing), but
/// wrong for a lookup whose keys and queries can originate in *different*
/// stores.
///
/// The method-override / vtable-offset lookups are exactly that case: their
/// keys are populated from the override descriptors' implementation symbols —
/// which `SymbolIndexStore.demangledNodeReference(for:)` hands back from a
/// per-symbol *mini* store whenever the symbol falls outside the build sweep —
/// while the member side queries them with references drawn from the shared
/// image store. Under store-identity keys those never match, silently dropping
/// the `override` keyword and the vtable-offset comment for the affected
/// methods (the pre-migration `Node`-keyed dictionaries matched structurally,
/// so this is a regression the wrapper repairs — the same fix the `Name`
/// types carry).
package struct StructuralNodeReferenceKey: Hashable {
    package let reference: NodeReference

    package init(_ reference: NodeReference) {
        self.reference = reference
    }

    package static func == (lhs: StructuralNodeReferenceKey, rhs: StructuralNodeReferenceKey) -> Bool {
        lhs.reference.structurallyEquals(rhs.reference)
    }

    package func hash(into hasher: inout Hasher) {
        reference.structuralHash(into: &hasher)
    }
}
