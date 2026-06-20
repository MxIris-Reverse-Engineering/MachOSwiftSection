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
    /// A file-backed image keyed additionally by its `LC_BUILD_VERSION`
    /// (platform + SDK). The same install path can back *different* binaries — the
    /// SwiftUI image extracted from two dyld shared caches, or two simulator
    /// runtimes, all live at `/System/.../SwiftUI` — so keying on the path alone
    /// collides in `SharedCache`-backed per-image caches (the symbol index, …),
    /// letting the second-indexed binary read the first's data. The build version
    /// distinguishes the OS builds and keeps the keys apart.
    case versionedFile(path: String, platform: UInt32, sdk: UInt32)
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
        if let buildVersionCommand = loadCommands.buildVersionCommand {
            return .versionedFile(path: imagePath, platform: buildVersionCommand.layout.platform, sdk: buildVersionCommand.layout.sdk)
        }
        return .file(imagePath)
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
    public var imagePath: String {
        path ?? ""
    }

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

extension MachORepresentableWithCache {
    public func address(forOffset offset: Int) -> UInt64 {
        if let machOImage = asMachOImage, let cache = machOImage.cache, let slide = cache.slide {
            let startOffset = machOImage.ptr.bitPattern.int - slide
            return .init(startOffset + offset)
        } else if let cache {
            return .init(cache.mainCacheHeader.sharedRegionStart.cast() + offset)
        } else {
            return ((loadCommands.text64?.virtualMemoryAddress ?? loadCommands.text?.virtualMemoryAddress) ?? 0).uint64 + UInt64(offset)
        }
    }

    public func addressString(forOffset offset: Int) -> String {
        String(address(forOffset: offset), radix: 16, uppercase: true)
    }
}

extension MachORepresentable {
    package var asMachOImage: MachOImage? {
        self as? MachOImage
    }
}
