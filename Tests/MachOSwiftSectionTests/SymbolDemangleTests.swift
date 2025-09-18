import Foundation
import Testing
@testable import Demangle
import MachOKit
import MachOMacro
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport

@Suite(.serialized)
final class DyldCacheSymbolDemangleTests: DyldCacheTests {
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

    #if !SILENT_TEST
    @MainActor
    @Test func writeSymbolsToDesktop() async throws {
        var string = ""
        let imageName: MachOImageName = .SwiftUICore
        let symbols = try symbols(for: imageName)
        for symbol in symbols {
            let node = try demangleAsNode(symbol.stringValue)
            guard !symbol.stringValue.hasSuffix("$delayInitStub") else { continue }
            string += "---------------------------------------"
            string += "\n"
            string += symbol.stringValue
            string += "\n"
            string += node.print(using: .default)
            string += "\n"
            string += node.description
            string += "\n"
            string += "---------------------------------------"
            string += "\n"
            string += "\n"
        }
        try string.write(to: .desktopDirectory.appending(components: "\(imageName.rawValue)-SwiftSymbolsExpand.txt"), atomically: true, encoding: .utf8)
    }

    @Test func demangle() async throws {
        var demangler = Demangler(scalars: "_$s6Charts10ChartProxyV5value2at2asx_q_tSgSo7CGPointV_x_q_tmtAA9PlottableRzAaJR_r0_lF".unicodeScalars)
        let node = try demangler.demangleSymbol()
        node.print().print()
    }
    #endif

    private func symbols(for machOImageNames: MachOImageName...) throws -> [MachOSwiftSymbol] {
        var symbols: [MachOSwiftSymbol] = []
        for machOImageName in machOImageNames {
            let machOFile = try required(mainCache.machOFile(named: machOImageName))
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

    private func allSymbols() throws -> [MachOSwiftSymbol] {
        var symbols: [MachOSwiftSymbol] = []
        for machOFile in Array(mainCache.machOFiles()) + Array(subCache.machOFiles()) {
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

#if !SILENT_TEST
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
        for machOFile in try XcodeMachOFileName.allCases.compactMap({ try File.loadFromFile(url: .init(fileURLWithPath: $0.path)).machOFiles.first }) {
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
#endif
