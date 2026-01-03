/// A string composed of semantically typed components.
///
/// `SemanticString` is the primary type for building styled text output.
/// It stores a list of semantic components that can be flattened into
/// atomic components for rendering.
///
/// This type implements copy-on-write semantics for efficient copying
/// and caches computed components to avoid redundant calculations.
///
/// Example:
/// ```swift
/// @SemanticStringBuilder
/// var declaration: SemanticString {
///     Keyword("public")
///     Space()
///     Keyword("struct")
///     Space()
///     TypeName(kind: .struct, "MyType")
/// }
/// ```
public struct SemanticString: Sendable, ExpressibleByStringLiteral, SemanticStringComponent {
    /// Internal storage class for copy-on-write semantics
    @usableFromInline
    final class Storage: @unchecked Sendable {
        @usableFromInline
        var elements: [any SemanticStringComponent]

        @usableFromInline
        var cachedComponents: [AtomicComponent]?

        @usableFromInline
        var cachedString: String?

        @inlinable
        init(elements: [any SemanticStringComponent] = []) {
            self.elements = elements
        }

        @inlinable
        init(copying other: Storage) {
            self.elements = other.elements
            self.cachedComponents = other.cachedComponents
            self.cachedString = other.cachedString
        }
    }

    @usableFromInline
    var _storage: Storage

    /// Ensures unique ownership of storage for mutation (copy-on-write)
    @inlinable
    mutating func makeUnique() {
        if !isKnownUniquelyReferenced(&_storage) {
            _storage = Storage(copying: _storage)
        }
    }

    /// Invalidates cached values when elements are modified
    @inlinable
    mutating func invalidateCache() {
        _storage.cachedComponents = nil
        _storage.cachedString = nil
    }

    @usableFromInline
    internal var elements: [any SemanticStringComponent] {
        _storage.elements
    }

    public var components: [AtomicComponent] {
        if let cached = _storage.cachedComponents {
            return cached
        }
        let computed = _storage.elements.flatMap { $0.buildComponents() }
        _storage.cachedComponents = computed
        return computed
    }

    /// The number of components.
    @inlinable
    public var count: Int { components.count }

    /// The combined string of all components.
    public var string: String {
        if let cached = _storage.cachedString {
            return cached
        }
        let computed = components.map(\.string).joined()
        _storage.cachedString = computed
        return computed
    }

    // MARK: - Collection-like Properties

    /// Returns `true` if the semantic string has no components.
    @inlinable
    public var isEmpty: Bool { _storage.elements.isEmpty }

    /// Returns the first component, or `nil` if empty.
    @inlinable
    public var first: AtomicComponent? { components.first }

    /// Returns the last component, or `nil` if empty.
    @inlinable
    public var last: AtomicComponent? { components.last }

    // MARK: - Initialization

    @inlinable
    public init() {
        self._storage = Storage()
    }

    @inlinable
    public init(@SemanticStringBuilder builder: () -> SemanticString) {
        self = builder()
    }

    @inlinable
    public init(components: [any SemanticStringComponent]) {
        self._storage = Storage(elements: components)
    }

    @inlinable
    public init(components: [AtomicComponent]) {
        self._storage = Storage(elements: components)
        // Pre-cache since we already have atomic components
        _storage.cachedComponents = components
    }

    @inlinable
    public init(components: AtomicComponent...) {
        self._storage = Storage(elements: components)
        _storage.cachedComponents = components
    }

    @inlinable
    public init(_ component: some SemanticStringComponent) {
        self._storage = Storage(elements: [component])
    }

    @inlinable
    public init(stringLiteral value: StringLiteralType) {
        if value.isEmpty {
            self._storage = Storage()
        } else {
            let component = AtomicComponent(string: value, type: .standard)
            self._storage = Storage(elements: [component])
            _storage.cachedComponents = [component]
            _storage.cachedString = value
        }
    }

    // MARK: - SemanticStringComponent Conformance

    @inlinable
    public func buildComponents() -> [AtomicComponent] {
        components
    }

    // MARK: - Mutation

    @inlinable
    public mutating func append(_ string: String, type: SemanticType) {
        if !string.isEmpty {
            makeUnique()
            invalidateCache()
            _storage.elements.append(AtomicComponent(string: string, type: type))
        }
    }

    @inlinable
    public mutating func append(_ component: some SemanticStringComponent) {
        makeUnique()
        invalidateCache()
        _storage.elements.append(component)
    }

    @inlinable
    public mutating func append(_ semanticString: SemanticString) {
        makeUnique()
        invalidateCache()
        _storage.elements.append(contentsOf: semanticString._storage.elements)
    }

    // MARK: - Enumeration

    @inlinable
    public func enumerate(using block: (String, SemanticType) -> Void) {
        components.forEach { block($0.string, $0.type) }
    }

    // MARK: - Transformation

    @inlinable
    public func map(_ modifier: (AtomicComponent) -> AtomicComponent) -> SemanticString {
        SemanticString(components: components.map(modifier))
    }

    @inlinable
    public func replacing(_ transform: (SemanticType) -> SemanticType) -> SemanticString {
        map { AtomicComponent(string: $0.string, type: transform($0.type)) }
    }

    @inlinable
    public func replacing(from types: SemanticType..., to newType: SemanticType) -> SemanticString {
        map { component in
            if types.contains(component.type) {
                return AtomicComponent(string: component.string, type: newType)
            } else {
                return component
            }
        }
    }

    // MARK: - Prefix and Suffix Checking

    /// Returns `true` if the combined string starts with the given prefix.
    @inlinable
    public func hasPrefix(_ prefix: String) -> Bool {
        string.hasPrefix(prefix)
    }

    /// Returns `true` if the combined string ends with the given suffix.
    @inlinable
    public func hasSuffix(_ suffix: String) -> Bool {
        string.hasSuffix(suffix)
    }

    /// Returns `true` if the first component has the given semantic type.
    @inlinable
    public func starts(with type: SemanticType) -> Bool {
        first?.type == type
    }

    /// Returns `true` if the last component has the given semantic type.
    @inlinable
    public func ends(with type: SemanticType) -> Bool {
        last?.type == type
    }

    /// Returns `true` if the first component's string starts with the given prefix.
    @inlinable
    public func firstComponentHasPrefix(_ prefix: String) -> Bool {
        first?.string.hasPrefix(prefix) ?? false
    }

    /// Returns `true` if the last component's string ends with the given suffix.
    @inlinable
    public func lastComponentHasSuffix(_ suffix: String) -> Bool {
        last?.string.hasSuffix(suffix) ?? false
    }

    // MARK: - Trimming

    /// Returns a new semantic string with leading whitespace-only components removed.
    @inlinable
    public func trimmingLeadingWhitespace() -> SemanticString {
        var items = components
        while let first = items.first,
              first.string.allSatisfy(\.isWhitespace) {
            items.removeFirst()
        }
        return SemanticString(components: items)
    }

    /// Returns a new semantic string with trailing whitespace-only components removed.
    @inlinable
    public func trimmingTrailingWhitespace() -> SemanticString {
        var items = components
        while let last = items.last,
              last.string.allSatisfy(\.isWhitespace) {
            items.removeLast()
        }
        return SemanticString(components: items)
    }

    /// Returns a new semantic string with both leading and trailing whitespace-only components removed.
    @inlinable
    public func trimmingWhitespace() -> SemanticString {
        trimmingLeadingWhitespace().trimmingTrailingWhitespace()
    }

    /// Returns a new semantic string with leading newline-only components removed.
    @inlinable
    public func trimmingLeadingNewlines() -> SemanticString {
        var items = components
        while let first = items.first,
              first.string.allSatisfy(\.isNewline) {
            items.removeFirst()
        }
        return SemanticString(components: items)
    }

    /// Returns a new semantic string with trailing newline-only components removed.
    @inlinable
    public func trimmingTrailingNewlines() -> SemanticString {
        var items = components
        while let last = items.last,
              last.string.allSatisfy(\.isNewline) {
            items.removeLast()
        }
        return SemanticString(components: items)
    }

    /// Returns a new semantic string with both leading and trailing newline-only components removed.
    @inlinable
    public func trimmingNewlines() -> SemanticString {
        trimmingLeadingNewlines().trimmingTrailingNewlines()
    }

    // MARK: - Subscript Access

    /// Access a component by index.
    @inlinable
    public subscript(index: Int) -> AtomicComponent? {
        let items = components
        guard index >= 0, index < items.count else { return nil }
        return items[index]
    }

    /// Access a range of components.
    @inlinable
    public subscript(range: Range<Int>) -> SemanticString {
        let items = components
        let validRange = range.clamped(to: 0 ..< items.count)
        return SemanticString(components: Array(items[validRange]))
    }

    // MARK: - Dropping

    /// Returns a new semantic string with the first `n` components removed.
    @inlinable
    public func dropFirst(_ n: Int = 1) -> SemanticString {
        SemanticString(components: Array(components.dropFirst(n)))
    }

    /// Returns a new semantic string with the last `n` components removed.
    @inlinable
    public func dropLast(_ n: Int = 1) -> SemanticString {
        SemanticString(components: Array(components.dropLast(n)))
    }

    /// Returns a new semantic string with components while the predicate is true.
    @inlinable
    public func drop(while predicate: (AtomicComponent) -> Bool) -> SemanticString {
        SemanticString(components: Array(components.drop(while: predicate)))
    }

    // MARK: - Prefix/Suffix Extraction

    /// Returns a semantic string containing the first `n` components.
    @inlinable
    public func prefix(_ n: Int) -> SemanticString {
        SemanticString(components: Array(components.prefix(n)))
    }

    /// Returns a semantic string containing the last `n` components.
    @inlinable
    public func suffix(_ n: Int) -> SemanticString {
        SemanticString(components: Array(components.suffix(n)))
    }

    // MARK: - Filtering

    /// Returns a semantic string containing only components of the specified type.
    @inlinable
    public func filter(byType type: SemanticType) -> SemanticString {
        SemanticString(components: components.filter { $0.type == type })
    }

    /// Returns a semantic string containing only components matching the predicate.
    @inlinable
    public func filter(_ predicate: (AtomicComponent) -> Bool) -> SemanticString {
        SemanticString(components: components.filter(predicate))
    }

    // MARK: - Containment

    /// Returns `true` if any component has the specified semantic type.
    @inlinable
    public func contains(type: SemanticType) -> Bool {
        components.contains { $0.type == type }
    }

    /// Returns `true` if the combined string contains the specified substring.
    @inlinable
    public func contains(_ substring: String) -> Bool {
        guard !substring.isEmpty else { return true }
        var searchIndex = string.startIndex
        while searchIndex < string.endIndex {
            let remaining = string[searchIndex...]
            if remaining.hasPrefix(substring) {
                return true
            }
            searchIndex = string.index(after: searchIndex)
        }
        return false
    }

    // MARK: - Conditional Operations

    /// Returns the semantic string with the prefix prepended, only if the condition is true.
    @inlinable
    public func prefixed(with prefix: String, if condition: Bool) -> SemanticString {
        condition ? SemanticString(Standard(prefix)).appending(self) : self
    }

    /// Returns the semantic string with the prefix prepended, only if the condition is true.
    @inlinable
    public func prefixed(with prefix: SemanticString, if condition: Bool) -> SemanticString {
        condition ? prefix.appending(self) : self
    }

    /// Returns the semantic string with the prefix prepended, only if the condition is true.
    @inlinable
    public func prefixed(with prefix: some SemanticStringComponent, if condition: Bool) -> SemanticString {
        condition ? SemanticString(prefix).appending(self) : self
    }

    /// Returns the semantic string with the suffix appended, only if the condition is true.
    @inlinable
    public func suffixed(with suffix: String, if condition: Bool) -> SemanticString {
        condition ? appending(SemanticString(Standard(suffix))) : self
    }

    /// Returns the semantic string with the suffix appended, only if the condition is true.
    @inlinable
    public func suffixed(with suffix: SemanticString, if condition: Bool) -> SemanticString {
        condition ? appending(suffix) : self
    }

    /// Returns the semantic string with the suffix appended, only if the condition is true.
    @inlinable
    public func suffixed(with suffix: some SemanticStringComponent, if condition: Bool) -> SemanticString {
        condition ? appending(SemanticString(suffix)) : self
    }

    /// Returns self if the condition is true, otherwise returns an empty semantic string.
    @inlinable
    public func `if`(_ condition: Bool) -> SemanticString {
        condition ? self : SemanticString()
    }

    /// Returns self if the value is non-nil, otherwise returns an empty semantic string.
    /// The closure receives the unwrapped value.
    @inlinable
    public func ifLet<T>(_ value: T?, @SemanticStringBuilder then: (T) -> SemanticString) -> SemanticString {
        if let value {
            return appending(then(value))
        }
        return self
    }

    // MARK: - Appending

    /// Returns a new semantic string with the other string appended.
    @inlinable
    public func appending(_ other: SemanticString) -> SemanticString {
        var result = self
        result.makeUnique()
        result.invalidateCache()
        result._storage.elements.append(contentsOf: other._storage.elements)
        return result
    }

    /// Returns a new semantic string with the component appended.
    @inlinable
    public func appending(_ component: some SemanticStringComponent) -> SemanticString {
        var result = self
        result.makeUnique()
        result.invalidateCache()
        result._storage.elements.append(component)
        return result
    }

    /// Returns a new semantic string with the string appended.
    @inlinable
    public func appending(_ string: String, type: SemanticType = .standard) -> SemanticString {
        var result = self
        if !string.isEmpty {
            result.makeUnique()
            result.invalidateCache()
            result._storage.elements.append(AtomicComponent(string: string, type: type))
        }
        return result
    }

    // MARK: - Wrapping

    /// Returns a new semantic string wrapped with the given prefix and suffix.
    @inlinable
    public func wrapped(prefix: String, suffix: String) -> SemanticString {
        SemanticString(Standard(prefix))
            .appending(self)
            .appending(Standard(suffix))
    }

    /// Returns a new semantic string wrapped with the given prefix and suffix, only if condition is true.
    @inlinable
    public func wrapped(prefix: String, suffix: String, if condition: Bool) -> SemanticString {
        condition ? wrapped(prefix: prefix, suffix: suffix) : self
    }

    /// Returns a new semantic string wrapped in parentheses.
    @inlinable
    public func parenthesized() -> SemanticString {
        wrapped(prefix: "(", suffix: ")")
    }

    /// Returns a new semantic string wrapped in brackets.
    @inlinable
    public func bracketed() -> SemanticString {
        wrapped(prefix: "[", suffix: "]")
    }

    /// Returns a new semantic string wrapped in braces.
    @inlinable
    public func braced() -> SemanticString {
        wrapped(prefix: "{", suffix: "}")
    }

    /// Returns a new semantic string wrapped in angle brackets.
    @inlinable
    public func angleBracketed() -> SemanticString {
        wrapped(prefix: "<", suffix: ">")
    }
}

// MARK: - Codable Conformance

extension SemanticString: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let atomicComponents = try container.decode([AtomicComponent].self)
        self.init(components: atomicComponents)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(components)
    }
}

// MARK: - Hashable Conformance

extension SemanticString: Hashable {
    public static func == (lhs: SemanticString, rhs: SemanticString) -> Bool {
        lhs.components == rhs.components
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(components)
    }
}

// MARK: - TextOutputStream Conformance

extension SemanticString: TextOutputStream {
    @inlinable
    public mutating func write(_ string: String) {
        append(string, type: .standard)
    }

    @inlinable
    public mutating func write(_ string: String, type: SemanticType) {
        append(string, type: type)
    }
}

// MARK: - Operators

extension SemanticString {
    @inlinable
    public static func + (lhs: SemanticString, rhs: SemanticString) -> SemanticString {
        lhs.appending(rhs)
    }

    @inlinable
    public static func + (lhs: SemanticString, rhs: some SemanticStringComponent) -> SemanticString {
        lhs.appending(rhs)
    }

    @inlinable
    public static func += (lhs: inout SemanticString, rhs: SemanticString) {
        lhs.append(rhs)
    }

    @inlinable
    public static func += (lhs: inout SemanticString, rhs: some SemanticStringComponent) {
        lhs.append(rhs)
    }
}
