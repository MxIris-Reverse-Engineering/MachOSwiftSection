/// A member declaration component with `.member(.declaration)` semantic type.
///
/// Example:
/// ```swift
/// MemberDeclaration("count")
/// MemberDeclaration("description")
/// ```
public struct MemberDeclaration: AtomicSemanticComponent {
    public let string: String

    @inlinable
    public var type: SemanticType { .member(.declaration) }

    @inlinable
    public init(_ string: String) {
        self.string = string
    }
}
