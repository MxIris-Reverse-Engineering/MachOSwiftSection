/// A type declaration component with `.type(.declaration)` semantic type.
///
/// Example:
/// ```swift
/// TypeDeclaration(kind: .struct, "MyStruct")
/// TypeDeclaration(kind: .class, "ViewController")
/// ```
public struct TypeDeclaration: AtomicSemanticComponent {
    public let string: String
    public let kind: SemanticType.TypeKind

    @inlinable
    public var type: SemanticType { .type(kind, .declaration) }

    @inlinable
    public init(kind: SemanticType.TypeKind, _ string: String) {
        self.kind = kind
        self.string = string
    }
}
