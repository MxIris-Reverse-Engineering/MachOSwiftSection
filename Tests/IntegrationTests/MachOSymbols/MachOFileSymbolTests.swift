import Foundation
import Testing
@_spi(Internals) import SwiftSymbols
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

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
        
//        for symbol in SwiftSymbolIndexStore.shared.allSymbols(in: machOFile) {
//            symbol.demangledNode.print().print()
//        }
        
        let duration = ContinuousClock().measure {
            _ = SwiftSymbolIndexStore.shared.allSymbols(in: machOFile)
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
        
//        for symbol in SwiftSymbolIndexStore.shared.allSymbols(in: machOFile) {
//            symbol.demangledNode.print().print()
//        }
        
        let duration = ContinuousClock().measure {
            _ = SwiftSymbolIndexStore.shared.allSymbols(in: machOImage)
        }
        print(duration)
        
    }
}
