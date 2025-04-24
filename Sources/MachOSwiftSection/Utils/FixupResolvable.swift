import Foundation
@_spi(Support) import MachOKit

public protocol _FixupResolvable {
    associatedtype LayoutField

    var offset: Int { get }

    func layoutOffset(of field: LayoutField) -> Int
}

extension _FixupResolvable {
    @_spi(Core)
    public func resolveRebase(
        _ field: LayoutField,
        in machO: MachOFile
    ) -> UInt64? {
        let offset = self.offset + layoutOffset(of: field)
        return resolveRebase(fileOffset: offset, in: machO)
    }

    @_spi(Core)
    public func resolveBind(
        _ field: LayoutField,
        in machO: MachOFile
    ) -> String? {
        let offset = self.offset + layoutOffset(of: field)
        return resolveBind(fileOffset: offset, in: machO)
    }

    @_spi(Core)
    public func isBind(
        _ field: LayoutField,
        in machO: MachOFile
    ) -> Bool {
        let offset = self.offset + layoutOffset(of: field)
        return isBind(fileOffset: offset, in: machO)
    }
}

#if false
extension _FixupResolvable where Self: LayoutWrapper {
    @_spi(Core)
    public func resolveRebase(
        _ keyPath: PartialKeyPath<Layout>,
        in machO: MachOFile
    ) -> UInt64? {
        let offset = self.offset + layoutOffset(of: keyPath)
        return resolveRebase(fileOffset: offset, in: machO)
    }

    @_spi(Core)
    public func resolveBind(
        _ keyPath: PartialKeyPath<Layout>,
        in machO: MachOFile
    ) -> String? {
        let offset = self.offset + layoutOffset(of: keyPath)
        return resolveBind(fileOffset: offset, in: machO)
    }

    @_spi(Core)
    public func isBind(
        _ keyPath: PartialKeyPath<Layout>,
        in machO: MachOFile
    ) -> Bool {
        let offset = self.offset + layoutOffset(of: keyPath)
        return isBind(fileOffset: offset, in: machO)
    }
}
#endif

extension _FixupResolvable {
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
    @_spi(Core)
    public func resolveRebase(
        fileOffset: Int,
        in machO: MachOFile
    ) -> UInt64? {
        let offset: UInt64 = numericCast(fileOffset)
        if let (cache, _offset) = resolveCacheStartOffsetIfNeeded(offset: offset, in: machO),
           let resolved = cache.resolveOptionalRebase(at: _offset) {
            return resolved - cache.mainCacheHeader.sharedRegionStart
        }

        if machO.cache != nil {
            return nil
        }

        if let resolved = machO.resolveOptionalRebase(at: offset) {
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
    @_spi(Core)
    public func resolveBind(
        fileOffset: Int,
        in machO: MachOFile
    ) -> String? {
        guard !machO.isLoadedFromDyldCache else { return nil }
        guard let fixup = machO.dyldChainedFixups else { return nil }

        let offset: UInt64 = numericCast(fileOffset)

        if let resolved = machO.resolveBind(at: offset) {
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
    @_spi(Core)
    public func isBind(
        fileOffset: Int,
        in machO: MachOFile
    ) -> Bool {
        guard !machO.isLoadedFromDyldCache else { return false }
        let offset: UInt64 = numericCast(fileOffset)
        return machO.isBind(numericCast(offset))
    }
}

extension _FixupResolvable {
    func resolveCacheStartOffsetIfNeeded(
        offset: UInt64,
        in machO: MachOFile
    ) -> (DyldCache, UInt64)? {
        if let (cache, _offset) = machO.cacheAndFileOffset(
            fromStart: offset
        ) {
            return (cache, _offset)
        }
        return nil
    }
}
