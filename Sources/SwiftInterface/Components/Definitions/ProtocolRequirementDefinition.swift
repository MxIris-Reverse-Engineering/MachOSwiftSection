import Demangle

public enum ProtocolRequirementDefinition {
    case variable(VariableDefinition)
    case function(FunctionDefinition)
    case `subscript`(SubscriptDefinition)
    
    public var node: Node {
        switch self {
        case .variable(let variable):
            return variable.node
        case .function(let function):
            return function.node
        case .subscript(let `subscript`):
            return `subscript`.node
        }
    }

    public var name: String? {
        switch self {
        case .variable(let variable):
            return variable.name
        case .function(let function):
            return function.name
        case .subscript:
            return nil
        }
    }
}
