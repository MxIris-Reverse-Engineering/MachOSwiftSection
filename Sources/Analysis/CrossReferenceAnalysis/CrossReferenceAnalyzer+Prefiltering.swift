import Foundation
import MachOKit

extension CrossReferenceAnalyzer {
    /// The images among `candidates` whose symbol table imports
    /// `symbolName` — the only ones that can call an exported function from
    /// outside its own image. A shared cache image keeps its undefined
    /// symbols even where the cache builder bound the calls directly.
    public func imageIndices(importing symbolName: String, among candidates: some Sequence<Int>) -> [Int] {
        symbolName.withCString { wantedName in
            candidates.filter { imageIndex in
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
                    if strcmp(symbols.stringBase.advanced(by: Int(entry.n_un.n_strx)), wantedName) == 0 { return true }
                }
                return false
            }
        }
    }

    /// The images among `candidates` whose `__objc_selrefs` reference
    /// `selector` — the only ones that can send it.
    public func imageIndices(referencingSelector selector: String, among candidates: some Sequence<Int>) -> [Int] {
        selector.withCString { wantedSelector in
            // The cache uniques selector strings; once one reference matched,
            // the same pointer is compared before any string.
            var matchedString: UInt?
            return candidates.filter { imageIndex in
                let image = images[imageIndex]
                guard let slide = image.vmaddrSlide,
                      let section = image.sections64.first(where: { $0.sectionName == "__objc_selrefs" }),
                      section.size > 0,
                      let slots = UnsafeRawPointer(bitPattern: Int(bitPattern: UInt(section.address)) &+ slide)
                else { return false }
                for slotIndex in 0 ..< section.size / 8 {
                    let string = UInt(slots.loadUnaligned(fromByteOffset: slotIndex * 8, as: UInt64.self) & 0x0000_7FFF_FFFF_FFFF)
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
