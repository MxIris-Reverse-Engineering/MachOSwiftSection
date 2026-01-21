/// A transparent grouping container for semantic string components.
///
/// Use `Group` to collect multiple components and optionally apply a separator.
/// Unlike `Joined`, `Group` preserves the structure for later manipulation.
///
/// Example:
/// ```swift
/// Group {
///     Keyword("public")
///     Space()
///     Keyword("func")
/// }
/// .separator(Standard(", "))
/// ```
public struct Group: SemanticStringComponent {
    @usableFromInline
    var items: [any SemanticStringComponent]

    @usableFromInline
    var separator: (any SemanticStringComponent)?

    /// Creates a group from a builder.
    @inlinable
    public init(@SemanticStringBuilder content: () -> SemanticString) {
        self.items = content().elements
        self.separator = nil
    }

    /// Creates a group from an array of semantic strings.
    @inlinable
    public init(_ items: [SemanticString]) {
        self.items = items
        self.separator = nil
    }

    /// Creates a group from variadic semantic strings.
    @inlinable
    public init(_ items: SemanticString...) {
        self.items = items
        self.separator = nil
    }

    /// Creates an empty group.
    @inlinable
    public init() {
        self.items = []
        self.separator = nil
    }

    @inlinable
    public func buildComponents() -> [AtomicComponent] {
        let expanded = items.map { $0.buildComponents() }.filter { !$0.isEmpty }

        guard !expanded.isEmpty else { return [] }

        if let sep = separator {
            let sepComponents = sep.buildComponents()
            var result: [AtomicComponent] = []
            for (index, components) in expanded.enumerated() {
                result.append(contentsOf: components)
                if index < expanded.count - 1 {
                    result.append(contentsOf: sepComponents)
                }
            }
            return result
        }

        return expanded.flatMap { $0 }
    }

    /// Applies a separator between components.
    @inlinable
    public func separator(_ separator: some SemanticStringComponent) -> Group {
        var copy = self
        copy.separator = separator
        return copy
    }

    /// Applies a string separator between components.
    @inlinable
    public func separator(_ separator: String) -> Group {
        var copy = self
        copy.separator = Standard(separator)
        return copy
    }
}
