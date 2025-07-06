// MARK: - AccessLevel Enum

/// Specifies the access level for the generated members.
/// It is used as an argument for the @AssociatedValue macro.
public enum AccessLevel: String {
    // The raw values match the Swift keywords.
    case `private`
    case `fileprivate`
    case `internal`
    // `package` is available in Swift 5.9+
    case `package`
    case `public`
    // `open` is not valid for properties, but included for completeness.
    // The macro will generate valid code, but the compiler will catch if it's misused.
    case `open`
}
