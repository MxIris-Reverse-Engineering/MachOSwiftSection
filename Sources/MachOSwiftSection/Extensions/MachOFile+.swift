import Foundation
import MachOKit
import FileIO

extension MachOFile {
    var fileHandle: FileHandle {
        try! .init(forReadingFrom: url)
    }
    
    var fileIO: MemoryMappedFile {
        try! File.open(
            url: url,
            isWritable: false
        )
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

    func resolveBind<Pointer: RelativePointerProtocol>(at offset: Int, for pointer: Pointer) throws -> (DyldChainedImport, addend: UInt64)? {
//        try (resolveBind(at: pointer.resolveDirectFileOffset(from: offset).cast()) ?? resolveBind(at: pointer.resolveIndirectableFileOffset(from: offset, in: self).cast()))
        resolveBind(at: pointer.resolveDirectFileOffset(from: offset).cast())
    }
}

extension MachOFile {
    func readElement<Element>(
        offset: Int,
        swapHandler: ((inout Data) -> Void)? = nil
    ) throws -> Element {
        var offset = offset
        var fileHandle = fileIO
        if let cacheAndFileOffset = cacheAndFileOffset(fromStart: offset.cast()) {
            offset = cacheAndFileOffset.1.cast()
//            fileHandle = cacheAndFileOffset.0.fileHandle
        }
        return try fileHandle.machO.read(offset: numericCast(offset + effectiveHeaderStartOffset), swapHandler: swapHandler)
    }

    func readElement<Element>(
        offset: Int,
        swapHandler: ((inout Data) -> Void)? = nil
    ) throws -> Element where Element: LocatableLayoutWrapper {
//        var offset = offset
//        var fileHandle = fileHandle
//        if let cache {
//            offset = cache.fileOffset(of: numericCast(offset + cache.mainCacheHeader.sharedRegionStart.cast()))?.cast() ?? offset
//            fileHandle = cacheAndFileOffset.0.fileHandle
//        }
        var offset = offset
        var fileHandle = fileIO
        if let cacheAndFileOffset = cacheAndFileOffset(fromStart: offset.cast()) {
            offset = cacheAndFileOffset.1.cast()
//            fileHandle = cacheAndFileOffset.0.fileHandle
        }
        let layout: Element.Layout = try fileHandle.machO.read(offset: numericCast(offset + effectiveHeaderStartOffset), swapHandler: swapHandler)
        return .init(layout: layout, offset: offset)
    }

    func readElements<Element>(
        offset: Int,
        numberOfElements: Int,
        swapHandler: ((inout Data) -> Void)? = nil
    ) throws -> [Element] {
        var offset = offset
        var fileHandle = fileIO
        if let cacheAndFileOffset = cacheAndFileOffset(fromStart: offset.cast()) {
            offset = cacheAndFileOffset.1.cast()
//            fileHandle = cacheAndFileOffset.0.fileHandle
        }
        var currentOffset = offset
        let elements = try fileHandle.machO.readDataSequence(offset: numericCast(offset + effectiveHeaderStartOffset), numberOfElements: numberOfElements, swapHandler: swapHandler).map { (element: Element) -> Element in
            currentOffset += MemoryLayout<Element>.size
            return element
        }
        return elements
    }
    
    func readElements<Element>(
        offset: Int,
        numberOfElements: Int,
        swapHandler: ((inout Data) -> Void)? = nil
    ) throws -> [Element] where Element: LocatableLayoutWrapper {
        var offset = offset
        var fileHandle = fileIO
        if let cacheAndFileOffset = cacheAndFileOffset(fromStart: offset.cast()) {
            offset = cacheAndFileOffset.1.cast()
//            fileHandle = cacheAndFileOffset.0.fileHandle
        }
        var currentOffset = offset
        let elements = try fileHandle.machO.readDataSequence(offset: numericCast(offset + effectiveHeaderStartOffset), numberOfElements: numberOfElements, swapHandler: swapHandler).map { (layout: Element.Layout) -> Element in
            let element = Element(layout: layout, offset: currentOffset)
            currentOffset += Element.layoutSize
            return element
        }
        return elements
    }

    func readString(offset: Int) throws -> String? {
        var offset = offset
        var fileHandle = fileIO
        if let cacheAndFileOffset = cacheAndFileOffset(fromStart: offset.cast()) {
            offset = cacheAndFileOffset.1.cast()
//            fileHandle = cacheAndFileOffset.0.fileHandle
        }
        return fileHandle.machO.readString(offset: numericCast(offset + effectiveHeaderStartOffset))
    }

    var effectiveHeaderStartOffset: Int {
//        cache != nil ? headerStartOffsetInCache : headerStartOffset
        headerStartOffset
    }

    var sharedCacheRegionStart: Int {
        cache.map { .init($0.mainCacheHeader.sharedRegionStart) } ?? 0
    }
}


extension MachOFile {
    /// Resolves the rebase operation at the specified file offset within the given MachO file.
    ///
    /// This function determines if the rebase operation can be resolved from the provided file offset
    /// in the MachO file. If the MachO file is loaded from a Dyld shared cache, the rebase is resolved
    /// using the cache information. Otherwise, it directly resolves the rebase using the MachO file.
    ///
    /// - Parameters:
    ///   - fileOffset: The offset in the file where the rebase operation occurs.
    ///   - machO: The `MachOFile` object representing the MachO file to resolve rebases from.
    /// - Returns: The resolved rebase value as a `UInt64`, or `nil` if the rebase cannot be resolved.
    
    func resolveRebase(fileOffset: Int) -> UInt64? {
        let offset: UInt64 = numericCast(fileOffset)
        if let (cache, _offset) = resolveCacheStartOffsetIfNeeded(offset: offset),
           let resolved = cache.resolveOptionalRebase(at: _offset) {
            return resolved - cache.mainCacheHeader.sharedRegionStart
        }

        if cache != nil {
            return nil
        }

        if let resolved = resolveOptionalRebase(at: offset) {
            return resolved
        }
        return nil
    }

    /// Resolves the bind operation at the specified file offset within the given MachO file.
    ///
    /// This function determines if the bind operation can be resolved from the provided file offset
    /// in the MachO file. Bind operations are used to dynamically link symbols at runtime.
    ///
    /// The function checks the following conditions:
    /// 1. The MachO file must not be loaded from the Dyld shared cache. If it is, the method returns `nil`.
    /// 2. The MachO file must contain `dyldChainedFixups` data. If not available, the method returns `nil`.
    ///
    /// If these conditions are satisfied, the method attempts to resolve the bind operation at the given offset
    /// and retrieves the associated symbol name.
    ///
    /// - Parameters:
    ///   - fileOffset: An `Int` value representing the offset in the file where the bind operation occurs.
    ///   - machO: The `MachOFile` object representing the MachO file to analyze.
    /// - Returns: The resolved symbol name as a `String`, or `nil` if the bind operation cannot be resolved.

    func resolveBind(fileOffset: Int) -> String? {
        guard !isLoadedFromDyldCache else { return nil }
        guard let fixup = dyldChainedFixups else { return nil }

        let offset: UInt64 = numericCast(fileOffset)

        if let resolved = resolveBind(at: offset) {
            return fixup.symbolName(for: resolved.0.info.nameOffset)
        }
        return nil
    }

    /// Determines whether the specified file offset within the MachO file represents a bind operation.
    ///
    /// This function evaluates if the file offset corresponds to a bind operation. Bind operations
    /// are used in MachO files to dynamically link symbols at runtime.
    ///
    /// The function operates as follows:
    /// 1. Checks if the MachO file is loaded from the Dyld shared cache. If so, returns `false` as
    ///    bind operations cannot be evaluated in this context.
    /// 2. Converts the file offset to a `UInt64` value to ensure compatibility with MachOKit APIs.
    /// 3. Invokes `machO.isBind(_:)` to determine if the specified offset corresponds to a bind operation.
    ///
    /// - Parameters:
    ///   - fileOffset: The offset in the MachO file to check for a bind operation.
    ///   - machO: The `MachOFile` instance representing the file being analyzed.
    /// - Returns: A `Bool` indicating whether the specified offset represents a bind operation.
    
    func isBind(fileOffset: Int) -> Bool {
        guard !isLoadedFromDyldCache else { return false }
        let offset: UInt64 = numericCast(fileOffset)
        return isBind(numericCast(offset))
    }
}

extension MachOFile {
    func resolveCacheStartOffsetIfNeeded(
        offset: UInt64) -> (DyldCache, UInt64)? {
        if let (cache, _offset) = cacheAndFileOffset(
            fromStart: offset
        ) {
            return (cache, _offset)
        }
        return nil
    }
}
