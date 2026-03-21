import MemberwiseInit
import Demangling

@MemberwiseInit(.public)
public struct SubscriptDefinition: Sendable, AccessorRepresentable {
    public let node: Node
    public let accessors: [Accessor]
    public let isStatic: Bool
    public var offset: Int? { accessors.first?.offset }
    public var hasVTableOffset: Bool { accessors.contains { $0.vtableOffset != nil } }
}
