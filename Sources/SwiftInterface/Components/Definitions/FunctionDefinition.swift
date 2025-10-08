import MemberwiseInit
import Demangle
import MachOSwiftSection

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
    public let isOverride: Bool
}
