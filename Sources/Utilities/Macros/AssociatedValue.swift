// MARK: - @AssociatedValue Macro

/// Adds a computed property for each enum case with a single associated value.
///
/// The property returns the associated value if the enum instance is that specific case,
/// otherwise it returns `nil`.
///
/// - Parameters:
///   - access: The access level for the generated properties (e.g., `.public`, `.internal`).
///             If omitted, the properties will inherit the access level of the enum.
///   - prefix: An optional string to prepend to the generated property name.
///             If provided, the original case name will be capitalized.
///   - suffix: An optional string to append to the generated property name.
///
/// ## Example
///
/// ```swift
/// @AssociatedValue(.public)
/// public enum State {
///     case loaded(User)
///     case failed(Error)
/// }
///
/// // Expands to:
/// // public enum State {
/// //     case loaded(User)
/// //     case failed(Error)
/// //
/// //     public var loaded: User? { ... }
/// //     public var failed: Error? { ... }
/// // }
/// ```
@attached(member, names: arbitrary)
public macro AssociatedValue(
    _ access: AccessLevel? = nil, // Changed to an unlabeled enum parameter
    prefix: String? = nil,
    suffix: String? = nil
) = #externalMacro(
    module: "MachOMacros",
    type: "AssociatedValueMacro"
)
