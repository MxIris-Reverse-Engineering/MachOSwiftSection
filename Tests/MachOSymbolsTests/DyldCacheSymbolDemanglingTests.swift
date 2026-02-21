import Foundation
import Testing
import Dependencies
import PowerAssert
import MachOKit
import MachOFoundation
@testable import Demangling
@testable import MachOTestingSupport

@Suite
final class DyldCacheSymbolDemanglingTests: DyldCacheSymbolTests, DemanglingTests {
    @Test func main() async throws {
        try await mainTest()
    }

    @Test func demangle() async throws {
        let node = try Demangling.demangleAsNode("_$sSis15WritableKeyPathCy17RealityFoundation23PhysicallyBasedMaterialVAE9BaseColorVGTHTm")
//        try Demangling.mangleAsString(node).print()
        node.description.print()
    }

    @Test func stdlib_demangleNodeTree() async throws {
        let mangledName = "_$s7SwiftUI11DisplayListV10PropertiesVs9OptionSetAAsAFP8rawValuex03RawI0Qz_tcfCTW"
        let demangleNodeTree = MachOTestingSupport.stdlib_demangleNodeTree(mangledName)
        let stdlibNodeDescription = try #require(demangleNodeTree)
        let swiftSectionNodeDescription = try demangleAsNode(mangledName).description + "\n"
        #expect(stdlibNodeDescription == swiftSectionNodeDescription)
    }
}
