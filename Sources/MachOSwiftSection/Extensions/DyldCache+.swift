import Foundation
import MachOKit

extension DyldCache {
    var fileHandle: FileHandle {
        try! .init(forReadingFrom: url)
    }

    var fileStartOffset: UInt64 {
        numericCast(
            header.sharedRegionStart - mainCacheHeader.sharedRegionStart
        )
    }
}

extension DyldCache {
    var mainCache: DyldCache? {
        if url.lastPathComponent.contains(".") {
            var url = url
            url.deletePathExtension()
            return try? .init(url: url)
        } else {
            return self
        }
    }
}
