import Semantic

public enum SwiftAttribute: Int, Comparable, Sendable, CaseIterable {
    // Type-level (inferred from members)
    case propertyWrapper
    case resultBuilder
    case dynamicMemberLookup
    case dynamicCallable

    // Type-level (from metadata flags)
    case objcType

    // Member-level (from Node tree / descriptor flags)
    case objc
    case nonobjc
    case dynamic

    // Type-level (from conformance: conforms to GlobalActor)
    case globalActor

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
        case .objcType: return "@objc"
        case .objc: return "@objc"
        case .nonobjc: return "@nonobjc"
        case .dynamic: return "dynamic"
        case .globalActor: return "@globalActor"
        case .retroactive: return "@retroactive"
        }
    }

    package var keyword: Keyword.Swift {
        switch self {
        case .propertyWrapper: return .atPropertyWrapper
        case .resultBuilder: return .atResultBuilder
        case .dynamicMemberLookup: return .atDynamicMemberLookup
        case .dynamicCallable: return .atDynamicCallable
        case .objcType: return .atObjc
        case .objc: return .atObjc
        case .nonobjc: return .atNonobjc
        case .dynamic: return .dynamic
        case .globalActor: return .atGlobalActor
        case .retroactive: return .atRetroactive
        }
    }
}
