import MemberwiseInit
import Demangle

@MemberwiseInit(.public)
public struct SubscriptDefinition: Sendable {
    public let node: Node
    public let hasSetter: Bool
    public let hasReadAccessor: Bool
    public let hasModifyAccessor: Bool
    public let isStatic: Bool
}
