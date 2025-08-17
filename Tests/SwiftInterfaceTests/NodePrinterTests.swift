import Foundation
import Demangle
import Testing
import MachOSymbols
@testable import MachOTestingSupport
@testable import SwiftInterface

@Suite
final class NodePrinterTests: DyldCacheTests {
    @Test func functionNode() async throws {
        let node = try demangleAsNode("_$s7SwiftUI33LimitedAvailabilityCommandContentV15IndirectOutputs33_345D0464CE5C92DE3AB73ADEFB278856LLV11updateValueyyF")
        var printer = FunctionNodePrinter()
        try printer.printRoot(node.children.first!).print()
    }

    @Test func variableNode() async throws {
        let variableNode = try demangleAsNode("_$s7SwiftUI38HostingViewTransparentBackgroundReasonVs10SetAlgebraAAsADP7isEmptySbvgTW")
        var variableNodePrinter = VariableNodePrinter(isSetter: true)
        try variableNodePrinter.printRoot(#require(variableNode.children.first)).print()
    }

    @Test func functionNodes() throws {
        let symbols = SymbolIndexStore.shared.memberSymbols(of: .function, in: machOFileInMainCache)

        for symbol in symbols {
            let node = try demangleAsNode(symbol.stringValue)
            do {
                var printer = FunctionNodePrinter()
                print("Mangled  : \(symbol.stringValue)")
                print("Demangled: \(node.print(using: .interface))")
                try print("Interface: \(printer.printRoot(#require(node.children.first)))")
            } catch {
                print("Error printing node: \(node.print(using: .default))")
            }
            print("--------------------")
        }
    }
}
