import Foundation
import Testing
@_spi(Internals) import MachOSymbols
@testable import MachOSwiftSection
@testable import MachOTestingSupport

final class MachOFileSymbolTests: MachOFileTests, @unchecked Sendable {
    override class var fileName: MachOFileName { .iOS_18_5_Simulator_SwiftUI }

    @MainActor
    @Test func allSymbols() async throws {
//        for symbol in machOFile.symbols(for: 20942616) {
//            print(symbol.name)
//        }
        
//        for symbol in machOFile.symbols {
//            symbol.name.print()
//        }
        
//        for symbol in SymbolIndexStore.shared.allSymbols(in: machOFile) {
//            symbol.demangledNode.print().print()
//        }
        
        let duration = ContinuousClock().measure {
            _ = SymbolIndexStore.shared.allSymbols(in: machOFile)
        }
        print(duration)
        
    }
}

final class MachOImageSymbolTests: MachOImageTests, @unchecked Sendable {
    override class var imageName: MachOImageName { .SwiftUI }

    @MainActor
    @Test func allSymbols() async throws {
//        for symbol in machOFile.symbols(for: 20942616) {
//            print(symbol.name)
//        }
        
//        for symbol in machOFile.symbols {
//            symbol.name.print()
//        }
        
//        for symbol in SymbolIndexStore.shared.allSymbols(in: machOFile) {
//            symbol.demangledNode.print().print()
//        }
        
        let duration = ContinuousClock().measure {
            _ = SymbolIndexStore.shared.allSymbols(in: machOImage)
        }
        print(duration)
        
    }
}
