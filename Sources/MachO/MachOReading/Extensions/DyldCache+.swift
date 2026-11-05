import Foundation
@_spi(Support) import MachOKit
import FileIO

extension DyldCache {
    /// The mapping this cache file is read through, shared with every other
    /// reader of the same opening of the file (``SharedFileMapping``): the
    /// images in it, and the other instances MachOKit assembles for it.
    var fileIO: MemoryMappedFile {
        get throws {
            try SharedFileMapping.mapping(of: fileHandleIdentity, at: url)
        }
    }
}
