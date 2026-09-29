import Foundation
@_spi(Internals) import Demangling
import MachOKit
import MachOKitExtensions
@_spi(Internals) import MachOCaches
import SwiftStdlibToolbox

/// Scope-keyed shared interning arenas for metadata-derived name trees.
///
/// One `SharedNodeStore` per scope: every tree interned in a scope lands in
/// that scope's single appendable arena, whose interning tables deduplicate
/// persistently — structurally equal trees return the *same* reference
/// (store identity included), at any two points in the scope's lifetime.
/// The name-construction sites (`TypeName` / `ProtocolName` /
/// `ExtensionName` built from `SymbolicDemangler` trees, and `TypeDefinition`'s
/// field type trees) intern once per *occurrence*, and occurrences repeat
/// heavily: every conformance re-interns its protocol's name, every nested
/// type re-interns its parent's, every extension its target's. Sharing one
/// store per scope keeps name equality on `structurallyEquals`' same-store
/// `store ===` fast path (an index compare, not a tree walk).
///
/// Historically this type was a structural-hash bucket layer over
/// `NodeReference(interning:)` — one private mini store per unique tree,
/// because the frozen `NodeStoreBuilder` flow could not hand out references
/// before `freeze()`. Upstream evolution 0010 (`SharedNodeStore`) removed
/// that barrier, so the bucket layer retired; what remains here is the part
/// `SharedNodeStore` deliberately does not know about — Mach-O scope keying
/// and eviction:
/// - **Per image** (`reference(interning:in:)`): the store lives and dies
///   with the image — evicted on memory pressure with every other shared
///   cache, and dropped by `SwiftDeclarationIndexer`'s per-image cleanup so
///   the recycling model holds.
/// - **Per process** (`reference(interning:)`): for the in-process reading
///   paths that have no Mach-O handle. One process-wide store that is never
///   evicted, bounded by the unique names the process actually touches.
///
/// Eviction reclaims nothing while external references survive: a
/// `NodeReference` keeps its backing storage alive after the scope drops
/// (reads stay valid, interning stops) — the same semantics the retired
/// mini stores had. No capacity reservation: the 0009 coefficients are
/// calibrated on the bulk symbol corpus and name-tree workloads grow
/// incrementally by nature; use `capacityUtilization` if calibration is
/// ever wanted.
@_spi(ForSymbolViewer)
@_spi(Internals)
public final class InternedNodeReferenceCache: @unchecked Sendable {
    public static let shared = InternedNodeReferenceCache()

    private let cache = SharedCache<Storage>(evictionGroup: .internedNames)

    /// The process-scoped arena, for the in-process reading paths that have
    /// no Mach-O handle. A `static let` is created lazily and is thread-safe
    /// by language rule. It is never evicted: nothing owns it the way an
    /// indexer owns an image's entries, and it is bounded by the unique
    /// names the process interns in-process.
    private static let processScopedStorage = Storage()

    private init() {}

    public final class Storage: Sendable {
        /// The scope's single appendable arena; `intern` serializes on the
        /// store's own writer lock and deduplicates structurally.
        fileprivate let store = SharedNodeStore()

        fileprivate func reference(interning node: Node) -> NodeReference {
            store.intern(node)
        }
    }

    /// The image-scoped shared reference for `node`'s structural identity.
    public func reference(interning node: Node, in machO: some MachORepresentableWithCache) -> NodeReference {
        guard let storage = cache.storage(in: machO, buildUsing: { _ in Storage() }) else { return NodeReference(interning: node) }
        return storage.reference(interning: node)
    }

    /// The process-scoped shared reference for `node`'s structural identity,
    /// for call sites without a Mach-O handle (in-process reading contexts).
    public func reference(interning node: Node) -> NodeReference {
        Self.processScopedStorage.reference(interning: node)
    }

    public func contains(in machO: some MachORepresentableWithCache) -> Bool {
        cache.contains(in: machO)
    }

    public func remove(for machO: some MachORepresentableWithCache) {
        cache.remove(for: machO)
    }
}
