public struct Variable: SemanticStringComponent {
    public private(set) var string: String

    public var type: SemanticType { .variable }

    public init(_ string: String) {
        self.string = string
    }
}
