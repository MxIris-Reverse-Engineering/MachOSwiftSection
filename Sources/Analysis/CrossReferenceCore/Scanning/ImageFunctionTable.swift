import Foundation
import MachOKit
import ARM64InstructionDecoding

/// One image's functions and the sections a scan reads, collected in one pass
/// over its load commands and symbol table.
///
/// Symbol names are kept as pointers into the image's mapped `__LINKEDIT`,
/// which stays valid for the life of the analyzer's memory; that is what
/// makes the unchecked `Sendable` sound.
///
/// Knows no language. What a language layer reads per image — the
/// Objective-C sections, the names its metadata gives — it keeps as an
/// attachment (``attachment(_:makingIt:)``), which lives and goes with the
/// table.
package final class ImageFunctionTable: @unchecked Sendable {
    /// One entry of the image's `__stubs` / `__auth_stubs`.
    package struct SymbolStub {
        /// The GOT slot the stub loads its target from, unslid.
        package let slotAddress: UInt64?
        /// The imported symbol its indirect symbol entry names.
        package let name: UnsafePointer<CChar>?
    }

    package let imageIndex: Int
    package let image: MachOImage
    /// Where the image's bytes are read.
    package let memory: any CrossReferenceMemory
    /// What to add to an unslid address to reach memory.
    package let slide: Int
    package let textStart: UInt64
    package let textEnd: UInt64
    /// Every function start, sorted: `LC_FUNCTION_STARTS` and the symbols in
    /// `__text`.
    package let starts: [UInt64]
    /// For each start, the index of its primary name in `primaryNames`, or -1.
    package let primaryNameIndices: [Int32]
    package let primaryNames: [UnsafePointer<CChar>]
    /// The other names at an address, left by identical code folding.
    package let foldedNames: [UInt64: [UnsafePointer<CChar>]]
    package let runtimeHelperStarts: Set<UInt64>
    package let symbolStubRanges: [Range<UInt64>]
    package let symbolStubs: [UInt64: SymbolStub]
    /// `__got` and `__auth_got`, whose slots may hold a reference to
    /// anything another image defines. Other slots that point at a class — a
    /// constant string's `isa` — are no reference to it.
    package let globalOffsetTableRanges: [Range<UInt64>]
    /// The image's segments other than `__TEXT` and `__LINKEDIT`, unslid: where
    /// its own class objects lie.
    package let dataSegmentRanges: [Range<UInt64>]
    /// Every segment of the image, unslid.
    package let segmentRanges: [Range<UInt64>]
    package let dataInCodeRanges: [Range<UInt64>]
    /// The unslid address of the Mach header — `__TEXT`'s vmaddr.
    package let headerAddress: UInt64
    /// Every section of the image, in load-command order, collected in the
    /// table's one pass over them: a language layer reads the sections it
    /// knows from here rather than walking the load commands again for every
    /// scan.
    package let sections: [Section64]
    /// The instructions of `__text`, from `textStart` on.
    private let instructions: UnsafePointer<UInt32>?

    private let attachmentsLock = NSLock()
    private var attachments: [ObjectIdentifier: any ImageFunctionTableAttachment] = [:]

    /// `isRuntimeHelperName` tells the functions a scan marks as runtime
    /// helpers by their symbols — the language layers know which.
    package init(imageIndex: Int, image: MachOImage, memory: any CrossReferenceMemory, isRuntimeHelperName: (UnsafePointer<CChar>) -> Bool) {
        self.imageIndex = imageIndex
        self.image = image
        self.memory = memory
        let slide = image.vmaddrSlide ?? 0
        self.slide = slide
        let headerAddress = image.segments64.first { $0.segmentName == "__TEXT" }.map { UInt64($0.layout.vmaddr) } ?? 0
        self.headerAddress = headerAddress

        var textStart: UInt64 = 0
        var textEnd: UInt64 = 0
        var textSectionOrdinal = 0
        var symbolStubRanges: [Range<UInt64>] = []
        var symbolStubs: [UInt64: SymbolStub] = [:]
        var globalOffsetTableRanges: [Range<UInt64>] = []
        let symbols = image.symbols64
        let indirectSymbols = image.indirectSymbols.map { Array($0) } ?? []

        var ordinal = 0
        var sections: [Section64] = []
        for section in image.sections64 {
            sections.append(section)
            ordinal += 1
            let sectionStart = UInt64(section.address)
            let sectionRange = sectionStart ..< sectionStart + UInt64(section.size)
            let sectionName = section.sectionName
            if section.segmentName == "__TEXT", sectionName == "__text" {
                textStart = sectionRange.lowerBound
                textEnd = sectionRange.upperBound
                textSectionOrdinal = ordinal
            } else if section.flags.type == .symbol_stubs, !sectionRange.isEmpty, let stubs = section.stubs(in: image) {
                symbolStubRanges.append(sectionRange)
                for stub in stubs {
                    var slotAddress: UInt64?
                    if case .viaSlot(let address) = stub.branch {
                        slotAddress = address
                    } else if case .slotLoad(let address)? = Self.trampoline(in: stub) {
                        // `nop` / `ldr x16, <slot>` / `br x16`: ld64's stub
                        // when the slot lies within a megabyte, every stub of
                        // a third-party app linked that way. MachOKit reads no
                        // slot from it.
                        slotAddress = address
                    }
                    var name: UnsafePointer<CChar>?
                    if let indirectIndex = stub.indirectSymbolIndex, indirectIndex < indirectSymbols.count,
                       let symbolIndex = indirectSymbols[indirectIndex].index,
                       let symbols, symbolIndex < symbols.numberOfSymbols {
                        name = symbols.stringBase.advanced(by: Int(symbols.symbols[symbolIndex].n_un.n_strx))
                    }
                    symbolStubs[stub.address] = SymbolStub(slotAddress: slotAddress, name: name)
                }
            } else if !sectionRange.isEmpty, sectionName == "__got" || sectionName == "__auth_got" {
                globalOffsetTableRanges.append(sectionRange)
            }
        }
        self.textStart = textStart
        self.textEnd = textEnd
        self.instructions = textEnd > textStart
            ? memory.typedPointer(to: UInt32.self, at: Self.runtimeAddress(ofUnslid: textStart, slide: slide), length: Int(textEnd - textStart))
            : nil
        self.symbolStubRanges = symbolStubRanges
        self.symbolStubs = symbolStubs
        self.globalOffsetTableRanges = globalOffsetTableRanges
        self.sections = sections
        var dataSegmentRanges: [Range<UInt64>] = []
        var segmentRanges: [Range<UInt64>] = []
        for segment in image.segments64 where segment.layout.vmsize > 0 && segment.segmentName != "__PAGEZERO" {
            let range = UInt64(segment.layout.vmaddr) ..< UInt64(segment.layout.vmaddr) + UInt64(segment.layout.vmsize)
            segmentRanges.append(range)
            if segment.segmentName != "__TEXT", segment.segmentName != "__LINKEDIT" { dataSegmentRanges.append(range) }
        }
        self.dataSegmentRanges = dataSegmentRanges
        self.segmentRanges = segmentRanges

        // Symbols in __text, external ones first at each address.
        var namedAddresses: [(address: UInt64, isExternal: Bool, name: UnsafePointer<CChar>?)] = []
        if let symbols, textSectionOrdinal > 0 {
            namedAddresses.reserveCapacity(symbols.numberOfSymbols / 2)
            for symbolIndex in 0 ..< symbols.numberOfSymbols {
                let entry = symbols.symbols[symbolIndex]
                // Not a debugging entry, defined in a section, and that section is __text.
                guard entry.n_type & 0xE0 == 0, entry.n_type & 0x0E == 0x0E, Int(entry.n_sect) == textSectionOrdinal else { continue }
                let name = symbols.stringBase.advanced(by: Int(entry.n_un.n_strx))
                let isRedacted = strcmp(name, "<redacted>") == 0
                namedAddresses.append((entry.n_value, entry.n_type & 0x01 != 0, isRedacted ? nil : name))
            }
        }
        namedAddresses.sort { left, right in
            left.address != right.address ? left.address < right.address : (left.isExternal && !right.isExternal)
        }

        var functionStarts: [UInt64] = []
        if let starts = image.functionStarts {
            // `MachOImage.FunctionStarts` seeds its running offset with
            // __TEXT's vmaddr, so `offset` is already the unslid address,
            // whatever its documentation says. The trailing padding of the
            // encoding repeats the last start.
            for functionStart in starts {
                let address = UInt64(functionStart.offset)
                if address >= textStart, address < textEnd, functionStarts.last != address { functionStarts.append(address) }
            }
            functionStarts.sort()
        }

        var mergedStarts: [UInt64] = []
        var primaryNameIndices: [Int32] = []
        var primaryNames: [UnsafePointer<CChar>] = []
        var foldedNames: [UInt64: [UnsafePointer<CChar>]] = [:]
        var runtimeHelperStarts = Set<UInt64>()
        mergedStarts.reserveCapacity(max(functionStarts.count, namedAddresses.count))
        primaryNameIndices.reserveCapacity(mergedStarts.capacity)

        var namedCursor = 0
        var startCursor = 0
        while namedCursor < namedAddresses.count || startCursor < functionStarts.count {
            let namedAddress = namedCursor < namedAddresses.count ? namedAddresses[namedCursor].address : .max
            let startAddress = startCursor < functionStarts.count ? functionStarts[startCursor] : .max
            let address = min(namedAddress, startAddress)
            if startAddress == address { startCursor += 1 }
            var names: [UnsafePointer<CChar>] = []
            while namedCursor < namedAddresses.count, namedAddresses[namedCursor].address == address {
                if let name = namedAddresses[namedCursor].name { names.append(name) }
                namedCursor += 1
            }
            mergedStarts.append(address)
            if let primaryName = names.first {
                primaryNameIndices.append(Int32(primaryNames.count))
                primaryNames.append(primaryName)
                if names.count > 1 { foldedNames[address] = Array(names.dropFirst()) }
                if names.contains(where: isRuntimeHelperName) { runtimeHelperStarts.insert(address) }
            } else {
                primaryNameIndices.append(-1)
            }
        }
        self.starts = mergedStarts
        self.primaryNameIndices = primaryNameIndices
        self.primaryNames = primaryNames
        self.foldedNames = foldedNames
        self.runtimeHelperStarts = runtimeHelperStarts

        var dataInCodeRanges: [Range<UInt64>] = []
        if let entries = image.dataInCode {
            for entry in entries {
                let start = headerAddress + UInt64(entry.layout.offset)
                dataInCodeRanges.append(start ..< start + UInt64(entry.layout.length))
            }
            dataInCodeRanges.sort { $0.lowerBound < $1.lowerBound }
        }
        self.dataInCodeRanges = dataInCodeRanges
    }

    /// The trampoline a stub's own bytes make.
    private static func trampoline(in stub: Stub) -> ARM64Trampoline? {
        let bytes = stub.rawData
        let words = stride(from: 0, to: bytes.count - 3, by: 4).map { offset in
            UInt32(littleEndian: bytes.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) })
        }
        return ARM64Trampoline(words: words, at: stub.address)
    }

    package static func runtimeAddress(ofUnslid address: UInt64, slide: Int) -> UInt {
        UInt(bitPattern: Int(bitPattern: UInt(address)) &+ slide)
    }

    /// Where the unslid `address` of this image lies in the analyzer's
    /// address space.
    package func runtimeAddress(ofUnslid address: UInt64) -> UInt {
        Self.runtimeAddress(ofUnslid: address, slide: slide)
    }

    /// The unslid address in this image of the runtime `address`.
    package func unslidAddress(ofRuntime address: UInt) -> UInt64 {
        UInt64(bitPattern: Int64(Int(bitPattern: address) &- slide))
    }

    /// The index in `starts` of the function containing `address`.
    package func functionIndex(containing address: UInt64) -> Int? {
        guard address >= textStart, address < textEnd, let first = starts.first, address >= first else { return nil }
        var lower = 0
        var upper = starts.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if starts[middle] <= address { lower = middle + 1 } else { upper = middle }
        }
        return lower - 1
    }

    package func end(ofFunctionAt index: Int) -> UInt64 {
        index + 1 < starts.count ? starts[index + 1] : textEnd
    }

    package func primaryName(ofFunctionAt index: Int) -> UnsafePointer<CChar>? {
        let nameIndex = primaryNameIndices[index]
        return nameIndex < 0 ? nil : primaryNames[Int(nameIndex)]
    }

    /// The memory holding the `count` instructions from the unslid `address`
    /// on, or `nil` when they cannot be read.
    ///
    /// A function start usually lies in `__text`, read from the section's
    /// bytes. Not always: some images' symbol tables put a start of `__text`
    /// below the section's own start, and such a function is read where it
    /// lies, as the scan always did.
    package func instructionPointer(at address: UInt64, count: Int) -> UnsafePointer<UInt32>? {
        if let instructions, address >= textStart, address &+ UInt64(count) &* 4 <= textEnd {
            return instructions.advanced(by: Int((address - textStart) / 4))
        }
        return memory.typedPointer(to: UInt32.self, at: runtimeAddress(ofUnslid: address), length: count &* 4)
    }

    package func isInDataInCode(_ address: UInt64) -> Bool {
        guard !dataInCodeRanges.isEmpty else { return false }
        return dataInCodeRanges.contains { $0.contains(address) }
    }

    /// What a language layer keeps for this image, made on first use and
    /// kept as long as the table is: `make` runs once, under the table's lock,
    /// and must not ask the table for an attachment.
    package func attachment<Attachment: ImageFunctionTableAttachment>(_ type: Attachment.Type, makingIt make: () -> Attachment) -> Attachment {
        attachmentsLock.lock()
        defer { attachmentsLock.unlock() }
        if let existing = attachments[ObjectIdentifier(type)] as? Attachment { return existing }
        let attachment = make()
        attachments[ObjectIdentifier(type)] = attachment
        return attachment
    }

    /// The attachment of type `type`, when something has made it.
    package func existingAttachment<Attachment: ImageFunctionTableAttachment>(_ type: Attachment.Type) -> Attachment? {
        attachmentsLock.lock()
        defer { attachmentsLock.unlock() }
        return attachments[ObjectIdentifier(type)] as? Attachment
    }

    /// The memory the table takes, with its attachments; see
    /// `ApproximateSize`. The names it points at belong to the image.
    package var approximateByteCount: Int {
        var byteCount = ApproximateSize.of(starts) + ApproximateSize.of(primaryNameIndices) + ApproximateSize.of(primaryNames)
        byteCount += foldedNames.values.reduce(ApproximateSize.of(foldedNames)) { $0 + ApproximateSize.of($1) }
        byteCount += ApproximateSize.of(runtimeHelperStarts) + ApproximateSize.of(symbolStubs)
        byteCount += ApproximateSize.of(symbolStubRanges) + ApproximateSize.of(globalOffsetTableRanges) + ApproximateSize.of(dataSegmentRanges)
        byteCount += ApproximateSize.of(segmentRanges) + ApproximateSize.of(dataInCodeRanges)
        attachmentsLock.lock()
        let attachments = Array(self.attachments.values)
        attachmentsLock.unlock()
        return attachments.reduce(byteCount) { $0 + $1.approximateByteCount }
    }
}

/// What a language layer keeps per image on its function table.
package protocol ImageFunctionTableAttachment: AnyObject, Sendable {
    /// The memory it takes; see `ApproximateSize`.
    var approximateByteCount: Int { get }
}
