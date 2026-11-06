import Foundation
@_spi(Support) import MachOKit
import MachOKitExtensions
import Testing
@testable import MachODependencies
import MachOFixtureSupport

/// Every `FileDependencyLocator` that searches one dyld shared cache file by
/// path reads one opening of it, for as long as anything still holds that
/// opening.
///
/// Each consumer of a dependency closure — static layout, the indexer, thunk
/// analysis, the Objective-C ancestor chain, the property wrapper catalog, an
/// interface's dependencies — builds a locator for every root, and each opened
/// a cache it was given by path again: DockHelper paired with an archived
/// macOS 27.0 cache held 369 descriptors on that cache's 80 files in one
/// `interface` run, up to 7 on a single file.
@Suite
struct SharedDyldCacheOpeningTests {
    private static let libobjcPath = "/usr/lib/libobjc.A.dylib"

    /// How many roots' locators the descriptor test builds: each opening of
    /// the host cache takes one descriptor per file, so even two exceed what
    /// a service starts with.
    private static let locatorCount = 6

    /// The descriptor limit launchd starts an XPC service with.
    private static let serviceDescriptorLimit: rlim_t = 256

    private static var hostCachePath: String {
        DyldSharedCachePath.current.rawValue
    }

    private static var isHostDyldCacheAvailable: Bool {
        FileManager.default.fileExists(atPath: hostCachePath)
    }

    @Test(.enabled(if: isHostDyldCacheAvailable))
    func locatorsSearchingOneCachePathShareOneOpening() throws {
        let firstImage = try #require(FileDependencyLocator(searchPaths: [.dyldSharedCache(path: Self.hostCachePath)]).locate(loadName: Self.libobjcPath))
        let secondImage = try #require(FileDependencyLocator(searchPaths: [.dyldSharedCache(path: Self.hostCachePath)]).locate(loadName: Self.libobjcPath))

        let firstCache = try #require(firstImage._cachedFullCache)
        #expect(secondImage._cachedFullCache === firstCache)
    }

    /// Shared, but not kept: once nothing holds an opening it closes, so a
    /// run over dozens of caches does not keep every one of them open. In a
    /// child process, where no other test can be holding the same opening.
    @Test(.enabled(if: isHostDyldCacheAvailable))
    func anOpeningNothingHoldsIsReleased() async {
        await #expect(processExitsWith: .success) {
            exit(SharedDyldCacheOpeningTests.openingIsReleasedOnceNothingHoldsIt() ? EXIT_SUCCESS : EXIT_FAILURE)
        }
    }

    /// The roots of one image each build a locator, as RuntimeViewer's offline
    /// service does, under the descriptor limit the service starts with. Soft
    /// and hard limit both: the first use of `CFSocket` raises the soft limit
    /// by 2,304 within the hard one.
    @Test(.enabled(if: isHostDyldCacheAvailable))
    func locatorsOfManyRootsStayWithinAServiceDescriptorLimit() async {
        await #expect(processExitsWith: .success) {
            exit(SharedDyldCacheOpeningTests.locatorsLocateUnderTheServiceDescriptorLimit() ? EXIT_SUCCESS : EXIT_FAILURE)
        }
    }

    // MARK: - Exit test bodies

    static func openingIsReleasedOnceNothingHoldsIt() -> Bool {
        weak var openedCache: FullDyldCache?
        var wasOpened = false
        autoreleasepool {
            guard let image = FileDependencyLocator(searchPaths: [.dyldSharedCache(path: hostCachePath)]).locate(loadName: libobjcPath) else { return }
            openedCache = image._cachedFullCache
            wasOpened = openedCache != nil
        }
        return wasOpened && openedCache == nil
    }

    static func locatorsLocateUnderTheServiceDescriptorLimit() -> Bool {
        var limit = rlimit(rlim_cur: serviceDescriptorLimit, rlim_max: serviceDescriptorLimit)
        guard setrlimit(RLIMIT_NOFILE, &limit) == 0 else { return false }
        var heldImages: [MachOFile] = []
        for _ in 0 ..< locatorCount {
            guard let image = FileDependencyLocator(searchPaths: [.dyldSharedCache(path: hostCachePath)]).locate(loadName: libobjcPath) else {
                return false
            }
            heldImages.append(image)
        }
        return heldImages.count == locatorCount
    }
}
