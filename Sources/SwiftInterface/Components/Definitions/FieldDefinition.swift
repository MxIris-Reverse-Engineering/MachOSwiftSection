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
}

@MemberwiseInit(.public)
public struct FieldDefinition: Sendable {
    public let name: String
    public let typeNode: Node
    public let flags: FieldFlags
}
