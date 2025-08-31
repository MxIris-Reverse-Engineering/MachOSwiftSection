import MemberwiseInit
import Demangle

@MemberwiseInit
struct FunctionDefinition: Sendable {
    enum Kind: Sendable {
        case function
        case allocator
        case deallocator
    }

    let node: Node
    let name: String
    let kind: Kind
    let isStatic: Bool
}
