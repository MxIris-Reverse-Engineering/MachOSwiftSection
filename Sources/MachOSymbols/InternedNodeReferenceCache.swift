import Foundation
@_spi(Internals) import Demangling
import MachOKit
import MachOExtensions
@_spi(Internals) import MachOCaches
import SwiftStdlibToolbox

/// Structural deduplication for `NodeReference(interning:)`.
///
/// `NodeReference(interning:)` mints one private arena per call — upstream
/// documents it as the wrong tool for a batch, since deduplication and
/// compactness are both properties of a shared arena. The name-construction
/// sites (`TypeName` / `ProtocolName` / `ExtensionName` built from
/// `MetadataReader` trees) call it once per *occurrence*, and occurrences
/// repeat heavily: every conformance re-interns its protocol's name, every
/// nested type re-interns its parent's, every extension its target's.
/// Measured on the `SymbolTestsCore` fixture, 730 retained mini stores
/// backed only 472 structurally unique trees — and the repeat factor grows
/// with framework size (conformance fan-out dominates).
///
/// This cache keeps one reference per structurally unique tree: repeats hand
/// back the previously minted reference, so equal names share one store and
/// `structurallyEquals`' same-store `store ===` fast path starts firing for
/// them (name equality drops from a full tree walk to an index compare).
///
/// Two scopes, matching `SharedCache`'s two keying modes:
/// - **Per image** (`reference(interning:in:)`): the bucket lives and dies
///   with the image — evicted on memory pressure with every other shared
///   cache, and dropped by `SwiftDeclarationIndexer`'s per-image cleanup so
///   the recycling model holds.
/// - **Per process** (`reference(interning:)`): for the in-process reading
///   paths that have no Mach-O handle. One type-keyed bucket, memory-pressure
///   evictable, bounded by the unique names the process actually touches.
///
/// Retention trade: the cache pins every minted mini store for its scope's
/// lifetime, including names a query produced and dropped. That is bounded
/// by *unique* names per scope and buys the dedup above; the pre-cache
/// behavior pinned one store per *retained occurrence* with no sharing at
/// all.
@_spi(ForSymbolViewer)
@_spi(Internals)
public final class InternedNodeReferenceCache: SharedCache<InternedNodeReferenceCache.Storage>, @unchecked Sendable {
    public static let shared = InternedNodeReferenceCache()

    public final class Storage: @unchecked Sendable {
        /// Minted references bucketed by their tree's structural hash
        /// (`Node`'s `Hashable` is structural); collisions resolve by
        /// `structurallyEquals`, so a bucket almost always holds one entry.
        @Mutex
        private var referencesByStructuralHash: [Int: [NodeReference]] = [:]

        /// Get-or-mint following the same discipline as
        /// `SymbolIndexStore.Storage.lateDemangledNode(forName:)`: the
        /// interning runs *outside* the critical section (it allocates and
        /// walks the whole tree, which has no business inside an
        /// `os_unfair_lock`), and the lock arbitrates insert-if-absent — a
        /// racing loser discards its freshly minted store and returns the
        /// winner's reference, so one structural name never hands out
        /// references into two stores within one scope.
        fileprivate func reference(interning node: Node) -> NodeReference {
            var hasher = Hasher()
            hasher.combine(node)
            let structuralHashValue = hasher.finalize()

            if let existing = _referencesByStructuralHash.withLockUnchecked({ buckets in
                buckets[structuralHashValue]?.first(where: { $0.structurallyEquals(node) })
            }) {
                return existing
            }

            let minted = NodeReference(interning: node)
            return _referencesByStructuralHash.withLockUnchecked { buckets in
                if let winner = buckets[structuralHashValue]?.first(where: { $0.structurallyEquals(node) }) {
                    return winner
                }
                buckets[structuralHashValue, default: []].append(minted)
                return minted
            }
        }

        /// Test-only visibility: the number of structurally distinct trees
        /// currently cached in this scope.
        public var cachedReferenceCountForTesting: Int {
            _referencesByStructuralHash.withLockUnchecked { buckets in
                buckets.values.reduce(0) { $0 + $1.count }
            }
        }
    }

    override public func buildStorage(for machO: some MachORepresentableWithCache) -> Storage? {
        Storage()
    }

    override public func buildStorage() -> Storage? {
        Storage()
    }

    /// The image-scoped shared reference for `node`'s structural identity.
    public func reference<MachO: MachORepresentableWithCache>(interning node: Node, in machO: MachO) -> NodeReference {
        guard let storage = storage(in: machO) else { return NodeReference(interning: node) }
        return storage.reference(interning: node)
    }

    /// The process-scoped shared reference for `node`'s structural identity,
    /// for call sites without a Mach-O handle (in-process reading contexts).
    public func reference(interning node: Node) -> NodeReference {
        guard let storage = storage() else { return NodeReference(interning: node) }
        return storage.reference(interning: node)
    }
}
