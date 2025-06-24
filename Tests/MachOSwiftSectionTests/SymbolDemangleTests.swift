import Foundation
import Testing
import Demangle
import MachOKit
import MachOMacro
import MachOFoundation
@testable import MachOSwiftSection

@Suite(.serialized)
struct SymbolDemangleTests {
    let mainCache: DyldCache

    let subCache: DyldCache

    let machOFileInMainCache: MachOFile

    let machOFileInSubCache: MachOFile

    let machOFileInCache: MachOFile

    init() async throws {
        self.mainCache = try DyldCache(path: .current)
        self.subCache = try required(mainCache.subCaches?.first?.subcache(for: mainCache))

        self.machOFileInMainCache = try #require(mainCache.machOFile(named: .SwiftUI))
        self.machOFileInSubCache = if #available(macOS 15.5, *) {
            try #require(subCache.machOFile(named: .CodableSwiftUI))
        } else {
            try #require(subCache.machOFile(named: .UIKitCore))
        }

        self.machOFileInCache = try #require(mainCache.machOFile(named: .SwiftUICore))
    }

    @MainActor
    @Test func symbols() throws {
        for symbol in Array(machOFileInMainCache.symbols) + Array(machOFileInSubCache.symbols) + Array(machOFileInCache.symbols) where symbol.name.starts(with: "_$s") {
            var demangler = Demangler(scalars: symbol.name.unicodeScalars)
            let node = try demangler.demangleSymbol()
            let swiftStdlibDemangledName = stdlib_demangleName(symbol.name)
            let swiftSectionDemanlgedName = node.print()
            #expect(swiftStdlibDemangledName == swiftSectionDemanlgedName, "\(symbol.name)")
        }
    }

    @Test func demangle() async throws {
        var demangler = Demangler(scalars: "_$ss5Error_pIgzo_ytsAA_pIegrzo_TRTA".unicodeScalars)
        let node = try demangler.demangleSymbol()
        node.print().print()
    }
}
