import MemberwiseInit
import MachOSymbols

public protocol AccessorRepresentable: Sendable {
    var accessors: [Accessor] { get }
}

extension AccessorRepresentable {
    public var isStored: Bool { accessors.contains { $0.kind == .none } }
    public var isOverride: Bool { accessors.contains(where: { $0.methodDescriptor?.isMethodOverride ?? false }) }
    public var hasSetter: Bool { accessors.contains { $0.kind == .setter } }
    public var hasModifyAccessor: Bool { accessors.contains { $0.kind == .modifyAccessor } }
}

@MemberwiseInit(.public)
public struct Accessor: Sendable {
    public let kind: AccessorKind
    public let symbol: DemangledSymbol
    public let methodDescriptor: MethodDescriptorWrapper?
}
