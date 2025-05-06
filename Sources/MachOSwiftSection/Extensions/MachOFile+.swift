import Foundation
import MachOKit

extension MachOFile {
    var fileHandle: FileHandle {
        try! .init(forReadingFrom: url)
    }
}

extension MachOFile {
    var cache: DyldCache? {
        guard isLoadedFromDyldCache else { return nil }
        guard let cache = try? DyldCache(url: url) else {
            return nil
        }
        if let mainCache = cache.mainCache {
            return try? .init(
                subcacheUrl: cache.url,
                mainCacheHeader: mainCache.header
            )
        }
        return cache
    }

    func cache(for address: UInt64) -> DyldCache? {
        cacheAndFileOffset(for: address)?.0
    }

    /// Convert an address that is not slided into the actual cache it contains and the file offset in it.
    /// - Parameter address: address (unslid)
    /// - Returns: cache and file offset
    func cacheAndFileOffset(for address: UInt64) -> (DyldCache, UInt64)? {
        guard let cache else { return nil }
        if let offset = cache.fileOffset(of: address) {
            return (cache, offset)
        }
        guard let mainCache = cache.mainCache else {
            return nil
        }

        if let offset = mainCache.fileOffset(of: address) {
            return (mainCache, offset)
        }

        guard let subCaches = mainCache.subCaches else {
            return nil
        }
        for subCache in subCaches {
            guard let cache = try? subCache.subcache(for: mainCache) else {
                continue
            }
            if let offset = cache.fileOffset(of: address) {
                return (cache, offset)
            }
        }
        return nil
    }

    /// Converts the offset from the start of the main cache to the actual cache
    /// it contains and the file offset within that cache.
    /// - Parameter offset: Offset from the start of the main cache.
    /// - Returns: cache and file offset
    func cacheAndFileOffset(fromStart offset: UInt64) -> (DyldCache, UInt64)? {
        guard let cache else { return nil }
        return cacheAndFileOffset(
            for: cache.mainCacheHeader.sharedRegionStart + offset
        )
    }
}

extension MachOFile {
    func isBind(
        _ offset: Int
    ) -> Bool {
        resolveBind(at: numericCast(offset)) != nil
    }

    func resolveBind<Pointer: RelativePointer>(at offset: Int, for pointer: Pointer) throws -> (DyldChainedImport, addend: UInt64)? {
//        try (resolveBind(at: pointer.resolveDirectFileOffset(from: offset).cast()) ?? resolveBind(at: pointer.resolveIndirectableFileOffset(from: offset, in: self).cast()))
        resolveBind(at: pointer.resolveDirectFileOffset(from: offset).cast())
    }
}

extension MachOFile {
    func readElement<Element>(
        offset: Int,
        swapHandler: ((inout Data) -> Void)? = nil
    ) throws -> Element where Element: LocatableLayoutWrapper {
        let layout: Element.Layout = try fileHandle.read(offset: numericCast(offset + headerStartOffset), swapHandler: swapHandler)
        return .init(layout: layout, offset: offset)
    }

    func readElements<Element>(
        offset: Int,
        numberOfElements: Int,
        swapHandler: ((inout Data) -> Void)? = nil
    ) throws -> [Element] where Element: LocatableLayoutWrapper {
        var currentOffset = offset
        let elements = try fileHandle.readDataSequence(offset: numericCast(offset + headerStartOffset), numberOfElements: numberOfElements, swapHandler: swapHandler).map { (layout: Element.Layout) -> Element in
            let element = Element(layout: layout, offset: currentOffset)
            currentOffset += Element.layoutSize
            return element
        }
        return elements
    }
}
