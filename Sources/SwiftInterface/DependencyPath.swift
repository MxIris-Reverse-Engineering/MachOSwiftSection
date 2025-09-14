/// Represents different paths for loading dependencies when building Swift interfaces.
/// This enum is only available on macOS as it deals with Mach-O binaries and dyld caches.
@available(iOS, unavailable)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
@available(visionOS, unavailable)
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
}
