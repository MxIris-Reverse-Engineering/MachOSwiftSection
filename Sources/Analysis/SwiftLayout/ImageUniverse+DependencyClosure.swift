import MachOKit
import MachODependencies
import MachOSwiftSection
import MachOFoundation

/// The search-path enum moved down to `MachODependencies` so every feature
/// resolves dependencies the same way (evolution proposal
/// macho-dependencies-module). Kept one release for source
/// compatibility; the cases are spelled identically.
@available(*, deprecated, renamed: "DependencySearchPath")
public typealias LayoutDependencySearchPath = DependencySearchPath

extension ImageUniverse {
    /// Builds a universe over an already-resolved `DependencyClosure` — the
    /// entry point for a host that resolves the closure once and shares it with
    /// other consumers (interface generation, `__C` attribution). The closure's
    /// resolution order is preserved: the universe indexes dependencies lazily
    /// in exactly that order and stops at the first hit, which is why the
    /// closure walks breadth-first.
    public static func dependencyClosure(_ closure: DependencyClosure<MachO>) throws -> ImageUniverse<MachO> {
        try dependencyClosure(root: closure.root, dependencyImages: closure.images)
    }
}

// MARK: - In-process closure (MachOImage)

extension ImageUniverse where MachO == MachOImage {
    /// Builds a dependency closure for an in-process image by recursively
    /// resolving every `LC_LOAD_DYLIB` through the active dyld. System
    /// frameworks resolve from the shared cache automatically; locally-loaded
    /// frameworks (reached via `@rpath`) resolve too, as long as they are
    /// already mapped into this process. Dependencies that cannot be located
    /// are skipped — their types simply degrade per field rather than failing
    /// the whole closure.
    public static func dependencyClosure(root: MachOImage) throws -> ImageUniverse<MachOImage> {
        try dependencyClosure(DependencyClosure(root: root, traversal: .transitive))
    }
}

// MARK: - Offline closure (MachOFile)

extension ImageUniverse where MachO == MachOFile {
    /// Builds an offline dependency closure for a file-backed image. Each
    /// dependency is located through the supplied search paths (explicit
    /// on-disk files, then the dyld shared caches — exact install path first,
    /// ranked bare-name match second; see `FileDependencyLocator`),
    /// recursively, deduped by bare name. Dependencies that cannot be located
    /// are skipped.
    ///
    /// `@rpath` / `@loader_path` / `@executable_path` are not expanded: a
    /// non-cache dependency must be reachable through an explicit
    /// `.machOFile(path:)` entry. Cache-resident system frameworks resolve
    /// automatically.
    public static func dependencyClosure(
        root: MachOFile,
        searchPaths: [DependencySearchPath] = [.systemDyldSharedCache]
    ) throws -> ImageUniverse<MachOFile> {
        try dependencyClosure(DependencyClosure(root: root, searchPaths: searchPaths, traversal: .transitive))
    }
}
