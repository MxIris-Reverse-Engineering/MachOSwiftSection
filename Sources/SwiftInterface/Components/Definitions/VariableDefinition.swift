import MemberwiseInit
import Demangling
import MachOSymbols
import MachOSwiftSection

@MemberwiseInit(.public)
public struct VariableDefinition: Sendable, AccessorRepresentable {
    public let node: Node
    public let name: String
    public let accessors: [Accessor]
    public let isGlobalOrStatic: Bool
    public var offset: Int? { accessors.first?.offset }
}
