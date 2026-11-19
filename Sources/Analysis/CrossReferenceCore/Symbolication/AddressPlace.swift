import Foundation
import MachOKit
import ARM64InstructionDecoding

/// Where an unslid address lies, as far as the core can tell without any
/// language: in which image, segment and section, and what the section
/// holds there — a function's body, a stub, a pointer slot, a string — or
/// nothing any image maps. What a slot or a stub means to Objective-C or
/// Swift is the language layers' to add.
package struct AddressPlace: Sendable {
    package enum Content: Sendable {
        /// Inside a function's body: the function's index in the image's
        /// function table.
        case function(index: Int)
        /// One of the image's own symbol stubs, or a trampoline between
        /// images: every trampoline passed through from the address on, and
        /// where the chain ends.
        case trampoline(hops: [UInt64], target: ResolvedCallTarget)
        /// A section of code that is no `__text` and no symbol stub section —
        /// `__objc_stubs` — whose meaning a language layer knows.
        case otherCode
        /// A pointer-sized slot, and what it holds.
        case slot(SlotContent?)
        case string(StringLiteralReference)
        /// None of the above: the nearest symbol at or below the address in
        /// its image, when there is one.
        case data(nearestSymbol: (name: String, offset: UInt64)?)
        /// No image maps the address.
        case unmapped
    }

    /// The image the address lies in; `nil` between images or nowhere.
    package let imageIndex: Int?
    package let segmentName: String?
    package let sectionName: String?
    package let content: Content
}

extension CodeImageSet {
    /// The sections whose every pointer-sized word is a pointer slot, by
    /// name: the GOT and lazy pointers, and the language layers' reference
    /// sections, which they name to the core.
    package static let languageFreeSlotSectionNames: Set<String> = ["__got", "__auth_got", "__la_symbol_ptr", "__nl_symbol_ptr", "__auth_ptr"]

    /// What lies at the unslid `address`.
    ///
    /// Unslid addresses are unique within one shared cache; standalone
    /// files each keep their own, so two of them may share one — the first
    /// image holding the address is taken, unless `imageIndex` names one.
    /// `slotSectionNames` lists the sections, besides the GOT and the lazy
    /// pointers, a language layer reads as pointer slots.
    package func place(ofUnslid address: UInt64, inImageAt requestedImageIndex: Int? = nil, slotSectionNames: Set<String> = []) -> AddressPlace {
        guard let imageIndex = requestedImageIndex ?? imageIndex(holdingUnslid: address) else {
            return placeOutsideEveryImage(unslid: address)
        }
        let image = images[imageIndex]
        let segment = image.reader.segments64.first { address >= UInt64($0.layout.vmaddr) && address < UInt64($0.layout.vmaddr) + UInt64($0.layout.vmsize) }
        let section = image.reader.sections64.first { address >= UInt64($0.address) && address < UInt64($0.address) + UInt64($0.size) }
        let place = { (content: AddressPlace.Content) in
            AddressPlace(imageIndex: imageIndex, segmentName: segment?.segmentName, sectionName: section?.sectionName, content: content)
        }
        guard segment != nil else { return place(.unmapped) }
        // Kept: an address is rarely asked about alone, and naming its
        // function needs the table again.
        let table = functionTable(ofImageAt: imageIndex)
        if address >= table.textStart, address < table.textEnd, let index = table.functionIndex(containing: address) {
            return place(.function(index: index))
        }
        if table.symbolStubRanges.contains(where: { $0.contains(address) }) {
            // A stub's first instruction: the chain from there.
            let stubAddress = table.symbolStubs.keys.filter { $0 <= address }.max() ?? address
            let resolved = CallTargetResolver(images: self, table: table).resolveWithRoute(stubAddress)
            return place(.trampoline(hops: [stubAddress], target: resolved.target))
        }
        if let section {
            if section.flags.type == .cstring_literals || section.sectionName == "__cfstring" {
                if let literal = stringLiteral(at: address, in: table) { return place(.string(literal)) }
            }
            if Self.languageFreeSlotSectionNames.contains(section.sectionName) || slotSectionNames.contains(section.sectionName) {
                let slot = address & ~UInt64(7)
                return place(.slot(memory.slotContent(at: image.runtimeAddress(ofUnslid: slot))))
            }
            if section.segmentName == "__TEXT", section.flags.attributes.contains(.pure_instructions) || section.flags.attributes.contains(.some_instructions) {
                return place(.otherCode)
            }
        }
        return place(.data(nearestSymbol: nearestSymbol(toUnslid: address, inImageAt: imageIndex)))
    }

    /// The image whose segments hold the unslid `address`: tried at every
    /// slide the set's images use, the shared cache's first.
    private func imageIndex(holdingUnslid address: UInt64) -> Int? {
        var triedSlides = Set<Int>()
        for image in images where triedSlides.insert(image.slide).inserted {
            let runtimeAddress = image.runtimeAddress(ofUnslid: address)
            if let imageIndex = imageIndex(containingRuntimeAddress: runtimeAddress) ?? imageIndex(containingDataAddress: runtimeAddress),
               images[imageIndex].slide == image.slide {
                return imageIndex
            }
        }
        return nil
    }

    /// Between images: a trampoline the cache builder put there, a slot of
    /// the GOT pool the cache keeps outside every image, or nothing mapped.
    private func placeOutsideEveryImage(unslid address: UInt64) -> AddressPlace {
        let slide = images.first?.slide ?? 0
        let runtimeAddress = UInt(bitPattern: Int(bitPattern: UInt(address)) &+ slide)
        if isExecutable(runtimeAddress: runtimeAddress, length: UInt(ARM64Trampoline.maximumInstructionCount * 4)) {
            var hops: [UInt64] = []
            var current = runtimeAddress
            var target: ResolvedCallTarget = .unrecognized
            while hops.count < 8 {
                if let location = location(ofRuntimeAddress: current) {
                    target = .function(location)
                    break
                }
                guard isExecutable(runtimeAddress: current, length: UInt(ARM64Trampoline.maximumInstructionCount * 4)),
                      let pointer = memory.bytes(at: current, length: ARM64Trampoline.maximumInstructionCount * 4)?.baseAddress,
                      let trampoline = ARM64Trampoline(readingAt: pointer, address: UInt64(current))
                else { break }
                hops.append(UInt64(bitPattern: Int64(Int(bitPattern: current) &- slide)))
                switch trampoline {
                case .selectorStub(let constant, _):
                    target = .registerSettingTrampoline(register: 1, value: constant)
                    return AddressPlace(imageIndex: nil, segmentName: nil, sectionName: nil, content: .trampoline(hops: hops, target: target))
                case .computed(let next):
                    current = UInt(next)
                case .slotLoad(let slot):
                    guard let next = memory.pointer(at: UInt(slot)), next != 0 else {
                        return AddressPlace(imageIndex: nil, segmentName: nil, sectionName: nil, content: .trampoline(hops: hops, target: .unrecognized))
                    }
                    current = next
                }
            }
            if !hops.isEmpty {
                return AddressPlace(imageIndex: nil, segmentName: nil, sectionName: nil, content: .trampoline(hops: hops, target: target))
            }
        }
        if isSlotOutsideEveryImage(runtimeAddress: runtimeAddress) {
            return AddressPlace(imageIndex: nil, segmentName: nil, sectionName: nil, content: .slot(memory.slotContent(at: runtimeAddress & ~UInt(7))))
        }
        return AddressPlace(imageIndex: nil, segmentName: nil, sectionName: nil, content: .unmapped)
    }

    /// The string literal starting at — or, for a C string, running through
    /// — the unslid `address`.
    private func stringLiteral(at address: UInt64, in table: ImageFunctionTable) -> StringLiteralReference? {
        if let section = table.cStringSectionRanges.first(where: { $0.contains(address) }),
           let bytes = memory.bytes(at: table.runtimeAddress(ofUnslid: address), length: Int(section.upperBound - address)),
           let terminator = bytes.firstIndex(of: 0) {
            return .cString(String(decoding: bytes[..<terminator], as: UTF8.self))
        }
        guard let section = table.constantStringSectionRanges.first(where: { $0.contains(address) }) else { return nil }
        let structure = table.runtimeAddress(ofUnslid: address - (address - section.lowerBound) % 32)
        guard let flags = memory.load(UInt64.self, at: structure &+ 8),
              let characters = memory.pointer(at: structure &+ 16),
              let length = memory.load(UInt64.self, at: structure &+ 24),
              length < 1 << 24
        else { return nil }
        if flags & 0x10 != 0 {
            guard let bytes = memory.bytes(at: characters, length: Int(length) * 2) else { return nil }
            return .constantString(String(decoding: (0 ..< Int(length)).map { bytes.loadUnaligned(fromByteOffset: $0 * 2, as: UInt16.self) }, as: UTF16.self))
        }
        guard let bytes = memory.bytes(at: characters, length: Int(length)) else { return nil }
        return .constantString(String(decoding: bytes, as: UTF8.self))
    }

    /// The nearest symbol at or below the unslid `address` in the image —
    /// from its symbol table and its export trie — and how far past it the
    /// address lies.
    package func nearestSymbol(toUnslid address: UInt64, inImageAt imageIndex: Int) -> (name: String, offset: UInt64)? {
        let image = images[imageIndex]
        let linkEdit = linkEdit(ofImageAt: imageIndex)
        var best: (address: UInt64, name: String)?
        func isCloser(_ candidate: UInt64) -> Bool {
            candidate <= address && best.map { candidate > $0.address } ?? true
        }
        for symbolIndex in linkEdit.symbols.indices {
            let entry = linkEdit.symbols[symbolIndex]
            guard ImageLinkEdit.isDefinedInSection(entry), isCloser(entry.n_value), let name = linkEdit.name(ofSymbolAt: symbolIndex) else { continue }
            best = (entry.n_value, String(cString: name))
        }
        for symbol in image.reader.exportedSymbols {
            guard let offset = symbol.offset else { continue }
            let symbolAddress = image.unslidAddress(atHeaderOffset: offset)
            if isCloser(symbolAddress) { best = (symbolAddress, symbol.name) }
        }
        return best.map { ($0.name, address - $0.address) }
    }
}
