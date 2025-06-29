import Foundation
import Testing
import Demangle
import MachOKit
import MachOMacro
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport

@Suite(.serialized)
final class SymbolDemangleTests: DyldCacheTests {
    struct MachOSwiftSymbol {
        let imagePath: String
        let offset: Int
        let stringValue: String
    }

    @MainActor
    @Test func symbols() throws {
        let allSwiftSymbols = try allSymbols()
        print("Total Swift Symbols: \(allSwiftSymbols.count)")
        for symbol in allSwiftSymbols {
            let swiftStdlibDemangledName = stdlib_demangleName(symbol.stringValue)
            do {
                guard !symbol.stringValue.hasSuffix("$delayInitStub") else { continue }
                var demangler = Demangler(scalars: symbol.stringValue.unicodeScalars)
                let node = try demangler.demangleSymbol()
                let swiftSectionDemanlgedName = node.print()
                #expect(swiftStdlibDemangledName == swiftSectionDemanlgedName, "\(symbol.stringValue)")
            } catch {
                #expect(symbol.stringValue == swiftStdlibDemangledName)
                print(symbol)
                print(error)
            }
        }
    }
    
    #if !SILENT_TEST
    @Test func writeSwiftUISymbolsToDesktop() async throws {
        var string = ""
        let imageName: MachOImageName = .SwiftUI
        let symbols = try symbols(for: imageName)
        for symbol in symbols {
            let swiftStdlibDemangledName = stdlib_demangleName(symbol.stringValue)
            guard !symbol.stringValue.hasSuffix("$delayInitStub") else { continue }
            string += symbol.stringValue
            string += "\n"
            string += swiftStdlibDemangledName
            string += "\n"
            string += "\n"
        }
        try string.write(to: .desktopDirectory.appendingPathComponent("\(imageName.rawValue)-SwiftSymbols.txt"), atomically: true, encoding: .utf8)
    }
    #endif
    
    @Test func demangle() async throws {
        var demangler = Demangler(scalars: "_$s6Charts10ChartProxyV5value2at2asx_q_tSgSo7CGPointV_x_q_tmtAA9PlottableRzAaJR_r0_lF".unicodeScalars)
        let node = try demangler.demangleSymbol()
        node.print().print()
    }

    @Test func swiftSymbols() async throws {
        let symbols = try symbols(for: .SwiftUI)
        for symbol in symbols {
            var demangler = Demangler(scalars: symbol.stringValue.unicodeScalars)
            let node = try demangler.demangleSymbol()
            if let functionNode = node.children.first, functionNode.kind == .function {
                if let structureNode = functionNode.children.first, structureNode.kind == .structure {
                    node.print(using: .interface).print()
                    let typeNode = Node(kind: .global) {
                        Node(kind: .type, child: structureNode)
                    }
                    typeNode.print(using: .interface).print()
                }
            }
        }
    }

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
