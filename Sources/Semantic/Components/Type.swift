public struct `Type`: SemanticStringComponent {
    public private(set) var string: String

    public var type: SemanticType { .type }

    public init(_ string: String) {
        self.string = string
    }
}
