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
    
    @Test func symbols() async throws {
        for symbol in machOFileInCache.symbols where symbol.name.starts(with: "_$s") {
            do {
                var demangler = Demangler(scalars: symbol.name.unicodeScalars)
                _ = try demangler.demangleSymbol()
//                print("Successfully: \(symbol.name)")
            } catch {
                print("Failed: \(symbol.name)")
                print(error)
                print("\n")
            }
        }
    }
    
    @Test func demangle() async throws {
        var demangler = Demangler(scalars: "_$sSTsE10compactMapySayqd__Gqd__Sg7ElementQzKXEKlFSaySSG_7SwiftUI14ToolbarStorageV5EntryV2IDVTg503$s7d4UI13f115BridgeC11makeStorage33_558B6B1E48F37C8B0E16B128287879E0LL2in4from8strategyAA0C0O08LocationF0VAJ03BarS0O_SayAA0cF0V5H20VGxtFAR2IDVSgSSXEfU_AG0F0O08LocationG0VTf1cn_nTf4ngX_n".unicodeScalars)
        _ = try demangler.demangleSymbol()
    }
}
