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
