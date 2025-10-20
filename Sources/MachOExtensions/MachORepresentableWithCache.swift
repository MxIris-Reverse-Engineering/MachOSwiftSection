import MachOKit

public protocol MachORepresentableWithCache: MachORepresentable {
    associatedtype Cache: DyldCacheRepresentable
    associatedtype Identifier: Hashable

    var imagePath: String { get }
    var identifier: Identifier { get }
    var cache: Cache? { get }
    var startOffset: Int { get }
    func resolveOffset(at address: UInt64) -> Int
}

public enum MachOTargetIdentifier: Hashable {
    case image(UnsafeRawPointer)
    case file(String)
}

extension MachOFile {
    public func resolveOffset(at address: UInt64) -> Int {
        numericCast(fileOffset(of: address))
    }
}

extension MachOImage {
    public func resolveOffset(at address: UInt64) -> Int {
        Int(address) - ptr.int
    }
}

extension MachOFile: MachORepresentableWithCache {
    public var identifier: MachOTargetIdentifier {
        .file(imagePath)
    }

    public var startOffset: Int {
        if let cache {
            headerStartOffsetInCache + cache.fileStartOffset.cast()
        } else {
            headerStartOffset
        }
    }
}

extension MachOImage: MachORepresentableWithCache {
    
    public var imagePath: String { path ?? "" }
    
    public var identifier: MachOTargetIdentifier {
        .image(ptr)
    }

    public var cache: DyldCacheLoaded? {
        guard let currentCache = DyldCacheLoaded.current else { return nil }

        if ptr.int - currentCache.mainCacheHeader.sharedRegionStart.cast() >= 0 {
            return currentCache
        }
        return nil
    }

    public var startOffset: Int {
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
