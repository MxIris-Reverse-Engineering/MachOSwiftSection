import Foundation
import MachOKit
import MachOKitExtensions
import Testing
@testable import MachODependencies

/// Pins the two-step lookup of `FileDependencyLocator` against the host's own
/// dyld shared cache: exact install path first, ranked bare name second.
///
/// The ranking matters on macOS specifically. The macOS cache carries the Mac
/// Catalyst build of SwiftUI under `/System/iOSSupport` next to the native
/// framework, so a first-writer-wins bare-name index (the pre-unification
/// SwiftLayout locator) resolved whichever the cache enumerated first.
@Suite
struct FileDependencyLocatorTests {
    private static let nativeSwiftUIPath = "/System/Library/Frameworks/SwiftUI.framework/Versions/A/SwiftUI"
    private static let catalystSwiftUIPath = "/System/iOSSupport/System/Library/Frameworks/SwiftUI.framework/Versions/A/SwiftUI"

    private func hostLocator() -> FileDependencyLocator? {
        guard FullDyldCache.host != nil else {
            print("skipped: no host dyld shared cache")
            return nil
        }
        return FileDependencyLocator(searchPaths: [.systemDyldSharedCache])
    }

    @Test func exactInstallPathIsAnsweredVerbatim() throws {
        guard let locator = hostLocator() else { return }
        let native = try #require(locator.locate(loadName: Self.nativeSwiftUIPath))
        #expect(native.imagePath == Self.nativeSwiftUIPath)

        // The Catalyst build shares SwiftUI's bare name; asked for by exact
        // path it must come back as itself, never as the native winner.
        if let catalyst = locator.locate(loadName: Self.catalystSwiftUIPath) {
            #expect(catalyst.imagePath == Self.catalystSwiftUIPath)
        } else {
            print("note: this host cache carries no Catalyst SwiftUI; exact-path half of the check skipped")
        }
    }

    @Test func bareNameFallbackPrefersTheNativeCanonicalFramework() throws {
        guard let locator = hostLocator() else { return }
        let resolved = try #require(locator.locate(loadName: "@rpath/SwiftUI.framework/SwiftUI"))
        #expect(resolved.imagePath == Self.nativeSwiftUIPath)
        #expect(!resolved.imagePath.hasPrefix("/System/iOSSupport"))
    }

    @Test func bareNameFallbackResolvesAbsolutePathsTheCacheDoesNotSpell() throws {
        guard let locator = hostLocator() else { return }
        // A plausible load name whose exact path is not in the cache (no
        // `Versions/A`), so only the bare-name step can answer.
        let resolved = try #require(locator.locate(loadName: "/System/Library/Frameworks/Foundation.framework/Foundation"))
        #expect(DependencyLoadName.bareImageName(of: resolved.imagePath) == "Foundation")
    }

    // MARK: - Platform guard

    /// The platforms come from `LC_BUILD_VERSION`: the native SwiftUI is a
    /// macOS build (zippered ones also declare Mac Catalyst), the copy under
    /// `/System/iOSSupport` a Mac Catalyst one and nothing else.
    @Test func platformsAreReadFromTheBuildVersionCommands() throws {
        guard let locator = hostLocator() else { return }
        let native = try #require(locator.locate(loadName: Self.nativeSwiftUIPath))
        #expect(DependencyPlatforms.platforms(of: native).contains(.macOS))
        if let catalyst = locator.locate(loadName: Self.catalystSwiftUIPath) {
            let platforms = DependencyPlatforms.platforms(of: catalyst)
            #expect(platforms == [.macCatalyst])
        } else {
            print("note: this host cache carries no Catalyst SwiftUI; the Catalyst half of the check skipped")
        }
        #expect(DependencyPlatforms.areCompatible([.macOS], [.macOS, .macCatalyst]))
        #expect(!DependencyPlatforms.areCompatible([.iOSSimulator], [.macCatalyst]))
        #expect(!DependencyPlatforms.areCompatible([.iOSSimulator], [.iOS]))
        #expect(DependencyPlatforms.areCompatible([], [.iOS]), "a root declaring no platform accepts every image")
        #expect(DependencyPlatforms.areCompatible([.iOS], []), "an image declaring no platform is never rejected")
    }

    /// An iOS-simulator root's `UIKit` must not resolve to the macOS cache's
    /// Mac Catalyst UIKit: same class names, another platform's method
    /// tables and instance sizes. Without the guard the bare-name fallback
    /// handed it back, since no native build exists to outrank it.
    @Test func cacheImagesOfAnotherPlatformAreNotCandidates() throws {
        guard FullDyldCache.host != nil else {
            print("skipped: no host dyld shared cache")
            return
        }
        let uiKitLoadName = "/System/Library/Frameworks/UIKit.framework/UIKit"
        let unguarded = FileDependencyLocator(searchPaths: [.systemDyldSharedCache])
        guard let catalystUIKit = unguarded.locate(loadName: uiKitLoadName) else {
            print("note: this host cache carries no Catalyst UIKit; guard check skipped")
            return
        }
        #expect(catalystUIKit.imagePath.hasPrefix("/System/iOSSupport"))

        let simulatorRoot = FileDependencyLocator(searchPaths: [.systemDyldSharedCache], platforms: [.iOSSimulator])
        #expect(simulatorRoot.locate(loadName: uiKitLoadName) == nil)
        #expect(simulatorRoot.locate(loadName: "/usr/lib/libobjc.A.dylib") == nil, "an exact install path is rejected on platform too")

        let macOSRoot = FileDependencyLocator(searchPaths: [.systemDyldSharedCache], platforms: [.macOS])
        #expect(macOSRoot.locate(loadName: Self.nativeSwiftUIPath)?.imagePath == Self.nativeSwiftUIPath)
        #expect(macOSRoot.locate(loadName: "/usr/lib/libobjc.A.dylib") != nil)
        // A zippered root shares a platform with the Catalyst images and
        // may take them; a plain macOS root does not.
        #expect(macOSRoot.locate(loadName: uiKitLoadName) == nil)
        let zipperedRoot = FileDependencyLocator(searchPaths: [.systemDyldSharedCache], platforms: [.macOS, .macCatalyst])
        #expect(zipperedRoot.locate(loadName: uiKitLoadName)?.imagePath == catalystUIKit.imagePath)
    }

    @Test func unknownNameResolvesToNil() {
        guard let locator = hostLocator() else { return }
        #expect(locator.locate(loadName: "@rpath/NoSuchLibrary.framework/NoSuchLibrary") == nil)
        #expect(locator.locate(loadName: "") == nil)
    }

    @Test func unopenableCachePathIsRecorded() {
        let missingPath = "/nonexistent/dyld_shared_cache_arm64e"
        let locator = FileDependencyLocator(searchPaths: [.dyldSharedCache(path: missingPath)])
        #expect(locator.loadFailures.count == 1)
        #expect(locator.loadFailures.first?.searchPath == .dyldSharedCache(path: missingPath))
        #expect(locator.locate(loadName: "/usr/lib/swift/libswiftCore.dylib") == nil)
    }

    @Test func searchPathDescriptionsAreStable() {
        #expect(DependencySearchPath.machOFile(path: "/a").description == "machOFile(/a)")
        #expect(DependencySearchPath.dyldSharedCache(path: "/b").description == "dyldSharedCache(/b)")
        #expect(DependencySearchPath.systemDyldSharedCache.description == "systemDyldSharedCache")
    }
}
