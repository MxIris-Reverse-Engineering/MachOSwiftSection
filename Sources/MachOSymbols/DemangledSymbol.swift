import Demangling

@dynamicMemberLookup
public struct DemangledSymbol: Sendable {
    public let symbol: Symbol

    public let demangledNode: NodeReference

    public init(symbol: Symbol, demangledNode: NodeReference) {
        self.symbol = symbol
        self.demangledNode = demangledNode
    }

    public subscript<Value>(dynamicMember keyPath: KeyPath<Symbol, Value>) -> Value {
        return symbol[keyPath: keyPath]
    }

    public subscript<Value>(dynamicMember keyPath: KeyPath<NodeReference, Value>) -> Value {
        return demangledNode[keyPath: keyPath]
    }
}
