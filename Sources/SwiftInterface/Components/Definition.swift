protocol Definition: Sendable {
    var allocators: [FunctionDefinition] { get }
    var constructors: [FunctionDefinition] { get }
    var variables: [VariableDefinition] { get }
    var functions: [FunctionDefinition] { get }
    var subscripts: [SubscriptDefinition] { get }
    var staticVariables: [VariableDefinition] { get }
    var staticFunctions: [FunctionDefinition] { get }
    var staticSubscripts: [SubscriptDefinition] { get }
}
