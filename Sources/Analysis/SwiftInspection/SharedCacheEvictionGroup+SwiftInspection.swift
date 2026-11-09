@_spi(Internals) import MachOCaches

/// The eviction groups of this module's per-image caches. Which of them
/// follow another group is declared where the cache is created — by the
/// cache that holds the reference.
extension SharedCacheEvictionGroup {
    /// `SymbolicManglingIndex`: holds the symbol store's symbolic-mangling
    /// table, so it follows `symbolStore`.
    package static let symbolicMangling = SharedCacheEvictionGroup("symbolicMangling")

    /// `SymbolicDemanglerCache` and `AnonymousContextNameIndex`:
    /// the memo's values are references into the interned arena, so the
    /// group follows `internedNames`.
    package static let demangleMemo = SharedCacheEvictionGroup("demangleMemo")
}
