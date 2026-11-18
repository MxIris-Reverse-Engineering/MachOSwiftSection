@_spi(Internals) import MachOCaches

/// The eviction groups of this module's per-image caches.
extension SharedCacheEvictionGroup {
    /// `SwiftSymbolIndexStore`: the image's symbol table and node arena.
    package static let swiftSymbolStore = SharedCacheEvictionGroup("swiftSymbolStore")

    /// `InternedNodeReferenceCache`: the image's interned name arena.
    package static let internedNames = SharedCacheEvictionGroup("internedNames")
}
