protocol Definition: Sendable {
    var allocators: [FunctionDefinition] { get }
    var variables: [VariableDefinition] { get }
    var functions: [FunctionDefinition] { get }
    var staticVariables: [VariableDefinition] { get }
    var staticFunctions: [FunctionDefinition] { get }
}
