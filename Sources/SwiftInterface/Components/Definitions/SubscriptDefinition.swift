import MemberwiseInit
import Demangle

@MemberwiseInit(.public)
public struct SubscriptDefinition: Sendable {
    public let node: Node
    public let accessors: [Accessor]
    public let isStatic: Bool
    public var hasSetter: Bool { accessors.contains { $0.kind == .setter } }
    public var hasModifyAccessor: Bool { accessors.contains { $0.kind == .modifyAccessor } }
}
