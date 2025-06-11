public struct TypeDeclaration: SemanticStringComponent {
    public private(set) var string: String

    public var type: SemanticType { .typeDeclaration }

    public init(_ string: String) {
        self.string = string
    }
}
