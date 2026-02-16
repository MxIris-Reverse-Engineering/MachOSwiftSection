import Foundation
import Testing
@testable import Demangling
import MachOKit
import MachOFoundation
@testable import MachOTestingSupport
import Dependencies

@Suite(.serialized)
final class XcodeMachOFilesSymbolDemanglingTests: DemanglingTests {
    @MainActor
    @Test func symbols() async throws {
        try await mainTest()
    }

    func allSymbols() throws -> [MachOSwiftSymbol] {
        guard FileManager.default.fileExists(atPath: "/Applications/Xcode.app") else { return [] }
        var symbols: [MachOSwiftSymbol] = []
        for machOFile in try XcodeMachOFileName.allCases.compactMap({ try File.loadFromFile(url: $0.url).machOFiles.first }) {
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
