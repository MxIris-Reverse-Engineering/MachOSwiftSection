import Foundation
import Demangle
import Testing
import MachOSymbols
@testable import MachOTestingSupport
@testable import SwiftInterface

@Suite
final class NodePrinterTests: DyldCacheTests {
    @Test
    func functionNodes() throws {
//        let node = try demangleAsNode("_$ss18_DictionaryStorageC6resize8original8capacity4moveAByxq_Gs05__RawaB0C_SiSbtFZ")

//        let variableNode = try demangleAsNode("_$s7SwiftUI38HostingViewTransparentBackgroundReasonVs10SetAlgebraAAsADP7isEmptySbvgTW")
//        var variableNodePrinter = VariableNodePrinter(isSetter: true)
//        try variableNodePrinter.printRoot(#require(variableNode.children.first)).print()

        let symbols = SymbolIndexStore.shared.memberSymbols(of: .function, in: machOFileInMainCache)

        for symbol in symbols {
            let node = try demangleAsNode(symbol.stringValue)
            do {
                var printer = FunctionNodePrinter()
                print("Dump     : \(node.print(using: .interface))")
                print("Interface: \(try printer.printRoot(#require(node.children.first)))")
            } catch {
                print("Error printing node: \(node.print(using: .default))")
            }
            print("--------------------")
        }
    }
}
