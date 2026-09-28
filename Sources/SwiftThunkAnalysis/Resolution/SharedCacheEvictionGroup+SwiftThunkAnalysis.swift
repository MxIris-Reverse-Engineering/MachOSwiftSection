@_spi(Internals) import MachOCaches

/// The eviction group of this module's per-image caches.
extension SharedCacheEvictionGroup {
    /// `MetadataAccessorIndex` and `DependencyImageResolver`: the thunk
    /// reader's per-root accessor index and dependency image handles.
    package static let thunkResolution = SharedCacheEvictionGroup("thunkResolution")
}
