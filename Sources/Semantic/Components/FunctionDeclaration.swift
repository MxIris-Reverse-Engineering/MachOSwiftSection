public struct FunctionDeclaration: SemanticStringComponent {
    public private(set) var string: String

    public var type: SemanticType { .functionDeclaration }

    public init(_ string: String) {
        self.string = string
    }
}
