import MachOKit

#if !canImport(Darwin)
extension DyldCacheLoaded {
    // FIXME: fallback for linux
    package static var current: DyldCacheLoaded? {
        return nil
    }
}
#endif
