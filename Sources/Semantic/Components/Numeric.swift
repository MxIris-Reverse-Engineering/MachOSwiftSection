public struct Numeric: SemanticStringComponent {
    public private(set) var string: String

    public var type: SemanticType { .numeric }

    public init(_ string: String) {
        self.string = string
    }
}
