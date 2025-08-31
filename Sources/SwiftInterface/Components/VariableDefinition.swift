import MemberwiseInit
import Demangle

@MemberwiseInit
struct VariableDefinition: Sendable {
    let node: Node
    let name: String
    let hasSetter: Bool
    let hasModifyAccessor: Bool
    let isStatic: Bool
}
