import Foundation
import MachOKit
import CrossReferenceCore

extension ObjCCodeReferenceRecognizer {
    /// How many selector references the selector prefilter reads at once.
    private static let selectorReferenceChunkSize = 256

    /// The images among `candidates` that can send `selector`: the ones whose
    /// `__objc_selrefs` reference it, and — for a selector a libobjc entry
    /// point sends, `init` for `objc_alloc_init` — the ones importing or
    /// defining such an entry point. An image may send `init` through
    /// `objc_alloc_init` alone, keeping no `init` selector reference.
    package func imageIndices(referencingSelector selector: String, among candidates: some Sequence<Int>) -> [Int] {
        let candidates = Array(candidates)
        var entryPointSenders = Set<Int>()
        let entryPointSymbols = MessageSendEntryPoints.symbols(sending: selector)
        if !entryPointSymbols.isEmpty {
            entryPointSenders.formUnion(images.imageIndices(importingAnyOf: entryPointSymbols, among: candidates))
            entryPointSenders.formUnion(runtimeFunctions.messageSendEntryPoints.filter { $0.value.contains(selector) }.map(\.key.imageIndex))
        }
        let memory = images.memory
        return selector.withCString { wantedSelector in
            // The cache uniques selector strings; once one reference matched,
            // the same pointer is compared before any string.
            var matchedString: UInt?
            return candidates.filter { imageIndex in
                if entryPointSenders.contains(imageIndex) { return true }
                let image = images.images[imageIndex]
                guard let slide = image.vmaddrSlide,
                      let section = image.sections64.first(where: { $0.sectionName == "__objc_selrefs" }),
                      section.size > 0
                else { return false }
                let slots = UInt(bitPattern: Int(bitPattern: UInt(section.address)) &+ slide)
                let slotCount = section.size / 8
                // Read in chunks: most images that send it have a match among
                // their first slots, and stop there.
                for chunkStart in stride(from: 0, to: slotCount, by: Self.selectorReferenceChunkSize) {
                    let strings = memory.pointers(inSlotsAt: slots &+ UInt(chunkStart * 8), count: min(Self.selectorReferenceChunkSize, slotCount - chunkStart))
                    let stringPointers = memory.readablePointers(at: strings)
                    for (string, stringPointer) in zip(strings, stringPointers) {
                        if string == matchedString { return true }
                        guard let pointer = stringPointer?.assumingMemoryBound(to: CChar.self) else { continue }
                        if strcmp(pointer, wantedSelector) == 0 {
                            matchedString = string
                            return true
                        }
                    }
                }
                return false
            }
        }
    }

    /// Where the image at `imageIndex` defines a class named `name`: one
    /// location, or none. The first query on an image reads the names of all
    /// its classes.
    package func classLocations(named name: String, inImageAt imageIndex: Int) -> [CodeLocation] {
        classIndex(ofImageAt: imageIndex).classLocations(named: name)
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
    /// symbols, so every image that can bind to its image counts too, unless
    /// `includingSwiftLinkage` is false — for a class known to export no
    /// Swift symbol.
    package func imageIndices(referencingClassAt classLocation: CodeLocation, among candidates: some Sequence<Int>, includingSwiftLinkage: Bool) -> [Int] {
        let definer = classLocation.imageIndex
        let image = images.images[definer]
        let objectAddresses = Set(classIndex(ofImageAt: definer).objectAddresses(ofClassAt: classLocation))
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
        let importedNames = names.sorted() + images.reexportedNames(ofSymbolsNamed: names.sorted(), inImageAt: definer)
        var result = Set(images.imageIndices(importingAnyOf: importedNames, among: candidates))
        if candidates.contains(definer) { result.insert(definer) }
        // Swift code reaches a Swift class through its metadata symbols, which
        // few cache images keep among their undefined symbols.
        if includingSwiftLinkage, classIndex(ofImageAt: definer).isSwiftClass(at: classLocation) {
            result.formUnion(images.imageIndices(linkingImageAt: definer, among: candidates))
        }
        return result.sorted()
    }
}
