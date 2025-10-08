import MemberwiseInit
import Demangle
import MachOSwiftSection
import Utilities

@AssociatedValue(.public)
@CaseCheckable(.public)
public enum MethodDescriptorWrapper: Sendable {
    case method(MethodDescriptor)
    case methodOverride(MethodOverrideDescriptor)
    case methodDefaultOverride(MethodDefaultOverrideDescriptor)
}

@MemberwiseInit(.public)
public struct FunctionDefinition: Sendable {
    public let node: Node
    public let name: String
    public let kind: FunctionKind
    public let symbol: DemangledSymbol
    public let isGlobalOrStatic: Bool
    public let methodDescriptor: MethodDescriptorWrapper?
    
    public var isOverride: Bool { methodDescriptor?.isMethodOverride ?? false }
}
