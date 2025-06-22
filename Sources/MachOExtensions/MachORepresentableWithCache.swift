import MachOKit

package protocol MachORepresentableWithCache: MachORepresentable {
    associatedtype Cache: DyldCacheRepresentable

    var cache: Cache? { get }
    var startOffset: Int { get }
}

extension MachOFile: MachORepresentableWithCache {
    package var startOffset: Int {
        if let cache {
            headerStartOffsetInCache + cache.fileStartOffset.cast()
        } else {
            headerStartOffset
        }
    }
}

extension MachOImage: MachORepresentableWithCache {
    package var cache: DyldCacheLoaded? {
        guard let currentCache = DyldCacheLoaded.current else { return nil }

        if ptr.int - currentCache.mainCacheHeader.sharedRegionStart.cast() >= 0 {
            return currentCache
        }
        return nil
    }

    package var startOffset: Int {
        if let cache {
            return cache.mainCacheHeader.sharedRegionStart.cast()
        } else {
            return 0
        }
    }
}

package func address<MachO: MachORepresentableWithCache>(of fileOffset: Int, in machO: MachO) -> UInt64 {
    if let cache = machO.cache {
        return .init(cache.mainCacheHeader.sharedRegionStart.cast() + fileOffset)
    } else {
        return .init(0x100000000 + fileOffset)
    }
}

package func addressString<MachO: MachORepresentableWithCache>(of fileOffset: Int, in machO: MachO) -> String {
    return .init(address(of: fileOffset, in: machO), radix: 16, uppercase: true)
}
