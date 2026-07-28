import Foundation
import FoundationToolbox
import MachOKit

extension DyldCache {
    package var fileStartOffset: UInt64 {
        numericCast(
            header.sharedRegionStart - mainCacheHeader.sharedRegionStart
        )
    }
}

package enum DyldCacheImageSearchMode {
    case name(String)
    case path(String)
}

extension DyldCacheImageSearchMode {
    /// Best (lowest) rank an image path can score, i.e. "this is certainly the
    /// image the caller meant". Reaching it lets the search stop early.
    package static let bestMatchRank = 0

    /// Path component naming the macOS support root that holds the Mac
    /// Catalyst build of an iOS framework. Everything under it is
    /// framework-shaped and shares its leaf name with the native framework.
    /// Typed as `Substring` to match the split path components it is compared
    /// against, so the lookup needs no per-call bridging.
    private static let catalystSupportRootDirectoryName: Substring = "iOSSupport"

    /// How well `imagePath` satisfies this search mode — lower is better,
    /// `nil` means "not a match at all".
    ///
    /// Ranking exists because **leaf names are not unique inside a shared
    /// cache**. iOS 27 ships both
    /// `/System/Library/Frameworks/SwiftUI.framework/SwiftUI` and
    /// `/System/Library/AccessibilityBundles/SwiftUI.axbundle/SwiftUI`, so a
    /// first-match-wins name lookup silently resolved to whichever the cache
    /// happened to enumerate first. On the simulator caches that is the
    /// accessibility bundle, which carries no Swift metadata — `swift-section
    /// --dyld-shared-cache -n SwiftUI` produced an empty dump and still exited
    /// zero. Preferring the canonical framework binary makes the choice
    /// deterministic and correct; `.path` lookups are exact and always score
    /// `bestMatchRank`, so their behavior is unchanged.
    package func matchRank(forImagePath imagePath: String) -> Int? {
        switch self {
        case .path(let path):
            return imagePath == path ? Self.bestMatchRank : nil
        case .name(let name):
            let leafName = imagePath.lastPathComponent
            guard leafName.deletingPathExtension == name else { return nil }
            // The canonical framework binary lives inside a `<name>.framework`
            // directory — directly (iOS: `SwiftUI.framework/SwiftUI`) or under a
            // version directory (macOS: `SwiftUI.framework/Versions/A/SwiftUI`).
            let enclosingDirectories = imagePath.split(separator: "/").dropLast()
            if enclosingDirectories.contains("\(name).framework") {
                // A macOS cache also carries the Mac Catalyst build of the same
                // framework under `/System/iOSSupport`, framework-shaped and
                // with the same leaf name — 74 frameworks collide this way on
                // macOS 26 (SwiftUI, ARKit, AVKit, GameKit, HealthKit, …).
                // Both are real dylibs so neither can be rejected, but `-n
                // <name>` means the native one; ranking the support root just
                // below it stops the answer from depending on which cache file
                // the enumeration happened to reach first.
                return enclosingDirectories.contains(Self.catalystSupportRootDirectoryName) ? 1 : Self.bestMatchRank
            }
            // A plain dylib is still a real library, just not framework-shaped.
            if leafName.hasSuffix(".dylib") {
                return 2
            }
            // Anything else wearing the same leaf name: bundles (`.axbundle`,
            // `.bundle`, `.appex`, …) and other non-library payloads.
            return 3
        }
    }
}

extension DyldCacheImageSearchMode {
    /// Running best match while a search walks one or more caches.
    fileprivate typealias RankedMatch = (rank: Int, machOFile: MachOFile)

    /// Folds `machOFiles` into `rankedMatch`, returning `true` once an image
    /// scores `bestMatchRank` — nothing later can beat it, so the caller can
    /// stop. Ties keep the earliest image, so the result stays deterministic.
    fileprivate func accumulateBestMatch(in machOFiles: some Sequence<MachOFile>, into rankedMatch: inout RankedMatch?) -> Bool {
        for machOFile in machOFiles {
            guard let rank = matchRank(forImagePath: machOFile.imagePath) else { continue }
            guard rank < (rankedMatch?.rank ?? Int.max) else { continue }
            rankedMatch = (rank, machOFile)
            if rank == Self.bestMatchRank {
                return true
            }
        }
        return false
    }

    /// The best-ranked image of `machOFiles`, or `nil` when none matches.
    fileprivate func bestMatch(in machOFiles: some Sequence<MachOFile>) -> MachOFile? {
        var rankedMatch: RankedMatch?
        _ = accumulateBestMatch(in: machOFiles, into: &rankedMatch)
        return rankedMatch?.machOFile
    }
}

extension DyldCache {
    package func machOFile(by mode: DyldCacheImageSearchMode) -> MachOFile? {
        // `machOFiles()` only yields the images mapped in *this* cache file, so
        // a split cache spreads same-leaf-name images across several of them —
        // the SwiftUI accessibility bundle can sit in the file scanned first
        // while the canonical framework binary sits in a subcache. Ranking has
        // to span every cache file before choosing, otherwise a low-ranked hit
        // here shadows the framework binary over there and reproduces the very
        // empty-dump-with-exit-zero bug the ranking was introduced to fix.
        // Only a `bestMatchRank` hit is allowed to stop the scan early.
        var rankedMatch: DyldCacheImageSearchMode.RankedMatch?

        // Each cache file is scanned at most once. `mainCache` returns `self`
        // when `self` *is* the main cache, and the sub-cache array lists the
        // file the caller opened directly whenever that file is a sub-cache —
        // without this both would be enumerated twice, and a name that never
        // reaches `bestMatchRank` (a plain `.dylib`) pays for the whole
        // duplicated walk before returning.
        var scannedCacheURLs: Set<URL> = []

        func scanReachedBestMatch(in cache: DyldCache) -> Bool {
            guard scannedCacheURLs.insert(cache.url).inserted else { return false }
            return mode.accumulateBestMatch(in: cache.machOFiles(), into: &rankedMatch)
        }

        if scanReachedBestMatch(in: self) {
            return rankedMatch?.machOFile
        }

        guard let mainCache else { return rankedMatch?.machOFile }

        if scanReachedBestMatch(in: mainCache) {
            return rankedMatch?.machOFile
        }

        // The sub-cache array lives in the *main* cache header only: a
        // sub-cache header reports a count of zero. Reading `self.subCaches`
        // therefore found nothing whenever the caller opened a sub-cache
        // directly (`--dyld-shared-cache …/dyld_shared_cache_arm64e.03`),
        // silently skipping every sibling — so an image mapped in another
        // sub-cache came back `nil`, or lost to a worse-ranked namesake.
        if let subCaches = mainCache.subCaches {
            for subCacheEntry in subCaches {
                guard let subCache = try? subCacheEntry.subcache(for: mainCache) else { continue }
                if scanReachedBestMatch(in: subCache) {
                    return rankedMatch?.machOFile
                }
            }
        }
        return rankedMatch?.machOFile
    }
}

extension FullDyldCache {
    package func machOFile(by mode: DyldCacheImageSearchMode) -> MachOFile? {
        mode.bestMatch(in: machOFiles())
    }
}
