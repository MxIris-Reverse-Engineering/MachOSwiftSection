import Demangle

enum ProtocolRequirementDefinition {
    case variable(VariableDefinition)
    case function(FunctionDefinition)

    var node: Node {
        switch self {
        case .variable(let variable):
            return variable.node
        case .function(let function):
            return function.node
        }
    }

    var name: String {
        switch self {
        case .variable(let variable):
            return variable.name
        case .function(let function):
            return function.name
        }
    }
}
