import MemberwiseInit
import Demangle

@MemberwiseInit(.public)
public struct SubscriptDefinition: Sendable, AccessorRepresentable {
    public let node: Node
    public let accessors: [Accessor]
    public let isStatic: Bool
}
