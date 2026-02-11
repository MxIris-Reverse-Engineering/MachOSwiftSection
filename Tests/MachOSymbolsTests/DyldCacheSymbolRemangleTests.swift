import Foundation
import Testing
@testable import Demangling
import MachOKit
import MachOFoundation
@testable import MachOTestingSupport
import Dependencies

@MainActor
protocol DemangleAndRemangleTests {
    func allSymbols() async throws -> [MachOSwiftSymbol]
    func mainTest() async throws
}

extension DemangleAndRemangleTests {
    func mainTest() async throws {
        let allSwiftSymbols = try await allSymbols()
        "Total Swift Symbols: \(allSwiftSymbols.count)".print()
//        await withTaskGroup { group in
            for symbol in allSwiftSymbols {
//                group.addTask {
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
//                }
            }
            
//            await group.waitForAll()
//        }
    }
}

@Suite
final class DyldCacheSymbolRemangleTests: DyldCacheSymbolTests, DemangleAndRemangleTests {
    @Test func main() async throws {
        try await mainTest()
    }

    @Test func demangleAsNode() async throws {
        let node = try Demangling.demangleAsNode("_$sSis15WritableKeyPathCy17RealityFoundation23PhysicallyBasedMaterialVAE9BaseColorVGTHTm")
//        try Demangling.mangleAsString(node).print()
        node.description.print()
    }
    
    @Test func stdlib_demangleNodeTree() async throws {
        let treeString = MachOTestingSupport.stdlib_demangleNodeTree("_$sSis15WritableKeyPathCy17RealityFoundation23PhysicallyBasedMaterialVAE9BaseColorVGTHTm")!
        treeString.print()
    }
}
