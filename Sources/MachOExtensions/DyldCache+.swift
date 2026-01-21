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

extension DyldCache {
    package func machOFile(by mode: DyldCacheImageSearchMode) -> MachOFile? {
        if let found = machOFiles().first(where: { $0.match(by: mode) }) {
            return found
        }

        guard let mainCache else { return nil }

        if let found = mainCache.machOFiles().first(where: { $0.match(by: mode) }) {
            return found
        }

        if let subCaches {
            for subCacheEntry in subCaches {
                if let subCache = try? subCacheEntry.subcache(for: mainCache), let found = subCache.machOFiles().first(where: { $0.match(by: mode) }) {
                    return found
                }
            }
        }
        return nil
    }
}

extension FullDyldCache {
    package func machOFile(by mode: DyldCacheImageSearchMode) -> MachOFile? {
        if let found = machOFiles().first(where: { $0.match(by: mode) }) {
            return found
        }

        return nil
    }
}

extension MachOFile {
    fileprivate func match(by mode: DyldCacheImageSearchMode) -> Bool {
        switch mode {
        case .name(let name):
            return imagePath.lastPathComponent.deletingPathExtension == name
        case .path(let path):
            return imagePath == path
        }
    }
}
