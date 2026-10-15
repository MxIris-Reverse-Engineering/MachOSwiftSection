import Foundation
import MachOKit
import MachOKitExtensions
import FileIO
import AssociatedObject
import FoundationToolbox

extension MachOFile {
    /// The lock a file's handle and mapping are created under, the way
    /// `DyldCache`'s are. Created unlocked, readers racing to make a file's
    /// first read each opened it again and stored their own over the others',
    /// and a reader holding a replaced one unretained (the association is
    /// non-atomic) could read through a file already unmapped. Created under
    /// it, each is stored once and never replaced, so every later read takes
    /// it without the lock.
    @Mutex
    private static var fileAccessCreation: Void = ()

    @AssociatedObject(.retain(.nonatomic))
    private var _fileHandle: FileHandle?

    var fileHandle: FileHandle {
        if let _fileHandle {
            return _fileHandle
        }
        return Self._fileAccessCreation.withLockUnchecked { _ in
            if let _fileHandle {
                return _fileHandle
            }
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
        }
        return Self._fileAccessCreation.withLockUnchecked { _ in
            if let _fileIO {
                return _fileIO
            }
            let fileIO = try! MemoryMappedFile.open(url: url, isWritable: false)
            _fileIO = fileIO
            return fileIO
        }
    }
}
