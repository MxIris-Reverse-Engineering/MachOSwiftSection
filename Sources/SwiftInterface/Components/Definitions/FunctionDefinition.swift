import MemberwiseInit
import Demangling
import MachOSwiftSection
import SwiftDump
import Utilities

@MemberwiseInit(.public)
public struct FunctionDefinition: Sendable {
    public let node: Node
    public let name: String
    public let kind: FunctionKind
    public let symbol: DemangledSymbol
    public let isGlobalOrStatic: Bool
    public let methodDescriptor: MethodDescriptorWrapper?
    public let offset: Int?
    public let vtableOffset: Int?
    public var attributes: [SwiftAttribute] = []

    public var isOverride: Bool { methodDescriptor?.isMethodOverride ?? methodDescriptor?.isMethodDefaultOverride ?? false }
}
