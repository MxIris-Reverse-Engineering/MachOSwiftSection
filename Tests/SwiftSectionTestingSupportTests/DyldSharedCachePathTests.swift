import Testing
import SwiftSectionFixtureSupport

/// The named macOS caches this package adds to `DyldSharedCachePath` are
/// built from a version. Only the integration dumps — which nothing runs
/// automatically — open them, so a path or a label that came out wrong would
/// go unnoticed until someone ran one by hand. How a version spells an
/// archived path is MachOKitExtensions' to test.
@Suite
struct DyldSharedCachePathTests {
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
        #expect(cachePath.path == expectedPath)
        #expect(cachePath.versionLabel == expectedVersionLabel)
    }
}
