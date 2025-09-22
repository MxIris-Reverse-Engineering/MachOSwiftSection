import MemberwiseInit
import Demangle

@MemberwiseInit(.public)
public struct FunctionDefinition: Sendable {
    public enum Kind: Sendable {
        case function
        case allocator
        case constructor
    }

    public let node: Node
    public let name: String
    public let kind: Kind
    public let isGlobalOrStatic: Bool
}
