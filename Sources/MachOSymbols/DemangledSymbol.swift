import Demangle

package struct DemangledSymbol {
    package let symbol: Symbol

    package let demangledNode: Node

    package init(symbol: Symbol, demangledNode: Node) {
        self.symbol = symbol
        self.demangledNode = demangledNode
    }
}
