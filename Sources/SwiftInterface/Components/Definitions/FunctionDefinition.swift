import MemberwiseInit
import Demangle

@MemberwiseInit(.public)
public struct FunctionDefinition: Sendable {
    public let node: Node
    public let name: String
    public let kind: FunctionKind
    public let isGlobalOrStatic: Bool
}
