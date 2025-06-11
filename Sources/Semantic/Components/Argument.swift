public struct Argument: SemanticStringComponent {
    public private(set) var string: String

    public var type: SemanticType { .argument }

    public init(_ string: String) {
        self.string = string
    }
}
