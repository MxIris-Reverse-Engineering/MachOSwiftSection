import Foundation
import MachOKit
import FileIO
import AssociatedObject

extension DyldCache {
    @AssociatedObject(.retain(.nonatomic))
    private var _fileHandle: FileHandle?

    var fileHandle: FileHandle {
        if let _fileHandle {
            return _fileHandle
        } else {
            let fileHandle = try! FileHandle(forReadingFrom: url)
            _fileHandle = fileHandle
            return fileHandle
        }
    }

    @AssociatedObject(.retain(.nonatomic))
    private var _fileIO: MemoryMappedFile?

    var fileIO: MemoryMappedFile {
        if let _fileIO {
            return _fileIO
        } else {
            let fileIO = try! MemoryMappedFile.open(url: url, isWritable: false)
            _fileIO = fileIO
            return fileIO
        }
    }

    
}
