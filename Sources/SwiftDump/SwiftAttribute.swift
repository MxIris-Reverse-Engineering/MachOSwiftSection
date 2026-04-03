import Semantic

public enum SwiftAttribute: Int, Comparable, Sendable, CaseIterable {
    // Type-level (inferred from members)
    case propertyWrapper
    case resultBuilder
    case dynamicMemberLookup
    case dynamicCallable

    // Type-level (from metadata flags)
    case frozen
    case usableFromInline
    case objcType

    // Member-level (from Node tree / descriptor flags)
    case objc
    case nonobjc
    case inlinable
    case dynamic

    // Conformance-level
    case retroactive

    public static func < (lhs: SwiftAttribute, rhs: SwiftAttribute) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var annotationString: String {
        switch self {
        case .propertyWrapper: return "@propertyWrapper"
        case .resultBuilder: return "@resultBuilder"
        case .dynamicMemberLookup: return "@dynamicMemberLookup"
        case .dynamicCallable: return "@dynamicCallable"
        case .frozen: return "@frozen"
        case .usableFromInline: return "@usableFromInline"
        case .objcType: return "@objc"
        case .objc: return "@objc"
        case .nonobjc: return "@nonobjc"
        case .inlinable: return "@inlinable"
        case .dynamic: return "dynamic"
        case .retroactive: return "@retroactive"
        }
    }

    package var keyword: Keyword.Swift {
        switch self {
        case .propertyWrapper: return .atPropertyWrapper
        case .resultBuilder: return .atResultBuilder
        case .dynamicMemberLookup: return .atDynamicMemberLookup
        case .dynamicCallable: return .atDynamicCallable
        case .frozen: return .atFrozen
        case .usableFromInline: return .atUsableFromInline
        case .objcType: return .atObjc
        case .objc: return .atObjc
        case .nonobjc: return .atNonobjc
        case .inlinable: return .atInlinable
        case .dynamic: return .dynamic
        case .retroactive: return .atRetroactive
        }
    }
}
