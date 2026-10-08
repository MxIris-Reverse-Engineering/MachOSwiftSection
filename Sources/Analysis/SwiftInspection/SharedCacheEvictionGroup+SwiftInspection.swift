@_spi(Internals) import MachOCaches

/// The eviction groups of this module's per-image caches. Which of them
/// follow another group is declared where the cache is created — by the
/// cache that holds the reference.
extension SharedCacheEvictionGroup {
    /// `SymbolicManglingIndex`: holds the symbol store's symbolic-mangling
    /// table, so it follows `symbolStore`.
    package static let symbolicMangling = SharedCacheEvictionGroup("symbolicMangling")

    /// `ObjCImplementationClassIndex`: holds `NodeReference`s into the
    /// symbol store's arena, so it follows `symbolStore`.
    package static let objcImplementationClasses = SharedCacheEvictionGroup("objcImplementationClasses")

    /// `ObjCClassMethodIndex`, `SwiftClassObjectIndex` and the host's
    /// `ObjCClassHierarchyProviderStore` registration: ObjC-side per-image
    /// state of the symbol store's lifetime, so it follows `symbolStore`.
    package static let objcHierarchy = SharedCacheEvictionGroup("objcHierarchy")

    /// `ObjCAncestorResolverStore`: holds the file's dependency images once
    /// it has resolved them; same lifetime, follows `symbolStore`.
    package static let objcAncestorResolver = SharedCacheEvictionGroup("objcAncestorResolver")

    /// `SymbolicDemanglerCache` and `AnonymousContextPrivateDiscriminatorIndex`:
    /// the memo's values are references into the interned arena, so the
    /// group follows `internedNames`.
    package static let demangleMemo = SharedCacheEvictionGroup("demangleMemo")
}
