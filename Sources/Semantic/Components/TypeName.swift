/// A type name component with `.type` semantic type.
///
/// Example:
/// ```swift
/// TypeName(kind: .struct, "Int")
/// TypeName(kind: .class, "UIViewController")
/// TypeName(kind: .protocol, "Equatable")
/// ```
public struct TypeName: AtomicSemanticComponent {
    public let string: String
    public let kind: SemanticType.TypeKind

    @inlinable
    public var type: SemanticType { .type(kind, .name) }

    @inlinable
    public init(kind: SemanticType.TypeKind, _ string: String) {
        self.kind = kind
        self.string = string
    }
}
