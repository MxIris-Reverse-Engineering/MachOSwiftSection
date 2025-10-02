import MemberwiseInit
import Demangle
import MachOSymbols

@MemberwiseInit(.public)
public struct Accessor: Sendable {
    public let kind: AccessorKind
    public let symbol: DemangledSymbol
}

@MemberwiseInit(.public)
public struct VariableDefinition: Sendable {
    public let node: Node
    public let name: String
    public let accessors: [Accessor]
    public let isGlobalOrStatic: Bool
    public var isStored: Bool { accessors.contains { $0.kind == .none } }
    public var hasSetter: Bool { accessors.contains { $0.kind == .setter } }
    public var hasModifyAccessor: Bool { accessors.contains { $0.kind == .modifyAccessor } }
}
