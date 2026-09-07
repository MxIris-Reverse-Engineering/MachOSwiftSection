import Foundation

/// Where an offline (`MachOFile`) dependency locator may look for a dependency
/// binary. Cache-resident system frameworks (the stdlib, Foundation, the rest
/// of the OS) resolve through a dyld shared cache; anything else — a sibling
/// framework reached through `@rpath`, a test helper next to the root binary —
/// has to be handed over as an explicit file, because `@rpath` /
/// `@loader_path` / `@executable_path` are not expanded.
public enum DependencySearchPath: Sendable, Hashable, CustomStringConvertible {
    /// An explicit on-disk path to a Mach-O (or fat) binary file.
    case machOFile(path: String)
    /// An explicit path to a dyld shared cache file.
    case dyldSharedCache(path: String)
    /// The running system's active dyld shared cache.
    case systemDyldSharedCache

    public var description: String {
        switch self {
        case .machOFile(let path):
            return "machOFile(\(path))"
        case .dyldSharedCache(let path):
            return "dyldSharedCache(\(path))"
        case .systemDyldSharedCache:
            return "systemDyldSharedCache"
        }
    }
}

/// Why a search path contributed nothing. Recorded on the closure rather than
/// thrown: one unusable search path must not fail the whole resolution, and
/// this module sits below the event layer, so the host decides where the
/// degradation is reported.
public enum DependencySearchPathError: Error, Sendable, Equatable {
    /// The file loaded but yielded no Mach-O slice.
    case noMachOSlice(path: String)
    /// `FullDyldCache.host` returned `nil` — the platform exposes no shared
    /// cache file to this process.
    case systemDyldSharedCacheUnavailable
}

/// A search path that could not be opened, paired with the reason.
public struct DependencySearchPathLoadFailure: Sendable {
    public let searchPath: DependencySearchPath
    public let error: any Error

    public init(searchPath: DependencySearchPath, error: any Error) {
        self.searchPath = searchPath
        self.error = error
    }
}
