import Foundation
import Testing
@_spi(Internals) import MachOCaches

/// The registry's ownership rules, driven on a registry of its own with
/// caches created against it — the process-wide registry and the real
/// indexer are exercised end to end by `PerImageCacheEvictionTests`.
@Suite("SharedCacheRegistry")
struct SharedCacheRegistryTests {
    /// A registry plus one cache per group the rules below reach.
    private struct Fixture {
        let registry = SharedCacheRegistry()
        let symbolStore: SharedCache<Int>
        let symbolicMangling: SharedCache<Int>
        let internedNames: SharedCache<Int>
        let demangleMemo: SharedCache<Int>
        let propertyWrapperCatalog: SharedCache<Int>

        init() {
            symbolStore = SharedCache(evictionGroup: .symbolStore, registry: registry)
            symbolicMangling = SharedCache(evictionGroup: .symbolicMangling, registry: registry)
            internedNames = SharedCache(evictionGroup: .internedNames, registry: registry)
            demangleMemo = SharedCache(evictionGroup: .demangleMemo, registry: registry)
            propertyWrapperCatalog = SharedCache(evictionGroup: .propertyWrapperCatalog, registry: registry)
        }

        var everyCache: [SharedCache<Int>] {
            [symbolStore, symbolicMangling, internedNames, demangleMemo, propertyWrapperCatalog]
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

    @Test func registrationClaimsTheGroupsAbsentAtThatMoment() {
        let fixture = Fixture()
        fixture.fill(fixture.internedNames, for: image)

        fixture.registry.registerLiveOwner(owner, for: image)

        let claims = fixture.registry.claims(for: image)
        #expect(!claims.contains(.internedNames), "a group with a finished entry belongs to whoever built it, not to the owner registering later")
        #expect(claims.contains(.symbolStore))
        #expect(claims.contains(.propertyWrapperCatalog))
    }

    @Test func lastOwnerEvictsOnlyWhatWasClaimed() {
        let fixture = Fixture()
        fixture.fill(fixture.propertyWrapperCatalog, for: image)
        fixture.registry.registerLiveOwner(owner, for: image)
        fixture.fillEverything(for: image)

        fixture.registry.deregisterLiveOwner(owner, for: image)

        #expect(!fixture.symbolStore.containsEntry(for: image), "the claimed symbol store must go with its last owner")
        #expect(fixture.propertyWrapperCatalog.containsEntry(for: image), "an entry that predates the owner was never claimed and must survive it")
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

    @Test func claimedSymbolStoreTakesItsDependentsEvenWhenTheyWereNotClaimed() {
        let fixture = Fixture()
        // Present at registration, so not claimed on its own.
        fixture.fill(fixture.symbolicMangling, for: image)
        fixture.registry.registerLiveOwner(owner, for: image)
        fixture.fill(fixture.symbolStore, for: image)

        fixture.registry.deregisterLiveOwner(owner, for: image)

        #expect(!fixture.symbolStore.containsEntry(for: image))
        #expect(!fixture.symbolicMangling.containsEntry(for: image), "the symbolic-mangling index holds the symbol store's table; left behind it pins what the eviction meant to free")
    }

    @Test func claimedInternedNamesTakesTheDemangleMemo() {
        let fixture = Fixture()
        fixture.fill(fixture.demangleMemo, for: image)
        fixture.registry.registerLiveOwner(owner, for: image)
        fixture.fill(fixture.internedNames, for: image)

        fixture.registry.deregisterLiveOwner(owner, for: image)

        #expect(!fixture.internedNames.containsEntry(for: image))
        #expect(!fixture.demangleMemo.containsEntry(for: image), "the memo's values point into the interned arena; dropping the arena and keeping the memo frees nothing")
    }

    @Test func droppingTheMemoAloneLeavesTheArena() {
        let fixture = Fixture()
        fixture.fill(fixture.internedNames, for: image)
        fixture.registry.registerLiveOwner(owner, for: image)
        fixture.fill(fixture.demangleMemo, for: image)

        fixture.registry.deregisterLiveOwner(owner, for: image)

        #expect(!fixture.demangleMemo.containsEntry(for: image))
        #expect(fixture.internedNames.containsEntry(for: image), "the pairing is one-way: the memo follows the arena, the arena does not follow the memo")
    }

    @Test func repeatedRegistrationDoesNotResample() {
        let fixture = Fixture()
        fixture.fill(fixture.internedNames, for: image)
        fixture.registry.registerLiveOwner(owner, for: image)
        // Between the two registrations the entry disappears; a second
        // sampling would now claim it and the owner would evict what it
        // never built.
        fixture.internedNames.removeEntry(for: image)
        fixture.registry.registerLiveOwner(owner, for: image)
        fixture.fill(fixture.internedNames, for: image)

        fixture.registry.deregisterLiveOwner(owner, for: image)

        #expect(fixture.internedNames.containsEntry(for: image), "only an owner's first registration contributes claims")
    }

    @Test func explicitEvictionTakesExactlyTheNamedGroups() {
        let fixture = Fixture()
        fixture.fillEverything(for: image)

        fixture.registry.evict(groups: [.symbolStore], for: image)

        #expect(!fixture.symbolStore.containsEntry(for: image))
        #expect(fixture.symbolicMangling.containsEntry(for: image), "an explicit eviction names what it wants gone; dependents are an ownership rule, not part of it")
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
