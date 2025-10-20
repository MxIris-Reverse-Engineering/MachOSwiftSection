import Foundation
import Testing
@testable import Demangling
import MachOKit
import MachOFoundation
@testable import MachOTestingSupport
import Dependencies

protocol DemangleAndRemangleTests {
    func allSymbols() throws ->[MachOSwiftSymbol]
    @MainActor func mainTest() throws
}

extension DemangleAndRemangleTests {
    func mainTest() throws {
        let allSwiftSymbols = try allSymbols()
        "Total Swift Symbols: \(allSwiftSymbols.count)".print()
        for symbol in allSwiftSymbols {
            let swiftStdlibDemangledName = stdlib_demangleName(symbol.stringValue)
            do {
                let node = try demangleAsNode(symbol.stringValue)
                let swiftSectionDemanlgedName = node.print()
                #expect(swiftStdlibDemangledName == swiftSectionDemanlgedName, "\(symbol.stringValue)")
                let remangledString = try Demangling.mangleAsString(node)
                #expect(remangledString == symbol.stringValue)
            } catch {
                if symbol.stringValue != swiftStdlibDemangledName {
                    Issue.record(error)
                    symbol.stringValue.print()
                }
            }
        }
    }
}

@Suite
final class DyldCacheSymbolRemangleTests: DyldCacheSymbolTests, DemangleAndRemangleTests {
    @MainActor
    @Test func symbols() throws {
        try mainTest()
    }
    
    @Test func test() async throws {
        let node = try demangleAsNode("_$sSis15WritableKeyPathCy17RealityFoundation23PhysicallyBasedMaterialVAE9BaseColorVGTHTm")
//        try Demangling.mangleAsString(node).print()
        node.description.print()
    }
}
