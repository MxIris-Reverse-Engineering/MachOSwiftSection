import Foundation
import MachOKit
import MachOKitExtensions

/// The images of one dyld shared cache as `FileDependencyLocator` looks them
/// up — each one's install path, bare name and rank under that name, the
/// platforms it was built for, and the unslid address of its header — read
/// once per process and shared by every locator that searches the cache.
///
/// A locator is built per root, and before it the first lookup of every
/// locator walked all of the cache's images (about 3,500 in a macOS 27
/// cache), making a `MachOFile` of each and reading its platforms.
/// RuntimeViewer builds a dependency closure, and so a locator, for every
/// offline interface it prints with a layout comment on.
///
/// The directory holds no `MachOFile` and no cache: a `MachOFile` fills in
/// some of its state lazily without a lock (the cache it belongs to, among
/// others) and its reads share one file handle, so an instance is never
/// handed to two locators. Each locator makes its own, through
/// ``machOFile(of:in:)`` and its own opening of the cache, for the images
/// it locates and no others. What is shared is plain data, immutable once
/// built; the per-platform lookup tables are filled in under a lock.
///
/// Keyed by the cache's main file — its standardized path, symbolic links
/// resolved — and the main header's UUID, so a cache replaced on disk while
/// the process runs is read again. Entries are kept for the process's
/// lifetime: a few hundred kilobytes per cache, and they hold nothing open.
final class DyldCacheImageDirectory: @unchecked Sendable {
    struct Image: Sendable {
        let installPath: String
        let bareImageName: String
        /// `DyldCacheImageSearchMode.matchRank(forImagePath:)` under the bare
        /// name; ``unrankedShapeRank`` for a shape that rule does not know.
        let bareNameRank: Int
        let platforms: Set<Platform>
        /// The unslid address of the image's Mach-O header, which names the
        /// image in every opening of the cache.
        let headerAddress: UInt64
    }

    /// The images a root of given platforms may take, as two lookup tables
    /// into ``images``.
    struct Lookup: Sendable {
        /// The first compatible image, in cache order, under each install path.
        let imageIndicesByInstallPath: [String: Int]
        /// The best-ranked compatible image under each bare name, the earlier
        /// one winning a tie.
        let bestImagesByBareName: [String: (rank: Int, imageIndex: Int)]
    }

    /// Rank given to an image whose path the `DyldCacheImageSearchMode` name
    /// rule does not recognize under its bare name (a multi-dotted leaf such
    /// as `libc++.1.dylib`, whose `deletingPathExtension` form is not the bare
    /// name). It still resolves — every image under a bare name legitimately
    /// carries it — it just loses to any recognized shape.
    static let unrankedShapeRank = Int.max

    /// In the cache's own image order.
    let images: [Image]

    private let lookupsLock = NSLock()
    private var lookupsByRootPlatforms: [Set<Platform>: Lookup] = [:]

    private init(images: [Image]) {
        self.images = images
    }

    /// The lookup tables for a root built for `rootPlatforms`, made once per
    /// platform set from ``images`` with `DependencyPlatforms.areCompatible`.
    func lookup(forRootPlatforms rootPlatforms: Set<Platform>) -> Lookup {
        lookupsLock.lock()
        defer { lookupsLock.unlock() }
        if let lookup = lookupsByRootPlatforms[rootPlatforms] {
            return lookup
        }
        var imageIndicesByInstallPath: [String: Int] = [:]
        var bestImagesByBareName: [String: (rank: Int, imageIndex: Int)] = [:]
        for (imageIndex, image) in images.enumerated() {
            guard DependencyPlatforms.areCompatible(rootPlatforms, image.platforms) else { continue }
            if imageIndicesByInstallPath[image.installPath] == nil {
                imageIndicesByInstallPath[image.installPath] = imageIndex
            }
            guard !image.bareImageName.isEmpty else { continue }
            if let existing = bestImagesByBareName[image.bareImageName], existing.rank <= image.bareNameRank {
                continue
            }
            bestImagesByBareName[image.bareImageName] = (image.bareNameRank, imageIndex)
        }
        let lookup = Lookup(imageIndicesByInstallPath: imageIndicesByInstallPath, bestImagesByBareName: bestImagesByBareName)
        lookupsByRootPlatforms[rootPlatforms] = lookup
        return lookup
    }

    /// A new `MachOFile` for `image`, read through `cache` — an opening of
    /// the cache this directory was read from. Made the way
    /// `FullDyldCache.machOFiles()` makes it: the cache file holding the
    /// header, the header's offset in that file, and the image's path.
    static func machOFile(of image: Image, in cache: FullDyldCache) -> MachOFile? {
        machOFile(headerAddress: image.headerAddress, imagePath: image.installPath, in: cache)
    }

    private static func machOFile(headerAddress: UInt64, imagePath: String, in cache: FullDyldCache) -> MachOFile? {
        guard let (cacheFile, fileOffset) = cache.cacheAndFileOffset(for: headerAddress) else {
            return nil
        }
        return try? MachOFile(
            url: cacheFile.url,
            imagePath: imagePath,
            headerStartOffsetInCache: numericCast(fileOffset),
            cache: cacheFile
        )
    }

    // MARK: - Process-wide registry

    /// The directory of `cache`, read from it on the first request for that
    /// cache in this process. Concurrent first requests for one cache wait
    /// for a single read; requests for different caches do not wait for each
    /// other.
    static func directory(of cache: FullDyldCache) -> DyldCacheImageDirectory {
        registry.directory(of: cache)
    }

    private static let registry = Registry()

    private struct CacheIdentity: Hashable {
        let mainCacheFilePath: String
        let mainCacheUUID: UUID

        init(_ cache: FullDyldCache) {
            mainCacheFilePath = cache.url.standardizedFileURL.resolvingSymlinksInPath().path
            mainCacheUUID = cache.header.uuid
        }
    }

    private final class Registry: @unchecked Sendable {
        /// One per cache, created under the registry's lock and filled in
        /// under its own, so a cache being read holds up only the requests
        /// for that cache.
        private final class Slot: @unchecked Sendable {
            let lock = NSLock()
            var directory: DyldCacheImageDirectory?
        }

        private let lock = NSLock()
        private var slotsByCacheIdentity: [CacheIdentity: Slot] = [:]

        func directory(of cache: FullDyldCache) -> DyldCacheImageDirectory {
            let cacheIdentity = CacheIdentity(cache)
            lock.lock()
            let slot: Slot
            if let existingSlot = slotsByCacheIdentity[cacheIdentity] {
                slot = existingSlot
            } else {
                slot = Slot()
                slotsByCacheIdentity[cacheIdentity] = slot
            }
            lock.unlock()

            slot.lock.lock()
            defer { slot.lock.unlock() }
            if let directory = slot.directory {
                return directory
            }
            let directory = DyldCacheImageDirectory(images: DyldCacheImageDirectory.readImages(of: cache))
            slot.directory = directory
            return directory
        }
    }

    /// Every image of `cache` in its own order, with the same skips as
    /// `FullDyldCache.machOFiles()`: an image without a mapped header or a
    /// path, or whose header does not read as a Mach-O.
    private static func readImages(of cache: FullDyldCache) -> [Image] {
        guard let imageInfos = cache.imageInfos else { return [] }
        var images: [Image] = []
        for imageInfo in imageInfos {
            guard let imagePath = imageInfo.path(in: cache) else { continue }
            guard let machOFile = machOFile(headerAddress: imageInfo.address, imagePath: imagePath, in: cache) else { continue }
            let installPath = machOFile.imagePath
            let bareImageName = DependencyLoadName.bareImageName(of: installPath)
            let bareNameRank = bareImageName.isEmpty
                ? unrankedShapeRank
                : DyldCacheImageSearchMode.name(bareImageName).matchRank(forImagePath: installPath) ?? unrankedShapeRank
            images.append(Image(
                installPath: installPath,
                bareImageName: bareImageName,
                bareNameRank: bareNameRank,
                platforms: DependencyPlatforms.platforms(of: machOFile),
                headerAddress: imageInfo.address
            ))
        }
        return images
    }
}
