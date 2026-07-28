@testable import MachOExtensions
import Testing

/// Regression coverage for dyld-shared-cache image selection.
///
/// Leaf names are not unique inside a cache: iOS 27 ships both
/// `/System/Library/Frameworks/SwiftUI.framework/SwiftUI` and
/// `/System/Library/AccessibilityBundles/SwiftUI.axbundle/SwiftUI`. The old
/// first-match-wins name lookup resolved to whichever the cache enumerated
/// first — on the simulator caches the accessibility bundle, which carries no
/// Swift metadata, so `swift-section --dyld-shared-cache -n SwiftUI` emitted an
/// empty dump and still exited zero. Ranking must make the framework binary win.
///
/// The ranking is pure path arithmetic, so these cases pin it directly without
/// needing a cache on disk.
@Suite
struct DyldCacheImageSearchTests {
    private let iOSFrameworkPath = "/System/Library/Frameworks/SwiftUI.framework/SwiftUI"
    private let macOSFrameworkPath = "/System/Library/Frameworks/SwiftUI.framework/Versions/A/SwiftUI"
    private let accessibilityBundlePath = "/System/Library/AccessibilityBundles/SwiftUI.axbundle/SwiftUI"
    private let catalystFrameworkPath = "/System/iOSSupport/System/Library/Frameworks/SwiftUI.framework/SwiftUI"

    private let bestRank = DyldCacheImageSearchMode.bestMatchRank

    // MARK: - Name lookup ranking

    @Test func frameworkBinaryScoresBestRank() {
        let mode = DyldCacheImageSearchMode.name("SwiftUI")
        #expect(mode.matchRank(forImagePath: iOSFrameworkPath) == bestRank)
        #expect(mode.matchRank(forImagePath: macOSFrameworkPath) == bestRank)
    }

    @Test func accessibilityBundleMatchesButRanksWorseThanFramework() throws {
        let mode = DyldCacheImageSearchMode.name("SwiftUI")
        // It is still a name match — the cache really does contain it — but it
        // must never outrank the framework binary.
        let bundleRank = try #require(mode.matchRank(forImagePath: accessibilityBundlePath))
        let frameworkRank = try #require(mode.matchRank(forImagePath: iOSFrameworkPath))
        #expect(bundleRank > frameworkRank)
        #expect(frameworkRank == bestRank)
    }

    @Test func dylibRanksBetweenFrameworkAndBundle() throws {
        let dylibMode = DyldCacheImageSearchMode.name("libswiftCore")
        let dylibRank = try #require(dylibMode.matchRank(forImagePath: "/usr/lib/swift/libswiftCore.dylib"))
        let bundleMode = DyldCacheImageSearchMode.name("SwiftUI")
        let bundleRank = try #require(bundleMode.matchRank(forImagePath: accessibilityBundlePath))
        #expect(dylibRank > bestRank)
        #expect(dylibRank < bundleRank)
    }

    /// A macOS cache also carries the Mac Catalyst build of the same framework
    /// under `/System/iOSSupport` — framework-shaped, same leaf name, a real
    /// dylib. 74 frameworks collide this way on macOS 26 (SwiftUI, ARKit,
    /// AVKit, GameKit, HealthKit, …).
    ///
    /// Both used to score `bestMatchRank`, and `accumulateBestMatch` returns at
    /// the *first* image reaching that rank, so `-n SwiftUI` resolved to
    /// whichever the cache happened to enumerate first — the same
    /// order-dependence the ranking was introduced to remove, just moved from
    /// bundle-versus-framework to Catalyst-versus-native. Only the native
    /// framework may reach `bestMatchRank`.
    @Test func catalystVariantMatchesButNeverScoresBestRank() throws {
        let mode = DyldCacheImageSearchMode.name("SwiftUI")
        let catalystRank = try #require(mode.matchRank(forImagePath: catalystFrameworkPath))
        #expect(catalystRank > bestRank)
        #expect(mode.matchRank(forImagePath: iOSFrameworkPath) == bestRank)
        #expect(mode.matchRank(forImagePath: macOSFrameworkPath) == bestRank)
    }

    /// The Catalyst variant is a real framework binary, so it still outranks a
    /// plain dylib and a bundle wearing the same leaf name — it loses only to
    /// the native framework.
    @Test func catalystVariantOutranksDylibAndBundle() throws {
        let mode = DyldCacheImageSearchMode.name("SwiftUI")
        let catalystRank = try #require(mode.matchRank(forImagePath: catalystFrameworkPath))
        let bundleRank = try #require(mode.matchRank(forImagePath: accessibilityBundlePath))
        let dylibRank = try #require(
            DyldCacheImageSearchMode.name("libswiftCore").matchRank(forImagePath: "/usr/lib/swift/libswiftCore.dylib")
        )
        #expect(catalystRank < dylibRank)
        #expect(dylibRank < bundleRank)
    }

    /// `/System/iOSSupport` demotes only a framework that has a native twin to
    /// lose to; the support root must not make a path stop matching.
    @Test func catalystVariantIsStillAMatch() {
        let mode = DyldCacheImageSearchMode.name("SwiftUI")
        #expect(mode.matchRank(forImagePath: catalystFrameworkPath) != nil)
    }

    @Test func nonMatchingLeafNameIsNotAMatch() {
        let mode = DyldCacheImageSearchMode.name("SwiftUI")
        #expect(mode.matchRank(forImagePath: "/System/Library/Frameworks/SwiftUICore.framework/SwiftUICore") == nil)
        #expect(mode.matchRank(forImagePath: "/System/Library/Frameworks/_AVKit_SwiftUI.framework/_AVKit_SwiftUI") == nil)
    }

    /// A leaf sitting inside a *different* framework must not be promoted:
    /// only `<name>.framework` counts as the canonical home.
    @Test func leafInsideForeignFrameworkDoesNotScoreBestRank() throws {
        let mode = DyldCacheImageSearchMode.name("SwiftUI")
        let rank = try #require(mode.matchRank(forImagePath: "/System/Library/Frameworks/Foo.framework/SwiftUI"))
        #expect(rank > bestRank)
    }

    // MARK: - Path lookup

    @Test func pathLookupIsExactAndAlwaysBestRank() {
        let mode = DyldCacheImageSearchMode.path(iOSFrameworkPath)
        #expect(mode.matchRank(forImagePath: iOSFrameworkPath) == bestRank)
        #expect(mode.matchRank(forImagePath: macOSFrameworkPath) == nil)
        #expect(mode.matchRank(forImagePath: accessibilityBundlePath) == nil)
    }
}
