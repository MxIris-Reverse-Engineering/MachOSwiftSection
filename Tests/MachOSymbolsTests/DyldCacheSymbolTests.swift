import Foundation
import Testing
@testable import Demangling
import MachOKit
import MachOFoundation
@testable import MachOTestingSupport
import Dependencies

struct MachOSwiftSymbol {
    let imagePath: String
    let offset: Int
    let stringValue: String
}

class DyldCacheSymbolTests: DyldCacheTests {
    

    func symbols(for machOImageNames: MachOImageName...) throws -> [MachOSwiftSymbol] {
        var symbols: [MachOSwiftSymbol] = []
        for machOImageName in machOImageNames {
            let machOFile = try #require(fullCache.machOFile(named: machOImageName))
            for symbol in machOFile.symbols where symbol.name.isSwiftSymbol {
                symbols.append(MachOSwiftSymbol(imagePath: machOFile.imagePath, offset: symbol.offset, stringValue: symbol.name))
            }
            for symbol in machOFile.exportedSymbols where symbol.name.isSwiftSymbol {
                if let offset = symbol.offset {
                    symbols.append(MachOSwiftSymbol(imagePath: machOFile.imagePath, offset: offset, stringValue: symbol.name))
                }
            }
        }

        return symbols
    }

    func allSymbols() throws -> [MachOSwiftSymbol] {
        var symbols: [MachOSwiftSymbol] = []
        for machOFile in fullCache.machOFiles() {
            for symbol in machOFile.symbols where symbol.name.isSwiftSymbol {
                symbols.append(MachOSwiftSymbol(imagePath: machOFile.imagePath, offset: symbol.offset, stringValue: symbol.name))
            }
            for symbol in machOFile.exportedSymbols where symbol.name.isSwiftSymbol {
                if let offset = symbol.offset {
                    symbols.append(MachOSwiftSymbol(imagePath: machOFile.imagePath, offset: offset, stringValue: symbol.name))
                }
            }
        }
        return symbols
    }
}
