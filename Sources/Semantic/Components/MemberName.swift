/// A member name component with `.member(.name)` semantic type.
///
/// Example:
/// ```swift
/// MemberName("count")
/// MemberName("description")
/// ```
public struct MemberName: AtomicSemanticComponent {
    public let string: String

    @inlinable
    public var type: SemanticType { .member(.name) }

    @inlinable
    public init(_ string: String) {
        self.string = string
    }
}
