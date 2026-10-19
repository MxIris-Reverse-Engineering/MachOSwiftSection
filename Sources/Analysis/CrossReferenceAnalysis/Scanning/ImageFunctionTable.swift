import Foundation
import MachOKit

/// One image's functions and the sections a scan reads, collected in one pass
/// over its load commands and symbol table.
///
/// Symbol and selector names are kept as pointers into the image's mapped
/// `__LINKEDIT` and the cache's selector strings, which stay valid for the
/// life of the process; that is what makes the unchecked `Sendable` sound.
final class ImageFunctionTable: @unchecked Sendable {
    /// One entry of the image's `__stubs` / `__auth_stubs`.
    struct SymbolStub {
        /// The GOT slot the stub loads its target from, unslid.
        let slotAddress: UInt64?
        /// The imported symbol its indirect symbol entry names.
        let name: UnsafePointer<CChar>?
    }

    let imageIndex: Int
    let image: MachOImage
    /// What to add to an unslid address to reach memory.
    let slide: Int
    let textStart: UInt64
    let textEnd: UInt64
    /// Every function start, sorted: `LC_FUNCTION_STARTS` and the symbols in
    /// `__text`.
    let starts: [UInt64]
    /// For each start, the index of its primary name in `primaryNames`, or -1.
    let primaryNameIndices: [Int32]
    let primaryNames: [UnsafePointer<CChar>]
    /// The other names at an address, left by identical code folding.
    let foldedNames: [UInt64: [UnsafePointer<CChar>]]
    let runtimeHelperStarts: Set<UInt64>
    let objectiveCStubRange: Range<UInt64>?
    let objectiveCStubSelectors: [UInt64: UnsafePointer<CChar>]
    let symbolStubRanges: [Range<UInt64>]
    let symbolStubs: [UInt64: SymbolStub]
    let selectorReferenceRange: Range<UInt64>?
    /// The sections whose slots may hold a reference to a class or a Swift
    /// type: `__got`, `__auth_got`, `__objc_classrefs`. Other slots that point
    /// at a class — a constant string's `isa` — are no reference to it.
    let referenceSlotRanges: [Range<UInt64>]
    /// `__objc_superrefs`: the class a super send in one of its methods starts
    /// above.
    let superclassReferenceRange: Range<UInt64>?
    /// The image's segments other than `__TEXT` and `__LINKEDIT`, unslid: where
    /// its own class objects lie.
    let dataSegmentRanges: [Range<UInt64>]
    /// Every segment of the image, unslid.
    let segmentRanges: [Range<UInt64>]
    let dataInCodeRanges: [Range<UInt64>]
    /// The unslid address of the Mach header — `__TEXT`'s vmaddr.
    let headerAddress: UInt64

    private let fallbackNamesLock = NSLock()
    private var fallbackNamesStorage: ImageFallbackNames?

    init(imageIndex: Int, image: MachOImage) {
        self.imageIndex = imageIndex
        self.image = image
        let slide = image.vmaddrSlide ?? 0
        self.slide = slide
        let headerAddress = image.segments64.first { $0.segmentName == "__TEXT" }.map { UInt64($0.layout.vmaddr) } ?? 0
        self.headerAddress = headerAddress

        var textStart: UInt64 = 0
        var textEnd: UInt64 = 0
        var textSectionOrdinal = 0
        var objectiveCStubRange: Range<UInt64>?
        var objectiveCStubSelectors: [UInt64: UnsafePointer<CChar>] = [:]
        var symbolStubRanges: [Range<UInt64>] = []
        var symbolStubs: [UInt64: SymbolStub] = [:]
        var selectorReferenceRange: Range<UInt64>?
        var referenceSlotRanges: [Range<UInt64>] = []
        var superclassReferenceRange: Range<UInt64>?
        let symbols = image.symbols64
        let indirectSymbols = image.indirectSymbols.map { Array($0) } ?? []

        var ordinal = 0
        for section in image.sections64 {
            ordinal += 1
            let sectionStart = UInt64(section.address)
            let sectionRange = sectionStart ..< sectionStart + UInt64(section.size)
            let sectionName = section.sectionName
            if section.segmentName == "__TEXT", sectionName == "__text" {
                textStart = sectionRange.lowerBound
                textEnd = sectionRange.upperBound
                textSectionOrdinal = ordinal
            } else if sectionName == "__objc_stubs", !sectionRange.isEmpty, let stubs = section.objcStubs(in: image) {
                objectiveCStubRange = sectionRange
                for objectiveCStub in stubs {
                    guard let selectorReference = objectiveCStub.selectorReference,
                          let selector = Self.selectorString(inSlotAt: selectorReference, slide: slide)
                    else { continue }
                    objectiveCStubSelectors[objectiveCStub.stub.address] = selector
                }
            } else if section.flags.type == .symbol_stubs, !sectionRange.isEmpty, let stubs = section.stubs(in: image) {
                symbolStubRanges.append(sectionRange)
                for stub in stubs {
                    var slotAddress: UInt64?
                    if case .viaSlot(let address) = stub.branch { slotAddress = address }
                    var name: UnsafePointer<CChar>?
                    if let indirectIndex = stub.indirectSymbolIndex, indirectIndex < indirectSymbols.count,
                       let symbolIndex = indirectSymbols[indirectIndex].index,
                       let symbols, symbolIndex < symbols.numberOfSymbols {
                        name = symbols.stringBase.advanced(by: Int(symbols.symbols[symbolIndex].n_un.n_strx))
                    }
                    symbolStubs[stub.address] = SymbolStub(slotAddress: slotAddress, name: name)
                }
            } else if sectionName == "__objc_selrefs", !sectionRange.isEmpty {
                selectorReferenceRange = sectionRange
            } else if sectionName == "__objc_superrefs", !sectionRange.isEmpty {
                superclassReferenceRange = sectionRange
            } else if !sectionRange.isEmpty, ["__got", "__auth_got", "__objc_classrefs"].contains(sectionName) {
                referenceSlotRanges.append(sectionRange)
            }
        }
        self.textStart = textStart
        self.textEnd = textEnd
        self.objectiveCStubRange = objectiveCStubRange
        self.objectiveCStubSelectors = objectiveCStubSelectors
        self.symbolStubRanges = symbolStubRanges
        self.symbolStubs = symbolStubs
        self.selectorReferenceRange = selectorReferenceRange
        self.referenceSlotRanges = referenceSlotRanges
        self.superclassReferenceRange = superclassReferenceRange
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
        namedAddresses.sort { lhs, rhs in
            lhs.address != rhs.address ? lhs.address < rhs.address : (lhs.isExternal && !rhs.isExternal)
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
                if names.contains(where: { RuntimeHelperNames.isRuntimeHelper($0) }) { runtimeHelperStarts.insert(address) }
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

    /// The selector string a selector reference slot points at, read from
    /// memory — the cache builder and dyld have already bound it.
    static func selectorString(inSlotAt slotAddress: UInt64, slide: Int) -> UnsafePointer<CChar>? {
        guard let slot = UnsafeRawPointer(bitPattern: Int(bitPattern: UInt(slotAddress)) &+ slide) else { return nil }
        let value = slot.loadUnaligned(as: UInt64.self) & 0x0000_7FFF_FFFF_FFFF
        return UnsafePointer<CChar>(bitPattern: UInt(value))
    }

    /// The index in `starts` of the function containing `address`.
    func functionIndex(containing address: UInt64) -> Int? {
        guard address >= textStart, address < textEnd, let first = starts.first, address >= first else { return nil }
        var lower = 0
        var upper = starts.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if starts[middle] <= address { lower = middle + 1 } else { upper = middle }
        }
        return lower - 1
    }

    func end(ofFunctionAt index: Int) -> UInt64 {
        index + 1 < starts.count ? starts[index + 1] : textEnd
    }

    func primaryName(ofFunctionAt index: Int) -> UnsafePointer<CChar>? {
        let nameIndex = primaryNameIndices[index]
        return nameIndex < 0 ? nil : primaryNames[Int(nameIndex)]
    }

    /// Whether the function at `index` is an Objective-C method, whose `x0`
    /// on entry is its receiver.
    func isObjectiveCMethod(at index: Int) -> Bool {
        guard let name = primaryName(ofFunctionAt: index) else { return false }
        return (name[0] == 0x2D || name[0] == 0x2B) && name[1] == 0x5B
    }

    /// The memory holding the instruction at the unslid `address`.
    func instructionPointer(at address: UInt64) -> UnsafePointer<UInt32> {
        UnsafeRawPointer(bitPattern: Int(bitPattern: UInt(address)) &+ slide)!.assumingMemoryBound(to: UInt32.self)
    }

    func isInDataInCode(_ address: UInt64) -> Bool {
        guard !dataInCodeRanges.isEmpty else { return false }
        return dataInCodeRanges.contains { $0.contains(address) }
    }

    func codeFunction(at index: Int) -> CodeFunction {
        let start = starts[index]
        var name: CodeFunction.Name? = primaryName(ofFunctionAt: index).map { .symbol(String(cString: $0)) }
        var foldedSymbolNames = foldedNames[start]?.map { String(cString: $0) } ?? []
        if name == nil, let fallback = fallbackNames.name(at: start) {
            name = fallback.name
            foldedSymbolNames = fallback.foldedSymbolNames
        }
        return CodeFunction(
            location: CodeLocation(imageIndex: imageIndex, address: start),
            size: Int(end(ofFunctionAt: index) - start),
            name: name,
            foldedSymbolNames: foldedSymbolNames,
            isRuntimeHelper: runtimeHelperStarts.contains(start)
        )
    }

    /// The names the symbol table does not give, read on first use: naming a
    /// function needs them, scanning never does.
    var fallbackNames: ImageFallbackNames {
        fallbackNamesLock.lock()
        defer { fallbackNamesLock.unlock() }
        if let fallbackNamesStorage { return fallbackNamesStorage }
        let fallbackNames = ImageFallbackNames(image: image, headerAddress: headerAddress, slide: slide, textRange: textStart ..< textEnd)
        fallbackNamesStorage = fallbackNames
        return fallbackNames
    }

    /// The fallback names, when something has asked for them.
    var existingFallbackNames: ImageFallbackNames? {
        fallbackNamesLock.lock()
        defer { fallbackNamesLock.unlock() }
        return fallbackNamesStorage
    }

    /// The memory the table takes, with the fallback names read for it; see
    /// `ApproximateSize`. The names it points at belong to the image.
    var approximateByteCount: Int {
        var byteCount = ApproximateSize.of(starts) + ApproximateSize.of(primaryNameIndices) + ApproximateSize.of(primaryNames)
        byteCount += foldedNames.values.reduce(ApproximateSize.of(foldedNames)) { $0 + ApproximateSize.of($1) }
        byteCount += ApproximateSize.of(runtimeHelperStarts) + ApproximateSize.of(objectiveCStubSelectors) + ApproximateSize.of(symbolStubs)
        byteCount += ApproximateSize.of(symbolStubRanges) + ApproximateSize.of(referenceSlotRanges) + ApproximateSize.of(dataSegmentRanges)
        byteCount += ApproximateSize.of(segmentRanges) + ApproximateSize.of(dataInCodeRanges)
        return byteCount + (existingFallbackNames?.approximateByteCount ?? 0)
    }
}
