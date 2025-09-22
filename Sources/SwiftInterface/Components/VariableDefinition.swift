import MemberwiseInit
import Demangle

@MemberwiseInit(.public)
public struct VariableDefinition: Sendable {
    public let node: Node
    public let name: String
    public let hasSetter: Bool
    public let hasModifyAccessor: Bool
    public let isGlobalOrStatic: Bool
    public let isStored: Bool
}
