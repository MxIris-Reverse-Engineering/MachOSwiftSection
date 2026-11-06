import Foundation

/// The identity of a file a dependency locator opens: device, inode, size and
/// modification time.
///
/// The openings locators share by path are keyed by it, so a file replaced on
/// disk is opened afresh rather than served from an opening of the old one,
/// and two paths that reach one file share an opening.
struct DependencyFileIdentity: Hashable {
    let device: Int32
    let inode: UInt64
    let size: Int64
    let modificationSeconds: Int
    let modificationNanoseconds: Int

    /// `nil` when the file cannot be examined; opening it then reports why.
    init?(fileAt url: URL) {
        var status = stat()
        guard stat(url.path, &status) == 0 else { return nil }
        device = status.st_dev
        inode = status.st_ino
        size = status.st_size
        modificationSeconds = status.st_mtimespec.tv_sec
        modificationNanoseconds = status.st_mtimespec.tv_nsec
    }
}
