import Foundation
import MachOKit
import FileIO

extension DyldCache {
    var fileHandle: FileHandle {
        try! .init(forReadingFrom: url)
    }
    
    var fileIO: MemoryMappedFile {
        try! .open(url: url, isWritable: false)
    }

    package var fileStartOffset: UInt64 {
        numericCast(
            header.sharedRegionStart - mainCacheHeader.sharedRegionStart
        )
    }
}
