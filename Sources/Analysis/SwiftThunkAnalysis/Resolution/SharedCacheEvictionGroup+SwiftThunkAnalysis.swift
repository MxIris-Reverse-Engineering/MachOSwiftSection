@_spi(Internals) import MachOCaches

/// The eviction group of this module's per-image caches.
extension SharedCacheEvictionGroup {
    /// `MetadataAccessorIndex`, `DependencyImageResolver`, `CacheImageResolver`
    /// and the image's own runtime symbols `MachOThunkEnvironment` names call
    /// targets by: the thunk reader's per-root accessor index, dependency
    /// image handles, cache image table and symbol table extract.
    package static let thunkResolution = SharedCacheEvictionGroup("thunkResolution")
}
