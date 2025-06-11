public struct FunctionOrMethodDeclaration: SemanticStringComponent {
    public private(set) var string: String

    public var type: SemanticType { .functionOrMethodDeclaration }

    public init(_ string: String) {
        self.string = string
    }
}
