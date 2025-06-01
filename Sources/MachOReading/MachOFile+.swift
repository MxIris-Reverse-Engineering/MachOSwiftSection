import Foundation
import MachOKit
import FileIO

extension MachOFile {
    package var fileHandle: FileHandle {
        try! .init(forReadingFrom: url)
    }

    package var fileIO: MemoryMappedFile {
        try! .open(
            url: url,
            isWritable: false
        )
    }
}
