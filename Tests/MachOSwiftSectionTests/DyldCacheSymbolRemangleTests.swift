import Foundation
import Testing
@testable import Demangle
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import Dependencies

@Suite
final class DyldCacheSymbolRemangleTests: DyldCacheSymbolTests {
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
                let remangledString = try Demangle.mangleAsString(node)
                #expect(remangledString == symbol.stringValue)
            } catch {
                if symbol.stringValue != swiftStdlibDemangledName {
                    Issue.record(error)
                    symbol.stringValue.print()
                }
            }
        }
    }
    
    @Test func test() async throws {
        let node = try demangleAsNode("_$sSis15WritableKeyPathCy17RealityFoundation23PhysicallyBasedMaterialVAE9BaseColorVGTHTm")
//        try Demangle.mangleAsString(node).print()
        node.description.print()
    }
}
