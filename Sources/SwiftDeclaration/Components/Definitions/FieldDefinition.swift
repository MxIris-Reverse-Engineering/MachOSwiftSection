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
public struct FieldDefinition: Sendable {
    public let name: String
    public let typeNode: Node
    public let flags: FieldFlags
}
