import Foundation
import MachOKit
import MachOExtensions
import MachOSwiftSection

/// Where the `MachOFile` dependency-closure factory may locate a dependency
/// binary. Mirrors the resolution strategies used elsewhere in the package, but
/// kept local so `SwiftLayout` does not depend on the higher-level
/// `SwiftInterface` module that defines the analogous `DependencyPath`.
public enum LayoutDependencySearchPath: Sendable, Equatable, Hashable {
    /// An explicit on-disk path to a Mach-O (or fat) binary file. Used for
    /// non-cache dependencies such as a sibling framework reached through
    /// `@rpath` (the MVP does not expand `@rpath` itself).
    case machOFile(path: String)
    /// An explicit path to a dyld shared cache file.
    case dyldSharedCache(path: String)
    /// The system's active dyld shared cache (covers stdlib / Foundation /
    /// Distributed and the rest of the OS frameworks).
    case systemDyldSharedCache
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
        let collectedDependencies = transitiveDependencies(of: root) { bareName in
            MachOImage(name: bareName)
        }
        return try dependencyClosure(root: root, dependencyImages: collectedDependencies)
    }
}

// MARK: - Offline closure (MachOFile)

extension ImageUniverse where MachO == MachOFile {
    /// Builds an offline dependency closure for a file-backed image. Each
    /// dependency is located by its bare name through the supplied search paths
    /// (explicit on-disk files first, then the dyld shared cache), recursively,
    /// deduped by bare name. Dependencies that cannot be located are skipped.
    ///
    /// `@rpath` / `@loader_path` / `@executable_path` are not expanded in this
    /// MVP: a non-cache dependency must be reachable through an explicit
    /// `.machOFile(path:)` entry. Cache-resident system frameworks resolve by
    /// bare name automatically.
    public static func dependencyClosure(
        root: MachOFile,
        searchPaths: [LayoutDependencySearchPath] = [.systemDyldSharedCache]
    ) throws -> ImageUniverse<MachOFile> {
        let locator = try MachOFileDependencyLocator(searchPaths: searchPaths)
        let collectedDependencies = transitiveDependencies(of: root) { bareName in
            locator.locate(bareName: bareName)
        }
        return try dependencyClosure(root: root, dependencyImages: collectedDependencies)
    }
}

/// Collects the transitive dependency closure of `root` in breadth-first order
/// (direct dependencies first, then their dependencies, …), deduped by bare
/// image name, using `locate` to turn each `LC_LOAD_DYLIB` bare name into a
/// concrete image. Breadth-first ordering matters because the universe indexes
/// dependencies lazily in this order: the binary's own direct Swift
/// dependencies — the ones most field types resolve against — come first.
private func transitiveDependencies<MachO: MachORepresentableWithCache>(
    of root: MachO,
    locate: (String) -> MachO?
) -> [MachO] {
    var visitedBareNames: Set<String> = [bareImageName(fromDependencyLoadName: root.imagePath)]
    var collected: [MachO] = []
    var frontier: [MachO] = [root]

    while !frontier.isEmpty {
        var nextFrontier: [MachO] = []
        for image in frontier {
            for dependencyLoadName in image.dependencies.map(\.dylib.name) {
                let bareName = bareImageName(fromDependencyLoadName: dependencyLoadName)
                guard !bareName.isEmpty, visitedBareNames.insert(bareName).inserted else { continue }
                guard let dependencyImage = locate(bareName) else { continue }
                collected.append(dependencyImage)
                nextFrontier.append(dependencyImage)
            }
        }
        frontier = nextFrontier
    }
    return collected
}

/// Locates dependency `MachOFile`s by bare name across a set of search paths.
/// Explicit on-disk files are indexed eagerly by bare name (keyed by the
/// supplied path's bare name, since a file's `imagePath` is its install name,
/// not its on-disk path). Each dyld shared cache is indexed lazily by bare name
/// the first time a cache lookup is needed — one full pass over the cache,
/// rather than a fresh per-lookup scan (which would be `O(dependencies × cache
/// size)`).
private final class MachOFileDependencyLocator {
    private let explicitFilesByBareName: [String: MachOFile]
    private let caches: [FullDyldCache]
    private var cacheFilesByBareName: [String: MachOFile]?

    init(searchPaths: [LayoutDependencySearchPath]) throws {
        var explicitFilesByBareName: [String: MachOFile] = [:]
        var caches: [FullDyldCache] = []
        for searchPath in searchPaths {
            switch searchPath {
            case .machOFile(let path):
                guard let machOFile = try? File.loadFromFile(url: URL(fileURLWithPath: path)).machOFiles.first else { continue }
                // Key by the supplied path's bare name: `machOFile.imagePath`
                // resolves to the install name (`@rpath/Foo.framework/.../Foo`),
                // whose bare name matches a dependent's load name anyway.
                let bareName = bareImageName(fromDependencyLoadName: path)
                if explicitFilesByBareName[bareName] == nil {
                    explicitFilesByBareName[bareName] = machOFile
                }
            case .dyldSharedCache(let path):
                if let cache = try? FullDyldCache(url: URL(fileURLWithPath: path)) {
                    caches.append(cache)
                }
            case .systemDyldSharedCache:
                if let hostCache = FullDyldCache.host {
                    caches.append(hostCache)
                }
            }
        }
        self.explicitFilesByBareName = explicitFilesByBareName
        self.caches = caches
    }

    func locate(bareName: String) -> MachOFile? {
        if let explicit = explicitFilesByBareName[bareName] {
            return explicit
        }
        guard !caches.isEmpty else { return nil }
        return cacheIndex()[bareName]
    }

    /// Builds (once) and returns the bare-name → cache image index across every
    /// configured cache, first writer wins.
    private func cacheIndex() -> [String: MachOFile] {
        if let cacheFilesByBareName { return cacheFilesByBareName }
        var index: [String: MachOFile] = [:]
        for cache in caches {
            for machOFile in cache.machOFiles() {
                let bareName = bareImageName(fromDependencyLoadName: machOFile.imagePath)
                if !bareName.isEmpty, index[bareName] == nil {
                    index[bareName] = machOFile
                }
            }
        }
        cacheFilesByBareName = index
        return index
    }
}

/// Reduces a dylib load name (`@rpath/Foo.framework/Versions/A/Foo`,
/// `/usr/lib/swift/libswiftDistributed.dylib`, a bare module name) to the bare
/// image name `MachOImage(name:)` and the dyld-cache `.name` matcher use — the
/// last path component with its first extension component stripped.
func bareImageName(fromDependencyLoadName dependencyLoadName: String) -> String {
    let lastPathComponent = dependencyLoadName.components(separatedBy: "/").last ?? dependencyLoadName
    return lastPathComponent.components(separatedBy: ".").first ?? lastPathComponent
}
