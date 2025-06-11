public struct Keyword: SemanticStringComponent {
    public private(set) var string: String

    public var type: SemanticType { .keyword }

    public init(_ string: String) {
        self.string = string
    }
}
