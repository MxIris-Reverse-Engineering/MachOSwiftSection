import MachOKit

public protocol MachORepresentableWithCache: MachORepresentable, Sendable {
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
        if let offset = fileOffset(of: address) {
            return offset.cast()
        } else {
            return stripPointerTags(of: address).cast()
        }
    }
}

extension MachOImage {
    public func resolveOffset(at address: UInt64) -> Int {
        Int(stripPointerTags(of: address)) - ptr.bitPattern.int
    }
}

extension MachOFile: MachORepresentableWithCache, @unchecked @retroactive Sendable {
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

extension MachOImage: MachORepresentableWithCache, @unchecked @retroactive Sendable {
    public var imagePath: String { path ?? "" }

    public var identifier: MachOTargetIdentifier {
        .image(ptr)
    }

    public var cache: DyldCacheLoaded? {
        guard let currentCache = DyldCacheLoaded.current else { return nil }

        if ptr.bitPattern.int - currentCache.mainCacheHeader.sharedRegionStart.cast() >= 0 {
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
        return .init(0x1_0000_0000 + fileOffset)
    }
}

package func addressString<MachO: MachORepresentableWithCache>(of fileOffset: Int, in machO: MachO) -> String {
    return .init(address(of: fileOffset, in: machO), radix: 16, uppercase: true)
}


extension MachORepresentable {
    package var asMachOImage: MachOImage? {
        self as? MachOImage
    }
}
