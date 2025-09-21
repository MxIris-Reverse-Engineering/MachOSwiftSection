import MemberwiseInit
import Demangle

@MemberwiseInit
struct FieldDefinition: Sendable {
    let node: Node
    let name: String
    let isLazy: Bool
    let isWeak: Bool
    let isVar: Bool
    let isIndirectCase: Bool
}
