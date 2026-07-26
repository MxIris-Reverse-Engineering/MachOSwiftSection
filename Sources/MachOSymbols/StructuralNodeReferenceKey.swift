import Demangling

/// A dictionary/set key that compares `NodeReference`s by **structure**, not by
/// store identity.
///
/// `NodeReference`'s intrinsic `Hashable` keys on `(store, index)`, so two
/// structurally-equal nodes minted into different stores hash and compare as
/// distinct. That is correct for grouping nodes that all come from one image
/// store (equal structure ⇒ equal index there, via hash-consing), but wrong for
/// any collection whose keys and lookups can originate in *different* stores.
///
/// Different stores are the norm rather than the exception once demangled trees
/// leave `SymbolIndexStore`: `demangledNodeReference(for:)` falls back to a mini
/// store for names outside the build sweep, and `NodeReference(interning:)` —
/// which `MetadataReader` uses for every metadata-derived tree — mints a fresh
/// private store on each call by design. Collections that mix those with
/// references drawn from the shared image store must use this wrapper.
///
/// The method-override / vtable-offset lookups were the case that surfaced the
/// hazard: their keys are populated from override descriptors' implementation
/// symbols while the member side queries them with image-store references, and
/// under store-identity keys those never matched — silently dropping the
/// `override` keyword and the vtable-offset comment for the affected methods.
/// The pre-migration `Node`-keyed dictionaries matched structurally, so it was
/// a regression this wrapper repairs (the same fix the `Name` types carry).
///
/// Lives in `MachOSymbols`, next to the mini stores it exists to reconcile, so
/// both the symbol index itself and the declaration layer above it can use it.
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
