public struct TypeDeclaration: SemanticStringComponent {
    public private(set) var string: String

    public let kind: SemanticType.TypeKind
    
    public var type: SemanticType { .type(kind, .declaration) }

    public init(kind: SemanticType.TypeKind, _ string: String) {
        self.kind = kind
        self.string = string
    }
}
