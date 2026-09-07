import MachODependencies

/// Superseded by `MachODependencies.DependencySearchPath`, which every
/// dependency-resolving feature now shares (evolution proposal
/// macho-dependencies-module). Kept one release for source
/// compatibility; the case spellings differ, so this is a conversion rather
/// than a typealias.
@available(*, deprecated, message: "Use DependencySearchPath (MachODependencies); convert with `searchPath`.")
public enum DependencyPath: CustomStringConvertible {
    /// A path to a specific Mach-O binary file
    case machO(String)
    /// A path to a dyld shared cache file
    case dyldSharedCache(String)
    /// Use the system's default dyld shared cache
    case usesSystemDyldSharedCache

    public var description: String {
        switch self {
        case .machO(let path):
            return "machO(\(path))"
        case .dyldSharedCache(let path):
            return "dyldSharedCache(\(path))"
        case .usesSystemDyldSharedCache:
            return "usesSystemDyldSharedCache"
        }
    }

    /// The equivalent shared search path.
    public var searchPath: DependencySearchPath {
        switch self {
        case .machO(let path):
            return .machOFile(path: path)
        case .dyldSharedCache(let path):
            return .dyldSharedCache(path: path)
        case .usesSystemDyldSharedCache:
            return .systemDyldSharedCache
        }
    }
}
