import MachOKitExtensions
import Testing
import Foundation
import MachOKit

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

    // Both of these exist on macOS 26. Neither sits inside a
    // `libGLVMPlugin.framework`, so both classify as plain dylibs.
    private let nativePluginDylibPath = "/System/Library/Frameworks/OpenGL.framework/Versions/A/Libraries/libGLVMPlugin.dylib"
    private let catalystPluginDylibPath = "/System/iOSSupport/System/Library/Frameworks/OpenGLES.framework/Versions/A/Libraries/libGLVMPlugin.dylib"

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

    /// The support-root demotion has to apply to **every** path shape, not just
    /// to framework-shaped ones.
    ///
    /// `libGLVMPlugin.dylib` ships natively under `OpenGL.framework` and as a
    /// Mac Catalyst build under `iOSSupport/…/OpenGLES.framework`. Neither is
    /// inside a `libGLVMPlugin.framework`, so both classify as plain dylibs —
    /// and while the demotion lived inside the framework branch they tied,
    /// putting `-n libGLVMPlugin` back at the mercy of enumeration order.
    @Test func catalystPlainDylibLosesToItsNativeNamesake() throws {
        let mode = DyldCacheImageSearchMode.name("libGLVMPlugin")
        let nativeRank = try #require(mode.matchRank(forImagePath: nativePluginDylibPath))
        let catalystRank = try #require(mode.matchRank(forImagePath: catalystPluginDylibPath))
        #expect(nativeRank < catalystRank)
    }

    /// The penalty is a tiebreak *within* a shape, never a reclassification: a
    /// demoted Catalyst build still beats every worse shape. Otherwise a native
    /// `.axbundle` — the metadata-less payload that started all of this — could
    /// outrank a Catalyst framework binary.
    @Test func supportRootPenaltyNeverCrossesAShapeBoundary() throws {
        let frameworkMode = DyldCacheImageSearchMode.name("SwiftUI")
        let catalystFrameworkRank = try #require(frameworkMode.matchRank(forImagePath: catalystFrameworkPath))
        let nativeBundleRank = try #require(frameworkMode.matchRank(forImagePath: accessibilityBundlePath))
        #expect(catalystFrameworkRank < nativeBundleRank)

        let dylibMode = DyldCacheImageSearchMode.name("libGLVMPlugin")
        let catalystDylibRank = try #require(dylibMode.matchRank(forImagePath: catalystPluginDylibPath))
        #expect(catalystFrameworkRank < catalystDylibRank)
        #expect(catalystDylibRank < nativeBundleRank)
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

// MARK: - End-to-End Cache Lookup

/// End-to-end lookup against the CURRENT system's dyld shared cache — the
/// shape all three ranking rounds missed is a plain `.dylib` name, which can
/// never reach `bestMatchRank` (only a native canonical framework can) and
/// therefore always pays the full multi-cache scan before answering.
/// PR #103 review, finding L3.
private let currentSystemDyldSharedCachePath = "/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_arm64e"

@Suite(.enabled(if: FileManager.default.fileExists(atPath: currentSystemDyldSharedCachePath)))
struct DyldCacheEndToEndLookupTests {

    @Test func plainDylibNameResolvesToTheRealDylib() throws {
        let cache = try DyldCache(url: URL(fileURLWithPath: currentSystemDyldSharedCachePath))
        let machOFile = try #require(cache.machOFile(by: .name("libswiftCore")))
        #expect(machOFile.imagePath == "/usr/lib/swift/libswiftCore.dylib")
    }

    @Test func frameworkNameStillResolvesToTheCanonicalBinary() throws {
        let cache = try DyldCache(url: URL(fileURLWithPath: currentSystemDyldSharedCachePath))
        let machOFile = try #require(cache.machOFile(by: .name("SwiftUI")))
        #expect(machOFile.imagePath.hasSuffix("SwiftUI.framework/Versions/A/SwiftUI"))
        #expect(!machOFile.imagePath.contains("iOSSupport"))
    }
}
