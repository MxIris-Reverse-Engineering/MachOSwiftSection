public struct Method: SemanticStringComponent {
    public private(set) var string: String

    public var type: SemanticType { .method }

    public init(_ string: String) {
        self.string = string
    }
}
