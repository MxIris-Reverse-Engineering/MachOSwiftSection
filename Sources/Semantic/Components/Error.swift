/// An error component with `.error` semantic type.
///
/// Example:
/// ```swift
/// Error("Unknown type")
/// Error("<invalid>")
/// ```
public struct Error: AtomicSemanticComponent {
    public let string: String

    @inlinable
    public var type: SemanticType { .error }

    @inlinable
    public init(_ string: String) {
        self.string = string
    }
}
