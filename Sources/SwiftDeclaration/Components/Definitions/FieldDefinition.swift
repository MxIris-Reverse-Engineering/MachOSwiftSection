import MemberwiseInit
import Demangling

public struct FieldFlags: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let isVariable = FieldFlags(rawValue: 1 << 0)
    public static let isLazy = FieldFlags(rawValue: 1 << 1)
    public static let isWeak = FieldFlags(rawValue: 1 << 2)
    public static let isIndirectCase = FieldFlags(rawValue: 1 << 3)
    public static let isUnowned = FieldFlags(rawValue: 1 << 4)
    public static let isUnownedUnsafe = FieldFlags(rawValue: 1 << 5)
    public static let isArtificial = FieldFlags(rawValue: 1 << 6)
    /// The field record carries a non-empty mangled type name. For enum cases
    /// this is the ABI's payload-case signal (a `Void` payload participates in
    /// the payload-case count and keeps its parentheses), captured at index
    /// time so renderers need not re-read the record positionally.
    public static let hasMangledTypeName = FieldFlags(rawValue: 1 << 7)
}

@MemberwiseInit(.public)
public struct FieldDefinition: AccessorRepresentable, Sendable {
    public let name: String
    public let typeNode: NodeReference
    public let flags: FieldFlags

    /// Accessors resolved from the symbol table for this stored property
    /// (getter/setter/modify), carrying the vtable method descriptors and
    /// slots where the owning class's vtable attribution succeeded. Empty when
    /// no accessor symbol joined — enum cases, stripped symbol tables, or
    /// fields the indexer never saw accessor symbols for.
    public var accessors: [Accessor] = []

    /// The caller-facing type from the getter symbol. Differs from `typeNode`
    /// for lazy storage, whose field record carries the `Optional` storage
    /// type rather than the type callers see.
    public var accessorTypeNode: NodeReference? = nil

    /// Recovered `final` (evolution proposal 0006): inside a class whose
    /// vtable was readable, a stored `var` whose joined accessors carry no
    /// vtable method descriptor was declared `final`. Set at index time;
    /// stays `false` whenever the evidence is missing (no accessor join, no
    /// vtable, value type, actor).
    public var isFinal: Bool = false

    // Also provided by `AccessorRepresentable`'s extension; kept spelled out
    // here because it predates the conformance (evolution proposal 0006) and
    // callers read it as a field-level fact.
    public var hasVTableAccessor: Bool { accessors.contains { $0.methodDescriptor != nil } }
}
