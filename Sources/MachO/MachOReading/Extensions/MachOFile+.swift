import Foundation
@_spi(Support) import MachOKit
import FileIO

extension MachOFile {
    /// The mapping this file is read through, shared with every other reader
    /// of the same opening of the file (``SharedFileMapping``): an image read
    /// out of a dyld cache shares its cache file's.
    var fileIO: MemoryMappedFile {
        get throws {
            try SharedFileMapping.mapping(of: fileHandleIdentity, at: url)
        }
    }
}
