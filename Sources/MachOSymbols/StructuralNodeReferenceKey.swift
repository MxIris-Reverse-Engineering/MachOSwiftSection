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
///
/// SPI-public, at the same level as `SymbolIndexStore` itself, because the
/// store's bulk query APIs return dictionaries keyed on it: an SPI consumer
/// probing one of those with a tree it demangled itself needs to be able to
/// name the key type and build a lookup key. Keying those on a bare
/// `NodeReference` instead made every such probe miss silently — the keys live
/// in the frozen image arena and store-identity equality can never match a
/// caller's own store.
@_spi(Internals)
public struct StructuralNodeReferenceKey: Hashable {
    /// A stored key holds a `NodeReference`; a lookup-only key may instead hold
    /// a bare `Node` the caller just demangled.
    ///
    /// Both forms hash through the structural hash `Node` and `NodeReference`
    /// agree on (`NodeReference.structuralHash(into:)` is documented to stay in
    /// step with `Node.hash(into:)`), so a `Node` query finds a `NodeReference`
    /// key without materializing the stored tree or interning the query one.
    /// That is what lets a structurally-keyed dictionary answer a print-time
    /// lookup in one probe instead of a linear scan over structural
    /// comparisons.
    package enum Storage {
        case reference(NodeReference)
        case queryNode(Node)
    }

    package let storage: Storage

    /// The stored reference.
    ///
    /// Traps on a lookup-only key. That cannot happen for a key read back out
    /// of a collection: `init(querying:)` values exist only as the argument to
    /// a subscript and are never stored (a bare `Node` carries no store, so a
    /// stored query key would fail to keep alive the arena its structural peers
    /// live in). The trap is therefore a programming-error guard on this
    /// module's own API — not an input-driven one, unlike the binary-supplied
    /// geometry checks in `PackedNameReference`, which deliberately degrade
    /// instead of trapping because a malformed binary must never decide whether
    /// the host process lives.
    package var reference: NodeReference {
        switch storage {
        case .reference(let reference):
            return reference
        case .queryNode:
            preconditionFailure("StructuralNodeReferenceKey(querying:) is lookup-only and carries no stored reference")
        }
    }

    @_spi(Internals)
    public init(_ reference: NodeReference) {
        self.storage = .reference(reference)
    }

    /// A lookup-only key over a freshly demangled tree.
    ///
    /// Never store one of these as a dictionary key: a bare `Node` carries no
    /// store, so a key built this way would not keep the arena its structural
    /// peers live in alive.
    @_spi(Internals)
    public init(querying node: Node) {
        self.storage = .queryNode(node)
    }

    @_spi(Internals)
    public static func == (lhs: StructuralNodeReferenceKey, rhs: StructuralNodeReferenceKey) -> Bool {
        switch (lhs.storage, rhs.storage) {
        case (.reference(let lhsReference), .reference(let rhsReference)):
            return lhsReference.structurallyEquals(rhsReference)
        case (.reference(let lhsReference), .queryNode(let rhsNode)):
            return lhsReference.structurallyEquals(rhsNode)
        case (.queryNode(let lhsNode), .reference(let rhsReference)):
            return rhsReference.structurallyEquals(lhsNode)
        case (.queryNode(let lhsNode), .queryNode(let rhsNode)):
            return lhsNode == rhsNode
        }
    }

    @_spi(Internals)
    public func hash(into hasher: inout Hasher) {
        switch storage {
        case .reference(let reference):
            reference.structuralHash(into: &hasher)
        case .queryNode(let node):
            node.structuralHash(into: &hasher)
        }
    }
}
