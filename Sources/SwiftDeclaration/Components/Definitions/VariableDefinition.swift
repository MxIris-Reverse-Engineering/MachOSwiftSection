import MemberwiseInit
import Demangling
import MachOSymbols
import MachOSwiftSection

@MemberwiseInit(.public)
public struct VariableDefinition: Sendable, AccessorRepresentable {
    public let node: NodeReference
    public let name: String
    public let accessors: [Accessor]
    public let isGlobalOrStatic: Bool
    public var attributes: [SwiftAttribute] = []
    public var offset: Int? { accessors.first?.offset }
    public var hasVTableOffset: Bool { accessors.contains { $0.vtableOffset != nil } }

    /// A type-level variable whose accessors have vtable method descriptors was declared `class`:
    /// `static` members are implicitly final and never get one (mangling cannot tell them apart).
    public var isClassMember: Bool { isGlobalOrStatic && hasVTableAccessor }

    /// Recovered `final` (evolution proposal 0006): set at index time when the
    /// owning class's vtable was readable and none of this member's accessors
    /// carry a vtable method descriptor — the dispatch shape `final` compiles
    /// to. Always `false` outside class bodies (extensions, protocols, value
    /// types) and for type-level members (`static` is implicitly final).
    public var isFinal: Bool = false
}
