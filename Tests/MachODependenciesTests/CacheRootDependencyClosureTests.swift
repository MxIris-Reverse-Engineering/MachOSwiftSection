import Foundation
@_spi(Support) import MachOKit
import MachOKitExtensions
import Testing
@testable import MachODependencies
import MachOFixtureSupport

/// Where the archived-cache-gated suite below finds its cache. A separate
/// type on purpose: a `@Suite(.enabled(if:))` condition that reads a static
/// of the suite it decorates is a circular macro reference.
enum ArchivedMacOS15CacheFixtures {
    static let cachePath = DyldSharedCachePath.macOS_15_5
    static let swiftUICoreInstallPath = "/System/Library/Frameworks/SwiftUICore.framework/Versions/A/SwiftUICore"
    static let foundationInstallPath = "/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation"
    static var hasCache: Bool { FileManager.default.fileExists(atPath: cachePath.rawValue) }
}

/// An image read out of a dyld shared cache is linked against the images of
/// that cache: dyld resolves its dependencies there and nowhere else. The
/// closure used to look only through the search paths it was handed, whose
/// default is the running system's cache, so an image of an archived macOS
/// 15.5 cache was laid out against the host's Foundation — where `URL` has a
/// different size.
@Suite(.enabled(if: ArchivedMacOS15CacheFixtures.hasCache))
struct CacheRootDependencyClosureTests {
    /// How the caller opened the cache the root is read from.
    enum CacheOpening: String, CaseIterable, CustomTestStringConvertible {
        /// The cache and its sub-caches, as `swift-section --dyld-shared-cache` opens it.
        case fullCache
        /// The main cache file alone.
        case mainCacheFile

        var testDescription: String { rawValue }

        func swiftUICore() throws -> MachOFile {
            let path = ArchivedMacOS15CacheFixtures.cachePath
            let image: MachOFile? = switch self {
            case .fullCache: try FullDyldCache(path: path).machOFile(by: .path(ArchivedMacOS15CacheFixtures.swiftUICoreInstallPath))
            case .mainCacheFile: try DyldCache(path: path).machOFile(by: .path(ArchivedMacOS15CacheFixtures.swiftUICoreInstallPath))
            }
            return try #require(image, "the macOS 15.5 cache has no SwiftUICore")
        }
    }

    private static func uuid(of image: MachOFile) -> UUID? {
        image.loadCommands.info(of: LoadCommand.uuid)?.uuid
    }

    @Test("A cache image's dependencies come from its own cache, not the host's", arguments: CacheOpening.allCases)
    func dependenciesComeFromTheRootsOwnCache(opening: CacheOpening) throws {
        let archivedCache = try FullDyldCache(path: ArchivedMacOS15CacheFixtures.cachePath)
        let archivedFoundation = try #require(archivedCache.machOFile(by: .path(ArchivedMacOS15CacheFixtures.foundationInstallPath)))
        let archivedFoundationUUID = try #require(Self.uuid(of: archivedFoundation))
        // The premise: the host's Foundation is another build, so a closure
        // that resolved there would be told apart.
        let hostCache = try #require(FullDyldCache.cachedHost, "no host dyld shared cache")
        let hostFoundation = try #require(hostCache.machOFile(by: .path(ArchivedMacOS15CacheFixtures.foundationInstallPath)))
        try #require(Self.uuid(of: hostFoundation) != archivedFoundationUUID)

        let root = try opening.swiftUICore()
        let closure = DependencyClosure(root: root, traversal: .direct)
        let foundation = try #require(closure.images.first { $0.imagePath == ArchivedMacOS15CacheFixtures.foundationInstallPath })
        #expect(Self.uuid(of: foundation) == archivedFoundationUUID)
    }

    /// The root's own cache is searched as the instance the root was read
    /// from: a fresh opening maps every file of the cache again.
    @Test("The root's cache is searched without being opened again")
    func rootCacheIsNotOpenedAgain() throws {
        let root = try CacheOpening.fullCache.swiftUICore()
        let rootCache = try #require(root._cachedFullCache)
        let closure = DependencyClosure(
            root: root,
            searchPaths: [.dyldSharedCache(path: ArchivedMacOS15CacheFixtures.cachePath.rawValue), .systemDyldSharedCache],
            traversal: .direct
        )
        let foundation = try #require(closure.images.first { $0.imagePath == ArchivedMacOS15CacheFixtures.foundationInstallPath })
        #expect(foundation._cachedFullCache === rootCache)
    }
}
