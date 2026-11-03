import Foundation
@_spi(Support) import MachOKit
import MachOKitExtensions
import Testing
@testable import MachODependencies
import MachOFixtureSupport

/// Every `FileDependencyLocator` over one dyld shared cache reads the same
/// directory of that cache's images, built once per process, and still
/// answers exactly what a locator walking the cache itself answers.
///
/// A locator is built per root: every offline interface RuntimeViewer prints
/// with a layout comment on built one, and each walked all ~3,500 images of
/// the cache — a `MachOFile` and the platforms of every one — before its
/// first answer.
@Suite
struct DyldCacheImageDirectorySharingTests {
    private static let foundationInstallPath = "/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation"

    /// The load names checked against the reference: a few install paths and
    /// bare names spelled the way a non-system binary links them.
    private static let sampleLoadNames = [
        foundationInstallPath,
        "/usr/lib/swift/libswiftCore.dylib",
        "/System/Library/Frameworks/SwiftUI.framework/Versions/A/SwiftUI",
        "/System/iOSSupport/System/Library/Frameworks/SwiftUI.framework/Versions/A/SwiftUI",
        "/System/Library/Frameworks/UIKit.framework/UIKit",
        "/usr/lib/libobjc.A.dylib",
        "/System/Library/Frameworks/Foundation.framework/Foundation",
        "@rpath/SwiftUI.framework/SwiftUI",
        "@rpath/libswiftCore.dylib",
        "@rpath/Foundation.framework/Foundation",
        "@rpath/libc++.1.dylib",
        "@rpath/NoSuchLibrary.framework/NoSuchLibrary",
    ]

    /// The root platforms the reference is compared under: none (every image
    /// a candidate), a macOS root, a zippered root, and a simulator root the
    /// host cache has nothing for.
    private static let platformSets: [Set<Platform>] = [[], [.macOS], [.macOS, .macCatalyst], [.iOSSimulator]]

    @Test func locatorsOverOneCacheShareItsDirectory() throws {
        guard FullDyldCache.cachedHost != nil else {
            print("skipped: no host dyld shared cache")
            return
        }
        let firstStart = Date()
        let firstLocator = FileDependencyLocator(searchPaths: [.systemDyldSharedCache], platforms: [.macOS])
        _ = firstLocator.locate(loadName: Self.foundationInstallPath)
        let firstDuration = Date().timeIntervalSince(firstStart)

        let secondStart = Date()
        let secondLocator = FileDependencyLocator(searchPaths: [.systemDyldSharedCache], platforms: [.macOS])
        _ = secondLocator.locate(loadName: Self.foundationInstallPath)
        let secondDuration = Date().timeIntervalSince(secondStart)
        // Information only: another test of this process may have built the
        // directory first, in which case both are the shared path.
        print("information: first locator's first lookup \(String(format: "%.3f", firstDuration)) s, second's \(String(format: "%.3f", secondDuration)) s")

        let firstDirectories = firstLocator.cacheImageDirectoryIdentifiers()
        let secondDirectories = secondLocator.cacheImageDirectoryIdentifiers()
        #expect(firstDirectories.count == 1)
        #expect(firstDirectories == secondDirectories)

        // A root of another platform reads the same directory too: the
        // platforms are stored per image and filtered per root.
        let simulatorLocator = FileDependencyLocator(searchPaths: [.systemDyldSharedCache], platforms: [.iOSSimulator])
        #expect(simulatorLocator.cacheImageDirectoryIdentifiers() == firstDirectories)
    }

    /// A `MachOFile` stores lazily filled state unguarded, so the shared
    /// directory never hands one instance to two locators: each makes its own
    /// for the images it locates, and gives the same one back each time.
    @Test func eachLocatorMakesItsOwnFiles() throws {
        guard FullDyldCache.cachedHost != nil else {
            print("skipped: no host dyld shared cache")
            return
        }
        let firstLocator = FileDependencyLocator(searchPaths: [.systemDyldSharedCache])
        let secondLocator = FileDependencyLocator(searchPaths: [.systemDyldSharedCache])
        let firstFoundation = try #require(firstLocator.locate(loadName: Self.foundationInstallPath))
        let secondFoundation = try #require(secondLocator.locate(loadName: Self.foundationInstallPath))
        #expect(firstFoundation !== secondFoundation)
        #expect(firstFoundation.imagePath == secondFoundation.imagePath)
        #expect(firstLocator.locate(loadName: Self.foundationInstallPath) === firstFoundation)
        #expect(firstLocator.locate(loadName: "@rpath/Foundation.framework/Foundation") === firstFoundation)
    }

    /// Every install path and every bare name of the host cache, under each
    /// platform set, resolves to the image the reference walk resolves it to.
    @Test(arguments: platformSets)
    func hostCacheAnswersMatchTheReference(platforms: Set<Platform>) throws {
        guard let hostCache = FullDyldCache.cachedHost else {
            print("skipped: no host dyld shared cache")
            return
        }
        let reference = ReferenceCacheIndex(caches: [hostCache], platforms: platforms)
        if !platforms.contains(.iOSSimulator) {
            #expect(reference.everyLoadName.count > 1_000, "the comparison covers the cache's images")
        }
        let locator = FileDependencyLocator(searchPaths: [.systemDyldSharedCache], platforms: platforms)
        try Self.expectAnswersMatch(locator: locator, reference: reference, loadNames: Self.sampleLoadNames + reference.everyLoadName)
    }

    /// With two caches, the root's own is searched first: an install path in
    /// both resolves to the root's, and a bare name to the best rank over
    /// both, the root's cache winning a tie.
    @Test(.enabled(if: ArchivedMacOS15CacheFixtures.hasCache))
    func rootCacheFirstAnswersMatchTheReference() throws {
        let hostCache = try #require(FullDyldCache.cachedHost, "no host dyld shared cache")
        let archivedCache = try FullDyldCache(path: ArchivedMacOS15CacheFixtures.cachePath)
        let reference = ReferenceCacheIndex(caches: [archivedCache, hostCache], platforms: [.macOS])
        #expect(reference.everyLoadName.count > 1_000, "the comparison covers the caches' images")
        let locator = FileDependencyLocator(searchPaths: [.systemDyldSharedCache], platforms: [.macOS], rootDyldCache: archivedCache)
        try Self.expectAnswersMatch(locator: locator, reference: reference, loadNames: Self.sampleLoadNames + reference.everyLoadName)

        let foundation = try #require(locator.locate(loadName: Self.foundationInstallPath))
        #expect(foundation.url.path.hasPrefix(archivedCache.url.deletingLastPathComponent().path))
    }

    private static func expectAnswersMatch(locator: FileDependencyLocator, reference: ReferenceCacheIndex, loadNames: [String]) throws {
        var mismatches: [String] = []
        for loadName in loadNames {
            let expected = reference.locate(loadName: loadName)
            let located = locator.locate(loadName: loadName)
            guard ImagePosition(expected) == ImagePosition(located) else {
                mismatches.append("\(loadName): expected \(String(describing: ImagePosition(expected))), located \(String(describing: ImagePosition(located)))")
                continue
            }
        }
        #expect(mismatches.isEmpty, "\(mismatches.count) of \(loadNames.count) load names differ:\n\(mismatches.prefix(20).joined(separator: "\n"))")
    }

    /// Where an image's header sits, which names it across two openings of
    /// one cache.
    private struct ImagePosition: Equatable, CustomStringConvertible {
        let imagePath: String
        let cacheFilePath: String
        let headerStartOffsetInCache: Int

        init?(_ machOFile: MachOFile?) {
            guard let machOFile else { return nil }
            imagePath = machOFile.imagePath
            cacheFilePath = machOFile.url.standardizedFileURL.path
            headerStartOffsetInCache = machOFile.headerStartOffsetInCache
        }

        var description: String {
            "\(imagePath) @ \(cacheFilePath)+0x\(String(headerStartOffsetInCache, radix: 16))"
        }
    }

    /// The cache half of `FileDependencyLocator` as it was before the
    /// directory was shared: one walk over every cache's `machOFiles()`, in
    /// order, skipping images of another platform; the first image under an
    /// install path wins, and under a bare name the best rank, the earlier
    /// image winning a tie.
    private struct ReferenceCacheIndex {
        private var imagesByInstallPath: [String: MachOFile] = [:]
        private var bestImagesByBareName: [String: (rank: Int, machOFile: MachOFile)] = [:]

        init(caches: [FullDyldCache], platforms: Set<Platform>) {
            for cache in caches {
                for machOFile in cache.machOFiles() {
                    guard DependencyPlatforms.areCompatible(platforms, DependencyPlatforms.platforms(of: machOFile)) else { continue }
                    let installPath = machOFile.imagePath
                    if imagesByInstallPath[installPath] == nil {
                        imagesByInstallPath[installPath] = machOFile
                    }
                    let bareImageName = DependencyLoadName.bareImageName(of: installPath)
                    guard !bareImageName.isEmpty else { continue }
                    let rank = DyldCacheImageSearchMode.name(bareImageName).matchRank(forImagePath: installPath) ?? Int.max
                    if let existing = bestImagesByBareName[bareImageName], existing.rank <= rank {
                        continue
                    }
                    bestImagesByBareName[bareImageName] = (rank, machOFile)
                }
            }
        }

        func locate(loadName: String) -> MachOFile? {
            if let image = imagesByInstallPath[loadName] {
                return image
            }
            let bareImageName = DependencyLoadName.bareImageName(of: loadName)
            guard !bareImageName.isEmpty else { return nil }
            return bestImagesByBareName[bareImageName]?.machOFile
        }

        /// Every install path, and every bare name spelled as an `@rpath`
        /// load name so that only the bare-name step can answer it.
        var everyLoadName: [String] {
            imagesByInstallPath.keys.sorted() + bestImagesByBareName.keys.sorted().map { "@rpath/\($0).dylib" }
        }
    }
}
