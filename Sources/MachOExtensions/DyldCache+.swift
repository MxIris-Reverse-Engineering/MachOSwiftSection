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
                return Self.bestMatchRank
            }
            // A plain dylib is still a real library, just not framework-shaped.
            if leafName.hasSuffix(".dylib") {
                return 1
            }
            // Anything else wearing the same leaf name: bundles (`.axbundle`,
            // `.bundle`, `.appex`, …) and other non-library payloads.
            return 2
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

        if mode.accumulateBestMatch(in: machOFiles(), into: &rankedMatch) {
            return rankedMatch?.machOFile
        }

        guard let mainCache else { return rankedMatch?.machOFile }

        if mode.accumulateBestMatch(in: mainCache.machOFiles(), into: &rankedMatch) {
            return rankedMatch?.machOFile
        }

        if let subCaches {
            for subCacheEntry in subCaches {
                guard let subCache = try? subCacheEntry.subcache(for: mainCache) else { continue }
                if mode.accumulateBestMatch(in: subCache.machOFiles(), into: &rankedMatch) {
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
