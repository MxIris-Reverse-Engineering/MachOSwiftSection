/// An argument label component with `.argument` semantic type.
///
/// Example:
/// ```swift
/// Argument("label")
/// Argument("_")
/// ```
public struct Argument: AtomicSemanticComponent {
    public let string: String

    @inlinable
    public var type: SemanticType { .argument }

    @inlinable
    public init(_ string: String) {
        self.string = string
    }
}
