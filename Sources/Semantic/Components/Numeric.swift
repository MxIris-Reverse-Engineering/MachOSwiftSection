/// A numeric literal component with `.numeric` semantic type.
///
/// Example:
/// ```swift
/// Numeric("42")
/// Numeric("3.14")
/// Numeric("0xFF")
/// ```
public struct Numeric: AtomicSemanticComponent {
    public let string: String

    @inlinable
    public var type: SemanticType { .numeric }

    @inlinable
    public init(_ string: String) {
        self.string = string
    }

    @inlinable
    public init<T: BinaryInteger>(_ value: T) {
        self.string = String(value)
    }

    @inlinable
    public init<T: BinaryFloatingPoint>(_ value: T) {
        self.string = String(describing: value)
    }
}
