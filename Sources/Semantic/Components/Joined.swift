/// A component that joins multiple semantic strings with a separator,
/// automatically filtering out empty items.
///
/// Example usage in a builder:
/// ```swift
/// Joined(separator: ", ") {
///     Keyword("public")
///     Keyword("static")
///     Keyword("func")
/// }
/// ```
///
/// Example usage with array:
/// ```swift
/// Joined(separator: ", ", items)
/// ```
public struct Joined: SemanticStringComponent {
    @usableFromInline
    let items: [any SemanticStringComponent]

    @usableFromInline
    let separator: any SemanticStringComponent

    /// Creates a joined component from a builder with a string separator.
    @inlinable
    public init(separator: String, @SemanticStringBuilder content: () -> SemanticString) {
        self.separator = Standard(separator)
        self.items = content().elements
    }

    /// Creates a joined component from a builder with a component separator.
    @inlinable
    public init(separator: some SemanticStringComponent, @SemanticStringBuilder content: () -> SemanticString) {
        self.separator = separator
        self.items = content().elements
    }

    /// Creates a joined component from an array of semantic strings.
    @inlinable
    public init(separator: String, _ items: [SemanticString]) {
        self.separator = Standard(separator)
        self.items = items
    }

    /// Creates a joined component from an array with a component separator.
    @inlinable
    public init(separator: some SemanticStringComponent, _ items: [SemanticString]) {
        self.separator = separator
        self.items = items
    }

    @inlinable
    public func buildComponents() -> [AtomicComponent] {
        let expanded = items.map { $0.buildComponents() }.filter { !$0.isEmpty }

        guard !expanded.isEmpty else { return [] }

        let sepComponents = separator.buildComponents()
        var result: [AtomicComponent] = []

        for (index, components) in expanded.enumerated() {
            result.append(contentsOf: components)
            if index < expanded.count - 1 {
                result.append(contentsOf: sepComponents)
            }
        }

        return result
    }
}

// MARK: - Array Extensions

extension Array where Element == SemanticString {
    /// Joins an array of semantic strings with a separator.
    @inlinable
    public func joined(separator: String) -> SemanticString {
        joined(separator: Standard(separator))
    }

    /// Joins an array of semantic strings with a component separator.
    @inlinable
    public func joined(separator: some SemanticStringComponent) -> SemanticString {
        Joined(separator: separator, self).asSemanticString()
    }
}

extension Array where Element: SemanticStringComponent {
    /// Joins an array of components with a separator.
    @inlinable
    public func joined(separator: String) -> SemanticString {
        map { $0.asSemanticString() }.joined(separator: separator)
    }

    /// Joins an array of components with a component separator.
    @inlinable
    public func joined(separator: some SemanticStringComponent) -> SemanticString {
        map { $0.asSemanticString() }.joined(separator: separator)
    }
}
