/// A line comment component with `.comment` semantic type.
///
/// Example:
/// ```swift
/// Comment("This is a comment")  // produces "// This is a comment"
/// ```
public struct Comment: AtomicSemanticComponent {
    public let string: String

    @inlinable
    public var type: SemanticType { .comment }

    @inlinable
    public init(_ string: String) {
        self.string = "// \(string)"
    }
}

/// An inline comment component with `.comment` semantic type.
///
/// Example:
/// ```swift
/// InlineComment("note")  // produces "/* note */"
/// ```
public struct InlineComment: AtomicSemanticComponent {
    public let string: String

    @inlinable
    public var type: SemanticType { .comment }

    @inlinable
    public init(_ string: String) {
        self.string = "/* \(string) */"
    }
}

/// A multi-line comment component with `.comment` semantic type.
///
/// Example:
/// ```swift
/// MultipleLineComment("Long\ncomment")
/// ```
public struct MultipleLineComment: AtomicSemanticComponent {
    public let string: String

    @inlinable
    public var type: SemanticType { .comment }

    @inlinable
    public init(_ string: String) {
        self.string = "/*\n\(string)\n*/"
    }
}
