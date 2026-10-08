import Foundation
import MachOKit
import MachOFoundation
import MachOSwiftSection

/// Converts between the offsets `MachOSwiftSection` uses and the virtual
/// addresses a disassembler needs.
///
/// ## Why this type exists at all
///
/// For an image **inside a dyld shared cache** the offsets threaded through
/// `MachOSwiftSection` are not file offsets. `MachOFile.Swift`'s
/// `_sectionOffsetAndSize` establishes the convention:
///
/// ```swift
/// let offset = if let cache = machO.cache {
///     section.address - cache.mainCacheHeader.sharedRegionStart.cast()
/// } else {
///     section.offset
/// }
/// ```
///
/// so every descriptor offset, every relative-pointer target, and the offset a
/// kind-9 node carries are all `unslidVirtualAddress - sharedRegionStart`.
/// Converting is one subtraction.
///
/// Three other conversions look like they would work and do not. All were
/// measured against SwiftUI on the macOS 26 cache, and all fail *silently* —
/// they return a plausible address in the wrong place rather than `nil`:
///
/// | Used instead | What goes wrong |
/// |---|---|
/// | `segment.fileOffset` / `headerStartOffsetInCache` | subcache file offsets; differ from the above by a constant (557056 for SwiftUI), yielding an address still inside `__TEXT` but off by 0x88000 |
/// | `MachOFile.fileOffset(of:)` | file accounting, **not** the accounting `readElements(offset:)` takes — the two are not inverses here |
/// | `FullDyldCache.address(of:)` | a third accounting again (a further 16384 off) |
///
/// The damage is subtle because `adrp` computes its page base from the
/// instruction's own address: an error smaller than a page leaves the
/// candidate addresses *computable and wrong*, pointing into a neighbouring
/// image's segments. Measured symptom: SwiftUI's candidates appearing to live
/// in `TextRecognition`'s `__AUTH_CONST`.
package struct ThunkAddressSpace: Sendable {
    /// `sharedRegionStart` when the image lives in a shared cache; `nil` for a
    /// standalone file, where offsets are ordinary file offsets.
    private let sharedRegionStart: UInt64?

    /// File-offset → address mapping for the standalone case, and the
    /// address ranges the image spans for ``containsAddress(_:)``.
    private let segments: [(fileOffset: Int, fileSize: Int, virtualMemoryAddress: UInt64, virtualMemorySize: UInt64)]

    /// Where the image's mach header sits: the start of `__TEXT`.
    private let textSegmentAddress: UInt64?

    /// The addresses `__TEXT` spans — where code the evaluator may follow
    /// into lives.
    private let textSegmentRange: Range<UInt64>?

    package init(of machO: MachOFile) {
        if let cache = machO.cache {
            self.sharedRegionStart = numericCast(cache.mainCacheHeader.sharedRegionStart)
        } else {
            self.sharedRegionStart = nil
        }
        segments = machO.segments.map {
            (fileOffset: $0.fileOffset, fileSize: $0.fileSize, virtualMemoryAddress: UInt64($0.virtualMemoryAddress), virtualMemorySize: UInt64($0.virtualMemorySize))
        }
        let textSegment = machO.segments.first { $0.segmentName == "__TEXT" }
        textSegmentAddress = textSegment.map { UInt64($0.virtualMemoryAddress) }
        textSegmentRange = textSegment.map { UInt64($0.virtualMemoryAddress) ..< UInt64($0.virtualMemoryAddress) &+ UInt64($0.virtualMemorySize) }
    }

    /// Whether `address` lies in this image's `__TEXT` segment.
    package func isInTextSegment(_ address: UInt64) -> Bool {
        textSegmentRange?.contains(address) ?? false
    }

    /// Whether `address` lies in any of this image's segments.
    ///
    /// Not the same question as ``offset(forAddress:)`` answering: inside a
    /// shared cache that conversion is one subtraction and answers for
    /// EVERY address in the cache, another image's included — so a callee
    /// reached through a rebased pointer (libswiftSynchronization's `Mutex`
    /// accessor from SwiftUICore) has an offset here that means nothing to
    /// this image's indexes. This is the test that sends such an address to
    /// the cache's image table instead.
    package func containsAddress(_ address: UInt64) -> Bool {
        segments.contains { address >= $0.virtualMemoryAddress && address < $0.virtualMemoryAddress &+ $0.virtualMemorySize }
    }

    /// An `ExportedSymbol.offset` → address.
    ///
    /// The export trie stores each symbol as an offset **from the mach
    /// header**, and `MachOKit` hands that number over unchanged for a cache
    /// image — so it is NOT a file offset there, and mapping it through the
    /// segments' file ranges lands inside `__LINKEDIT` (measured:
    /// `libswiftCore`'s `_$sShMa`, header offset 4598948, "found" at
    /// 0x1FFD3E9A4 — a computable, plausible, wrong address 1.8 GB past the
    /// real one). The header is the first byte of `__TEXT`, so the address
    /// is `__TEXT`'s plus the offset, which is also right for a standalone
    /// dylib (`__TEXT` at 0) and an executable (`__TEXT` at 0x100000000).
    package func address(forExportedSymbolOffset offset: Int) -> UInt64? {
        textSegmentAddress.map { $0 &+ UInt64(offset) }
    }

    package func address(forOffset offset: Int) -> UInt64? {
        if let sharedRegionStart {
            return UInt64(offset) &+ sharedRegionStart
        }
        for segment in segments where offset >= segment.fileOffset && offset < segment.fileOffset + segment.fileSize {
            return segment.virtualMemoryAddress &+ UInt64(offset - segment.fileOffset)
        }
        return nil
    }

    /// A `MachOFile` symbol table entry's value (`Symbol.offset`) → address,
    /// when it lies in one of this image's segments.
    ///
    /// `MachOKit` hands over the raw `n_value`, which already IS the unslid
    /// address — in a standalone file and inside a shared cache alike. It
    /// used to be run through the segment table as a file offset: right by
    /// coincidence for a dylib, whose `__TEXT` sits at 0, and nothing found
    /// for a main executable, whose `__TEXT` sits at 0x100000000 — so an
    /// executable's own runtime helpers went unrecognized. An export trie's
    /// offset is neither — see ``address(forExportedSymbolOffset:)``.
    package func address(forSymbolValue symbolValue: Int) -> UInt64? {
        guard symbolValue >= 0 else { return nil }
        let address = UInt64(symbolValue)
        return containsAddress(address) ? address : nil
    }

    package func offset(forAddress address: UInt64) -> Int? {
        if let sharedRegionStart {
            guard address >= sharedRegionStart else { return nil }
            return Int(address - sharedRegionStart)
        }
        for segment in segments {
            let segmentEnd = segment.virtualMemoryAddress &+ UInt64(segment.fileSize)
            guard address >= segment.virtualMemoryAddress, address < segmentEnd else { continue }
            return segment.fileOffset + Int(address - segment.virtualMemoryAddress)
        }
        return nil
    }
}
