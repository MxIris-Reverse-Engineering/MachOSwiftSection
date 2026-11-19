import Foundation
import MachOKit
import ARM64InstructionDecoding

/// One image's functions and the sections a scan reads, collected in one pass
/// over its load commands and symbol table.
///
/// Symbol names are kept as pointers into the image's `__LINKEDIT` in the
/// analyzer's memory, which stays valid for the life of the memory; that is
/// what makes the unchecked `Sendable` sound. Everything is read from the
/// load commands and that memory, so a table is built the same way for an
/// image in this process and for one in a file.
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
    package let image: CodeImage
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
    /// The sections of C string literals — `__cstring`, `__objc_methname`,
    /// `__oslogstring` and the like — and `__cfstring`, where constant
    /// `CFString`s lie: where a scan recording string references looks.
    package let cStringSectionRanges: [Range<UInt64>]
    package let constantStringSectionRanges: [Range<UInt64>]
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
    package init(imageIndex: Int, image: CodeImage, linkEdit: ImageLinkEdit, memory: any CrossReferenceMemory, isRuntimeHelperName: (UnsafePointer<CChar>) -> Bool) {
        self.imageIndex = imageIndex
        self.image = image
        self.memory = memory
        let slide = image.slide
        self.slide = slide
        let headerAddress = image.headerAddress
        self.headerAddress = headerAddress

        var textStart: UInt64 = 0
        var textEnd: UInt64 = 0
        var textSectionOrdinal = 0
        var symbolStubRanges: [Range<UInt64>] = []
        var symbolStubs: [UInt64: SymbolStub] = [:]
        var globalOffsetTableRanges: [Range<UInt64>] = []
        var cStringSectionRanges: [Range<UInt64>] = []
        var constantStringSectionRanges: [Range<UInt64>] = []

        var ordinal = 0
        var sections: [Section64] = []
        for section in image.reader.sections64 {
            sections.append(section)
            ordinal += 1
            let sectionStart = UInt64(section.address)
            let sectionRange = sectionStart ..< sectionStart + UInt64(section.size)
            let sectionName = section.sectionName
            if section.segmentName == "__TEXT", sectionName == "__text" {
                textStart = sectionRange.lowerBound
                textEnd = sectionRange.upperBound
                textSectionOrdinal = ordinal
            } else if section.flags.type == .symbol_stubs, !sectionRange.isEmpty, section.layout.reserved2 >= 4 {
                symbolStubRanges.append(sectionRange)
                // `reserved2` is the size of a stub, `reserved1` the index of
                // the first stub's entry in the indirect symbol table.
                let stubSize = UInt64(section.layout.reserved2)
                let wordCount = min(Int(stubSize / 4), ARM64Trampoline.maximumInstructionCount)
                for stubPosition in 0 ..< Int(UInt64(section.size) / stubSize) {
                    let stubAddress = sectionStart &+ UInt64(stubPosition) &* stubSize
                    // `adrp` / `ldr` / `br`, the arm64e `adrp` / `add` / `ldr`
                    // / `braa`, and `nop` / `ldr x16, <slot>` / `br x16` —
                    // ld64's stub when the slot lies within a megabyte, every
                    // stub of a third-party app linked that way. A stub the
                    // cache builder rewrote to branch straight to its target
                    // loads no slot.
                    var slotAddress: UInt64?
                    if let words = memory.typedPointer(to: UInt32.self, at: Self.runtimeAddress(ofUnslid: stubAddress, slide: slide), length: wordCount * 4),
                       case .slotLoad(let address)? = ARM64Trampoline(words: UnsafeBufferPointer(start: words, count: wordCount).map { UInt32(littleEndian: $0) }, at: stubAddress) {
                        slotAddress = address
                    }
                    var name: UnsafePointer<CChar>?
                    let indirectIndex = Int(section.layout.reserved1) + stubPosition
                    if indirectIndex < linkEdit.indirectSymbols.count {
                        let symbolIndex = linkEdit.indirectSymbols[indirectIndex]
                        if symbolIndex & (ImageLinkEdit.indirectSymbolLocal | ImageLinkEdit.indirectSymbolAbsolute) == 0, Int(symbolIndex) < linkEdit.symbols.count {
                            name = linkEdit.name(ofSymbolAt: Int(symbolIndex))
                        }
                    }
                    symbolStubs[stubAddress] = SymbolStub(slotAddress: slotAddress, name: name)
                }
            } else if !sectionRange.isEmpty, sectionName == "__got" || sectionName == "__auth_got" {
                globalOffsetTableRanges.append(sectionRange)
            } else if !sectionRange.isEmpty, section.flags.type == .cstring_literals {
                cStringSectionRanges.append(sectionRange)
            } else if !sectionRange.isEmpty, sectionName == "__cfstring" {
                constantStringSectionRanges.append(sectionRange)
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
        self.cStringSectionRanges = cStringSectionRanges
        self.constantStringSectionRanges = constantStringSectionRanges
        self.sections = sections
        var dataSegmentRanges: [Range<UInt64>] = []
        var segmentRanges: [Range<UInt64>] = []
        for segment in image.reader.segments64 where segment.layout.vmsize > 0 && segment.segmentName != "__PAGEZERO" {
            let range = UInt64(segment.layout.vmaddr) ..< UInt64(segment.layout.vmaddr) + UInt64(segment.layout.vmsize)
            segmentRanges.append(range)
            if segment.segmentName != "__TEXT", segment.segmentName != "__LINKEDIT" { dataSegmentRanges.append(range) }
        }
        self.dataSegmentRanges = dataSegmentRanges
        self.segmentRanges = segmentRanges

        // Symbols in __text, external ones first at each address.
        var namedAddresses: [(address: UInt64, isExternal: Bool, name: UnsafePointer<CChar>?)] = []
        if textSectionOrdinal > 0 {
            namedAddresses.reserveCapacity(linkEdit.symbols.count / 2)
            for symbolIndex in linkEdit.symbols.indices {
                let entry = linkEdit.symbols[symbolIndex]
                // Not a debugging entry, defined in a section, and that section is __text.
                guard ImageLinkEdit.isDefinedInSection(entry), Int(entry.n_sect) == textSectionOrdinal,
                      let name = linkEdit.name(ofSymbolAt: symbolIndex)
                else { continue }
                let isRedacted = strcmp(name, "<redacted>") == 0
                namedAddresses.append((entry.n_value, entry.n_type & 0x01 != 0, isRedacted ? nil : name))
            }
        }
        namedAddresses.sort { left, right in
            left.address != right.address ? left.address < right.address : (left.isExternal && !right.isExternal)
        }

        var functionStarts: [UInt64] = []
        for address in linkEdit.functionStartAddresses(textAddress: headerAddress) {
            if address >= textStart, address < textEnd, functionStarts.last != address { functionStarts.append(address) }
        }
        functionStarts.sort()

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
        for entry in linkEdit.dataInCode {
            let start = headerAddress + UInt64(entry.offset)
            dataInCodeRanges.append(start ..< start + UInt64(entry.length))
        }
        dataInCodeRanges.sort { $0.lowerBound < $1.lowerBound }
        self.dataInCodeRanges = dataInCodeRanges
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
