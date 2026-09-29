@_spi(Internals) import MachOCaches

/// The eviction groups of this module's per-image caches. None of them
/// points into another group's storage, so none follows one.
extension SharedCacheEvictionGroup {
    /// `PropertyWrapperTypeCatalogStore`.
    package static let propertyWrapperCatalog = SharedCacheEvictionGroup("propertyWrapperCatalog")

    /// `MultiPayloadEnumDescriptorCache`.
    package static let multiPayloadEnumDescriptors = SharedCacheEvictionGroup("multiPayloadEnumDescriptors")

    /// `DependentMemberProjection`: the root's dependency-closure universes.
    package static let dependentMemberProjection = SharedCacheEvictionGroup("dependentMemberProjection")
}
