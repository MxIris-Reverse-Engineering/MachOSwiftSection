import Foundation
@_spi(Support) import MachOKit
import MachOKitExtensions
import CodeAddressResolution

/// The memory of images read from files rather than loaded: every image of a
/// dyld shared cache, or a set of standalone Mach-O files — an app's
/// executable and its frameworks.
///
/// An address is an image's unslid virtual address plus the slide the
/// analyzer gave the image: 0 for a shared cache's images, which share one
/// address space already, and for standalone files whatever keeps their
/// address ranges apart, as dyld would. Bytes are read where MachOKit mapped
/// the files when it opened them (`fileBytes`), so the memory holds no
/// mapping of its own.
///
/// What a pointer slot holds is decoded, since nothing has bound or rebased
/// it: a shared cache's slots through its slide info, a standalone file's
/// through its chained fixups or its rebase and bind opcodes. A bind lands on
/// the symbol one of the files exports under its name — a self-bind on the
/// file's own export — and stays an imported name when none does. Lookups go
/// by name alone, not by the library the bind names: two of the files
/// exporting one name is not told apart.
///
/// The memory is a value that refers to its ``Storage`` without retaining
/// it: every read through `any CrossReferenceMemory` copies the memory, and
/// as a class — or a value holding one — each copy cost a retain and a
/// release, which made scanning a whole cache from its files several times
/// slower than in the process, whose memory holds no reference at all. So
/// whoever makes the memory keeps its storage alive (`CodeImageSet` does,
/// for its lifetime), and the memory is valid only as long.
package struct FileCrossReferenceMemory: CrossReferenceMemory, @unchecked Sendable {
    /// One mapped region: a shared cache mapping, or what a standalone
    /// file's segment holds. Trivial, so that the regions live in a buffer
    /// no reference counting touches.
    fileprivate struct Region {
        let start: UInt
        let end: UInt
        /// Where `start` lies in the mapped file.
        let bytes: UnsafeRawPointer
        /// The standalone file holding the region, by position in the
        /// storage's files; -1 in a shared cache.
        let fileIndex: Int
        /// For a shared cache's mapping, how its slots are decoded: version 5
        /// slide info is decoded here; for any other mapping — a simulator
        /// runtime's has no slide info — `fallbackSubcacheIndex` names the
        /// subcache MachOKit decodes the slot through.
        let decodesVersion5: Bool
        let fallbackSubcacheIndex: Int
        /// The file offset of `start` in that subcache.
        let fallbackFileOffset: UInt64
    }

    /// What the memory reads: the files, kept mapped while it lives, and
    /// what each slot is decoded with.
    ///
    /// A shared cache's slots are decoded from slide info taken once per
    /// mapping, not through MachOKit's `resolveOptionalRebase(at:)` for
    /// every slot, which looks the mapping up again, reads the slide info
    /// anew and — through `FullDyldCache` — makes the subcache object anew:
    /// a scan of a whole cache from its files was fifteen times slower that
    /// way. Only version 5, every arm64e cache from macOS 14 and iOS 17 on,
    /// is decoded here.
    package final class Storage: @unchecked Sendable {
        fileprivate let regions: UnsafeMutableBufferPointer<Region>
        fileprivate let cache: FullDyldCache?
        fileprivate let subcaches: [DyldCache]
        fileprivate let sharedRegionStart: UInt64
        fileprivate let files: [(file: MachOFile, slide: Int, slots: SlotResolver, hasChainedFixups: Bool)]
        /// Every symbol the standalone files export, at its address in the
        /// analyzer's address space.
        fileprivate let exportedAddressesByName: [String: UInt]

        fileprivate init(
            regions: [Region],
            cache: FullDyldCache?,
            subcaches: [DyldCache],
            files: [(file: MachOFile, slide: Int, slots: SlotResolver, hasChainedFixups: Bool)],
            exportedAddressesByName: [String: UInt]
        ) {
            let buffer = UnsafeMutableBufferPointer<Region>.allocate(capacity: regions.count)
            _ = buffer.initialize(from: regions.sorted { $0.start < $1.start })
            self.regions = buffer
            self.cache = cache
            self.subcaches = subcaches
            self.sharedRegionStart = cache?.mainCacheHeader.sharedRegionStart ?? 0
            self.files = files
            self.exportedAddressesByName = exportedAddressesByName
        }

        deinit {
            regions.deinitialize()
            regions.deallocate()
        }
    }

    private unowned(unsafe) let storage: Storage

    /// The memory of `storage`, which the caller keeps alive for as long as
    /// the memory is used.
    package init(storage: Storage) {
        self.storage = storage
    }

    /// What the memory of every image of `cache` reads.
    package static func storage(cache: FullDyldCache) -> Storage {
        var regions: [Region] = []
        var subcaches: [DyldCache] = []
        for subcache in cache.allCaches {
            let fileBytes = subcache.fileBytes
            guard let base = fileBytes.baseAddress else { continue }
            let subcacheIndex = subcaches.count
            subcaches.append(subcache)
            var mappings: [(address: UInt64, size: UInt64, fileOffset: UInt64, decodesVersion5: Bool)] = []
            if let mappingAndSlideInfos = subcache.mappingAndSlideInfos {
                for mapping in mappingAndSlideInfos {
                    let isVersion5 = if case .v5? = mapping.slideInfo(in: subcache) { true } else { false }
                    mappings.append((mapping.address, mapping.size, mapping.fileOffset, isVersion5))
                }
            } else if let mappingInfos = subcache.mappingInfos {
                for mapping in mappingInfos {
                    mappings.append((mapping.address, mapping.size, mapping.fileOffset, false))
                }
            }
            for mapping in mappings {
                let fileOffset = Int(mapping.fileOffset)
                let size = min(Int(mapping.size), fileBytes.count - fileOffset)
                guard fileOffset >= 0, size > 0 else { continue }
                let start = UInt(mapping.address)
                regions.append(Region(
                    start: start,
                    end: start + UInt(size),
                    bytes: base + fileOffset,
                    fileIndex: -1,
                    decodesVersion5: mapping.decodesVersion5,
                    fallbackSubcacheIndex: subcacheIndex,
                    fallbackFileOffset: mapping.fileOffset
                ))
            }
        }
        return Storage(regions: regions, cache: cache, subcaches: subcaches, files: [], exportedAddressesByName: [:])
    }

    /// What the memory of standalone files, each at `slide` from its own
    /// addresses, reads.
    package static func storage(files: [(file: MachOFile, slide: Int)]) -> Storage {
        var regions: [Region] = []
        var standaloneFiles: [(file: MachOFile, slide: Int, slots: SlotResolver, hasChainedFixups: Bool)] = []
        var exportedAddressesByName: [String: UInt] = [:]
        for (fileIndex, (file, slide)) in files.enumerated() {
            let hasChainedFixups = file.loadCommands.contains { if case .dyldChainedFixups = $0 { true } else { false } }
            standaloneFiles.append((file, slide, SlotResolver(machO: file), hasChainedFixups))
            let fileBytes = file.fileBytes
            guard let base = fileBytes.baseAddress else { continue }
            // A fat file's slice starts at `headerStartOffset`; segment file
            // offsets count from the slice.
            let sliceStart = file.headerStartOffset
            var textAddress: UInt64?
            for segment in file.segments64 where segment.layout.vmsize > 0 && segment.segmentName != "__PAGEZERO" {
                if segment.segmentName == "__TEXT" { textAddress = UInt64(segment.layout.vmaddr) }
                // Only what the file holds can be read; the zero-filled rest
                // of a segment cannot.
                let fileOffset = sliceStart + Int(segment.layout.fileoff)
                let size = min(Int(segment.layout.filesize), fileBytes.count - fileOffset)
                guard fileOffset >= 0, size > 0 else { continue }
                let start = UInt(bitPattern: Int(bitPattern: UInt(segment.layout.vmaddr)) &+ slide)
                regions.append(Region(start: start, end: start + UInt(size), bytes: base + fileOffset, fileIndex: fileIndex, decodesVersion5: false, fallbackSubcacheIndex: -1, fallbackFileOffset: 0))
            }
            guard let textAddress else { continue }
            for symbol in file.exportedSymbols {
                guard let offset = symbol.offset, exportedAddressesByName[symbol.name] == nil else { continue }
                let address = UInt64(bitPattern: Int64(bitPattern: textAddress) &+ Int64(offset))
                exportedAddressesByName[symbol.name] = UInt(bitPattern: Int(bitPattern: UInt(address)) &+ slide)
            }
        }
        return Storage(regions: regions, cache: nil, subcaches: [], files: standaloneFiles, exportedAddressesByName: exportedAddressesByName)
    }

    private func region(containing address: UInt) -> Region? {
        let regions = storage.regions
        var lower = 0
        var upper = regions.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if regions[middle].start <= address { lower = middle + 1 } else { upper = middle }
        }
        guard lower > 0 else { return nil }
        let candidate = regions[lower - 1]
        return address < candidate.end ? candidate : nil
    }

    package func bytes(at address: UInt, length: Int) -> UnsafeRawBufferPointer? {
        guard length >= 0, let region = region(containing: address) else { return nil }
        let (end, overflow) = address.addingReportingOverflow(UInt(length))
        guard !overflow, end <= region.end else { return nil }
        return UnsafeRawBufferPointer(start: region.bytes + Int(address - region.start), count: length)
    }

    package func slotContent(at address: UInt) -> SlotContent? {
        guard let region = region(containing: address), address &+ 8 <= region.end else { return nil }
        let raw = (region.bytes + Int(address - region.start)).loadUnaligned(as: UInt64.self)
        if region.fileIndex < 0 {
            // A null pointer, an absent weak import: no rebase.
            guard raw != 0 else { return .address(0) }
            let target: UInt64?
            if region.decodesVersion5 {
                // `dyld_cache_slide_pointer5.runtimeOffset`: the low 34 bits,
                // an offset from the shared region's start, authenticated or
                // not. A format field, not an address mask.
                target = (raw & 0x3_FFFF_FFFF) &+ storage.sharedRegionStart
            } else {
                target = storage.subcaches[region.fallbackSubcacheIndex].resolveOptionalRebase(at: region.fallbackFileOffset &+ UInt64(address - region.start))
            }
            guard let target else { return nil }
            return .address(UInt(truncatingIfNeeded: target))
        }
        let standaloneFile = storage.files[region.fileIndex]
        let unslidAddress = UInt64(bitPattern: Int64(Int(bitPattern: address) &- standaloneFile.slide))
        switch standaloneFile.slots.content(ofSlotAt: unslidAddress) {
        case .address(let target)?:
            return .address(UInt(bitPattern: Int(bitPattern: UInt(target)) &+ standaloneFile.slide))
        case .boundSymbol(let name)?:
            if let exported = storage.exportedAddressesByName[name] { return .address(exported) }
            return .importedSymbol(name)
        case nil:
            if raw == 0 { return .address(0) }
            // Rebased by opcodes rather than chained fixups: the slot holds
            // the target's address itself, which dyld only slides.
            guard !standaloneFile.hasChainedFixups else { return nil }
            return .address(UInt(bitPattern: Int(bitPattern: UInt(raw)) &+ standaloneFile.slide))
        }
    }

    /// A decoded slot holds a plain address: nothing to strip.
    package var addressMask: UInt {
        UInt.max
    }
}
