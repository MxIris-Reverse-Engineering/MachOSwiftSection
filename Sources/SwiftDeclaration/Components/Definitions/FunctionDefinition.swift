import MemberwiseInit
import Demangling
import MachOSwiftSection
import Utilities

@MemberwiseInit(.public)
public struct FunctionDefinition: Sendable {
    public let node: NodeReference
    public let name: String
    public let kind: FunctionKind
    public let symbol: DemangledSymbol
    public let isGlobalOrStatic: Bool
    public let methodDescriptor: MethodDescriptorWrapper?
    public let offset: Int?
    public let vtableOffset: Int?
    public var attributes: [SwiftAttribute] = []

    public var isOverride: Bool { methodDescriptor?.isMethodOverride ?? methodDescriptor?.isMethodDefaultOverride ?? false }

    /// A type-level function with a vtable method descriptor was declared `class`:
    /// `static` members are implicitly final and never get one (mangling cannot tell them apart).
    public var isClassMember: Bool { kind == .function && isGlobalOrStatic && methodDescriptor != nil }

    /// Recovered `final` (evolution proposal 0006): set at index time when the
    /// owning class's vtable was readable and this member carries no vtable
    /// method descriptor — the dispatch shape `final` compiles to. Always
    /// `false` outside class bodies (extensions, protocols, value types), for
    /// type-level members (`static` is implicitly final), and for allocators
    /// (`final` is not a valid initializer modifier).
    public var isFinal: Bool = false
}
