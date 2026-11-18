import Foundation
import MachOKit

extension CodeImageSet {
    /// Where the images among `candidates` define a symbol named `name`
    /// (with its leading underscore), unslid, in image order: what each
    /// image's export trie and the defined entries of its symbol table say.
    ///
    /// Both, because neither holds every name: a shared cache image's symbol
    /// table may hold its local symbols alone, while the export trie names
    /// exports only — a standalone file's private functions are in its symbol
    /// table. A re-export, which names no address of the image, is left out.
    package func locations(ofSymbolNamed name: String, among candidates: some Sequence<Int>) -> [CodeLocation] {
        var locations: [CodeLocation] = []
        name.withCString { wantedName in
            for imageIndex in candidates {
                let image = images[imageIndex]
                let linkEdit = linkEdit(ofImageAt: imageIndex)
                var addresses: [UInt64] = []
                if let exportedSymbol = linkEdit.exportedSymbol(named: name), let offset = exportedSymbol.offset {
                    addresses.append(image.unslidAddress(atHeaderOffset: offset))
                }
                for symbolIndex in linkEdit.symbols.indices {
                    let entry = linkEdit.symbols[symbolIndex]
                    guard ImageLinkEdit.isDefinedInSection(entry), let symbolName = linkEdit.name(ofSymbolAt: symbolIndex),
                          strcmp(symbolName, wantedName) == 0, !addresses.contains(entry.n_value)
                    else { continue }
                    addresses.append(entry.n_value)
                }
                locations += addresses.map { CodeLocation(imageIndex: imageIndex, address: $0) }
            }
        }
        return locations
    }
}
