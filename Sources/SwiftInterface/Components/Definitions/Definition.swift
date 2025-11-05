import MachOSwiftSection

public protocol Definition: AnyObject, Sendable {
    var isIndexed: Bool { get }
    var allocators: [FunctionDefinition] { get }
    var constructors: [FunctionDefinition] { get }
    var variables: [VariableDefinition] { get }
    var functions: [FunctionDefinition] { get }
    var subscripts: [SubscriptDefinition] { get }
    var staticVariables: [VariableDefinition] { get }
    var staticFunctions: [FunctionDefinition] { get }
    var staticSubscripts: [SubscriptDefinition] { get }
}

package protocol MutableDefinition: Definition {
    var allocators: [FunctionDefinition] { get set }
    var constructors: [FunctionDefinition] { get set }
    var variables: [VariableDefinition] { get set }
    var functions: [FunctionDefinition] { get set }
    var subscripts: [SubscriptDefinition] { get set }
    var staticVariables: [VariableDefinition] { get set }
    var staticFunctions: [FunctionDefinition] { get set }
    var staticSubscripts: [SubscriptDefinition] { get set }
    
    func index<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) async throws
}
