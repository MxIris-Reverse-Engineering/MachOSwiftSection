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
    /// The best-ranked image of `machOFiles`, or `nil` when none matches.
    ///
    /// Stops at the first `bestMatchRank` hit, so the common case (an exact
    /// path, or a name whose framework binary is present) costs no more than
    /// the previous first-match-wins scan. Ties keep the earliest image, so the
    /// result stays deterministic for a given cache.
    fileprivate func bestMatch(in machOFiles: some Sequence<MachOFile>) -> MachOFile? {
        var bestMatch: (rank: Int, machOFile: MachOFile)?
        for machOFile in machOFiles {
            guard let rank = matchRank(forImagePath: machOFile.imagePath) else { continue }
            if rank == Self.bestMatchRank {
                return machOFile
            }
            if rank < (bestMatch?.rank ?? Int.max) {
                bestMatch = (rank, machOFile)
            }
        }
        return bestMatch?.machOFile
    }
}

extension DyldCache {
    package func machOFile(by mode: DyldCacheImageSearchMode) -> MachOFile? {
        if let found = mode.bestMatch(in: machOFiles()) {
            return found
        }

        guard let mainCache else { return nil }

        if let found = mode.bestMatch(in: mainCache.machOFiles()) {
            return found
        }

        if let subCaches {
            for subCacheEntry in subCaches {
                if let subCache = try? subCacheEntry.subcache(for: mainCache), let found = mode.bestMatch(in: subCache.machOFiles()) {
                    return found
                }
            }
        }
        return nil
    }
}

extension FullDyldCache {
    package func machOFile(by mode: DyldCacheImageSearchMode) -> MachOFile? {
        mode.bestMatch(in: machOFiles())
    }
}
