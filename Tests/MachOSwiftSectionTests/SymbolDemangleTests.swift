import Foundation
import Testing
import Demangle
import MachOKit
import MachOMacro
import MachOFoundation
@testable import MachOSwiftSection
import MachOTestingSupport

@Suite(.serialized)
struct SymbolDemangleTests {
    let mainCache: DyldCache

    let subCache: DyldCache

    init() async throws {
        self.mainCache = try DyldCache(path: .current)
        self.subCache = try required(mainCache.subCaches?.first?.subcache(for: mainCache))
    }

    struct MachOSwiftSymbol {
        let imagePath: String
        let offset: Int
        let stringValue: String
    }

    @MainActor
    @Test func symbols() throws {
        let allSwiftSymbols = try allSymbols()
        print("Total Swift Symbols: \(allSwiftSymbols.count)")
        for symbol in allSwiftSymbols where symbol.stringValue.starts(with: "_$s") {
            guard !symbol.stringValue.hasSuffix("$delayInitStub") else { continue }
            var demangler = Demangler(scalars: symbol.stringValue.unicodeScalars)
            let node = try demangler.demangleSymbol()
            let swiftStdlibDemangledName = stdlib_demangleName(symbol.stringValue)
            let swiftSectionDemanlgedName = node.print()
            #expect(swiftStdlibDemangledName == swiftSectionDemanlgedName, "\(symbol.stringValue)")
        }
    }

    @Test func writeMangledNameToDesktop() async throws {
        let symbols = try symbols(for: .AppKit, .SwiftUI, .SwiftUICore, .Foundation, .UIKitCore, .AttributeGraph)
        let mangledNames = symbols.filter { $0.stringValue.starts(with: "_$s") }.map(\.stringValue).joined(separator: "\n")
        try mangledNames.write(to: .desktopDirectory.appendingPathComponent("MangledSymbols.txt"), atomically: true, encoding: .utf8)
    }

    @MainActor
    @Test func writeDemangledNameToDesktop() async throws {
        let symbols = try symbols(for: .AppKit, .SwiftUI, .SwiftUICore, .Foundation, .UIKitCore, .AttributeGraph)
        let demangledNames = try symbols.filter { $0.stringValue.starts(with: "_$s") }.map { symbol in
            var demangler = Demangler(scalars: symbol.stringValue.unicodeScalars)
            let node = try demangler.demangleSymbol()
            return node.print(using: .interface)
        }.joined(separator: "\n")
        try demangledNames.write(to: .desktopDirectory.appendingPathComponent("DemangledSymbols.txt"), atomically: true, encoding: .utf8)
    }

    @Test func demangle() async throws {
        var demangler = Demangler(scalars: "_$s7SwiftUI22FinishLaunchTestActionV14callAsFunctionyyF".unicodeScalars)
        let node = try demangler.demangleSymbol()
        node.print().print()
    }

    private func symbols(for machOImageNames: MachOImageName...) throws -> [MachOSymbol] {
        try (machOImageNames.flatMap { try (required(mainCache.machOFile(named: $0))).symbols.map { MachOSymbol(offset: $0.offset, stringValue: $0.name) } }) +
            (machOImageNames.flatMap { try (required(mainCache.machOFile(named: $0))).exportedSymbols.compactMap { symbol in symbol.offset.map { MachOSymbol(offset: $0, stringValue: symbol.name) } } })
    }

    private func allSymbols() throws -> [MachOSwiftSymbol] {
        var symbols: [MachOSwiftSymbol] = []
        for machOFile in Array(mainCache.machOFiles()) + Array(subCache.machOFiles()) {
            for symbol in machOFile.symbols {
                if symbol.name.isSwiftSymbol {
                    symbols.append(MachOSwiftSymbol(imagePath: machOFile.imagePath, offset: symbol.offset, stringValue: symbol.name))
                }
            }
            for symbol in machOFile.exportedSymbols {
                if let offset = symbol.offset, symbol.name.isSwiftSymbol {
                    symbols.append(MachOSwiftSymbol(imagePath: machOFile.imagePath, offset: offset, stringValue: symbol.name))
                }
            }
        }
        return symbols
    }
}

extension String {
    var isSwiftSymbol: Bool {
        getManglingPrefixLength(unicodeScalars) > 0
    }
}
