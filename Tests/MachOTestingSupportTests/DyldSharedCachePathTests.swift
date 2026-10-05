import Testing
import MachOFixtureSupport

/// `DyldSharedCachePath` builds an archived cache's path from its version.
/// The named macOS caches are built that way too, and only the integration
/// dumps — which nothing runs automatically — open them, so a path that came
/// out wrong would go unnoticed until someone ran one by hand.
@Suite
struct DyldSharedCachePathTests {
    @Test("A version names the cache file in that version's directory on the volume")
    func versionSpellsTheArchivedPath() {
        #expect(DyldSharedCachePath.macOS("14.0(Internal)").rawValue == "/Volumes/DyldSharedCaches/macOS/14.0(Internal)/dyld_shared_cache_arm64e")
        #expect(DyldSharedCachePath.iOS("27.0").rawValue == "/Volumes/DyldSharedCaches/iOS/27.0/dyld_shared_cache_arm64e")
    }

    /// The paths these named caches spelled out before they were built from a
    /// version.
    @Test("The named macOS caches keep the paths they had", arguments: [
        (DyldSharedCachePath.macOS_15_5, "/Volumes/DyldSharedCaches/macOS/15.5/dyld_shared_cache_arm64e"),
        (.macOS_26_5_1, "/Volumes/DyldSharedCaches/macOS/26.5.1/dyld_shared_cache_arm64e"),
        (.macOS_26_5_2, "/Volumes/DyldSharedCaches/macOS/26.5.2/dyld_shared_cache_arm64e"),
        (.macOS_27_0, "/Volumes/DyldSharedCaches/macOS/27.0/dyld_shared_cache_arm64e"),
    ])
    func namedCacheKeepsItsPath(cachePath: DyldSharedCachePath, expectedPath: String) {
        #expect(cachePath.rawValue == expectedPath)
    }
}
