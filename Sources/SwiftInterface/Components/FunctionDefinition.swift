import MemberwiseInit
import Demangle

@MemberwiseInit
struct FunctionDefinition: Sendable {
    enum Kind: Sendable {
        case function
        case allocator
        case constructor
    }

    let node: Node
    let name: String
    let kind: Kind
    let isGlobalOrStatic: Bool
}
