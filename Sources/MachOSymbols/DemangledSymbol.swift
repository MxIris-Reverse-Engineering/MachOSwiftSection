import Demangle

@dynamicMemberLookup
package struct DemangledSymbol {
    package let symbol: Symbol

    package let demangledNode: Node

    package init(symbol: Symbol, demangledNode: Node) {
        self.symbol = symbol
        self.demangledNode = demangledNode
    }
    
    package subscript<Value>(dynamicMember keyPath: KeyPath<Symbol, Value>) -> Value {
        return symbol[keyPath: keyPath]
    }
    
    package subscript<Value>(dynamicMember keyPath: KeyPath<Node, Value>) -> Value {
        return demangledNode[keyPath: keyPath]
    }
}
