@_spi(Internals) import MachOCaches

/// The eviction group of this module's per-image cache. It points into no
/// other group's storage, so it follows none.
extension SharedCacheEvictionGroup {
    /// `ImageReference.shared(for:)`: each image's layout indexes, shared by
    /// every universe that folds the image in.
    package static let layoutImageIndexes = SharedCacheEvictionGroup("layoutImageIndexes")
}
