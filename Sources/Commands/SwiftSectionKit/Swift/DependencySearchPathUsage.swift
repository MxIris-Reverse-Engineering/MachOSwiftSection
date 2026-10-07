import MachODependencies
import SwiftDeclarationRendering

/// Runs `operation` with `searchPaths` in force for every kind-9 accessor-thunk
/// rewrite it performs, or unchanged when none were named. The task-local is
/// the one injection point the rendering layer offers.
nonisolated(nonsending) func withAccessorThunkResolver<Result>(
    searchPaths: [DependencySearchPath],
    _ operation: nonisolated(nonsending) () async throws -> Result
) async rethrows -> Result {
    guard !searchPaths.isEmpty else { return try await operation() }
    return try await AccessorThunkResolution.$taskResolver.withValue(
        DisassemblingAccessorThunkResolver(searchPaths: searchPaths),
        operation: operation
    )
}

extension Array where Element == DependencySearchPath {
    /// How the static (offline) layout engine resolves cross-module types: the
    /// named paths first, the running system's shared cache as the fallback,
    /// so that a binary is laid out against the OS whose cache was named
    /// rather than the host's. With no path named, the library default.
    var staticLayoutDependencyResolution: StaticLayoutDependencyResolution {
        guard !isEmpty else { return .default }
        return .dependencyClosure(searchPaths: self + [.systemDyldSharedCache])
    }

    /// The same paths for the indexer's cross-image facts (a stored field
    /// whose type is a property wrapper from another image; a class's ObjC
    /// ancestors behind a bind): the named ones first, the running system's
    /// cache as the fallback.
    var indexingSearchPaths: [DependencySearchPath] {
        self + [.systemDyldSharedCache]
    }
}
