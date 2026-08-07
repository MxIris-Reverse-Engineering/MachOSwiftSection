import MemberwiseInit
import Demangling

@MemberwiseInit(.public)
public struct SubscriptDefinition: Sendable, AccessorRepresentable {
    public let node: Node
    public let accessors: [Accessor]
    public let isStatic: Bool
    public var attributes: [SwiftAttribute] = []
    public var offset: Int? { accessors.first?.offset }
    public var hasVTableOffset: Bool { accessors.contains { $0.vtableOffset != nil } }

    /// A type-level subscript whose accessors have vtable method descriptors was declared `class`:
    /// `static` members are implicitly final and never get one (mangling cannot tell them apart).
    public var isClassMember: Bool { isStatic && hasVTableAccessor }
}
