import MachOKit
import MachOKitExtensions

/// Converts a symbol table entry's value into the offset the symbol index
/// files it under — the accounting every descriptor-derived offset (a vtable
/// slot's implementation, a witness, a relative pointer's target) asks with.
///
/// `MachOKit` hands a `MachOFile` symbol over with its raw `n_value`, which is
/// a virtual address, whatever its documentation says:
///
/// | Image | Symbol value | Index offset |
/// |---|---|---|
/// | `MachOImage` (in-process) | already an offset from the mach header | unchanged |
/// | `MachOFile` in a dyld shared cache | unslid address | the value minus `sharedRegionStart` |
/// | standalone `MachOFile` | address | the file offset its segment maps it to |
///
/// A dylib links `__TEXT` at 0, where a standalone file's addresses and file
/// offsets coincide — which hid the standalone case until a main executable
/// (`__TEXT` at 0x100000000) had every symbol filed 0x100000000 too high: its
/// member addresses printed doubled, and no vtable slot found its name.
struct SymbolValueOffsetConverter {
    private struct SegmentMapping {
        let virtualMemoryAddress: UInt64
        let virtualMemorySize: UInt64
        let fileOffset: Int
    }

    private enum Accounting {
        case unchanged
        case sharedRegion(start: Int)
        case segments([SegmentMapping])
    }

    private let accounting: Accounting

    init(for machO: some MachORepresentableWithCache) {
        guard let machOFile = machO as? MachOFile else {
            accounting = .unchanged
            return
        }
        if let cache = machOFile.cache {
            accounting = .sharedRegion(start: cache.mainCacheHeader.sharedRegionStart.cast())
        } else {
            // Read once: `segments` walks the load commands on every access.
            accounting = .segments(machOFile.segments.map {
                SegmentMapping(
                    virtualMemoryAddress: UInt64($0.virtualMemoryAddress),
                    virtualMemorySize: UInt64($0.virtualMemorySize),
                    fileOffset: $0.fileOffset
                )
            })
        }
    }

    /// The index offset for `value`. A value that is no address in the image
    /// — negative (bit 63 set) or outside every segment, as an absolute
    /// symbol's constant can be — is returned unchanged.
    func offset(forSymbolValue value: Int) -> Int {
        switch accounting {
        case .unchanged:
            return value
        case .sharedRegion(let sharedRegionStart):
            return value >= 0 ? value - sharedRegionStart : value
        case .segments(let segments):
            guard value >= 0 else { return value }
            let address = UInt64(value)
            for segment in segments where address >= segment.virtualMemoryAddress && address - segment.virtualMemoryAddress < segment.virtualMemorySize {
                return segment.fileOffset + Int(address - segment.virtualMemoryAddress)
            }
            return value
        }
    }
}
