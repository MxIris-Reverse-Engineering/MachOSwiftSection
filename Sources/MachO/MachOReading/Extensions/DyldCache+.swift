import Foundation
import MachOKit
import FileIO
import AssociatedObject
import FoundationToolbox

extension DyldCache {
    /// The lock a cache file's handle and mapping are created under. One
    /// `DyldCache` is read by many readers at once: a `FullDyldCache` hands
    /// the same sub-cache instances to every image read from it, and the
    /// host's cache (`FullDyldCache.cachedHost`) is opened once per process —
    /// so `diff` and `evolution`, preparing their inputs concurrently, make
    /// the first read of a sub-cache from several roots together. Created
    /// unlocked, each racing reader mapped the file again and stored its own
    /// mapping over the others', and a reader holding a replaced one
    /// unretained (the association is non-atomic) could read through a file
    /// already unmapped. Created under this lock, each is stored once and
    /// never replaced, so every later read takes it without the lock.
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
