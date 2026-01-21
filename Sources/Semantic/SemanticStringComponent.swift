// MARK: - Core Protocol

/// A component that can be converted into semantic string content.
///
/// This protocol is the foundation of the semantic string system, similar to
/// SwiftUI's `View` protocol. Components can be either atomic (with a single
/// string and semantic type) or composite (containing other components).
///
/// Conforming to this protocol:
/// - For atomic components, also conform to `AtomicSemanticComponent`
/// - For composite components, implement `buildComponents()` directly
///
/// Example atomic component:
/// ```swift
/// struct Keyword: AtomicSemanticComponent {
///     let string: String
///     var type: SemanticType { .keyword }
/// }
/// ```
///
/// Example composite component:
/// ```swift
/// struct Group: SemanticStringComponent {
///     let items: [any SemanticStringComponent]
///
///     func buildComponents() -> [AtomicComponent] {
///         items.flatMap { $0.buildComponents() }
///     }
/// }
/// ```
public protocol SemanticStringComponent: Sendable {
    /// Expands this component into an array of atomic components.
    ///
    /// For atomic components, this returns a single-element array.
    /// For composite components, this recursively expands all children.
    func buildComponents() -> [AtomicComponent]
}

// MARK: - Atomic Component Protocol

/// A component with a single string value and semantic type.
///
/// Atomic components are the leaf nodes of the semantic string tree.
/// They represent indivisible units of styled text.
///
/// The default implementation of `buildComponents()` wraps `self`
/// in an `AtomicComponent`.
public protocol AtomicSemanticComponent: SemanticStringComponent {
    /// The string content of this component.
    var string: String { get }

    /// The semantic type for styling/categorization.
    var type: SemanticType { get }
}

extension AtomicSemanticComponent {
    @inlinable
    public func buildComponents() -> [AtomicComponent] {
        if string.isEmpty {
            return []
        }
        return [AtomicComponent(string: string, type: type)]
    }
}

// MARK: - Convenience Extensions

extension SemanticStringComponent {
    /// Converts this component to a `SemanticString`.
    @inlinable
    public func asSemanticString() -> SemanticString {
        SemanticString(self)
    }
}

// MARK: - Never Conformance (for result builder)

extension Never: SemanticStringComponent {
    public func buildComponents() -> [AtomicComponent] {
        switch self {}
    }
}

// MARK: - Optional Conformance

extension Optional: SemanticStringComponent where Wrapped: SemanticStringComponent {
    @inlinable
    public func buildComponents() -> [AtomicComponent] {
        self?.buildComponents() ?? []
    }
}

// MARK: - Array Conformance

extension Array: SemanticStringComponent where Element: SemanticStringComponent {
    @inlinable
    public func buildComponents() -> [AtomicComponent] {
        flatMap { $0.buildComponents() }
    }
}
