import MemberwiseInit
import Demangle
import MachOSymbols
import MachOSwiftSection

@MemberwiseInit(.public)
public struct VariableDefinition: Sendable, AccessorRepresentable {
    public let node: Node
    public let name: String
    public let accessors: [Accessor]
    public let isGlobalOrStatic: Bool
}
