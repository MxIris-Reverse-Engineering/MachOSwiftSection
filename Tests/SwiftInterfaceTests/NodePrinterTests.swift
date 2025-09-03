import Foundation
import Demangle
import Testing
import MachOSymbols
@testable import SwiftInterface
@testable import MachOTestingSupport

@Suite
final class NodePrinterTests: DyldCacheTests {
    @Test func functionNode() async throws {
        let node = try demangleAsNode("_$s7SwiftUI33LimitedAvailabilityCommandContentV15IndirectOutputs33_345D0464CE5C92DE3AB73ADEFB278856LLV11updateValueyyF")
        var printer = FunctionNodePrinter()
        try printer.printRoot(node.children.first!).string.print()
    }

    @Test func variableNode() async throws {
        let variableNode = try demangleAsNode("_$s7SwiftUI38HostingViewTransparentBackgroundReasonVs10SetAlgebraAAsADP7isEmptySbvgTW")
        var variableNodePrinter = VariableNodePrinter(hasSetter: true, indentation: 0)
        try variableNodePrinter.printRoot(#require(variableNode.children.first)).string.print()
    }

    @Test func functionNodes() throws {
        let demangledSymbols = SymbolIndexStore.shared.memberSymbols(of: .function, in: machOFileInMainCache)

        for demangledSymbol in demangledSymbols {
            let node = demangledSymbol.demangledNode
            do {
                var printer = FunctionNodePrinter()
                print("Mangled  : \(demangledSymbol.symbol.stringValue)")
                print("Demangled: \(node.print(using: .interface))")
                try print("Interface: \(printer.printRoot(#require(node.children.first)).string)")
            } catch {
                print("Error printing node: \(node.print(using: .default))")
            }
            print("--------------------")
        }
    }
}
