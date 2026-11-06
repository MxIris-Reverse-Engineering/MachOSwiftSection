import Foundation
import MachOKit

/// One opening of each dyld shared cache file that dependency locators search
/// by path, shared by every locator for as long as anything still holds it.
///
/// Each consumer of a dependency closure builds a locator for every root, and
/// a cache named by a `.dyldSharedCache(path:)` search path used to be opened
/// by each of them, all of its files mapped again with a descriptor apiece:
/// DockHelper paired with an archived macOS 27.0 cache held 369 descriptors on
/// that cache's 80 files in one `interface` run.
///
/// An opening is held weakly. The images a locator hands out keep their cache,
/// and through it the opening, alive; once none is left it closes, so a run
/// over dozens of caches keeps only the ones still in use open. Openings are
/// keyed by the file's identity — device, inode, size and modification time —
/// so a cache file replaced on disk is opened afresh.
///
/// `FullDyldCache` fills in its mapping tables and symbol cache on first use,
/// without a lock. They are read before an opening is handed out, so every
/// later reader only reads them: what `FullDyldCache.cachedHost` does for the
/// running system's cache.
enum SharedDyldCacheOpenings {
    /// The opening of the dyld shared cache whose main file is at `url`, made
    /// on the first request while no other is alive. Throws what opening the
    /// cache throws.
    static func cache(at url: URL) throws -> FullDyldCache {
        try registry.cache(at: url)
    }

    private static let registry = Registry()

    private struct FileIdentity: Hashable {
        let device: Int32
        let inode: UInt64
        let size: Int64
        let modificationSeconds: Int
        let modificationNanoseconds: Int

        /// `nil` when the file cannot be examined; opening it then reports why.
        init?(fileAt url: URL) {
            var status = stat()
            guard stat(url.path, &status) == 0 else { return nil }
            device = status.st_dev
            inode = status.st_ino
            size = status.st_size
            modificationSeconds = status.st_mtimespec.tv_sec
            modificationNanoseconds = status.st_mtimespec.tv_nsec
        }
    }

    private final class Registry: @unchecked Sendable {
        /// One per cache file, created under the registry's lock and filled in
        /// under its own, so a cache being opened holds up only the requests
        /// for that cache — the arrangement of `DyldCacheImageDirectory`'s
        /// registry.
        private final class Slot: @unchecked Sendable {
            let lock = NSLock()
            weak var cache: FullDyldCache?
        }

        private let lock = NSLock()
        private var slotsByFileIdentity: [FileIdentity: Slot] = [:]

        func cache(at url: URL) throws -> FullDyldCache {
            guard let fileIdentity = FileIdentity(fileAt: url) else {
                return try FullDyldCache(url: url)
            }
            lock.lock()
            let slot: Slot
            if let existingSlot = slotsByFileIdentity[fileIdentity] {
                slot = existingSlot
            } else {
                slot = Slot()
                slotsByFileIdentity[fileIdentity] = slot
            }
            lock.unlock()

            slot.lock.lock()
            defer { slot.lock.unlock() }
            if let cache = slot.cache {
                return cache
            }
            let cache = try FullDyldCache(url: url)
            _ = cache.mappingInfos
            _ = cache.mappingAndSlideInfos
            _ = try? cache.symbolCache
            slot.cache = cache
            return cache
        }
    }
}
