/// An indentation component.
///
/// Example:
/// ```swift
/// Indent(level: 2)  // produces 8 spaces (4 per level)
/// ```
public struct Indent: AtomicSemanticComponent, CustomStringConvertible {
    public let level: Int

    @inlinable
    public var string: String { description }

    @inlinable
    public var type: SemanticType { .standard }

    @inlinable
    public init(level: Int) {
        self.level = level
    }

    @inlinable
    public var description: String {
        level > 0 ? String(repeating: " ", count: level * 4) : ""
    }
}

/// A line break component.
///
/// Example:
/// ```swift
/// BreakLine()  // produces "\n"
/// ```
public struct BreakLine: AtomicSemanticComponent, CustomStringConvertible {
    @inlinable
    public var string: String { "\n" }

    @inlinable
    public var type: SemanticType { .standard }

    @inlinable
    public var description: String { "\n" }

    @inlinable
    public init() {}
}

/// A single space component.
///
/// Example:
/// ```swift
/// Space()  // produces " "
/// ```
public struct Space: AtomicSemanticComponent, CustomStringConvertible {
    @inlinable
    public var string: String { " " }

    @inlinable
    public var type: SemanticType { .standard }

    @inlinable
    public var description: String { " " }

    @inlinable
    public init() {}
}
