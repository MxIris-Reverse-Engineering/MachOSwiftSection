public struct FunctionName: SemanticStringComponent {
    public private(set) var string: String

    public var type: SemanticType { .function(.name) }

    public init(_ string: String) {
        self.string = string
    }
}


