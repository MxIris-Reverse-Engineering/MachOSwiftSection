import Foundation
import Demangle
import Testing
import MachOTestingSupport
@testable import SwiftInterface

@Suite
struct NodePrinterTests {
    @Test
    func printRoot() throws {
//        let node = try demangleAsNode("_$ss18_DictionaryStorageC6resize8original8capacity4moveAByxq_Gs05__RawaB0C_SiSbtFZ")
        let node = try demangleAsNode("_$s7SwiftUI9AsyncBodyV13_makeProperty2in9container11fieldOffset6inputsyAA08_DynamicF6BufferVz_AA11_GraphValueVyxGSiAA01_N6InputsVztlFZ")
        var printer = FunctionNodePrinter()
        try printer.printRoot(#require(node.children.first)).print()

        let variableNode = try demangleAsNode("_$s7SwiftUI38HostingViewTransparentBackgroundReasonVs10SetAlgebraAAsADP7isEmptySbvgTW")
        var variableNodePrinter = VariableNodePrinter(isSetter: true)
        try variableNodePrinter.printRoot(#require(variableNode.children.first)).print()
    }
}
