public struct FunctionOrMethodName: SemanticStringComponent {
    public private(set) var string: String

    public var type: SemanticType { .functionOrMethodName }

    public init(_ string: String) {
        self.string = string
    }
}


