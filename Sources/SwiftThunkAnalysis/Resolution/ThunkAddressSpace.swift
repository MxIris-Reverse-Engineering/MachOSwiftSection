#if THUNK_ANALYSIS

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

    /// File-offset → address mapping for the standalone case.
    private let segments: [(fileOffset: Int, fileSize: Int, virtualMemoryAddress: UInt64)]

    package init(of machO: MachOFile) {
        if let cache = machO.cache {
            self.sharedRegionStart = numericCast(cache.mainCacheHeader.sharedRegionStart)
        } else {
            self.sharedRegionStart = nil
        }
        segments = machO.segments.map {
            (fileOffset: $0.fileOffset, fileSize: $0.fileSize, virtualMemoryAddress: UInt64($0.virtualMemoryAddress))
        }
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

#endif
