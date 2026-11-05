import Foundation
@_spi(Support) import MachOKit
import FileIO
import AssociatedObject
import FoundationToolbox

/// The one mapping of a file that every reader of it reads through.
///
/// A mapping is kept per opening of the file — MachOKit's identity of the
/// handle it was opened through (`fileHandleIdentity`) — not per reader.
/// MachOKit assembles many readers from one opening of a dyld cache: a
/// `DyldCache` for each image a `FullDyldCache` enumerates, MachOKitExtensions
/// one for each sub-cache an image's reads cross into, and a dependency locator
/// a `MachOFile` for each image it locates, all carrying the identity of the
/// cache file they read. Kept per reader, the file was mapped again for each of
/// them, and every mapping holds a descriptor: RuntimeViewer's offline service,
/// reading Dock.app against the system's cache, held 2,548 descriptors on 85
/// cache files when the next open failed with `EMFILE`.
///
/// The mapping hangs off the identity, which MachOKit releases together with
/// its handle, so it is unmapped with the last reader of that opening. It is
/// made under a lock and never replaced: readers racing on a file's first read
/// are all handed one mapping, and a reader can never hold one that another
/// replaced and unmapped. Every later read takes it without the lock.
enum SharedFileMapping {
    @Mutex
    private static var creation: Void = ()

    /// The association key: the address of a byte nothing else uses.
    nonisolated(unsafe) private static let associationKey = UnsafeRawPointer(UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1))

    /// The mapping of the file at `url` that the opening `identity` names,
    /// made on the first request.
    ///
    /// Throws what mapping the file throws — a file removed since it was
    /// opened, a process out of descriptors — which fails the read rather than
    /// the process.
    static func mapping(of identity: any FileHandleIdentity, at url: URL) throws -> MemoryMappedFile {
        if let mapping = getAssociatedObject(identity, associationKey) as? MemoryMappedFile {
            return mapping
        }
        return try _creation.withLockUnchecked { _ in
            if let mapping = getAssociatedObject(identity, associationKey) as? MemoryMappedFile {
                return mapping
            }
            let mapping = try MemoryMappedFile.open(url: url, isWritable: false)
            setAssociatedObject(identity, associationKey, mapping)
            return mapping
        }
    }
}
