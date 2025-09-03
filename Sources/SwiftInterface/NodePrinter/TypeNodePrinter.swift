import Foundation
import Demangle
import Semantic

struct TypeNodePrinter: InterfaceNodePrinter {
    var target: SemanticString = ""

    let cImportedInfoProvider: (any CImportedInfoProvider)?

    init(cImportedInfoProvider: (any CImportedInfoProvider)? = nil) {
        self.cImportedInfoProvider = cImportedInfoProvider
    }

    mutating func printRoot(_ node: Node) throws -> SemanticString {
        printName(node)
        return target
    }

    mutating func printName(_ name: Node, asPrefixContext: Bool) -> Node? {
        if printNameInBase(name) {
            return nil
        }
        if printNameInBoundGeneric(name) {
            return nil
        }
        if printNameInType(name) {
            return nil
        }
        if printNameInDependentGeneric(name) {
            return nil
        }
        if printNameInFunction(name) {
            return nil
        }
        return nil
    }
}
