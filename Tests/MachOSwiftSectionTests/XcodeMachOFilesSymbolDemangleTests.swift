import Foundation
import Testing
@testable import Demangle
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import Dependencies

@Suite(.serialized)
final class XcodeMachOFilesSymbolDemangleTests {
    struct MachOSwiftSymbol {
        let imagePath: String
        let offset: Int
        let stringValue: String
    }

    @MainActor
    @Test func symbols() throws {
        let allSwiftSymbols = try allSymbols()
        "Total Swift Symbols: \(allSwiftSymbols.count)".print()
        for symbol in allSwiftSymbols {
            let swiftStdlibDemangledName = stdlib_demangleName(symbol.stringValue)
            do {
                let node = try demangleAsNode(symbol.stringValue)
                let swiftSectionDemanlgedName = node.print()
                #expect(swiftStdlibDemangledName == swiftSectionDemanlgedName, "\(symbol.stringValue)")
            } catch {
                #expect(symbol.stringValue == swiftStdlibDemangledName)
                #if !SILENT_TEST
                print(symbol)
                #endif
                error.print()
            }
        }
    }

    private func allSymbols() throws -> [MachOSwiftSymbol] {
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
