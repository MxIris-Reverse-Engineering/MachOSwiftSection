/// A keyword component with `.keyword` semantic type.
///
/// Example:
/// ```swift
/// Keyword("public")  // styled as keyword
/// Keyword("func")    // styled as keyword
/// ```
public struct Keyword: AtomicSemanticComponent {
    public let string: String

    @inlinable
    public var type: SemanticType { .keyword }

    @inlinable
    public init(_ string: String) {
        self.string = string
    }
}
