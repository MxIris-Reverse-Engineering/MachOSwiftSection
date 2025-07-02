import Foundation
import MachOKit
import AssociatedObject

extension MachOFile {
    package var cache: DyldCache? {
        guard isLoadedFromDyldCache else { return nil }
        if let _cache {
            return _cache
        } else {
            guard let cache = try? DyldCache(url: url) else {
                return nil
            }
            var currentCache: DyldCache? = cache
            if let mainCache = cache.mainCache {
                currentCache = try? .init(
                    subcacheUrl: cache.url,
                    mainCacheHeader: mainCache.header
                )
            }
            _cache = currentCache
            return currentCache
        }
    }
    
    @AssociatedObject(.retain(.nonatomic))
    private var _cache: DyldCache?

    package func cache(for address: UInt64) -> DyldCache? {
        cacheAndFileOffset(for: address)?.0
    }

    /// Convert an address that is not slided into the actual cache it contains and the file offset in it.
    /// - Parameter address: address (unslid)
    /// - Returns: cache and file offset
    package func cacheAndFileOffset(for address: UInt64) -> (DyldCache, UInt64)? {
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
    package func cacheAndFileOffset(fromStart offset: UInt64) -> (DyldCache, UInt64)? {
        guard let cache else { return nil }
        return cacheAndFileOffset(
            for: cache.mainCacheHeader.sharedRegionStart + offset
        )
    }

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

    package func resolveRebase(fileOffset: Int) -> UInt64? {
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

    package func resolveBind(fileOffset: Int) -> String? {
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

    package func isBind(fileOffset: Int) -> Bool {
        guard !isLoadedFromDyldCache else { return false }
        let offset: UInt64 = numericCast(fileOffset)
        return isBind(numericCast(offset))
    }

    package func isBind(_ offset: Int) -> Bool {
        resolveBind(at: numericCast(offset)) != nil
    }

    package func resolveCacheStartOffsetIfNeeded(
        offset: UInt64) -> (DyldCache, UInt64)? {
        if let (cache, _offset) = cacheAndFileOffset(
            fromStart: offset
        ) {
            return (cache, _offset)
        }
        return nil
    }
}
