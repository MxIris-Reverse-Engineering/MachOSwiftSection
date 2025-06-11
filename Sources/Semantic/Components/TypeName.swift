public struct TypeName: SemanticStringComponent {
    public private(set) var string: String

    public var type: SemanticType { .typeName }

    public init(_ string: String) {
        self.string = string
    }
}


