// MARK: - Conditional Extensions

extension SemanticStringComponent {
    /// Returns a semantic string containing this component only if the condition is true.
    ///
    /// Example:
    /// ```swift
    /// Keyword("class").if(isClass)
    /// ```
    @inlinable
    public func `if`(_ condition: Bool) -> SemanticString {
        condition ? asSemanticString() : SemanticString()
    }

    /// Returns a semantic string containing this component if the value is non-nil.
    ///
    /// Example:
    /// ```swift
    /// Keyword("override").ifNotNil(superclass)
    /// ```
    @inlinable
    public func ifNotNil<T>(_ value: T?) -> SemanticString {
        value != nil ? asSemanticString() : SemanticString()
    }
}

// MARK: - IfLet

/// A helper for conditional semantic string building with optional values.
///
/// Example:
/// ```swift
/// @SemanticStringBuilder
/// var content: SemanticString {
///     IfLet(optionalName) { name in
///         Standard("Name: ")
///         Standard(name)
///     }
/// }
/// ```
public struct IfLet<T>: SemanticStringComponent {
    @usableFromInline
    let content: [AtomicComponent]

    @inlinable
    public init(_ value: T?, @SemanticStringBuilder then: (T) -> SemanticString) {
        if let value {
            self.content = then(value).components
        } else {
            self.content = []
        }
    }

    @inlinable
    public init(
        _ value: T?,
        @SemanticStringBuilder then: (T) -> SemanticString,
        @SemanticStringBuilder else elseContent: () -> SemanticString
    ) {
        if let value {
            self.content = then(value).components
        } else {
            self.content = elseContent().components
        }
    }

    @inlinable
    public func buildComponents() -> [AtomicComponent] {
        content
    }
}

// MARK: - ForEach

/// A helper for iterating over collections in semantic string builders.
///
/// Example:
/// ```swift
/// @SemanticStringBuilder
/// var parameterList: SemanticString {
///     ForEach(parameters, separator: ", ") { param in
///         Standard(param.name)
///         Standard(": ")
///         TypeName(kind: .other, param.type)
///     }
/// }
/// ```
public struct ForEach<C: Collection>: SemanticStringComponent {
    @usableFromInline
    let content: [AtomicComponent]

    /// Creates a ForEach without separator.
    @inlinable
    public init(_ collection: C, @SemanticStringBuilder content: (C.Element) -> SemanticString) {
        var result: [AtomicComponent] = []
        for element in collection {
            result.append(contentsOf: content(element).components)
        }
        self.content = result
    }

    /// Creates a ForEach with a string separator.
    @inlinable
    public init(_ collection: C, separator: String, @SemanticStringBuilder content: (C.Element) -> SemanticString) {
        self.init(collection, separator: Standard(separator), content: content)
    }

    /// Creates a ForEach with a component separator.
    @inlinable
    public init(_ collection: C, separator: some SemanticStringComponent, @SemanticStringBuilder content: (C.Element) -> SemanticString) {
        let items = collection.map { content($0) }.filter { !$0.isEmpty }
        let sepComponents = separator.buildComponents()

        var result: [AtomicComponent] = []
        for (index, item) in items.enumerated() {
            result.append(contentsOf: item.components)
            if index < items.count - 1 {
                result.append(contentsOf: sepComponents)
            }
        }
        self.content = result
    }

    @inlinable
    public func buildComponents() -> [AtomicComponent] {
        content
    }
}

// MARK: - ForEachIndexed

/// A helper that provides index information during iteration.
///
/// Example:
/// ```swift
/// @SemanticStringBuilder
/// var list: SemanticString {
///     ForEachIndexed(items) { item, info in
///         if !info.isFirst {
///             Standard(", ")
///         }
///         Standard(item.name)
///     }
/// }
/// ```
public struct ForEachIndexed<C: Collection>: SemanticStringComponent {
    @usableFromInline
    let content: [AtomicComponent]

    /// Element info provided to the content closure.
    public struct ElementInfo: Sendable {
        public let index: Int
        public let isFirst: Bool
        public let isLast: Bool

        @inlinable
        public init(index: Int, isFirst: Bool, isLast: Bool) {
            self.index = index
            self.isFirst = isFirst
            self.isLast = isLast
        }
    }

    @inlinable
    public init(_ collection: C, @SemanticStringBuilder content: (C.Element, ElementInfo) -> SemanticString) {
        var result: [AtomicComponent] = []
        let count = collection.count
        for (index, element) in collection.enumerated() {
            let info = ElementInfo(index: index, isFirst: index == 0, isLast: index == count - 1)
            result.append(contentsOf: content(element, info).components)
        }
        self.content = result
    }

    @inlinable
    public func buildComponents() -> [AtomicComponent] {
        content
    }
}
