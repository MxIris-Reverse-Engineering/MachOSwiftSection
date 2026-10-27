import Foundation
import MachOKit

extension CrossReferenceAnalyzer {
    /// The images among `candidates` whose symbol table imports
    /// `symbolName` — for a C function or an Objective-C class, the ones that
    /// reach it by that name: a shared cache image keeps those undefined
    /// symbols even where the cache builder bound the calls directly.
    ///
    /// Not every image that can reach it. Another image may re-export it
    /// under a name of its own, which its callers import instead
    /// (`reexportedNames(ofSymbolsNamed:inImageAt:)`). And not for a Swift
    /// symbol: only 245 of the macOS 27.2 cache's 4,113 images keep any among
    /// their undefined symbols, so this finds a few of the images that use
    /// one. `imageIndices(callingFunctionAt:symbolNames:among:)` covers both.
    public func imageIndices(importing symbolName: String, among candidates: some Sequence<Int>) -> [Int] {
        imageIndices(importingAnyOf: [symbolName], among: candidates)
    }

    /// The images among `candidates` whose symbol table imports any of
    /// `symbolNames`.
    public func imageIndices(importingAnyOf symbolNames: [String], among candidates: some Sequence<Int>) -> [Int] {
        guard !symbolNames.isEmpty else { return [] }
        let wantedNames = symbolNames.map { strdup($0)! }
        defer { wantedNames.forEach { free($0) } }
        return candidates.filter { imageIndex in
            guard let symbols = images[imageIndex].symbols64 else { return false }
            var range = 0 ..< symbols.numberOfSymbols
            if let dynamicSymbols = images[imageIndex].loadCommands.info(of: LoadCommand.dysymtab) {
                let first = Int(dynamicSymbols.iundefsym)
                let count = Int(dynamicSymbols.nundefsym)
                if first + count <= symbols.numberOfSymbols { range = first ..< first + count }
            }
            for symbolIndex in range {
                let entry = symbols.symbols[symbolIndex]
                // An external, undefined symbol.
                guard entry.n_type & 0xE0 == 0, entry.n_type & 0x0E == 0, entry.n_type & 0x01 != 0 else { continue }
                let name = symbols.stringBase.advanced(by: Int(entry.n_un.n_strx))
                for wantedName in wantedNames where strcmp(name, wantedName) == 0 { return true }
            }
            return false
        }
    }

    /// The images among `candidates` that can send `selector`: the ones whose
    /// `__objc_selrefs` reference it, and — for a selector a libobjc entry
    /// point sends, `init` for `objc_alloc_init` — the ones importing or
    /// defining such an entry point. An image may send `init` through
    /// `objc_alloc_init` alone, with no selector reference to it.
    public func imageIndices(referencingSelector selector: String, among candidates: some Sequence<Int>) -> [Int] {
        let candidates = Array(candidates)
        var entryPointSenders = Set<Int>()
        let entryPointSymbols = MessageSendEntryPoints.symbols(sending: selector)
        if !entryPointSymbols.isEmpty {
            entryPointSenders.formUnion(imageIndices(importingAnyOf: entryPointSymbols, among: candidates))
            entryPointSenders.formUnion(messageSendEntryPoints.filter { $0.value.contains(selector) }.map(\.key.imageIndex))
        }
        return selector.withCString { wantedSelector in
            // The cache uniques selector strings; once one reference matched,
            // the same pointer is compared before any string.
            var matchedString: UInt?
            return candidates.filter { imageIndex in
                if entryPointSenders.contains(imageIndex) { return true }
                let image = images[imageIndex]
                guard let slide = image.vmaddrSlide,
                      let section = image.sections64.first(where: { $0.sectionName == "__objc_selrefs" }),
                      section.size > 0,
                      let slots = UnsafeRawPointer(bitPattern: Int(bitPattern: UInt(section.address)) &+ slide)
                else { return false }
                for slotIndex in 0 ..< section.size / 8 {
                    let string = StoredPointer.address(in: slots.loadUnaligned(fromByteOffset: slotIndex * 8, as: UInt64.self))
                    if string == matchedString { return true }
                    guard let pointer = UnsafePointer<CChar>(bitPattern: string) else { continue }
                    if strcmp(pointer, wantedSelector) == 0 {
                        matchedString = string
                        return true
                    }
                }
                return false
            }
        }
    }
}

extension CrossReferenceAnalyzer {
    /// Where the image at `imageIndex` defines a class named `name`: one
    /// location, or none. The first query on an image reads the names of all
    /// its classes.
    public func objectiveCClassLocations(named name: String, inImageAt imageIndex: Int) -> [CodeLocation] {
        objectiveCClassIndex(ofImageAt: imageIndex).classLocations(named: name)
    }

    /// The images among `candidates` that can reference the Objective-C class
    /// at `classLocation`: the image defining it, and the images importing a
    /// symbol that names the class or its metaclass.
    ///
    /// Most images reach another image's class as `_OBJC_CLASS_$_<name>`, but
    /// not all: a block literal's `isa` is `__NSConcreteStackBlock`, an XPC
    /// type is `__xpc_type_dictionary`. So every symbol the defining image
    /// has at either address counts. A Swift class is reached through Swift
    /// symbols as well, which the cache drops from its images' undefined
    /// symbols, so every image that can bind to its image counts too.
    public func imageIndices(referencingObjectiveCClassAt classLocation: CodeLocation, among candidates: some Sequence<Int>) -> [Int] {
        imageIndices(referencingObjectiveCClassAt: classLocation, among: candidates, includingSwiftLinkage: true)
    }

    /// `includingSwiftLinkage` false leaves out the images linking a Swift
    /// class's image, for a class known to export no Swift symbol — see
    /// `imageIndices(referencingSwiftType:among:)`.
    func imageIndices(referencingObjectiveCClassAt classLocation: CodeLocation, among candidates: some Sequence<Int>, includingSwiftLinkage: Bool) -> [Int] {
        let definer = classLocation.imageIndex
        let image = images[definer]
        let objectAddresses = Set(objectiveCClassIndex(ofImageAt: definer).objectAddresses(ofClassAt: classLocation))
        var names = Set<String>()
        if let symbols = image.symbols64 {
            for symbolIndex in 0 ..< symbols.numberOfSymbols {
                let entry = symbols.symbols[symbolIndex]
                // A symbol defined in a section of this image.
                guard entry.n_type & 0xE0 == 0, entry.n_type & 0x0E == 0x0E, objectAddresses.contains(entry.n_value) else { continue }
                names.insert(String(cString: symbols.stringBase.advanced(by: Int(entry.n_un.n_strx))))
            }
        }
        if let headerAddress = image.segments64.first(where: { $0.segmentName == "__TEXT" }).map({ UInt64($0.layout.vmaddr) }) {
            for symbol in image.exportedSymbols {
                guard let offset = symbol.offset,
                      objectAddresses.contains(UInt64(bitPattern: Int64(bitPattern: headerAddress) &+ Int64(offset)))
                else { continue }
                names.insert(symbol.name)
            }
        }
        let candidates = Array(candidates)
        // A class re-exported under another name is imported by that name:
        // UIFoundation's `NSEmojiImageAsset` is CoreText's `CTEmojiImageAsset`.
        let importedNames = names.sorted() + reexportedNames(ofSymbolsNamed: names.sorted(), inImageAt: definer)
        var result = Set(imageIndices(importingAnyOf: importedNames, among: candidates))
        if candidates.contains(definer) { result.insert(definer) }
        // Swift code reaches a Swift class through its metadata symbols, which
        // few cache images keep among their undefined symbols.
        if includingSwiftLinkage, objectiveCClassIndex(ofImageAt: definer).isSwiftClass(at: classLocation) {
            result.formUnion(imageIndices(linkingImageAt: definer, among: candidates))
        }
        return result.sorted()
    }
}
