import Foundation
import Demangle
import Semantic

struct SubscriptNodePrinter: InterfaceNodePrinter {
    var target: SemanticString = ""

    let cImportedInfoProvider: (any CImportedInfoProvider)?

    init(cImportedInfoProvider: (any CImportedInfoProvider)? = nil) {
        self.cImportedInfoProvider = cImportedInfoProvider
    }

    func printRoot(_ node: Node) throws -> SemanticString {}
}
