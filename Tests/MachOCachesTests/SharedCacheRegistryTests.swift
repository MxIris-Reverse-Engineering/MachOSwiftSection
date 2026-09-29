import Foundation
import Testing
@_spi(Internals) import MachOCaches

/// The registry's ownership rules, driven on a registry of its own with
/// caches created against it and groups declared here — the registry knows
/// no group by name, so the tests declare the shape they need. The
/// process-wide registry and the real indexer are exercised end to end by
/// `PerImageCacheEvictionTests`.
@Suite("SharedCacheRegistry")
struct SharedCacheRegistryTests {
    private enum Group {
        static let store = SharedCacheEvictionGroup("test.store")
        /// Holds the store's table: follows `store`.
        static let table = SharedCacheEvictionGroup("test.table")
        static let arena = SharedCacheEvictionGroup("test.arena")
        /// Holds references into the arena: follows `arena`.
        static let memo = SharedCacheEvictionGroup("test.memo")
        /// Holds references into the memo: follows `memo`, and so the arena
        /// transitively.
        static let annotation = SharedCacheEvictionGroup("test.annotation")
        static let catalog = SharedCacheEvictionGroup("test.catalog")
    }

    /// A registry plus one cache per group the rules below reach.
    private struct Fixture {
        let registry = SharedCacheRegistry()
        let store: SharedCache<Int>
        let table: SharedCache<Int>
        let arena: SharedCache<Int>
        let memo: SharedCache<Int>
        let annotation: SharedCache<Int>
        let catalog: SharedCache<Int>

        init() {
            store = SharedCache(evictionGroup: Group.store, registry: registry)
            table = SharedCache(evictionGroup: Group.table, follows: [Group.store], registry: registry)
            arena = SharedCache(evictionGroup: Group.arena, registry: registry)
            memo = SharedCache(evictionGroup: Group.memo, follows: [Group.arena], registry: registry)
            annotation = SharedCache(evictionGroup: Group.annotation, follows: [Group.memo], registry: registry)
            catalog = SharedCache(evictionGroup: Group.catalog, registry: registry)
        }

        var everyCache: [SharedCache<Int>] {
            [store, table, arena, memo, annotation, catalog]
        }

        func fill(_ cache: SharedCache<Int>, for key: SharedCacheKey) {
            _ = cache.resolve(key: key) { 1 }
        }

        func fillEverything(for key: SharedCacheKey) {
            for cache in everyCache {
                fill(cache, for: key)
            }
        }
    }

    private let image = SharedCacheKey(opaque: "image-a")
    private let otherImage = SharedCacheKey(opaque: "image-b")
    private let owner = ObjectIdentifier(NSObject.self)
    private let otherOwner = ObjectIdentifier(NSString.self)

    @Test func registeredGroupsAreWhatTheCachesDeclared() {
        let fixture = Fixture()

        #expect(fixture.registry.registeredGroups == [Group.store, Group.table, Group.arena, Group.memo, Group.annotation, Group.catalog])
        #expect(fixture.registry.followers(of: Group.store) == [Group.table])
        #expect(fixture.registry.followers(of: Group.arena) == [Group.memo, Group.annotation], "a group following a follower goes too")
        #expect(fixture.registry.followers(of: Group.catalog).isEmpty)
    }

    @Test func registrationClaimsTheGroupsAbsentAtThatMoment() {
        let fixture = Fixture()
        fixture.fill(fixture.arena, for: image)

        fixture.registry.registerLiveOwner(owner, for: image)

        let claims = fixture.registry.claims(for: image)
        #expect(!claims.contains(Group.arena), "a group with a finished entry belongs to whoever built it, not to the owner registering later")
        #expect(claims.contains(Group.store))
        #expect(claims.contains(Group.catalog))
    }

    @Test func lastOwnerEvictsOnlyWhatWasClaimed() {
        let fixture = Fixture()
        fixture.fill(fixture.catalog, for: image)
        fixture.registry.registerLiveOwner(owner, for: image)
        fixture.fillEverything(for: image)

        fixture.registry.deregisterLiveOwner(owner, for: image)

        #expect(!fixture.store.containsEntry(for: image), "the claimed store must go with its last owner")
        #expect(fixture.catalog.containsEntry(for: image), "an entry that predates the owner was never claimed and must survive it")
        #expect(!fixture.registry.hasLiveOwners(for: image))
    }

    @Test func survivingOwnerKeepsEverything() {
        let fixture = Fixture()
        fixture.registry.registerLiveOwner(owner, for: image)
        fixture.registry.registerLiveOwner(otherOwner, for: image)
        fixture.fillEverything(for: image)

        fixture.registry.deregisterLiveOwner(owner, for: image)

        for cache in fixture.everyCache {
            #expect(cache.containsEntry(for: image), "an owner leaving while a sibling is live must evict nothing")
        }
        #expect(fixture.registry.hasLiveOwners(for: image))
    }

    @Test func claimedGroupTakesItsFollowersEvenWhenTheyWereNotClaimed() {
        let fixture = Fixture()
        // Present at registration, so not claimed on its own.
        fixture.fill(fixture.table, for: image)
        fixture.registry.registerLiveOwner(owner, for: image)
        fixture.fill(fixture.store, for: image)

        fixture.registry.deregisterLiveOwner(owner, for: image)

        #expect(!fixture.store.containsEntry(for: image))
        #expect(!fixture.table.containsEntry(for: image), "the table holds the store's storage; left behind it pins what the eviction meant to free")
    }

    @Test func followersAreTakenTransitively() {
        let fixture = Fixture()
        fixture.fill(fixture.memo, for: image)
        fixture.fill(fixture.annotation, for: image)
        fixture.registry.registerLiveOwner(owner, for: image)
        fixture.fill(fixture.arena, for: image)

        fixture.registry.deregisterLiveOwner(owner, for: image)

        #expect(!fixture.arena.containsEntry(for: image))
        #expect(!fixture.memo.containsEntry(for: image), "the memo's values point into the arena; dropping the arena and keeping the memo frees nothing")
        #expect(!fixture.annotation.containsEntry(for: image), "the annotation points into the memo, which points into the arena: it goes with them")
    }

    @Test func droppingAFollowerAloneLeavesWhatItFollows() {
        let fixture = Fixture()
        fixture.fill(fixture.arena, for: image)
        fixture.registry.registerLiveOwner(owner, for: image)
        fixture.fill(fixture.memo, for: image)

        fixture.registry.deregisterLiveOwner(owner, for: image)

        #expect(!fixture.memo.containsEntry(for: image))
        #expect(fixture.arena.containsEntry(for: image), "following is one-way: the memo follows the arena, the arena does not follow the memo")
    }

    @Test func repeatedRegistrationDoesNotResample() {
        let fixture = Fixture()
        fixture.fill(fixture.arena, for: image)
        fixture.registry.registerLiveOwner(owner, for: image)
        // Between the two registrations the entry disappears; a second
        // sampling would now claim it and the owner would evict what it
        // never built.
        fixture.arena.removeEntry(for: image)
        fixture.registry.registerLiveOwner(owner, for: image)
        fixture.fill(fixture.arena, for: image)

        fixture.registry.deregisterLiveOwner(owner, for: image)

        #expect(fixture.arena.containsEntry(for: image), "only an owner's first registration contributes claims")
    }

    @Test func explicitEvictionTakesExactlyTheNamedGroups() {
        let fixture = Fixture()
        fixture.fillEverything(for: image)

        fixture.registry.evict(groups: [Group.store], for: image)

        #expect(!fixture.store.containsEntry(for: image))
        #expect(fixture.table.containsEntry(for: image), "an explicit eviction names what it wants gone; following is an ownership rule, not part of it")
    }

    @Test func evictingImagesWithoutLiveOwnersLeavesOwnedImagesAlone() {
        let fixture = Fixture()
        fixture.registry.registerLiveOwner(owner, for: image)
        fixture.fillEverything(for: image)
        fixture.fillEverything(for: otherImage)

        let evictedImageCount = fixture.registry.evictImagesWithoutLiveOwners()

        #expect(evictedImageCount == 1)
        for cache in fixture.everyCache {
            #expect(cache.containsEntry(for: image), "an image with a live owner is in use and must keep its entries")
            #expect(!cache.containsEntry(for: otherImage), "an image nobody owns is what the host asked to shed")
        }
    }

    @Test func deregisteringAnUnknownOwnerIsANoOp() {
        let fixture = Fixture()
        fixture.fillEverything(for: image)

        fixture.registry.deregisterLiveOwner(owner, for: image)

        for cache in fixture.everyCache {
            #expect(cache.containsEntry(for: image))
        }
    }
}
