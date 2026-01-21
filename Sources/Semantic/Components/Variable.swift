/// A variable name component with `.variable` semantic type.
///
/// Example:
/// ```swift
/// Variable("count")
/// Variable("self")
/// ```
public struct Variable: AtomicSemanticComponent {
    public let string: String

    @inlinable
    public var type: SemanticType { .variable }

    @inlinable
    public init(_ string: String) {
        self.string = string
    }
}
