import MemberwiseInit
import Demangle

@MemberwiseInit
struct SubscriptDefinition: Sendable {
    let node: Node
    let hasSetter: Bool
    let hasReadAccessor: Bool
    let hasModifyAccessor: Bool
    let isStatic: Bool
}
