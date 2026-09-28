import Foundation
import MachOKit
import MachOKitExtensions
import Utilities
import SwiftStdlibToolbox

/// One lazily built value per Mach-O image, shared by every caller that
/// asks for it.
///
/// Entries are keyed by ``SharedCacheKey``. A lookup that finds a finished
/// value returns it; one that finds a build in flight joins it; one that
/// finds nothing installs an in-flight marker, runs the caller's build
/// closure **outside** the cache lock, and publishes the result. So callers
/// building entries for different images run in parallel, and callers
/// building the same image's entry share one build.
///
/// The build closure is the caller's. The cache knows nothing about what a
/// reader can read, so the type that owns an index supplies the build at its
/// own call site, where the reader's concrete capabilities are known. A build
/// that returns `nil` is not cached, and the next lookup tries again.
///
/// Every cache belongs to a ``SharedCacheEvictionGroup`` and registers
/// itself with a ``SharedCacheRegistry`` at creation; eviction per image is
/// the registry's business. The cache itself never drops an entry on its
/// own — in particular not on memory pressure, which it once did per
/// instance, behind the registry's back and to no effect, since the entries
/// were pinned by live references anyway.
///
/// `final`: an owning type holds a private instance and forwards to it,
/// rather than subclassing. `@unchecked Sendable` because the mutable state
/// is behind an `os_unfair_lock`.
@_spi(Internals)
public final class SharedCache<Storage>: SharedCacheEvicting, @unchecked Sendable {
    /// The family this cache's entries are evicted with.
    public let evictionGroup: SharedCacheEvictionGroup

    /// - Parameters:
    ///   - evictionGroup: The family the entries belong to.
    ///   - registry: Where the cache registers itself. The process-wide
    ///     registry, except for a test driving a registry of its own.
    package init(evictionGroup: SharedCacheEvictionGroup, registry: SharedCacheRegistry = .shared) {
        self.evictionGroup = evictionGroup
        registry.register(self, group: evictionGroup)
    }

    /// Per-key state: a finished build (`completed`) or an in-flight build
    /// that other callers can join via the promise (`inFlight`). The
    /// in-flight marker lets concurrent callers for the same key share one
    /// build instead of serializing against the cache lock for the build's
    /// entire duration.
    private enum Entry {
        case completed(Storage)
        case inFlight(SharedCacheBuildPromise<Storage>)
    }

    @Mutex
    private var storageByKey: [SharedCacheKey: Entry] = [:]

    /// Routing decision the cache lock makes on behalf of `storage(...)`:
    /// either return a cached value, await someone else's in-flight build,
    /// or run the build ourselves under the freshly-installed promise.
    private enum Outcome {
        case completed(Storage)
        case wait(SharedCacheBuildPromise<Storage>)
        case build(SharedCacheBuildPromise<Storage>)
    }

    /// Atomic get-or-build with a caller-provided build closure.
    ///
    /// The closure may capture per-call context (progress continuations,
    /// options, the reader's concrete type); that context flows through
    /// closure capture, never through shared instance state, so concurrent
    /// calls cannot interfere.
    ///
    /// The cache lock is held only long enough to look up the key and either
    /// hand back a finished value, attach to an in-flight build, or install
    /// our own in-flight marker. The build closure itself executes
    /// **outside** the lock, so two callers building entries for different
    /// Mach-O identifiers run in parallel; two callers building entries for
    /// the same identifier de-duplicate via the in-flight promise.
    public func storage<MachO: MachORepresentableWithCache>(
        in machO: MachO,
        buildUsing build: (MachO) -> Storage?
    ) -> Storage? {
        return resolve(key: SharedCacheKey(machO)) { build(machO) }
    }

    /// Installs `storage` as the image's finished entry, replacing whatever
    /// was there. A build in flight for the same image loses: when it
    /// returns it finds a marker that is not its own and does not publish,
    /// though it still hands its own result to the callers that joined it.
    /// This is what lets an owner with configuration of its own — an
    /// indexer with search paths — override the default an earlier lookup
    /// built.
    public func register(_ storage: Storage, for machO: some MachORepresentableWithCache) {
        register(storage, forKey: SharedCacheKey(machO))
    }

    /// Key-taking form of ``register(_:for:)``, for the in-package tests.
    package func register(_ storage: Storage, forKey key: SharedCacheKey) {
        _storageByKey.withLockUnchecked { dict in
            dict[key] = .completed(storage)
        }
    }

    /// Returns `true` when a finished build is already cached for `machO`'s
    /// identifier. In-flight builds count as **not** cached: a caller that
    /// observes `false` here, then runs ``storage(in:buildUsing:)``, may end
    /// up sharing an existing in-flight build with another caller — but from
    /// the "self-triggered" perspective (see ``SharedCacheRegistry``) that is
    /// still cooperative ownership, not sole ownership, so reporting `true`
    /// for in-flight would mislead the bookkeeping.
    public func contains(in machO: some MachORepresentableWithCache) -> Bool {
        return containsEntry(for: SharedCacheKey(machO))
    }

    /// Drops the cached entry for `machO`'s identifier so the next lookup
    /// rebuilds from scratch. In-flight builds are left alone: their waiters
    /// still need the promise to settle, and the next completed result
    /// simply won't be re-installed because the in-flight marker has already
    /// been removed by the time we check on the build path. Safe to call
    /// even when no entry exists.
    public func remove(for machO: some MachORepresentableWithCache) {
        removeEntry(for: SharedCacheKey(machO))
    }

    /// Drops every cached entry — for tests, or a long-lived process
    /// flushing between unrelated batches. Bypasses the registry's
    /// ownership rules, so not something library code calls.
    public func removeAll() {
        _storageByKey.withLockUnchecked { dict in
            dict.removeAll(keepingCapacity: false)
        }
    }

    // MARK: - SharedCacheEvicting

    public func containsEntry(for key: SharedCacheKey) -> Bool {
        _storageByKey.withLockUnchecked { dict in
            if case .completed = dict[key] {
                return true
            }
            return false
        }
    }

    public func removeEntry(for key: SharedCacheKey) {
        _storageByKey.withLockUnchecked { dict in
            if case .completed = dict[key] {
                dict.removeValue(forKey: key)
            }
        }
    }

    public var entryKeys: [SharedCacheKey] {
        _storageByKey.withLockUnchecked { dict in
            dict.compactMap { key, entry in
                if case .completed = entry {
                    return key
                }
                return nil
            }
        }
    }

    /// The core of ``storage(in:buildUsing:)``. Holds the cache lock only
    /// across the dictionary lookup / marker install and across the
    /// post-build dictionary update — the actual `build` call runs
    /// unsynchronized so that concurrent builds for distinct keys don't
    /// serialize.
    ///
    /// `package`-visible so the in-package test target can exercise the
    /// concurrency contract directly without manufacturing a fake
    /// `MachORepresentableWithCache` conformer.
    package func resolve(key: SharedCacheKey, build: () -> Storage?) -> Storage? {
        let outcome: Outcome = _storageByKey.withLockUnchecked { dict in
            if let entry = dict[key] {
                switch entry {
                case .completed(let storage):
                    return .completed(storage)
                case .inFlight(let promise):
                    return .wait(promise)
                }
            }
            let promise = SharedCacheBuildPromise<Storage>()
            dict[key] = .inFlight(promise)
            return .build(promise)
        }

        switch outcome {
        case .completed(let storage):
            return storage
        case .wait(let promise):
            // A build closure that queries the entry it is itself building
            // finds its own in-flight marker here. Waiting would block
            // forever: the promise is fulfilled only when that closure
            // returns, and the closure is the one waiting. Before the
            // promise-based rewrite this trapped on the non-reentrant cache
            // lock, which at least left a crash log; a silent hang is worse,
            // so the same-thread case traps on purpose. A build that moved
            // to another thread first is not detectable at this layer.
            precondition(
                !promise.isBuilderCurrentThread,
                "SharedCache: re-entrant build for key \(key) — the build closure queried the entry it is building, on its own thread; waiting here would never return"
            )
            return promise.wait()
        case .build(let promise):
            let result = build()
            _storageByKey.withLockUnchecked { dict in
                // Only publish back if our promise is still the in-flight
                // marker. `removeAll()` could have cleared the dict
                // mid-build, or `register(_:for:)` could have installed a
                // finished entry over ours; in either case the dict is not
                // ours to write — but our promise still has waiters
                // attached, so we always call `fulfill(_:)` below.
                if case .inFlight(let installed) = dict[key], installed === promise {
                    if let storage = result {
                        dict[key] = .completed(storage)
                    } else {
                        // Mirror the original behaviour: a build that returns
                        // `nil` is not cached, so subsequent callers get a
                        // fresh attempt instead of being permanently stuck on
                        // the failure.
                        dict[key] = nil
                    }
                }
            }
            promise.fulfill(result)
            return result
        }
    }
}
