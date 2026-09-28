import Foundation

/// A per-image cache the registry can inspect and evict by key. Every
/// ``SharedCache`` conforms; a store that keeps something other than a
/// built value per image (a host's weakly held provider) conforms by hand.
@_spi(Internals)
public protocol SharedCacheEvicting: AnyObject, Sendable {
    /// Whether a finished entry exists for `key`. A build in flight does not
    /// count.
    func containsEntry(for key: SharedCacheKey) -> Bool
    /// Drops the finished entry for `key`, if any.
    func removeEntry(for key: SharedCacheKey)
    /// The keys with a finished entry.
    var entryKeys: [SharedCacheKey] { get }
}

/// Process-wide coordination of per-image cache eviction.
///
/// Every ``SharedCache`` registers itself here under its
/// ``SharedCacheEvictionGroup``, naming the groups it `follows` — the ones
/// whose storage its entries point into. An owner of an image's caches — the
/// declaration indexer — registers as a **live owner** when it prepares the
/// image and deregisters when it goes away. Registration claims, for that
/// image, every registered group that has no finished entry yet: those are
/// the groups the owner's preparation is about to build, and entries built
/// by non-owner callers before it are never claimed and never evicted here.
/// Deregistration of the image's **last** live owner evicts the claimed
/// groups together with every group that follows them, transitively. An
/// owner leaving earlier evicts nothing: the survivor's already-built names
/// would keep an orphaned store alive while new names land in a fresh one,
/// splitting the `store ===` fast paths for the rest of its lifetime
/// (PR #103 review, finding M6).
///
/// The registry knows no group by name. The set it works over is the set
/// the caches registered, so a module adding a cache adds a group without
/// touching this module.
///
/// The library does not react to memory pressure by itself. A host that
/// wants to shed cached state under pressure calls
/// ``evictImagesWithoutLiveOwners()`` at a moment of its choosing.
@_spi(Internals)
public final class SharedCacheRegistry: @unchecked Sendable {
    public static let shared = SharedCacheRegistry()

    private struct WeakCache {
        weak var cache: (any SharedCacheEvicting)?
    }

    private struct ImageEntry {
        /// Identity-keyed rather than counted: registration is idempotent
        /// per owner, so a double `prepare()` cannot inflate the population
        /// and strand the entry above zero forever.
        var liveOwners: Set<ObjectIdentifier> = []
        var claims: Set<SharedCacheEvictionGroup> = []
    }

    private let lock = NSLock()
    private var cachesByGroup: [SharedCacheEvictionGroup: [WeakCache]] = [:]
    /// Followed group → the groups that follow it, as the caches declared.
    private var followersByGroup: [SharedCacheEvictionGroup: Set<SharedCacheEvictionGroup>] = [:]
    private var entriesByImageKey: [SharedCacheKey: ImageEntry] = [:]

    /// `package` so a test can drive a registry of its own, with caches
    /// created against it, instead of the process-wide one.
    package init() {}

    /// Registers `cache` under `group`, following `follows`. Called by
    /// ``SharedCache``'s initializer; held weakly. Declarations are unioned:
    /// a group follows every group any of its caches named.
    public func register(_ cache: any SharedCacheEvicting, group: SharedCacheEvictionGroup, follows: Set<SharedCacheEvictionGroup> = []) {
        lock.lock()
        defer { lock.unlock() }
        cachesByGroup[group, default: []].append(WeakCache(cache: cache))
        for followed in follows {
            followersByGroup[followed, default: []].insert(group)
        }
    }

    /// Every group a cache registered under.
    public var registeredGroups: Set<SharedCacheEvictionGroup> {
        lock.lock()
        defer { lock.unlock() }
        return Set(cachesByGroup.keys)
    }

    /// The groups evicted along with `group` when it is claimed and evicted:
    /// the ones that declared they follow it, transitively.
    public func followers(of group: SharedCacheEvictionGroup) -> Set<SharedCacheEvictionGroup> {
        lock.lock()
        defer { lock.unlock() }
        var followers = expandingFollowers(of: [group])
        followers.remove(group)
        return followers
    }

    /// The groups with a finished entry for `key` in at least one of their
    /// caches.
    public func presentGroups(for key: SharedCacheKey) -> Set<SharedCacheEvictionGroup> {
        lock.lock()
        defer { lock.unlock() }
        return presentGroupsLocked(for: key)
    }

    /// Registers `owner` as a live owner of `key`'s caches, claiming — in the
    /// same critical section — every registered group with no finished entry
    /// for `key`.
    ///
    /// Sampled under the lock on purpose: sampled before it, a sibling's
    /// deregistration landing in between let an owner observe the caches as
    /// present, claim nothing, register into an entry the sibling then
    /// removed, rebuild everything and hold no claim to evict it — a symbol
    /// store leaked for the process lifetime.
    ///
    /// Only a first registration contributes claims: an owner registering
    /// again samples the caches its own earlier preparation just built and
    /// would otherwise read "nobody had this, so I claim it" backwards.
    public func registerLiveOwner(_ owner: ObjectIdentifier, for key: SharedCacheKey) {
        lock.lock()
        defer { lock.unlock() }
        var entry = entriesByImageKey[key, default: ImageEntry()]
        let isFirstRegistration = entry.liveOwners.insert(owner).inserted
        if isFirstRegistration {
            let present = presentGroupsLocked(for: key)
            entry.claims.formUnion(cachesByGroup.keys.filter { !present.contains($0) })
        }
        entriesByImageKey[key] = entry
    }

    /// Deregisters `owner`, and — only if it was `key`'s LAST live owner, so
    /// a shared entry never disappears under a live sibling — evicts the
    /// claimed groups and their followers.
    ///
    /// The eviction runs under the lock, in the same critical section as the
    /// deregistration: done afterwards, a sibling could sample the caches as
    /// still present in between and claim nothing. Safe because no cache
    /// calls back into the registry.
    public func deregisterLiveOwner(_ owner: ObjectIdentifier, for key: SharedCacheKey) {
        lock.lock()
        defer { lock.unlock() }
        guard var entry = entriesByImageKey[key] else { return }
        entry.liveOwners.remove(owner)
        guard entry.liveOwners.isEmpty else {
            entriesByImageKey[key] = entry
            return
        }
        entriesByImageKey.removeValue(forKey: key)
        evictLocked(groups: expandingFollowers(of: entry.claims), for: key)
    }

    /// Whether any live owner is registered for `key`.
    public func hasLiveOwners(for key: SharedCacheKey) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return !(entriesByImageKey[key]?.liveOwners.isEmpty ?? true)
    }

    /// The claims currently held for `key`, for tests and diagnostics.
    public func claims(for key: SharedCacheKey) -> Set<SharedCacheEvictionGroup> {
        lock.lock()
        defer { lock.unlock() }
        return entriesByImageKey[key]?.claims ?? []
    }

    /// Drops `key`'s entries from every cache in `groups` — exactly those
    /// groups, no followers: an explicit eviction names what it wants gone.
    public func evict(groups: Set<SharedCacheEvictionGroup>, for key: SharedCacheKey) {
        lock.lock()
        defer { lock.unlock() }
        evictLocked(groups: groups, for: key)
    }

    /// Drops every cached entry of every image that has no live owner, in
    /// every registered group. The host's memory-pressure hook: the library
    /// never calls this by itself. An image populated only by non-owner
    /// callers (a dump, a layout query) has no owner and is cleared too —
    /// the caller decides when that is acceptable.
    ///
    /// - Returns: The number of images cleared.
    @discardableResult
    public func evictImagesWithoutLiveOwners() -> Int {
        lock.lock()
        defer { lock.unlock() }
        var keys: Set<SharedCacheKey> = []
        for caches in cachesByGroup.values {
            for weakCache in caches {
                guard let cache = weakCache.cache else { continue }
                keys.formUnion(cache.entryKeys)
            }
        }
        let unownedKeys = keys.filter { entriesByImageKey[$0]?.liveOwners.isEmpty ?? true }
        for key in unownedKeys {
            evictLocked(groups: Set(cachesByGroup.keys), for: key)
        }
        return unownedKeys.count
    }

    // MARK: - Under the lock

    private func presentGroupsLocked(for key: SharedCacheKey) -> Set<SharedCacheEvictionGroup> {
        var present: Set<SharedCacheEvictionGroup> = []
        for (group, caches) in cachesByGroup {
            for weakCache in caches {
                guard let cache = weakCache.cache, cache.containsEntry(for: key) else { continue }
                present.insert(group)
                break
            }
        }
        return present
    }

    /// `groups` plus everything that follows them, transitively: a group
    /// following a follower goes too.
    private func expandingFollowers(of groups: Set<SharedCacheEvictionGroup>) -> Set<SharedCacheEvictionGroup> {
        var expanded = groups
        var pending = Array(groups)
        while let group = pending.popLast() {
            for follower in followersByGroup[group] ?? [] where expanded.insert(follower).inserted {
                pending.append(follower)
            }
        }
        return expanded
    }

    private func evictLocked(groups: Set<SharedCacheEvictionGroup>, for key: SharedCacheKey) {
        for group in groups {
            guard let caches = cachesByGroup[group] else { continue }
            // Compact the dead references while here; a cache is a
            // process-lifetime singleton in practice, a test's is not.
            let liveCaches = caches.filter { $0.cache != nil }
            cachesByGroup[group] = liveCaches
            for weakCache in liveCaches {
                weakCache.cache?.removeEntry(for: key)
            }
        }
    }
}
