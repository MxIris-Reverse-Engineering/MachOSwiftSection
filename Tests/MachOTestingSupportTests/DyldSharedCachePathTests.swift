import Testing
import MachOFixtureSupport

/// `DyldSharedCachePath` builds an archived cache's path and label from its
/// version. The named macOS caches are built that way too, and only the
/// integration dumps — which nothing runs automatically — open them, so a
/// path or a label that came out wrong would go unnoticed until someone ran
/// one by hand.
@Suite
struct DyldSharedCachePathTests {
    @Test("A version names the cache file in that version's directory on the volume, and labels it")
    func versionSpellsTheArchivedPathAndLabel() {
        let internalBuild = DyldSharedCachePath.macOS("14.0(Internal)")
        #expect(internalBuild.rawValue == "/Volumes/DyldSharedCaches/macOS/14.0(Internal)/dyld_shared_cache_arm64e")
        #expect(internalBuild.versionLabel == "14.0(Internal)")

        let device = DyldSharedCachePath.iOS("27.0")
        #expect(device.rawValue == "/Volumes/DyldSharedCaches/iOS/27.0/dyld_shared_cache_arm64e")
        #expect(device.versionLabel == "27.0")
    }

    /// The paths these named caches spelled out before they were built from a
    /// version, and the labels the evolution dumps used to write out for
    /// them by hand.
    @Test("The named macOS caches keep their paths and labels", arguments: [
        (DyldSharedCachePath.macOS_15_5, "/Volumes/DyldSharedCaches/macOS/15.5/dyld_shared_cache_arm64e", "15.5"),
        (.macOS_26_5_1, "/Volumes/DyldSharedCaches/macOS/26.5.1/dyld_shared_cache_arm64e", "26.5.1"),
        (.macOS_26_5_2, "/Volumes/DyldSharedCaches/macOS/26.5.2/dyld_shared_cache_arm64e", "26.5.2"),
        (.macOS_27_0, "/Volumes/DyldSharedCaches/macOS/27.0/dyld_shared_cache_arm64e", "27.0"),
    ])
    func namedCacheKeepsItsPathAndLabel(cachePath: DyldSharedCachePath, expectedPath: String, expectedVersionLabel: String) {
        #expect(cachePath.rawValue == expectedPath)
        #expect(cachePath.versionLabel == expectedVersionLabel)
    }
}
