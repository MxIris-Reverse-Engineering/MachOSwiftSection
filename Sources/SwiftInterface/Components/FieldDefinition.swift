import MemberwiseInit
import Demangle

@MemberwiseInit(.public)
public struct FieldDefinition: Sendable {
    public let node: Node
    public let name: String
    public let isLazy: Bool
    public let isWeak: Bool
    public let isVar: Bool
    public let isIndirectCase: Bool
}
