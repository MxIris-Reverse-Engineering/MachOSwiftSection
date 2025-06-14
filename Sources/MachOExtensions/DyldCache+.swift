import Foundation
import MachOKit

extension DyldCache {
    package var fileStartOffset: UInt64 {
        numericCast(
            header.sharedRegionStart - mainCacheHeader.sharedRegionStart
        )
    }
}

extension DyldCache {
    package enum ImageSearchMode {
        case name(String)
        case path(String)
    }

    package func machOFile(by mode: ImageSearchMode) -> MachOFile? {
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

extension MachOFile {
    fileprivate func match(by mode: DyldCache.ImageSearchMode) -> Bool {
        switch mode {
        case let .name(name):
            return imagePath.nsString.lastPathComponent.nsString.deletingPathExtension == name
        case let .path(path):
            return imagePath == path
        }
    }
}

extension String {
    fileprivate var nsString: NSString {
        return self as NSString
    }
}
