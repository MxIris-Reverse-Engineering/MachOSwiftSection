import Foundation

/// The family a per-image cache belongs to, for eviction.
///
/// An image's cached state is dropped per family rather than per cache:
/// the declaration indexer claims, when it prepares an image, every family
/// that has no finished entry for that image yet — those are the ones its
/// preparation is about to build — and the image's last live indexer evicts
/// what was claimed (``SharedCacheRegistry``). ``dependents`` folds in the
/// families whose entries point into a claimed one, so an eviction never
/// leaves behind a reference that pins what it just dropped.
///
/// Every ``SharedCache`` names its family at creation and is registered
/// under it; a family with no cache registered is claimed and evicted like
/// any other, which is harmless.
@_spi(Internals)
public enum SharedCacheEvictionGroup: Hashable, CaseIterable, Sendable {
    /// `SymbolIndexStore`: the image's symbol table and node arena.
    case symbolStore
    /// `SymbolicManglingIndex`: holds the symbol store's symbolic-mangling
    /// table.
    case symbolicMangling
    /// `ObjCImplementationClassIndex`: holds `NodeReference`s into the
    /// symbol store's arena.
    case objcImplementationClasses
    /// `ObjCClassMethodIndex`, `SwiftClassObjectIndex` and the host's
    /// `ObjCClassHierarchyProviderStore` registration.
    case objcHierarchy
    /// `ObjCAncestorResolverStore`: holds the file's dependency images once
    /// it has resolved them.
    case objcAncestorResolver
    /// `InternedNodeReferenceCache`: the image's interned name arena.
    case internedNames
    /// `SymbolicDemanglerCache` and `AnonymousContextPrivateDiscriminatorIndex`:
    /// references into the interned arena, and the per-image state the same
    /// demanglings read.
    case demangleMemo
    /// `PropertyWrapperTypeCatalogStore`.
    case propertyWrapperCatalog
    /// `MultiPayloadEnumDescriptorCache`.
    case multiPayloadEnumDescriptors
    /// `DependentMemberProjection`: the root's dependency-closure universes.
    case dependentMemberProjection
    /// `MetadataAccessorIndex` and `DependencyImageResolver`: the thunk
    /// reader's per-root accessor index and dependency image handles.
    case thunkResolution

    /// The families evicted together with `self` when `self` is claimed.
    ///
    /// - `symbolStore` takes `symbolicMangling` (it holds the store's
    ///   symbolic-mangling table), `objcImplementationClasses` (it holds
    ///   references into the store's arena), and the ObjC-side state of the
    ///   same lifetime (`objcHierarchy`, `objcAncestorResolver`).
    /// - `internedNames` takes `demangleMemo`: the memo's values are
    ///   references into the interned arena, and a surviving reference keeps
    ///   that arena's buffers alive, so dropping the arena while keeping the
    ///   memo frees nothing at all. One-way on purpose: dropping the memo does
    ///   not require dropping the arena.
    ///
    /// Before the registry, these relationships were spread over the
    /// indexer's `deinit` and three `removeCache` helpers; a comment
    /// explaining why the memo must follow the arena once outlived the code
    /// that made it true.
    public var dependents: Set<SharedCacheEvictionGroup> {
        switch self {
        case .symbolStore:
            [.symbolicMangling, .objcImplementationClasses, .objcHierarchy, .objcAncestorResolver]
        case .internedNames:
            [.demangleMemo]
        case .symbolicMangling, .objcImplementationClasses, .objcHierarchy, .objcAncestorResolver, .demangleMemo, .propertyWrapperCatalog, .multiPayloadEnumDescriptors, .dependentMemberProjection, .thunkResolution:
            []
        }
    }
}
